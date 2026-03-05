"""
Telemetry Data Model
====================
Pydantic model representing the drone telemetry payload.
All fields are typed and documented for clarity.
"""

from pydantic import BaseModel, Field
from datetime import datetime


class TelemetryData(BaseModel):
    """Complete telemetry snapshot from the drone."""

    drone_id: str = Field(
        ...,
        description="Unique identifier for the drone unit",
        examples=["VANGUARD-01"],
    )
    latitude: float = Field(
        ...,
        description="Current latitude in decimal degrees",
        ge=-90,
        le=90,
    )
    longitude: float = Field(
        ...,
        description="Current longitude in decimal degrees",
        ge=-180,
        le=180,
    )
    altitude: float = Field(
        ...,
        description="Altitude above ground level in metres",
        ge=0,
    )
    speed: float = Field(
        ...,
        description="Ground speed in m/s",
        ge=0,
    )
    battery: int = Field(
        ...,
        description="Battery level percentage",
        ge=0,
        le=100,
    )
    mode: str = Field(
        ...,
        description="Current flight mode (e.g. AUTO, LOITER, RTL)",
    )
    current_waypoint: int = Field(
        ...,
        description="Index of the waypoint the drone is currently heading to",
        ge=0,
    )
    total_waypoints: int = Field(
        ...,
        description="Total number of waypoints in the active mission",
        ge=0,
    )
    signal_strength: int = Field(
        ...,
        description="Communication link signal strength percentage",
        ge=0,
        le=100,
    )
    water_depth: float = Field(
        ...,
        description="Estimated water depth at the drone's current position in metres",
        ge=0,
    )
    timestamp: datetime = Field(
        ...,
        description="UTC timestamp of this telemetry snapshot",
    )
