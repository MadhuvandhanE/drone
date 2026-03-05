"""
Video Source Abstraction
========================
Unified cv2.VideoCapture wrapper that handles:

• Webcam by index       (0, 1, 2 …)
• RTSP stream from IP camera / phone app (rtsp://...)
• HTTP MJPEG URL        (http://...)
• Local video file      (path/to/file.mp4)

Why this exists
---------------
cv2.VideoCapture with an RTSP URL drops frames silently and never
recovers after a network hiccup.  This class adds:

  • graceful reconnection on read failure
  • correct backend selection (CAP_DSHOW on Windows for webcams)
  • RTSP-optimised transport flag (tcp > udp for LAN streaming)
  • human-readable source label for HUD overlay

Phone RTSP setup
----------------
Install one of these free apps on the Android phone:

  • IP Webcam (Pavel Khlebovich) — simple, no sign-up
  • DroidCam                     — also serves audio

In IP Webcam press "Start server". The app shows:

    http://192.168.1.X:8080/video

RTSP is available at:
    rtsp://192.168.1.X:8080/h264_ulaw.sdp

Pass this URL as the source when starting the stream:

    POST /video/start  {"source": "rtsp://192.168.1.X:8080/h264_ulaw.sdp"}

For DroidCam the default RTSP URL is:
    rtsp://192.168.1.X:4747/mjpegfeed
"""

import cv2
import platform
import threading
import time
import logging

log = logging.getLogger(__name__)


class VideoSource:
    """
    Thread-safe video capture wrapper with automatic reconnection.

    Parameters
    ----------
    source : int | str
        Webcam index (0, 1, …), or any URL / path accepted by
        cv2.VideoCapture.
    reconnect : bool
        If True (default), re-opens the source when a read fails.
    reconnect_delay : float
        Seconds to wait between reconnection attempts.
    """

    def __init__(
        self,
        source: int | str,
        reconnect: bool = True,
        reconnect_delay: float = 2.0,
    ):
        # Normalise: "0" → 0, "1" → 1, etc.
        if isinstance(source, str) and source.isdigit():
            source = int(source)

        self.source = source
        self.reconnect = reconnect
        self.reconnect_delay = reconnect_delay

        self._cap: cv2.VideoCapture | None = None
        self._lock = threading.Lock()
        self._connect()

    # ── Private ───────────────────────────────────────────────────────────────

    def _connect(self):
        """Open (or re-open) the video source."""
        if self._cap is not None:
            try:
                self._cap.release()
            except Exception:
                pass

        src = self.source

        if isinstance(src, int):
            # Webcam — use DirectShow backend on Windows for low latency
            backend = cv2.CAP_DSHOW if platform.system() == "Windows" else 0
            cap = cv2.VideoCapture(src, backend)
        elif isinstance(src, str) and (
            src.startswith("rtsp://") or src.startswith("rtsps://")
        ):
            # RTSP — force TCP transport (avoids UDP packet loss on LAN)
            cap = cv2.VideoCapture(
                src + "?tcp" if "?" not in src else src,
                cv2.CAP_FFMPEG,
            )
            # Reduce receive buffer to cut latency (at cost of resilience)
            cap.set(cv2.CAP_PROP_BUFFERSIZE, 1)
        else:
            # HTTP MJPEG / file path
            cap = cv2.VideoCapture(src)

        if cap.isOpened():
            log.info("[VideoSource] Opened: %s", self.source_label)
        else:
            log.warning("[VideoSource] Could not open: %s", self.source_label)

        self._cap = cap

    # ── Public API ────────────────────────────────────────────────────────────

    def configure(self, width: int = 640, height: int = 480, fps: int = 25):
        """Set preferred capture resolution / frame rate (hint only)."""
        with self._lock:
            if self._cap and self._cap.isOpened():
                self._cap.set(cv2.CAP_PROP_FRAME_WIDTH, width)
                self._cap.set(cv2.CAP_PROP_FRAME_HEIGHT, height)
                self._cap.set(cv2.CAP_PROP_FPS, fps)
                self._cap.set(cv2.CAP_PROP_BUFFERSIZE, 1)

    def read(self) -> tuple[bool, cv2.Mat | None]:
        """
        Read the next frame.

        Returns
        -------
        (True, frame)  on success
        (False, None)  on failure / not yet reconnected
        """
        with self._lock:
            if self._cap is None or not self._cap.isOpened():
                if self.reconnect:
                    log.warning(
                        "[VideoSource] Source not open, reconnecting in %.1fs …",
                        self.reconnect_delay,
                    )
                    time.sleep(self.reconnect_delay)
                    self._connect()
                return False, None

            ok, frame = self._cap.read()

            if not ok:
                if self.reconnect:
                    log.warning(
                        "[VideoSource] Read failed on %s, reconnecting …",
                        self.source_label,
                    )
                    time.sleep(self.reconnect_delay)
                    self._connect()
                return False, None

            return True, frame

    def release(self):
        """Release the underlying VideoCapture."""
        with self._lock:
            if self._cap:
                self._cap.release()
                self._cap = None
        log.info("[VideoSource] Released: %s", self.source_label)

    def is_open(self) -> bool:
        with self._lock:
            return self._cap is not None and self._cap.isOpened()

    # ── Properties ────────────────────────────────────────────────────────────

    @property
    def is_rtsp(self) -> bool:
        return isinstance(self.source, str) and self.source.startswith("rtsp")

    @property
    def is_webcam(self) -> bool:
        return isinstance(self.source, int)

    @property
    def source_label(self) -> str:
        """Human-readable label for HUD / logging."""
        if isinstance(self.source, int):
            return f"Webcam {self.source}"
        if self.is_rtsp:
            # strip credentials from display label
            url = str(self.source)
            if "@" in url:
                proto = url.split("://")[0]
                rest  = url.split("@", 1)[1]
                return f"{proto}://***@{rest}"
            return url
        return str(self.source)
