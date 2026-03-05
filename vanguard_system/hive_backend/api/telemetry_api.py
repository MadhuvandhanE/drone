"""
Telemetry API Router
====================
Exposes the GET /telemetry endpoint.
Returns the latest simulated drone telemetry snapshot.
"""

from fastapi import APIRouter

from models.telemetry_model import TelemetryData

router = APIRouter(tags=["Telemetry"])


# The simulator instance is injected via app.state in main.py
# We import it lazily inside the endpoint to avoid circular imports.


@router.get(
    "/telemetry",
    response_model=TelemetryData,
    summary="Get current drone telemetry",
    description="Returns a single telemetry snapshot. Each call advances the simulation by one tick.",
)
async def get_telemetry() -> TelemetryData:
    from main import simulator
    return simulator.get_telemetry()
