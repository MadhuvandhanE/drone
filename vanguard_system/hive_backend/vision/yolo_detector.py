"""
JARVIS Vision Engine – Aerial YOLO Detector
============================================
Provides two classes:

  AerialYOLODetector
      Stateless single-frame detector tuned for top-down drone footage.
      Accepts a raw OpenCV BGR frame and returns structured detections.

      YOLO settings (aerial-optimised):
        • classes  = [0]   (person only)
        • imgsz    = 960   (high res → small targets preserved)
        • conf     = 0.35  (low threshold → partially visible victims caught)
        • iou      = 0.50  (standard NMS)
        • device   = cuda if available, else cpu

      Bounding-box smoothing:
        Exponential Moving Average (EMA) is applied per tracked bounding box
        across consecutive frames to dampen jitter from aerial camera vibration.
        Alpha = 0.4  (higher = more responsive, lower = smoother)

  JARVISVisionEngine       ← kept for backward compatibility
      Background-thread wrapper used by the telemetry simulator.
      Internally delegates YOLO work to AerialYOLODetector.
"""

from __future__ import annotations

import os
import threading
import time
from typing import Optional

import cv2
import numpy as np
import torch

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

_MODEL_FILE   = os.path.join(os.path.dirname(os.path.dirname(__file__)), "yolov8n.pt")
_CLASSES      = [0]           # COCO class 0 = person
_IMGSZ        = 960           # high-res input for small aerial targets
_CONF_THRESH  = 0.35          # lower than default; catches partially visible victims
_IOU_THRESH   = 0.50          # NMS suppression threshold
_EMA_ALPHA    = 0.40          # bounding-box smoothing factor (0=frozen, 1=raw)

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def _best_device() -> str:
    """Return 'cuda' when an NVIDIA GPU is present, otherwise 'cpu'."""
    return "cuda" if torch.cuda.is_available() else "cpu"


def _xyxy_to_xywh(x1: float, y1: float, x2: float, y2: float) -> list[float]:
    """Convert [x1,y1,x2,y2] to [x, y, width, height] (top-left origin)."""
    return [x1, y1, x2 - x1, y2 - y1]


# ---------------------------------------------------------------------------
# AerialYOLODetector
# ---------------------------------------------------------------------------

class AerialYOLODetector:
    """
    Single-frame person detector tuned for aerial drone footage.

    Usage
    -----
        detector = AerialYOLODetector()
        detector.load()

        # Per frame:
        detections = detector.detect(frame)
        # → [{"label": "person", "confidence": 0.87, "bbox": [x, y, w, h]}, ...]
    """

    def __init__(self, model_path: str = _MODEL_FILE):
        self._model_path = model_path
        self._model      = None
        self._device     = _best_device()
        # EMA state: maps a stable slot index to smoothed bbox [x, y, w, h]
        self._smooth: dict[int, list[float]] = {}

    # ── Public API ────────────────────────────────────────────────────────────

    def load(self) -> None:
        """Load the YOLO model.  Safe to call multiple times (no-op after first)."""
        if self._model is not None:
            return
        from ultralytics import YOLO
        print(f"[AERIAL YOLO] Loading model from '{self._model_path}' on {self._device} …")
        self._model = YOLO(self._model_path)
        self._model.to(self._device)
        print(f"[AERIAL YOLO] Model ready ✓  (imgsz={_IMGSZ}, conf={_CONF_THRESH}, iou={_IOU_THRESH})")

    def detect(self, frame: np.ndarray) -> list[dict]:
        """
        Run inference on one BGR frame.

        Returns
        -------
        list of:
            {
                "label":      "person",
                "confidence": 0.92,        # rounded to 2 d.p.
                "bbox":       [x, y, w, h] # pixel coords, top-left origin
            }
        """
        if self._model is None:
            self.load()

        results = self._model.predict(
            frame,
            classes   = _CLASSES,
            imgsz     = _IMGSZ,
            conf      = _CONF_THRESH,
            iou       = _IOU_THRESH,
            device    = self._device,
            verbose   = False,
        )

        raw_bboxes: list[list[float]] = []
        raw_confs:  list[float]       = []

        for r in results:
            for box in r.boxes:
                x1, y1, x2, y2 = [float(v) for v in box.xyxy[0]]
                raw_bboxes.append(_xyxy_to_xywh(x1, y1, x2, y2))
                raw_confs.append(float(box.conf[0]))

        # Apply bounding-box EMA smoothing
        smoothed = self._smooth_bboxes(raw_bboxes)

        return [
            {
                "label":      "person",
                "confidence": round(conf, 2),
                "bbox":       [round(v, 1) for v in bbox],
            }
            for bbox, conf in zip(smoothed, raw_confs)
        ]

    def reset_smoothing(self) -> None:
        """Clear the EMA state (call when switching camera or after a gap)."""
        self._smooth.clear()

    # ── Internal ──────────────────────────────────────────────────────────────

    def _smooth_bboxes(self, bboxes: list[list[float]]) -> list[list[float]]:
        """
        Apply EMA smoothing per detection slot (positional matching).

        New slots are seeded with the raw value on their first frame.
        Stale slots beyond the current detection count are evicted.
        """
        n = len(bboxes)

        # Evict slots beyond current count
        for k in [k for k in self._smooth if k >= n]:
            del self._smooth[k]

        smoothed: list[list[float]] = []
        for i, bbox in enumerate(bboxes):
            if i in self._smooth:
                prev = self._smooth[i]
                ema  = [
                    _EMA_ALPHA * b + (1.0 - _EMA_ALPHA) * p
                    for b, p in zip(bbox, prev)
                ]
            else:
                ema = bbox[:]   # seed with raw value on first appearance

            self._smooth[i] = ema
            smoothed.append(ema)

        return smoothed


