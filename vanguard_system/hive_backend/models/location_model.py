"""
Drone Location Models
=====================
Pydantic models for the real-time GPS location endpoints.

Phone simulator  →  POST /update_location  (LocationUpdate)
Flutter map      →  GET  /drone_location   (DroneLocation)
"""

from pydantic import BaseModel, Field
from datetime import datetime, timezone


class LocationUpdate(BaseModel):
    """Payload sent by the phone GPS simulator (or real phone app)."""

    latitude: float = Field(
        ...,
        description="GPS latitude in decimal degrees",
        ge=-90,
        le=90,
        examples=[13.0827],
    )
    longitude: float = Field(
        ...,
        description="GPS longitude in decimal degrees",
        ge=-180,
        le=180,
        examples=[80.2707],
    )
    accuracy: float | None = Field(
        None,
        description="Horizontal accuracy radius in metres (smaller = better)",
        ge=0,
    )
    altitude: float | None = Field(
        None,
        description="Altitude above WGS-84 ellipsoid in metres",
    )
    heading: float | None = Field(
        None,
        description="True heading in degrees (0–359)",
        ge=0,
        lt=360,
    )
    speed: float | None = Field(
        None,
        description="Ground speed in m/s",
        ge=0,
    )
    source: str = Field(
        "phone_gps",
        description="Tag identifying the data origin (phone_gps | rtk | simulated)",
    )


class DroneLocation(BaseModel):
    """Latest drone position returned by GET /drone_location."""

    latitude: float
    longitude: float
    accuracy: float | None = None
    altitude: float | None = None
    heading: float | None = None
    speed: float | None = None
    timestamp: str
    source: str = "phone_gps"

    @classmethod
    def default(cls) -> "DroneLocation":
        """Default position (Chennai) used before the first GPS update arrives."""
        return cls(
            latitude=13.0827,
            longitude=80.2707,
            timestamp=datetime.now(timezone.utc).isoformat(),
            source="default",
        )
