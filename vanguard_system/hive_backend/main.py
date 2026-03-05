"""
JARVIS Hive Backend – Main Application
=======================================

FastAPI server that acts as the central processing hub
for the VANGUARD drone rescue system.

Phase 1: Serves simulated telemetry, mission, and detection data.
Future:  Will integrate MAVLink parsing, YOLO inference, and
         water-depth analysis modules.

Run with:
    uvicorn main:app --host 0.0.0.0 --port 8000 --reload
"""

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from telemetry_simulator import DroneSimulator
from api.telemetry_api import router as telemetry_router
from api.mission_api import router as mission_router
from api.detection_api import router as detection_router
from api.vision_api import router as vision_router
from api.stream_api import router as stream_router
from api.location_api import router as location_router

# ---------------------------------------------------------------------------
# Application factory
# ---------------------------------------------------------------------------

app = FastAPI(
    title="JARVIS Hive Backend",
    description=(
        "Ground processing station API for the VANGUARD disaster-rescue drone. "
        "Provides telemetry, mission status, and AI detection endpoints."
    ),
    version="0.1.0",
    docs_url="/docs",
    redoc_url="/redoc",
)

# ---------------------------------------------------------------------------
# CORS – allow the Flutter app and any local dev tools to connect
# ---------------------------------------------------------------------------

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],         # tighten in production
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# ---------------------------------------------------------------------------
# Shared simulator instance
# ---------------------------------------------------------------------------

simulator = DroneSimulator(drone_id="VANGUARD-01")

# ---------------------------------------------------------------------------
# Register routers
# ---------------------------------------------------------------------------

app.include_router(telemetry_router)
app.include_router(mission_router)
app.include_router(detection_router)
app.include_router(vision_router)
app.include_router(stream_router)
app.include_router(location_router)


# ---------------------------------------------------------------------------
# Root health-check
# ---------------------------------------------------------------------------

@app.get("/", tags=["Health"])
async def root() -> dict:
    """Health-check endpoint."""
    return {
        "system": "JARVIS Hive Backend",
        "status": "OPERATIONAL",
        "version": "0.1.0",
        "phase": 1,
    }


# ---------------------------------------------------------------------------
# Convenience aliases  (spec-compatible flat URLs)
# ---------------------------------------------------------------------------

@app.get("/video_feed", tags=["Video Stream"], include_in_schema=True,
         summary="MJPEG live feed (alias for /video/feed)")
async def video_feed_alias():
    """
    Top-level alias for the MJPEG vision stream — serves the same
    annotated webcam stream as /video/feed.

    Flutter usage:
        Image.network('http://localhost:8000/video_feed')

    Browser usage:
        http://localhost:8000/video_feed
    """
    from api.stream_api import video_feed
    return await video_feed()