# ---------------------------------------------------------------------------
# JARVISVisionEngine  (backward-compatible wrapper)
# ---------------------------------------------------------------------------

class JARVISVisionEngine:
    """
    Background-thread vision engine used by the telemetry simulator.
    Delegates inference to AerialYOLODetector.
    """

    def __init__(self):
        self.stream_url: str                          = "0"
        self.is_running: bool                         = False
        self.current_frame: Optional[np.ndarray]      = None
        self.latest_detections: list[dict]            = []
        self._thread: Optional[threading.Thread]      = None
        self._detector                                = AerialYOLODetector()

    # ── Public API ────────────────────────────────────────────────────────────

    def start(self, stream_url: str) -> None:
        """Start the vision pipeline on the given stream URL or camera index."""
        if self.is_running:
            self.stop()

        self.stream_url        = stream_url
        self.is_running        = True
        self.latest_detections = []
        self._detector.reset_smoothing()

        self._thread = threading.Thread(
            target=self._run, daemon=True, name="jarvis-yolo"
        )
        self._thread.start()
        print(f"[VISION ENGINE] Started → {stream_url}")

    def stop(self) -> None:
        """Stop the vision thread gracefully."""
        self.is_running = False
        if self._thread and self._thread.is_alive():
            self._thread.join(timeout=3)
        self._thread = None
        print("[VISION ENGINE] Stopped.")

    def get_latest_victims(self) -> list[dict]:
        """Return a snapshot of the latest detections."""
        return list(self.latest_detections)

    # ── Internal ──────────────────────────────────────────────────────────────

    def _run(self) -> None:
        """Background loop: grab frames → AerialYOLODetector → update state."""
        self._detector.load()

        src = int(self.stream_url) if self.stream_url.isdigit() else self.stream_url
        cap = cv2.VideoCapture(src)
        cap.set(cv2.CAP_PROP_BUFFERSIZE, 1)

        if not cap.isOpened():
            print(f"[VISION ENGINE] ERROR: cannot open → {src}")
            self.is_running = False
            return

        print(f"[VISION ENGINE] Stream opened → {src}")
        interval = 1.0 / 15   # target 15 fps max

        while self.is_running:
            t0 = time.perf_counter()

            ret, frame = cap.read()
            if not ret:
                time.sleep(0.05)
                continue

            self.current_frame     = frame
            self.latest_detections = self._detector.detect(frame)

            elapsed = time.perf_counter() - t0
            time.sleep(max(0.0, interval - elapsed))

        cap.release()
        print("[VISION ENGINE] Stream released.")
