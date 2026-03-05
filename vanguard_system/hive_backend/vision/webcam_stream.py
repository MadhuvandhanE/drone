"""
JARVIS Webcam Stream Module
============================
Captures frames from the local webcam, runs YOLO person detection,
annotates each frame with bounding boxes, and yields processed JPEG-
encoded frames suitable for MJPEG streaming.

This module simulates the surveillance drone camera during the
development phase (before real drone hardware is available).

Pipeline
--------
    Laptop Webcam
         ↓
    cv2.VideoCapture(0)
         ↓
    AerialYOLODetector.detect()
         ↓
    Bounding Box Annotation
         ↓
    JPEG Encoding
         ↓
    Caller (MJPEG stream / FRAME_STORE)

Usage
-----
    from vision.webcam_stream import WebcamStream

    stream = WebcamStream(camera_index=0)
    stream.open()

    for jpeg_bytes, detections in stream:
        # push jpeg_bytes to MJPEG client
        # detections → [{"label": "person", "confidence": 0.87, "bbox": [x,y,w,h]}]

    stream.close()
"""

from __future__ import annotations

import time
from typing import Generator, Optional, Tuple

import cv2
import numpy as np

from vision.yolo_detector import AerialYOLODetector

# ---------------------------------------------------------------------------
# Style constants (HUD / tactical look consistent with stream_api.py)
# ---------------------------------------------------------------------------

_BOX_COLOR     = (0, 240, 255)   # cyan (BGR)
_LABEL_FG      = (0, 0, 0)       # black text on label background
_CORNER_LEN    = 16              # corner-bracket arm length (px)
_CORNER_THICK  = 3               # corner-bracket line thickness
_JPEG_QUALITY  = 70              # JPEG compression quality (0–100)


# ---------------------------------------------------------------------------
# WebcamStream
# ---------------------------------------------------------------------------

class WebcamStream:
    """
    Captures frames from a local webcam, annotates them with YOLO
    detections, and yields (jpeg_bytes, detections) tuples.

    Parameters
    ----------
    camera_index : int
        OpenCV camera index. 0 = built-in webcam, 1 = first USB camera.
    target_fps : int
        Maximum frame rate.  Frames are throttled to this rate regardless
        of how fast the camera can deliver them.
    """

    def __init__(self, camera_index: int = 0, target_fps: int = 15):
        self.camera_index = camera_index
        self.target_fps   = target_fps
        self._cap: Optional[cv2.VideoCapture] = None
        self._detector = AerialYOLODetector()
        self._latest_detections: list[dict] = []

    # ── Public API ────────────────────────────────────────────────────────────

    def open(self) -> None:
        """Open the webcam and load the YOLO model."""
        if self._cap is not None and self._cap.isOpened():
            return

        print(f"[WEBCAM] Opening camera index {self.camera_index} …")
        self._cap = cv2.VideoCapture(self.camera_index, cv2.CAP_DSHOW)
        self._cap.set(cv2.CAP_PROP_FRAME_WIDTH,  640)
        self._cap.set(cv2.CAP_PROP_FRAME_HEIGHT, 480)
        self._cap.set(cv2.CAP_PROP_FPS,          self.target_fps)
        self._cap.set(cv2.CAP_PROP_BUFFERSIZE,   1)

        if not self._cap.isOpened():
            raise RuntimeError(
                f"[WEBCAM] Cannot open camera index {self.camera_index}. "
                "Make sure no other application is using the webcam."
            )
        print(f"[WEBCAM] Camera {self.camera_index} opened ✓")

        # Load model in calling thread (blocking once, then cached)
        self._detector.load()

    def close(self) -> None:
        """Release the webcam."""
        if self._cap is not None:
            self._cap.release()
            self._cap = None
            self._detector.reset_smoothing()
            print("[WEBCAM] Camera released.")

    @property
    def latest_detections(self) -> list[dict]:
        """Snapshot of the detections from the most recently processed frame."""
        return list(self._latest_detections)

    def read_frame(self) -> Tuple[Optional[bytes], list[dict]]:
        """
        Capture one frame, run detection, annotate, and return
        ``(jpeg_bytes, detections)``.

        Returns ``(None, [])`` if the camera is not open or the read fails.
        """
        if self._cap is None or not self._cap.isOpened():
            return None, []

        ret, frame = self._cap.read()
        if not ret:
            return None, []

        detections = self._detector.detect(frame)
        self._latest_detections = detections

        annotated = _annotate(frame, detections)
        ok, buf   = cv2.imencode(
            ".jpg", annotated,
            [cv2.IMWRITE_JPEG_QUALITY, _JPEG_QUALITY],
        )
        if not ok:
            return None, detections

        return buf.tobytes(), detections

    def __iter__(self) -> Generator[Tuple[bytes, list[dict]], None, None]:
        """
        Iterate over (jpeg_bytes, detections) at ``target_fps``.

        Opens the camera automatically if ``open()`` has not been called.
        Stops when the webcam is closed or yields empty on read failure.
        """
        if self._cap is None:
            self.open()

        interval = 1.0 / self.target_fps

        while self._cap is not None and self._cap.isOpened():
            t0 = time.perf_counter()

            jpeg, dets = self.read_frame()
            if jpeg is not None:
                yield jpeg, dets

            elapsed = time.perf_counter() - t0
            time.sleep(max(0.0, interval - elapsed))

    # ── Context manager support ───────────────────────────────────────────────

    def __enter__(self) -> "WebcamStream":
        self.open()
        return self

    def __exit__(self, *_) -> None:
        self.close()


