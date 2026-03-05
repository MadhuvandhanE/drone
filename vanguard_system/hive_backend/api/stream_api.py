"""
JARVIS Stream API
=================
MJPEG video streaming endpoint for the dashboard live feed.

GET /video/feed          — MJPEG stream (served to Flutter app & browser)
POST /video/start        — Start the YOLO vision engine on a given camera
POST /video/stop         — Stop the YOLO vision engine

The MJPEG format is natively supported by Flutter's Image.network() widget
when the server sets Content-Type: multipart/x-mixed-replace.
It also works directly in Chrome / Firefox for testing.
"""

import asyncio
import time
import cv2
import threading
import torch

from fastapi import APIRouter
from fastapi.responses import StreamingResponse
from pydantic import BaseModel

router = APIRouter(prefix="/video", tags=["Video Stream"])


# ─────────────────────────────────────────────────────────────────────────────
# Live detection state  (read by detection_api.py)
# ─────────────────────────────────────────────────────────────────────────────
# The vision thread writes here so GET /detections can return real YOLO data.

LIVE_DETECTIONS: list[dict] = []

# ─────────────────────────────────────────────────────────────────────────────
# Shared MJPEG frame store
# ─────────────────────────────────────────────────────────────────────────────
# The VisionThread writes encoded JPEG bytes here; the /video/feed endpoint
# reads from it continuously and pushes them out as multipart frames.

class _FrameStore:
    """Thread-safe single-slot frame store used between producer and consumers."""

    def __init__(self):
        self._lock  = threading.Lock()
        self._frame: bytes | None = None   # latest JPEG bytes
        self._cond  = threading.Condition(self._lock)

    def put(self, jpeg_bytes: bytes):
        with self._cond:
            self._frame = jpeg_bytes
            self._cond.notify_all()

    def get(self, timeout: float = 1.0) -> bytes | None:
        with self._cond:
            self._cond.wait(timeout=timeout)
            return self._frame

    def latest(self) -> bytes | None:
        with self._lock:
            return self._frame


FRAME_STORE = _FrameStore()


# ─────────────────────────────────────────────────────────────────────────────
# Vision producer thread (YOLO + OpenCV)
# ─────────────────────────────────────────────────────────────────────────────

