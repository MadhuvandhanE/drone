from fastapi import APIRouter
from pydantic import BaseModel

router = APIRouter(
    prefix="/vision",
    tags=["Computer Vision"],
)

class VisionStartRequest(BaseModel):
    stream_url: str

@router.post("/start")
async def start_vision_engine(req: VisionStartRequest):
    """
    Start the YOLO backend vision pipeline in a background thread.
    Pass 'http://172.16.127.190:8080/video' for IP Webcam, or '0' for laptop webcam.
    """
    from main import simulator  # deferred to avoid circular import
    simulator.yolo_vision.start(req.stream_url)
    return {"status": "SUCCESS", "message": f"Vision engine starting on {req.stream_url} (model loading in background)"}

@router.post("/stop")
async def stop_vision_engine():
    """Stop the YOLO vision pipeline."""
    from main import simulator  # deferred to avoid circular import
    simulator.yolo_vision.stop()
    return {"status": "SUCCESS", "message": "Vision tracking stopped."}
