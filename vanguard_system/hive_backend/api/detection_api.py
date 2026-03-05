"""
Detection API Router
====================
Exposes the GET /detections endpoint.

Returns live YOLO person-detection results from the active webcam / drone
camera stream.  If the vision pipeline is not running, returns an empty list.

Each detection follows the format:
    {
        "label":      "person",
        "confidence": 0.87,
        "bbox":       [x, y, width, height]   ← pixel coords, top-left origin
    }
"""

from fastapi import APIRouter

router = APIRouter(tags=["Detections"])


@router.get(
    "/detections",
    summary="Get live YOLO detections",
    description=(
        "Returns person detections from the most recent YOLO inference frame. "
        "Bounding boxes are in [x, y, width, height] format (pixel coordinates). "
        "Start the vision pipeline first via POST /video/start."
    ),
)
async def get_detections() -> dict:
    """Return the latest YOLO person detections from the live stream."""
    # Import here (deferred) to avoid circular imports at module load time.
    from api.stream_api import LIVE_DETECTIONS
    return {"detections": LIVE_DETECTIONS}