# ---------------------------------------------------------------------------
# Annotation helpers
# ---------------------------------------------------------------------------

def _annotate(frame: np.ndarray, detections: list[dict]) -> np.ndarray:
    """
    Draw bounding boxes and HUD elements on a copy of *frame*.

    Each detection dict must have:
        {"label": "person", "confidence": float, "bbox": [x, y, w, h]}
    """
    out = frame.copy()
    h, w = out.shape[:2]

    for det in detections:
        bbox = det["bbox"]
        conf = det["confidence"]

        x  = int(bbox[0])
        y  = int(bbox[1])
        bw = int(bbox[2])
        bh = int(bbox[3])
        x2 = x + bw
        y2 = y + bh

        # Main bounding rectangle
        cv2.rectangle(out, (x, y), (x2, y2), _BOX_COLOR, 2)

        # Sci-fi corner brackets
        for px, py, dx, dy in [
            (x,  y,   1,  1),
            (x2, y,  -1,  1),
            (x,  y2,  1, -1),
            (x2, y2, -1, -1),
        ]:
            cv2.line(out, (px, py), (px + dx * _CORNER_LEN, py),
                     _BOX_COLOR, _CORNER_THICK)
            cv2.line(out, (px, py), (px, py + dy * _CORNER_LEN),
                     _BOX_COLOR, _CORNER_THICK)

        # Confidence label
        label = f" PERSON  {conf:.0%} "
        (lw, lh), _base = cv2.getTextSize(
            label, cv2.FONT_HERSHEY_SIMPLEX, 0.52, 1
        )
        cv2.rectangle(
            out,
            (x, y - lh - 10),
            (x + lw + 4, y),
            _BOX_COLOR, -1,     # filled background
        )
        cv2.putText(
            out, label, (x + 2, y - 5),
            cv2.FONT_HERSHEY_SIMPLEX, 0.52, _LABEL_FG, 1, cv2.LINE_AA,
        )

    # HUD watermark – bottom-left
    ts = time.strftime("%H:%M:%S")
    cv2.putText(
        out,
        f"JARVIS VISION  |  CAM-{0}  |  {ts}",
        (10, h - 12),
        cv2.FONT_HERSHEY_SIMPLEX, 0.45, _BOX_COLOR, 1, cv2.LINE_AA,
    )

    # Detection count – bottom-right
    n = len(detections)
    status_color = (0, 230, 118) if n == 0 else _BOX_COLOR
    cv2.putText(
        out,
        f"TARGETS: {n}",
        (w - 120, h - 12),
        cv2.FONT_HERSHEY_SIMPLEX, 0.45, status_color, 1, cv2.LINE_AA,
    )

    return out


# ---------------------------------------------------------------------------
# Convenience: module-level generator (used by video_stream_api)
# ---------------------------------------------------------------------------

def generate_frames(camera_index: int = 0) -> Generator[bytes, None, None]:
    """
    Generator that yields raw JPEG bytes (no MJPEG envelope).

    Callers that need the full multipart MJPEG envelope should wrap the
    output in the appropriate Content-Type headers themselves.

    Example (FastAPI)
    -----------------
        from vision.webcam_stream import generate_frames
        from fastapi.responses import StreamingResponse

        def mjpeg_generator():
            for frame in generate_frames():
                yield (b"--frame\\r\\n"
                       b"Content-Type: image/jpeg\\r\\n\\r\\n"
                       + frame + b"\\r\\n")

        return StreamingResponse(mjpeg_generator(),
                                 media_type="multipart/x-mixed-replace; boundary=frame")
    """
    with WebcamStream(camera_index=camera_index) as stream:
        for jpeg, _ in stream:
            yield jpeg
