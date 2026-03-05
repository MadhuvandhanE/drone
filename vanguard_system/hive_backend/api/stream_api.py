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
    """

    CONF_THRESH  = 0.35          # aerial-tuned: catch partially visible victims
    IOU_THRESH   = 0.50
    IMGSZ        = 960           # high-res input preserves small aerial targets
    DEVICE       = "cuda" if torch.cuda.is_available() else "cpu"
    BOX_COLOR    = (0, 240, 255)   # cyan (BGR)
    TARGET_FPS   = 10              # intentionally low — keeps CPU usage manageable
    JPEG_QUALITY = 65              # lower = smaller payload, less bandwidth
    def __init__(self, stream_source):
        super().__init__(daemon=True, name="jarvis-mjpeg")
        # stream_source: int (camera index) or str (URL / IP camera / RTSP)
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
            print(f"[STREAM] Loading YOLO from {model_path} on {self.DEVICE} …")
            self._model = YOLO(model_path)
            self._model.to(self.DEVICE)
            print(f"[STREAM] YOLO ready ✓  (device={self.DEVICE}, imgsz={self.IMGSZ}, conf={self.CONF_THRESH})")

    def run(self):
        self._load_model()

        src = self.stream_source
        if isinstance(src, str) and src.isdigit():
            src = int(src)

        cap = cv2.VideoCapture(src, cv2.CAP_DSHOW) if isinstance(src, int) \
              else cv2.VideoCapture(src)
        cap.set(cv2.CAP_PROP_FRAME_WIDTH,  640)   # keep low to save CPU
        cap.set(cv2.CAP_PROP_FRAME_HEIGHT, 480)
        cap.set(cv2.CAP_PROP_FPS,          self.TARGET_FPS)
        cap.set(cv2.CAP_PROP_BUFFERSIZE,   1)

        if not cap.isOpened():
            print(f"[STREAM] ERROR: Cannot open source → {src}")
            return

        print(f"[STREAM] Camera opened → {src}")
        interval   = 1.0 / self.TARGET_FPS
        last_infer = 0.0      # throttle YOLO to at most 10fps independently

        while not self._stop_event.is_set():
            t0 = time.perf_counter()

            ret, frame = cap.read()
            if not ret:
                time.sleep(0.05)
                continue

            # YOLO inference – persons only (throttled)
            now       = time.perf_counter()
            detections = []
            if now - last_infer >= interval:   # only infer at TARGET_FPS rate
                results    = self._model(
                    frame,
                    classes = [0],
                    conf    = self.CONF_THRESH,
                    iou     = self.IOU_THRESH,
                    imgsz   = self.IMGSZ,
                    device  = self.DEVICE,
                    verbose = False,
                )
                last_infer = now
                raw: list[dict] = []
                for r in results:
                    for box in r.boxes:
                        conf = float(box.conf[0])
                        x1, y1, x2, y2 = [int(v) for v in box.xyxy[0]]
                        detections.append((x1, y1, x2, y2, conf))
                        raw.append({
                            "label":      "person",
                            "confidence": round(conf, 2),
                            "bbox":       [x1, y1, x2 - x1, y2 - y1],
                        })
                # Expose detections globally so /detections endpoint reads them
                global LIVE_DETECTIONS
                LIVE_DETECTIONS = raw

            annotated = self._annotate(frame, detections)

            # Encode to JPEG (low quality = fast)
            ok, buf = cv2.imencode(
                ".jpg", annotated,
                [cv2.IMWRITE_JPEG_QUALITY, self.JPEG_QUALITY]
            )
            if ok:
                FRAME_STORE.put(buf.tobytes())

            elapsed   = time.perf_counter() - t0
            sleep_for = max(0.0, interval - elapsed)
            time.sleep(sleep_for)

        cap.release()
        print("[STREAM] Camera released.")

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
                cv2.line(out, (px, py), (px + dx * bk, py),      self.BOX_COLOR, th)
                cv2.line(out, (px, py), (px,            py + dy * bk), self.BOX_COLOR, th)

            # Label
            label = f" PERSON  {conf:.0%} "
            (lw, lh), _ = cv2.getTextSize(
                label, cv2.FONT_HERSHEY_SIMPLEX, 0.52, 1)
            cv2.rectangle(out,
                          (x1, y1 - lh - 10), (x1 + lw + 4, y1),
                          self.BOX_COLOR, -1)
            cv2.putText(out, label, (x1 + 2, y1 - 5),
                        cv2.FONT_HERSHEY_SIMPLEX, 0.52,
                        (0, 0, 0), 1, cv2.LINE_AA)

        # Scanline vignette (subtle)
        overlay = out.copy()
        for y in range(0, h, 4):
            overlay[y, :] = (overlay[y, :] * 0.6).astype("uint8")
        cv2.addWeighted(overlay, 0.12, out, 0.88, 0, out)

        # HUD watermark
        ts = time.strftime("%H:%M:%S")
        cv2.putText(out, f"JARVIS VISION  |  CAM-1  |  {ts}",
                    (10, h - 12),
                    cv2.FONT_HERSHEY_SIMPLEX, 0.45, self.BOX_COLOR, 1, cv2.LINE_AA)

        det_count = len(detections)
        status_color = (0, 230, 118) if det_count == 0 else (0, 240, 255)
        cv2.putText(out,
                    f"TARGETS: {det_count}",
                    (w - 120, h - 12),
                    cv2.FONT_HERSHEY_SIMPLEX, 0.45, status_color, 1, cv2.LINE_AA)
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
