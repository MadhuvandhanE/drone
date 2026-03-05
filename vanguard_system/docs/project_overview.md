# JARVIS Rescue Intelligence System

## Project Idea

Autonomous drones assist rescue teams during flood disasters by identifying stranded individuals and delivering emergency supplies. JARVIS (Joint Autonomous Rescue & Vision Intelligence System) combines aerial surveillance, real-time AI person detection, and autonomous drone dispatch into a unified rescue coordination platform.

---

## How the System Works

The system operates as a two-drone team coordinated by the Hive ground computer.

### Step 1 — Surveillance Drone Scans the Area

A **large surveillance drone** (high endurance, wide camera field-of-view) is deployed over the flood zone. It flies a pre-programmed patrol route at altitude and continuously streams its camera feed back to the Hive computer over a wireless link.

```
Surveillance Drone (large, high altitude)
        ↓  live video stream
    Hive Computer
        ↓  YOLOv8n inference
    Person detected → bounding box + frame coordinates
```

### Step 2 — Victim GPS is Estimated

When YOLOv8 detects a person in the frame, the Hive computer uses the drone's known GPS position, altitude, and camera orientation to project the pixel coordinates of the bounding box centre into real-world **GPS latitude/longitude**. This gives an approximate ground position for the victim.

```
Bounding Box Centre (pixel x, y)
        ↓  camera projection + drone GPS/altitude
    Victim GPS Coordinate (lat, lon)
        ↓
    Stored as rescue target
```

### Step 3 — Rescue Drone is Dispatched

Once a victim coordinate is confirmed, the Hive computer transmits the target GPS to a **small, fast rescue drone** carrying a medical supply payload. The rescue drone is lighter and more agile — optimised for speed rather than endurance.

```
Victim GPS → Hive Computer → Rescue Drone mission upload
```

### Step 4 — A* Path Planning

Before the rescue drone moves, the Hive computer runs an **A\* pathfinding algorithm** on a 2D grid map of the flood zone. The grid encodes obstacle zones (buildings, trees, deep water, no-fly areas) as blocked cells. A* finds the shortest safe route from the rescue drone's current position to the victim's GPS coordinate.

```
Grid Map of Flood Zone
  S = rescue drone start
  G = victim GPS target
  X = obstacle (building / no-fly)

  . . . . X . . G
  . . X . X . . .
  S . X . . . . .
  . . . . . . . .

A* output: optimal waypoint path S → G
```

The computed waypoints are uploaded to the rescue drone as a navigation mission.

### Step 5 — Autonomous Navigation to Victim

The rescue drone follows the A\* waypoint path autonomously. It uses its onboard flight controller to navigate each waypoint in sequence until it reaches the victim's location and deploys the supply payload.

```
A* Waypoints [ W1, W2, W3 … Gn ]
        ↓  uploaded to flight controller
    Rescue Drone navigates autonomously
        ↓
    Arrives at victim GPS
        ↓
    Payload dropped / hovered for pickup
```

### Full End-to-End Flow

```
┌─────────────────────────────────────────────────────┐
│  SURVEILLANCE DRONE (large)                         │
│  Patrols flood zone at altitude                     │
│  Streams live video → Hive Computer                 │
└──────────────────────┬──────────────────────────────┘
                       │ live video stream
                       ▼
┌─────────────────────────────────────────────────────┐
│  HIVE COMPUTER (ground station)                     │
│  YOLOv8n detects person in frame                    │
│  Projects pixel → GPS coordinate                    │
│  Runs A* pathfinding on flood zone grid             │
│  Uploads waypoint mission to rescue drone           │
└──────────┬──────────────────────┬───────────────────┘
           │ victim GPS           │ waypoint path
           ▼                      ▼
┌──────────────────┐   ┌──────────────────────────────┐
│  JARVIS APP      │   │  RESCUE DRONE (small, fast)  │
│  Shows victim    │   │  Follows A* path             │
│  on map          │   │  Delivers supplies to victim │
│  Shows nav path  │   └──────────────────────────────┘
└──────────────────┘
```

---

## System Architecture

```
Surveillance Drone
        ↓
   Video Stream
        ↓
  Hive Computer
        ↓
YOLO Person Detection
        ↓
 Victim GPS Coordinates
        ↓
  A* Path Planning
        ↓
Rescue Drone Deployment
        ↓
  Payload Delivered
```

### Components

| Component | Role |
|---|---|
| **Surveillance Drone** | Large drone — aerial patrol, camera stream, victim detection |
| **Rescue Drone** | Small fast drone — supply delivery, follows A\* path to victim |
| **Hive Processing Computer** | Ground station — YOLO inference, GPS projection, A\* planning |
| **JARVIS App** | Flutter dashboard — live feed, victim map, rescue path display |

---

## Hardware Specification

### Hive Processing Computer (Ground Station)

| Resource | Specification |
|---|---|
| CPU | Intel Core i5 |
| RAM | 16 GB |
| GPU | NVIDIA RTX 3060 (CUDA-accelerated YOLO inference) |
| OS | Windows / Linux |

### Drone Fleet

| Drone | Payload | Function |
|---|---|---|
| Surveillance | Camera module | Area scanning, victim detection |
| Rescue | Medical supply kit | Autonomous delivery to GPS coordinates |

---

## Detection Pipeline

