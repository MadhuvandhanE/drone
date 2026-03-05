"""
Telemetry Simulator
===================
Generates realistic simulated drone telemetry data.

The simulator maintains internal state so that successive calls
produce a smooth, continuous trajectory rather than random jumps.
The drone follows a pre-defined patrol loop over a flood-affected
region near Chennai (Anna Nagar area).
"""

import math
import random
from datetime import datetime, timezone

from models.telemetry_model import TelemetryData


# ---------------------------------------------------------------------------
# Pre-defined patrol waypoints (lat, lon) over flood-affected area
# ---------------------------------------------------------------------------
PATROL_WAYPOINTS: list[tuple[float, float]] = [
    (13.0827, 80.2707),   # WP 0 – Start / Rally Point
    (13.0835, 80.2715),   # WP 1
    (13.0842, 80.2725),   # WP 2
    (13.0850, 80.2718),   # WP 3
    (13.0855, 80.2705),   # WP 4
    (13.0848, 80.2695),   # WP 5
    (13.0840, 80.2688),   # WP 6
    (13.0832, 80.2695),   # WP 7
    (13.0828, 80.2700),   # WP 8
    (13.0827, 80.2707),   # WP 9 – Loop back to start
]


class DroneSimulator:
    """
    Stateful drone telemetry simulator.

    Each call to `get_telemetry()` advances the drone along the
    patrol route and returns a `TelemetryData` snapshot.
    """

    def __init__(self, drone_id: str = "VANGUARD-01") -> None:
        self.drone_id = drone_id

        # Position state
        self._waypoint_index: int = 0
        self._progress: float = 0.0          # 0..1 between waypoints
        self._step_size: float = 0.05         # how far to advance per tick

        # Flight parameters
        self._base_altitude: float = 45.0
        self._base_speed: float = 12.0
        self._battery: float = 100.0
        self._battery_drain: float = 0.15     # per tick

        # Signal simulation
        self._base_signal: int = 92

        # Mission state
        self._mission_active: bool = True
        self._ticks: int = 0

        # Computer Vision Modules
        # Once RTSP is available, this will point to e.g. "rtsp://192.168.144.108:554/stream=0"
        from vision.phantom_depth import PhantomDepthEstimator
        self.phantom_vision = PhantomDepthEstimator(stream_url="mock://rx10_rtsp")
        self.phantom_vision.connect_stream()
        
        # Real YOLO Vision Engine (lazy - started on demand via /vision/start)
        from vision.yolo_detector import JARVISVisionEngine
        self.yolo_vision = JARVISVisionEngine()

    # ------------------------------------------------------------------
    # Public API
    # ------------------------------------------------------------------

    def get_telemetry(self) -> TelemetryData:
        """Advance simulation by one tick and return the current state."""
        self._advance()
        lat, lon = self._interpolated_position()

        return TelemetryData(
            drone_id=self.drone_id,
            latitude=round(lat, 6),
            longitude=round(lon, 6),
            altitude=round(self._jittered_altitude(), 1),
            speed=round(self._jittered_speed(), 1),
            battery=max(int(self._battery), 0),
            mode=self._current_mode(),
            current_waypoint=self._waypoint_index + 1,   # 1-indexed for UI
            total_waypoints=len(PATROL_WAYPOINTS),
            signal_strength=self._jittered_signal(),
            water_depth=round(self._simulated_water_depth(), 2),
            timestamp=datetime.now(timezone.utc),
        )

    def get_mission_status(self) -> dict:
        """Return high-level mission progress info."""
        return {
            "current_waypoint": self._waypoint_index + 1,
            "total_waypoints": len(PATROL_WAYPOINTS),
            "mission_status": "ACTIVE" if self._mission_active else "COMPLETED",
            "elapsed_ticks": self._ticks,
            "battery": max(int(self._battery), 0),
        }

    def get_detections(self) -> dict:
        """
        Return victim detections.
        If YOLO vision engine is running, pulls real detections from the camera stream.
        Otherwise, falls back to simulated victim detections.
        """
        victims = []
        
        # 1. Use Real YOLO Computer Vision (if active)
        if self.yolo_vision and self.yolo_vision.is_running:
            real_victims = self.yolo_vision.get_latest_victims()
            lat, lon = self._interpolated_position()
            
            for i, v in enumerate(real_victims):
                # We project the physical coordinates based on the drone's position + dummy offset
                offset_lat = random.uniform(-0.0001, 0.0001)
                offset_lon = random.uniform(-0.0001, 0.0001)
                
                victims.append({
                    "id": f"YOLO-{self._ticks:04d}-{i}",
                    "lat": round(lat + offset_lat, 6),
                    "lon": round(lon + offset_lon, 6),
                    "confidence": v["confidence"],
                    "label": v["label"],
                    "box": v["box"],
                    "timestamp": datetime.now(timezone.utc).isoformat(),
                })
        
        # 2. Fallback to Simulated Vision
        else:
            detection_count = random.randint(2, 4)
            for i in range(detection_count):
                wp = PATROL_WAYPOINTS[random.randint(0, len(PATROL_WAYPOINTS) - 1)]
                victims.append({
                    "id": f"DET-{self._ticks:04d}-{i}",
                    "lat": round(wp[0] + random.uniform(-0.0005, 0.0005), 6),
                    "lon": round(wp[1] + random.uniform(-0.0005, 0.0005), 6),
                    "confidence": round(random.uniform(0.75, 0.98), 2),
                    "label": "person",
                    "timestamp": datetime.now(timezone.utc).isoformat(),
                })
                
        return {
            "victims": victims,
            "total_count": len(victims),
        }

    # ------------------------------------------------------------------
    # Internal helpers
    # ------------------------------------------------------------------

    def _advance(self) -> None:
        """Move the drone forward along the patrol path."""
        self._ticks += 1
        self._progress += self._step_size

        if self._progress >= 1.0:
            self._progress -= 1.0
            self._waypoint_index += 1
            if self._waypoint_index >= len(PATROL_WAYPOINTS) - 1:
                self._waypoint_index = 0          # loop
                self._battery = 100.0             # simulated battery swap

        # Drain battery
        self._battery = max(self._battery - self._battery_drain, 0)

    def _interpolated_position(self) -> tuple[float, float]:
        """Linear interpolation between current and next waypoint."""
        idx = self._waypoint_index
        next_idx = (idx + 1) % len(PATROL_WAYPOINTS)

        lat0, lon0 = PATROL_WAYPOINTS[idx]
        lat1, lon1 = PATROL_WAYPOINTS[next_idx]

        lat = lat0 + (lat1 - lat0) * self._progress
        lon = lon0 + (lon1 - lon0) * self._progress
        return lat, lon

    def _jittered_altitude(self) -> float:
        return self._base_altitude + random.uniform(-2.0, 2.0)

    def _jittered_speed(self) -> float:
        return max(0.0, self._base_speed + random.uniform(-1.5, 1.5))

    def _jittered_signal(self) -> int:
        return max(0, min(100, self._base_signal + random.randint(-5, 3)))

    def _current_mode(self) -> str:
        if self._battery <= 15:
            return "RTL"          # Return to Launch when battery is low
        return "AUTO"

    def _simulated_water_depth(self) -> float:
        """
        Water depth is not provided by MAVLink telemetry in JARVIS.
        Instead, the backend uses the "Phantom Algorithm" analyzing the
        RTSP camera feed refractions.
        """
        return self.phantom_vision.process_frame_for_depth()
