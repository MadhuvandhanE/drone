"""
Drone Location API
==================
Endpoints for real-time GPS location sharing between the phone simulator
(or future real drone) and the Flutter dashboard.

POST /update_location   — phone / drone pushes its GPS position
GET  /drone_location    — Flutter map polls for the latest position
"""

import logging
from datetime import datetime, timezone

from fastapi import APIRouter
from models.location_model import DroneLocation, LocationUpdate

log = logging.getLogger(__name__)

router = APIRouter(tags=["Drone Location"])

# ---------------------------------------------------------------------------
# In-memory location store (single drone; extend to dict for multi-drone)
# ---------------------------------------------------------------------------

_current_location: DroneLocation = DroneLocation.default()


# ---------------------------------------------------------------------------
# Endpoints
# ---------------------------------------------------------------------------

@router.post(
    "/update_location",
    summary="Phone → Backend: push GPS position",
    response_model=dict,
)
async def update_location(update: LocationUpdate):
    """
    Called by the phone GPS client (phone_client.py) every second.

    Stores the latest drone position so the Flutter map can retrieve it.

    Example phone call::

        curl -X POST http://192.168.1.X:8000/update_location \\
             -H "Content-Type: application/json" \\
             -d '{"latitude":13.0827,"longitude":80.2707}'
    """
    global _current_location

    _current_location = DroneLocation(
        latitude=update.latitude,
        longitude=update.longitude,
        accuracy=update.accuracy,
        altitude=update.altitude,
        heading=update.heading,
        speed=update.speed,
        timestamp=datetime.now(timezone.utc).isoformat(),
        source=update.source,
    )

    log.debug(
        "Location updated → %.6f, %.6f  acc=%.1fm  src=%s",
        update.latitude,
        update.longitude,
        update.accuracy or 0,
        update.source,
    )

    return {
        "status": "OK",
        "lat": _current_location.latitude,
        "lng": _current_location.longitude,
        "ts":  _current_location.timestamp,
    }


@router.get(
    "/drone_location",
    summary="Flutter map ← Backend: fetch latest GPS position",
    response_model=DroneLocation,
)
async def get_drone_location():
    """
    Returns the most recent GPS position received from the phone.

    Flutter polls this endpoint every second to update the drone marker.

    If no update has been received yet, returns the default Chennai position
    so the map always has something to centre on.
    """
    return _current_location
