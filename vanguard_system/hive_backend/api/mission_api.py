"""
Mission API Router
==================
Exposes the GET /mission endpoint.
Returns the current mission progress and status.
"""

from fastapi import APIRouter

router = APIRouter(tags=["Mission"])


@router.get(
    "/mission",
    summary="Get mission progress",
    description="Returns current waypoint, total waypoints, and mission status.",
)
async def get_mission() -> dict:
    from main import simulator
    return simulator.get_mission_status()