class _MJPEGVisionThread(threading.Thread):
    """
    Captures frames from the chosen camera, annotates them with YOLO,
    and pushes JPEG bytes into FRAME_STORE so the MJPEG endpoint can serve them.

    Performance design
    ------------------
    CAPTURE_FPS (25)  – how fast frames are grabbed from the camera and
                        pushed to FRAME_STORE.  Drives the smooth video.
    INFER_FPS   (8)   – how often YOLO actually runs.  Last known detections
                        are reused for every frame between inference calls so
                        bounding boxes stay on screen without re-running YOLO.

    SAHI tiling
    -----------
    A single YOLO pass on a 640×480 frame won't see a person who is only
    5-10 pixels tall (drone altitude).  SAHI fixes this by splitting the
    frame into four overlapping 60%×60% tiles and running YOLO on each.
    Each tile is upscaled ~1.7× by the model, making tiny targets visible.
    Duplicate detections from overlapping tiles are removed with NMS.
    SAHI is automatically disabled on CPU to keep fps usable.
    """

    CONF_THRESH  = 0.30          # low threshold — aerial targets are partially occluded
    IOU_THRESH   = 0.45          # NMS: suppress overlapping boxes
    INFER_IMGSZ  = 640           # per-pass image size (5 passes at 640 = SAHI tiling)
    DEVICE       = "cuda" if torch.cuda.is_available() else "cpu"
    SAHI_ENABLED = torch.cuda.is_available()   # tiling only when GPU is available
    BOX_COLOR    = (0, 240, 255)   # cyan (BGR)
    CAPTURE_FPS  = 25              # stream / annotation rate
    INFER_FPS    = 8               # YOLO inference rate
    JPEG_QUALITY = 72              # slightly higher quality for sharper bounding boxes

    def __init__(self, stream_source):
        super().__init__(daemon=True, name="jarvis-mjpeg")
        self.stream_source = stream_source
        self._stop_event   = threading.Event()
        self._model        = None

    def stop(self):
        self._stop_event.set()

    # ── Internal ──────────────────────────────────────────────────────────────

    def _load_model(self):
        if self._model is None:
            from ultralytics import YOLO
            import os
            base = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
            model_path = os.path.join(base, "yolov8n.pt")
            mode = "SAHI tiling" if self.SAHI_ENABLED else "single-pass"
            print(f"[STREAM] Loading YOLO from {model_path} on {self.DEVICE} ({mode}) …")
            self._model = YOLO(model_path)
            self._model.to(self.DEVICE)
            print(f"[STREAM] YOLO ready ✓  conf={self.CONF_THRESH} imgsz={self.INFER_IMGSZ} fps={self.INFER_FPS}")

    def run(self):
        self._load_model()

        src = self.stream_source
        if isinstance(src, str) and src.isdigit():
            src = int(src)

        cap = cv2.VideoCapture(src, cv2.CAP_DSHOW) if isinstance(src, int) \
              else cv2.VideoCapture(src)
        cap.set(cv2.CAP_PROP_FRAME_WIDTH,  640)
        cap.set(cv2.CAP_PROP_FRAME_HEIGHT, 480)
        cap.set(cv2.CAP_PROP_FPS,          self.CAPTURE_FPS)
        cap.set(cv2.CAP_PROP_BUFFERSIZE,   1)

        if not cap.isOpened():
            print(f"[STREAM] ERROR: Cannot open source → {src}")
            return

        print(f"[STREAM] Camera opened → {src}  capture={self.CAPTURE_FPS}fps  infer={self.INFER_FPS}fps")

        capture_interval = 1.0 / self.CAPTURE_FPS
        infer_interval   = 1.0 / self.INFER_FPS
        last_infer       = 0.0
        last_detections: list[tuple] = []   # carried between inference calls

        while not self._stop_event.is_set():
            t0 = time.perf_counter()

            ret, frame = cap.read()
            if not ret:
                time.sleep(0.02)
                continue

            # ── YOLO inference (throttled to INFER_FPS) ───────────────────
            now = time.perf_counter()
            if now - last_infer >= infer_interval:
                last_detections = self._infer(frame)
                global LIVE_DETECTIONS
                LIVE_DETECTIONS = [
                    {
                        "label":      "person",
                        "confidence": round(d[4], 2),
                        "bbox":       [d[0], d[1], d[2] - d[0], d[3] - d[1]],
                    }
                    for d in last_detections
                ]
                last_infer = now

            # ── Annotate every frame with last known detections ────────────
            annotated = self._annotate(frame, last_detections)

            ok, buf = cv2.imencode(
                ".jpg", annotated,
                [cv2.IMWRITE_JPEG_QUALITY, self.JPEG_QUALITY],
            )
            if ok:
                FRAME_STORE.put(buf.tobytes())

            elapsed = time.perf_counter() - t0
            time.sleep(max(0.0, capture_interval - elapsed))

        cap.release()
        print("[STREAM] Camera released.")

    # ── SAHI Inference ────────────────────────────────────────────────────────

    def _infer(self, frame: cv2.Mat) -> list[tuple]:
        """
        Run YOLO with optional SAHI tiling for aerial small-target detection.

        Returns list of (x1, y1, x2, y2, conf) in full-frame pixel coords.

        SAHI strategy
        -------------
        Full-frame pass  → catches medium/close persons
        2×2 tiled passes → each tile is ~60% of the frame with 20% overlap,
                           upscaled by the model → tiny aerial targets visible
        NMS → removes duplicates from overlapping tiles
        """
        if self.SAHI_ENABLED:
            return self._infer_sahi(frame)
        return self._infer_single(frame, 0, 0)

    def _infer_single(self, img: cv2.Mat, ox: int, oy: int) -> list[tuple]:
        """Run one YOLO pass on img; translate results by (ox, oy) offset."""
        results = self._model(
            img,
            classes = [0],
            conf    = self.CONF_THRESH,
            iou     = self.IOU_THRESH,
            imgsz   = self.INFER_IMGSZ,
            device  = self.DEVICE,
            verbose = False,
        )
        dets = []
        for r in results:
            for box in r.boxes:
                conf = float(box.conf[0])
                x1, y1, x2, y2 = [int(v) for v in box.xyxy[0]]
                dets.append((x1 + ox, y1 + oy, x2 + ox, y2 + oy, conf))
        return dets

    def _infer_sahi(self, frame: cv2.Mat) -> list[tuple]:
        """Full-frame + 2×2 overlapping tile passes merged with NMS."""
        h, w = frame.shape[:2]
        all_dets = []

        # Pass 1: full frame (catches nearby / medium persons)
        all_dets.extend(self._infer_single(frame, 0, 0))

        # Passes 2-5: 2×2 tiles with 20% overlap
        tw = int(w * 0.60)   # tile width  (~60% = zoom ×1.67)
        th = int(h * 0.60)   # tile height
        sx = (w - tw) // 1   # stride so two cols cover full width
        sy = (h - th) // 1

        for row in range(2):
            for col in range(2):
                ox = col * (w - tw)
                oy = row * (h - th)
                tile = frame[oy : oy + th, ox : ox + tw]
                all_dets.extend(self._infer_single(tile, ox, oy))

        return self._nms(all_dets, iou_thresh=self.IOU_THRESH)

    def _nms(self, dets: list[tuple], iou_thresh: float = 0.45) -> list[tuple]:
        """Greedy NMS: sort by confidence, suppress lower-conf overlapping boxes."""
        if not dets:
            return []
        boxes = sorted(dets, key=lambda d: d[4], reverse=True)
        kept  = []
        while boxes:
            best = boxes.pop(0)
            kept.append(best)
            boxes = [b for b in boxes if self._iou(best, b) < iou_thresh]
        return kept

    @staticmethod
    def _iou(a: tuple, b: tuple) -> float:
        ax1, ay1, ax2, ay2, _ = a
        bx1, by1, bx2, by2, _ = b
        ix1 = max(ax1, bx1); iy1 = max(ay1, by1)
        ix2 = min(ax2, bx2); iy2 = min(ay2, by2)
        inter = max(0, ix2 - ix1) * max(0, iy2 - iy1)
        a_area = (ax2 - ax1) * (ay2 - ay1)
        b_area = (bx2 - bx1) * (by2 - by1)
        return inter / (a_area + b_area - inter + 1e-6)

    def _annotate(self, frame, detections):
        out = frame.copy()
        h, w = out.shape[:2]

        for (x1, y1, x2, y2, conf) in detections:
            # Bounding rectangle
            cv2.rectangle(out, (x1, y1), (x2, y2), self.BOX_COLOR, 2)

            # Sci-fi corner brackets
            bk, th = 16, 3
            for px, py, dx, dy in [
                (x1, y1,  1,  1), (x2, y1, -1,  1),
                (x1, y2,  1, -1), (x2, y2, -1, -1),
            ]:
                cv2.line(out, (px, py), (px + dx * bk, py),          self.BOX_COLOR, th)
                cv2.line(out, (px, py), (px,            py + dy * bk), self.BOX_COLOR, th)

            # Label
            label = f" PERSON  {conf:.0%} "
            (lw, lh), _ = cv2.getTextSize(label, cv2.FONT_HERSHEY_SIMPLEX, 0.52, 1)
            cv2.rectangle(out, (x1, y1 - lh - 10), (x1 + lw + 4, y1), self.BOX_COLOR, -1)
            cv2.putText(out, label, (x1 + 2, y1 - 5),
                        cv2.FONT_HERSHEY_SIMPLEX, 0.52, (0, 0, 0), 1, cv2.LINE_AA)

        # HUD watermark
        ts = time.strftime("%H:%M:%S")
        cv2.putText(out, f"JARVIS VISION  |  CAM-1  |  {ts}",
                    (10, h - 12), cv2.FONT_HERSHEY_SIMPLEX, 0.45, self.BOX_COLOR, 1, cv2.LINE_AA)

        det_count    = len(detections)
        status_color = (0, 230, 118) if det_count == 0 else (0, 240, 255)
        sahi_tag     = " SAHI" if self.SAHI_ENABLED else ""
        cv2.putText(out, f"TARGETS: {det_count}{sahi_tag}",
                    (w - 150, h - 12), cv2.FONT_HERSHEY_SIMPLEX, 0.45, status_color, 1, cv2.LINE_AA)
        return out


