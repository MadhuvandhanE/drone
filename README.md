# JARVIS — Rescue Intelligence System

> Autonomous drone system that locates flood victims using AI and deploys a rescue drone to deliver emergency supplies.

---

## How It Works

1. A **large surveillance drone** patrols the flood zone and streams live video to the ground computer
2. **YOLOv8** detects people in the frame in real time
3. The victim's **GPS coordinates** are estimated from the camera position
4. An **A\* path planning** algorithm calculates the safest route through the flood zone
5. A **small rescue drone** follows the computed path autonomously and drops supplies at the victim's location
6. The **JARVIS mobile app** shows the operator the live feed, victim locations, and rescue path on a map

```
Surveillance Drone  →  Hive Computer  →  YOLO Detection  →  Victim GPS
                                                                  ↓
                                                          A* Path Planning
                                                                  ↓
                                                         Rescue Drone Dispatch
```

---

## Project Structure

```
vanguard_system/
├── docs/                        ← Project documentation
│   ├── architecture.md
│   └── project_overview.md
├── hive_backend/                ← Python FastAPI backend (run on ground computer)
│   ├── main.py                  ← Server entry point
│   ├── requirements.txt         ← Python dependencies
│   ├── .env.example             ← Copy to .env and configure
│   ├── telemetry_simulator.py   ← Simulated drone telemetry
│   ├── yolov8n.pt               ← YOLOv8 nano weights
│   ├── api/
│   │   ├── stream_api.py        ← MJPEG /video/feed endpoint
│   │   ├── detection_api.py     ← GET /detections (live YOLO results)
│   │   ├── telemetry_api.py     ← GET /telemetry
│   │   ├── mission_api.py       ← GET /mission
│   │   └── vision_api.py        ← POST /vision/start|stop
│   ├── vision/
│   │   ├── yolo_detector.py     ← AerialYOLODetector (aerial-tuned YOLO)
│   │   ├── webcam_stream.py     ← WebcamStream capture module
│   │   └── phantom_depth.py     ← Simulated water depth estimator
│   └── models/
│       ├── detection_model.py   ← Pydantic detection schemas
│       └── telemetry_model.py   ← Pydantic telemetry schemas
└── mobile_app/
    └── jarvis_app/              ← Flutter dashboard app
        └── lib/
            ├── screens/         ← Dashboard, Map, Mission screens
            ├── widgets/         ← LiveFeedPanel, DroneMapPanel, TelemetryGrid
            ├── services/        ← TelemetryService (polling)
            ├── models/          ← Data models
            └── core/            ← Config, API client
```

---

## Development Setup

> During development the laptop webcam simulates the drone camera.  
> No drone hardware required to run the system.

### Requirements

- Python 3.11+
- Flutter 3.x
- NVIDIA GPU with CUDA (optional — CPU works fine for dev)

---

### 1 — Backend (Hive Computer)

```bash
cd vanguard_system/hive_backend

# Create and activate virtual environment
python -m venv .venv
.venv\Scripts\activate        # Windows
# source .venv/bin/activate   # Linux / macOS

# Install dependencies
pip install -r requirements.txt

# (Optional) CUDA support for RTX 3060
pip install torch torchvision --index-url https://download.pytorch.org/whl/cu121

# Copy config
cp .env.example .env

# Start the server
uvicorn main:app --host 0.0.0.0 --port 8000 --reload
```

API docs available at: `http://localhost:8000/docs`

---

### 2 — Start the Vision Pipeline

The Flutter app does this automatically on launch.  
To start manually:

```bash
curl -X POST http://localhost:8000/video/start \
     -H "Content-Type: application/json" \
     -d '{"source": "0"}'
```

View raw stream in browser: `http://localhost:8000/video/feed`

---

### 3 — Flutter App

```bash
cd vanguard_system/mobile_app/jarvis_app

flutter pub get
flutter run -d chrome        # web (easiest for dev)
# flutter run -d windows     # native Windows desktop
```

> Make sure the backend is running before launching the app.

---

## API Endpoints

| Method | Endpoint | Description |
|---|---|---|
| `POST` | `/video/start` | Start webcam + YOLO pipeline |
| `POST` | `/video/stop` | Stop the pipeline |
| `GET` | `/video/feed` | MJPEG live stream |
| `GET` | `/video/status` | Pipeline running status |
| `GET` | `/detections` | Latest YOLO person detections (JSON) |
| `GET` | `/telemetry` | Drone telemetry data |
| `GET` | `/mission` | Mission status |
| `GET` | `/docs` | Swagger interactive API docs |

---

## YOLO Detection Config

Tuned for aerial/drone footage — not standard ground-level settings:

| Parameter | Value | Reason |
|---|---|---|
| Model | `yolov8n.pt` | Fast nano — real-time on RTX 3060 |
| Classes | `[0]` person only | Eliminate non-human false positives |
| `imgsz` | `960` | High res preserves small aerial targets |
| `conf` | `0.35` | Catches partially visible / distant victims |
| `iou` | `0.50` | Standard NMS threshold |
| Device | `cuda` / `cpu` | Auto-detected |

Bounding boxes are smoothed with EMA (α = 0.4) to reduce jitter from camera vibration.

---

## Connecting the TX10 Camera (Future)

When the Peeper/Skydroid TX10 drone camera is available, change the stream source from webcam to RTSP:

```bash
curl -X POST http://localhost:8000/video/start \
     -H "Content-Type: application/json" \
     -d '{"source": "rtsp://192.168.144.108:554/stream=0"}'
```

No other code changes needed.

---

## Roadmap

| Feature | Status |
|---|---|
| Webcam → YOLO → MJPEG → Flutter | ✅ Done |
| Live telemetry simulation | ✅ Done |
| Interactive drone map | ✅ Done |
| TX10 RTSP drone camera | 🔲 Pending hardware |
| GPS victim coordinate projection | 🔲 Pending |
| Victim pins on map | 🔲 Pending |
| A\* path planning algorithm | 🔲 Pending |
| Rescue drone MAVLink dispatch | 🔲 Pending |

---

## Team

Built by the JARVIS rescue team. Contributions welcome — see open issues for what to work on next.
