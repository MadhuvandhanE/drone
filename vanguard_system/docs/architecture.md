# JARVIS – System Architecture

## Overview

JARVIS (Just A Rather Very Intelligent System) is a disaster-rescue drone monitoring platform built for flood rescue operations. The system consists of three main components:

```
┌─────────────────────────┐
│     VANGUARD Drone      │
│  ┌───────────────────┐  │
│  │ Pixhawk STM32 FC  │  │
│  │ 4K + Thermal Cam  │  │
│  │ Autonomous WP Nav  │  │
│  └────────┬──────────┘  │
└───────────┼─────────────┘
            │ MAVLink Telemetry
            │ (Future Phase)
            ▼
┌─────────────────────────┐
│   Hive Ground Station   │
│  ┌───────────────────┐  │
│  │ FastAPI Backend    │  │
│  │ ┌───────────────┐ │  │
│  │ │ Telemetry Sim │ │  │
│  │ │ Mission Mgr   │ │  │
│  │ │ Detection Sim │ │  │
│  │ └───────────────┘ │  │
│  └────────┬──────────┘  │
│           │              │
│  Specs:                  │
│  • Intel i5 CPU          │
│  • 16GB RAM              │
│  • RTX 3060 GPU          │
└───────────┼──────────────┘
            │ REST API (HTTP)
            ▼
┌─────────────────────────┐
│   JARVIS Mobile App     │
│  ┌───────────────────┐  │
│  │ Flutter (Dart)    │  │
│  │ ┌───────────────┐ │  │
│  │ │ Dashboard     │ │  │
│  │ │ Tactical Map  │ │  │
│  │ │ Mission Ctrl  │ │  │
│  │ └───────────────┘ │  │
│  └───────────────────┘  │
└─────────────────────────┘
```

## Phase 1 – Software Foundation

### What's Implemented
- ✅ Simulated drone telemetry (stateful, smooth trajectory)
- ✅ FastAPI REST API (3 endpoints)
- ✅ Flutter app with 3 screens
- ✅ Real-time telemetry polling (1s interval)
- ✅ Tactical map with radar sweep & flight path
- ✅ Mission progress with waypoint timeline
- ✅ Victim detection simulation

### API Endpoints

| Method | Path          | Description                        |
|--------|---------------|------------------------------------|
| GET    | `/`           | Health check                       |
| GET    | `/telemetry`  | Current drone telemetry snapshot   |
| GET    | `/mission`    | Mission progress & status          |
| GET    | `/detections` | Simulated victim detections        |

### Mobile App Screens

1. **Dashboard** – 6 telemetry cards (battery, altitude, speed, signal, water depth, coordinates) + mission progress
2. **Map** – Tactical radar view with flight path trail, grid overlay, and detection markers
3. **Mission** – Waypoint timeline, action buttons, detection results, mission statistics

### Future Phases
- Phase 2: MAVLink integration, real telemetry
- Phase 3: YOLO object detection, thermal processing
- Phase 4: Water depth analysis, flood heatmap
- Phase 5: Video streaming, autonomous path planning

## Running the System

### Backend
```bash
cd vanguard_system/hive_backend
pip install -r requirements.txt
uvicorn main:app --host 0.0.0.0 --port 8000 --reload
```

### Mobile App
```bash
cd vanguard_system/mobile_app/jarvis_app
flutter pub get
flutter run
```

### Standalone Simulator
```bash
cd vanguard_system/simulator
python drone_simulator.py
```

## Configuration

### Backend → Mobile App Connection
- Android Emulator: `http://10.0.2.2:8000`
- iOS Simulator: `http://localhost:8000`
- Physical Device: Use your machine's LAN IP

Update the `baseUrl` in `lib/core/config.dart`.