# ─────────────────────────────────────────────────────────────────────────────
# Module-level state
# ─────────────────────────────────────────────────────────────────────────────

_vision_thread: _MJPEGVisionThread | None = None


# ─────────────────────────────────────────────────────────────────────────────
# Endpoints
# ─────────────────────────────────────────────────────────────────────────────

class VideoStartRequest(BaseModel):
    source: str = "0"   # "0" = webcam, "1" = ext cam, or full URL


@router.post("/start", summary="Start MJPEG vision stream")
async def start_video_stream(req: VideoStartRequest):
    """
    Start (or restart) the YOLO-annotated MJPEG camera stream.
    Pass source='0' for built-in webcam, '1' for external USB camera,
    or a full RTSP/HTTP URL for IP cameras / Peeper TX10.
    """
    global _vision_thread

    if _vision_thread and _vision_thread.is_alive():
        _vision_thread.stop()
        _vision_thread.join(timeout=3)

    src = req.source
    _vision_thread = _MJPEGVisionThread(
        stream_source=int(src) if src.isdigit() else src
    )
    _vision_thread.start()

    return {
        "status":  "STARTED",
        "source":  req.source,
        "feed_url": "/video/feed",
    }


@router.post("/stop", summary="Stop MJPEG vision stream")
async def stop_video_stream():
    global _vision_thread
    if _vision_thread:
        _vision_thread.stop()
        _vision_thread = None
    return {"status": "STOPPED"}