```
Webcam / Drone Camera
         ↓
  OpenCV Frame Capture
  (cv2.VideoCapture)
         ↓
  YOLOv8n Inference
  (Aerial Config)
         ↓
  Bounding Box Overlay
  (Person annotations)
         ↓
  MJPEG Encoding
  (JPEG multipart stream)
         ↓
  FastAPI Endpoint
  GET /video/feed
         ↓
  Flutter LiveFeedPanel
  (Image.network MJPEG)
```

---

## YOLO Aerial Detection Configuration

Standard YOLO settings are not optimised for aerial/drone footage because:

- People appear small relative to the frame (far altitude)
- Perspective is top-down rather than eye-level
- High variability in lighting (sunlight, water reflections)

The system uses the following tuned configuration:

| Parameter | Value | Reason |
|---|---|---|
| `model` | `yolov8n.pt` | Fast nano model suitable for real-time inference |
| `classes` | `[0]` (person only) | Reduces false positives from non-human objects |
| `imgsz` | `960` | Higher resolution preserves small-target detail |
| `conf` | `0.35` | Lower threshold catches partially visible victims |
| `iou` | `0.5` | Standard NMS overlap threshold |
| `device` | `cuda` / `cpu` | CUDA on RTX 3060, CPU fallback for dev machines |

Bounding box smoothing is applied between frames using exponential moving average to stabilise detections under aerial camera vibration.

---

## Development Phase

Because the drone camera hardware is **not yet integrated**, the system uses the laptop webcam as a simulated drone camera during development.

```
Laptop Webcam  →  Simulated Drone Camera
```

This allows full-stack development of:

- Video streaming pipeline
- YOLO person detection
- Bounding box annotation
- Flutter live feed display
- REST detection API

…before drone hardware is connected.

---

## Folder Structure

```
vanguard_system/
├── docs/
│   ├── architecture.md
│   └── project_overview.md          ← this file
├── hive_backend/
│   ├── main.py                      ← FastAPI server entry point
│   ├── requirements.txt             ← Python dependencies
│   ├── telemetry_simulator.py       ← Simulated drone telemetry
│   ├── yolov8n.pt                   ← YOLOv8 nano weights
│   ├── api/
│   │   ├── stream_api.py            ← MJPEG /video/feed endpoint
│   │   ├── detection_api.py         ← /detections endpoint
│   │   ├── telemetry_api.py         ← /telemetry endpoint
│   │   ├── mission_api.py           ← /mission endpoint
│   │   └── vision_api.py            ← /vision/start|stop control
│   ├── vision/
│   │   ├── yolo_detector.py         ← AerialYOLODetector class
│   │   └── webcam_stream.py         ← WebcamStream capture module
│   └── models/
│       ├── detection_model.py       ← Pydantic detection schemas
│       └── telemetry_model.py       ← Pydantic telemetry schemas
└── mobile_app/
    └── jarvis_app/
        └── lib/
            ├── screens/
            │   └── dashboard_screen.dart
            └── widgets/
                ├── live_feed_panel.dart
                ├── drone_map_panel.dart
                └── telemetry_grid.dart
```

---

## API Endpoints

| Method | Path | Description |
|---|---|---|
| `POST` | `/video/start` | Start webcam + YOLO pipeline |
| `POST` | `/video/stop` | Stop the pipeline |
| `GET` | `/video/feed` | MJPEG live stream |
| `GET` | `/video/status` | Pipeline running status |
| `GET` | `/video_feed` | Alias → `/video/feed` |
| `GET` | `/detections` | Latest YOLO detections JSON |
| `GET` | `/telemetry` | Drone telemetry data |
| `GET` | `/mission` | Mission status |

---

## Flutter Frontend Integration

The `LiveFeedPanel` widget in the dashboard:

1. On mount: sends `POST /video/start` with `{"source": "0"}` (webcam index 0)
2. Polls MJPEG stream at `GET /video/feed` using `Image.network()` with cache-busting
3. Bounding boxes are rendered inside the JPEG frames by the backend (no client-side drawing)

### Dashboard Layout

```
┌─────────────────────────┬──────────────┐
│                         │              │
│    Live Video Feed      │ Tactical Map │
│    (65% width)          │ (35% width)  │
│                         │              │
└─────────────────────────┴──────────────┘
│         Telemetry Cards (compact grid)  │
└─────────────────────────────────────────┘
```

---

## Running the Backend

### 1. Install dependencies

```bash
cd vanguard_system/hive_backend
pip install -r requirements.txt
```

### 2. Start the server

```bash
uvicorn main:app --host 0.0.0.0 --port 8000 --reload
```

### 3. Start the vision pipeline

The Flutter app automatically POSTs to `/video/start` on launch.  
To start it manually via curl:

```bash
curl -X POST http://localhost:8000/video/start \
     -H "Content-Type: application/json" \
     -d '{"source": "0"}'
```

Or open the Swagger docs:

```
http://localhost:8000/docs
```

### 4. View the raw stream in a browser

```
http://localhost:8000/video/feed
```

### 5. Launch the Flutter app

```bash
cd vanguard_system/mobile_app/jarvis_app
flutter run -d chrome
```

---

## Roadmap (Not Yet Implemented)

| Feature | Description |
|---|---|
| MAVLink integration | Real drone telemetry via serial/UDP |
| RTSP drone camera | Replace webcam with drone RTSP stream |
| GPS victim projection | Map pixel coordinates → real-world GPS |
| Victim map markers | Pin detected victims on the tactical map |
| Path planning | A*/RRT route from rescue drone to victim |
| Rescue drone dispatch | Automated MAVLink mission upload |