@router.get("/status", summary="Vision stream status")
async def stream_status():
    global _vision_thread
    running = _vision_thread is not None and _vision_thread.is_alive()
    has_frame = FRAME_STORE.latest() is not None
    return {"running": running, "has_frame": has_frame}


@router.get("/snapshot", summary="Single JPEG frame (Flutter web compatible)")
async def video_snapshot():
    """
    Returns the latest annotated frame as a single JPEG image.

    Use this instead of /feed when running Flutter on web — Flutter web's
    Image.network() cannot decode MJPEG multipart streams, but handles
    plain JPEG responses perfectly.  Poll this endpoint with a cache-busting
    query param to achieve a smooth frame refresh:

        Image.network('http://localhost:8000/video/snapshot?t=$cacheBust')
    """
    from fastapi.responses import Response
    frame_bytes = FRAME_STORE.latest()

    if frame_bytes is None:
        # Return the no-signal placeholder so the widget always gets a valid image
        import numpy as np
        placeholder = _make_no_signal_frame()
        ok, buf = cv2.imencode(".jpg", placeholder,
                               [cv2.IMWRITE_JPEG_QUALITY, 70])
        if not ok:
            return Response(status_code=503)
        frame_bytes = buf.tobytes()

    return Response(
        content=frame_bytes,
        media_type="image/jpeg",
        headers={
            "Cache-Control": "no-cache, no-store, must-revalidate",
            "Access-Control-Allow-Origin": "*",
        },
    )


@router.get("/feed", summary="MJPEG live feed")
async def video_feed():
    """
    Streams the annotated YOLO camera feed as an MJPEG multipart response.

    Flutter usage:
        Image.network('http://<host>:8000/video/feed')

    Browser usage:
        <img src="http://localhost:8000/video/feed">
    """

    async def _generate():
        boundary = b"--jarvisframe\r\n"
        no_signal_sent = False

        while True:
            frame_bytes = FRAME_STORE.latest()

            if frame_bytes is None:
                if not no_signal_sent:
                    placeholder = _make_no_signal_frame()
                    ok, buf = cv2.imencode(".jpg", placeholder,
                                          [cv2.IMWRITE_JPEG_QUALITY, 60])
                    if ok:
                        frame_bytes = buf.tobytes()
                        no_signal_sent = True
                    else:
                        await asyncio.sleep(0.1)
                        continue
                else:
                    await asyncio.sleep(0.1)
                    continue
            else:
                no_signal_sent = False

            yield (
                boundary
                + b"Content-Type: image/jpeg\r\n"
                + b"Content-Length: " + str(len(frame_bytes)).encode() + b"\r\n"
                + b"\r\n"
                + frame_bytes
                + b"\r\n"
            )

            await asyncio.sleep(1 / 10)   # 10 fps push rate — easy on CPU

    return StreamingResponse(
        _generate(),
        media_type="multipart/x-mixed-replace; boundary=jarvisframe",
        headers={
            "Cache-Control": "no-cache, no-store",
            "Access-Control-Allow-Origin": "*",
        },
    )


def _make_no_signal_frame():
    """Generate a dark 'NO SIGNAL' placeholder frame."""
    import numpy as np
    h, w = 480, 854
    frame = np.zeros((h, w, 3), dtype="uint8")
    frame[:, :] = (8, 13, 20)    # BG_DARK

    # Grid lines
    for x in range(0, w, 40):
        frame[:, x] = (15, 25, 35)
    for y in range(0, h, 40):
        frame[y, :] = (15, 25, 35)

    cx, cy = w // 2, h // 2
    cv2.putText(frame, "NO SIGNAL", (cx - 115, cy - 10),
                cv2.FONT_HERSHEY_SIMPLEX, 1.2, (0, 100, 120), 2, cv2.LINE_AA)
    cv2.putText(frame, "Start vision: POST /video/start",
                (cx - 185, cy + 30),
                cv2.FONT_HERSHEY_SIMPLEX, 0.52, (40, 80, 90), 1, cv2.LINE_AA)

    ts = time.strftime("%H:%M:%S")
    cv2.putText(frame, f"JARVIS VISION  |  {ts}", (10, h - 12),
                cv2.FONT_HERSHEY_SIMPLEX, 0.45, (0, 80, 100), 1, cv2.LINE_AA)
    return frame
