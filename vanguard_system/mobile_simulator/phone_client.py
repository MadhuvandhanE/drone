"""
JARVIS Phone GPS Simulator Client
===================================
Simulates a smartphone acting as the drone by sending GPS coordinates
to the backend every second.

Mode A — SIMULATE (default)
----------------------------
Walks the drone along a pre-defined Chennai patrol route, looping
indefinitely.  Use this for local development when you don't have a
physical phone available.

Mode B — REAL GPS (optional)
------------------------------
Reads GPS from a connected GPS device / gpsd daemon (requires gpsd-py3).
Uncomment the REAL_GPS block below and comment out the SIMULATE block.

Mode C — MANUAL
-----------------
Pass --lat / --lng / --speed flags to inject a single fixed position for
debugging specific map coordinates.

Usage
-----
Basic (simulate patrol):
    python phone_client.py

Connect to a non-default backend:
    python phone_client.py --host 192.168.1.50 --port 8000

Single fixed position:
    python phone_client.py --lat 13.0827 --lng 80.2707

Real GPS device (uncomment REAL_GPS section below first):
    python phone_client.py --real-gps

----------------------------------------------------------------------
Phone RTSP camera setup (companion to this GPS client)
----------------------------------------------------------------------
Install IP Webcam (Android) or DroidCam on your phone.

IP Webcam:
  1. Open IP Webcam → Start server
  2. Note the IP shown e.g. http://192.168.1.X:8080
  3. Start RTSP stream on backend:
       curl -X POST http://BACKEND_IP:8000/video/start \\
            -H "Content-Type: application/json" \\
            -d '{"source":"rtsp://192.168.1.X:8080/h264_ulaw.sdp"}'

DroidCam:
  1. Open DroidCam → note IP
  2. Use rtsp://192.168.1.X:4747/mjpegfeed as the source above.
----------------------------------------------------------------------
"""

import argparse
import math
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
import json

# ─────────────────────────────────────────────────────────────────────────────
# Patrol route  (same waypoints as Flutter AppConfig.patrolWaypoints)
# Any number of [lat, lng] pairs.  The client walks between them at ~2 m/s.
# ─────────────────────────────────────────────────────────────────────────────

PATROL_ROUTE = [
    [13.0827, 80.2707],  # WP-0  Start / Rally Point
    [13.0835, 80.2715],  # WP-1
    [13.0842, 80.2725],  # WP-2
    [13.0850, 80.2718],  # WP-3
    [13.0855, 80.2705],  # WP-4
    [13.0848, 80.2695],  # WP-5
    [13.0840, 80.2688],  # WP-6
    [13.0832, 80.2695],  # WP-7
    [13.0828, 80.2700],  # WP-8
    [13.0827, 80.2707],  # WP-9  Loop back
]

# Speed at which the simulated drone walks the route (metres per second)
SIMULATE_SPEED_MPS = 2.0

# Update interval (seconds)  –  must match Flutter LocationPollIntervalMs / 1000
UPDATE_INTERVAL = 1.0


# ─────────────────────────────────────────────────────────────────────────────
# Helpers
# ─────────────────────────────────────────────────────────────────────────────

def _haversine_m(lat1, lng1, lat2, lng2) -> float:
    """Return the distance in metres between two WGS-84 points."""
    R = 6_371_000.0
    f1, f2 = math.radians(lat1), math.radians(lat2)
    df = math.radians(lat2 - lat1)
    dl = math.radians(lng2 - lng1)
    a = math.sin(df / 2) ** 2 + math.cos(f1) * math.cos(f2) * math.sin(dl / 2) ** 2
    return R * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a))


def _bearing_deg(lat1, lng1, lat2, lng2) -> float:
    """Return the initial bearing (degrees, 0–360) from point 1 to point 2."""
    f1, f2 = math.radians(lat1), math.radians(lat2)
    dl = math.radians(lng2 - lng1)
    x = math.sin(dl) * math.cos(f2)
    y = math.cos(f1) * math.sin(f2) - math.sin(f1) * math.cos(f2) * math.cos(dl)
    return (math.degrees(math.atan2(x, y)) + 360) % 360


def _interpolate(lat1, lng1, lat2, lng2, frac) -> tuple[float, float]:
    """Linear interpolation between two lat/lng points."""
    return lat1 + (lat2 - lat1) * frac, lng1 + (lng2 - lng1) * frac


def _post_location(url: str, payload: dict, verbose: bool = True) -> bool:
    """Send one POST /update_location request. Returns True on success."""
    data = json.dumps(payload).encode()
    req  = urllib.request.Request(
        url,
        data=data,
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    try:
        with urllib.request.urlopen(req, timeout=2) as resp:
            resp.read()
            if verbose:
                print(
                    f"\r  GPS → {payload['latitude']:.6f}, {payload['longitude']:.6f}"
                    f"  hdg={payload.get('heading', 0):.0f}°"
                    f"  spd={payload.get('speed', 0):.1f} m/s   ",
                    end="",
                    flush=True,
                )
            return True
    except (urllib.error.URLError, OSError) as e:
        print(f"\n[GPS] Error: {e}. Retrying …", flush=True)
        return False


# ─────────────────────────────────────────────────────────────────────────────
# Simulation mode — walk PATROL_ROUTE in a loop
# ─────────────────────────────────────────────────────────────────────────────

def run_simulate(url: str, speed_mps: float, verbose: bool):
    """Walk the patrol route at speed_mps, posting each interpolated position."""
    print(f"[GPS] Simulation mode  speed={speed_mps} m/s  url={url}")
    print(f"[GPS] Route has {len(PATROL_ROUTE)} waypoints. Press Ctrl+C to stop.\n")

    seg_idx   = 0            # which segment we're currently traversing
    seg_dist  = 0.0          # metres covered in the current segment
    n_segs    = len(PATROL_ROUTE) - 1

    while True:
        t_start = time.monotonic()

        wp_a = PATROL_ROUTE[seg_idx]
        wp_b = PATROL_ROUTE[(seg_idx + 1) % len(PATROL_ROUTE)]
        total = _haversine_m(*wp_a, *wp_b)

        frac = seg_dist / total if total > 0 else 0
        frac = min(frac, 1.0)

        lat, lng = _interpolate(wp_a[0], wp_a[1], wp_b[0], wp_b[1], frac)
        hdg      = _bearing_deg(*wp_a, *wp_b)

        payload = {
            "latitude":  round(lat, 7),
            "longitude": round(lng, 7),
            "heading":   round(hdg, 1),
            "speed":     speed_mps,
            "accuracy":  3.0,           # simulated 3 m accuracy
            "source":    "simulated",
        }

        _post_location(url, payload, verbose)

        # Advance position
        seg_dist += speed_mps * UPDATE_INTERVAL
        if seg_dist >= total:
            seg_dist = 0.0
            seg_idx  = (seg_idx + 1) % n_segs
            if verbose:
                print(f"\n[GPS] → Waypoint {seg_idx + 1}", flush=True)

        elapsed = time.monotonic() - t_start
        time.sleep(max(0.0, UPDATE_INTERVAL - elapsed))


# ─────────────────────────────────────────────────────────────────────────────
# Fixed position mode
# ─────────────────────────────────────────────────────────────────────────────

def run_fixed(url: str, lat: float, lng: float, verbose: bool):
    """Post a single fixed position every second (useful for UI debugging)."""
    print(f"[GPS] Fixed mode  lat={lat}  lng={lng}  url={url}")
    print("[GPS] Press Ctrl+C to stop.\n")
    while True:
        t_start = time.monotonic()
        _post_location(
            url,
            {"latitude": lat, "longitude": lng, "accuracy": 5.0, "source": "manual"},
            verbose,
        )
        elapsed = time.monotonic() - t_start
        time.sleep(max(0.0, UPDATE_INTERVAL - elapsed))


# ─────────────────────────────────────────────────────────────────────────────
# Real GPS mode (requires: pip install gpsd-py3)
# ─────────────────────────────────────────────────────────────────────────────

def run_real_gps(url: str, verbose: bool):
    """
    Read from a connected GPS device via gpsd and forward to backend.

    Prerequisites
    -------------
    pip install gpsd-py3
    sudo systemctl start gpsd   (Linux / Raspberry Pi)
    """
    try:
        import gpsd  # type: ignore
    except ImportError:
        print("[GPS] gpsd-py3 not installed. Run: pip install gpsd-py3")
        sys.exit(1)

    gpsd.connect()
    print(f"[GPS] Real GPS mode — connected to gpsd  url={url}")
    print("[GPS] Press Ctrl+C to stop.\n")

    while True:
        t_start = time.monotonic()
        try:
            packet = gpsd.get_current()
            if packet.mode >= 2:          # 2D or 3D fix
                payload = {
                    "latitude":  round(packet.lat, 7),
                    "longitude": round(packet.lon, 7),
                    "accuracy":  round(packet.error.get("x", 5.0), 1),
                    "altitude":  round(packet.alt, 1) if packet.mode == 3 else None,
                    "heading":   round(packet.movement().get("track", 0), 1),
                    "speed":     round(packet.movement().get("speed", 0), 2),
                    "source":    "phone_gps",
                }
                _post_location(url, payload, verbose)
            else:
                print("\r[GPS] Waiting for fix …", end="", flush=True)
        except Exception as e:
            print(f"\n[GPS] gpsd read error: {e}")

        elapsed = time.monotonic() - t_start
        time.sleep(max(0.0, UPDATE_INTERVAL - elapsed))


# ─────────────────────────────────────────────────────────────────────────────
# Entry point
# ─────────────────────────────────────────────────────────────────────────────

def main():
    parser = argparse.ArgumentParser(
        description="JARVIS Phone GPS Simulator – sends location to Hive backend"
    )
    parser.add_argument(
        "--host",
        default="localhost",
        help="Backend host (default: localhost). Use LAN IP for physical phone.",
    )
    parser.add_argument("--port", default=8000, type=int, help="Backend port (default: 8000)")
    parser.add_argument("--lat",  type=float, help="Fixed latitude  (enables fixed mode)")
    parser.add_argument("--lng",  type=float, help="Fixed longitude (enables fixed mode)")
    parser.add_argument("--speed", type=float, default=SIMULATE_SPEED_MPS,
                        help=f"Simulation walk speed in m/s (default: {SIMULATE_SPEED_MPS})")
    parser.add_argument("--real-gps", action="store_true",
                        help="Use real GPS via gpsd instead of simulation")
    parser.add_argument("--quiet", action="store_true", help="Suppress per-update output")
    args = parser.parse_args()

    url = f"http://{args.host}:{args.port}/update_location"

    try:
        if args.real_gps:
            run_real_gps(url, verbose=not args.quiet)
        elif args.lat is not None and args.lng is not None:
            run_fixed(url, args.lat, args.lng, verbose=not args.quiet)
        else:
            run_simulate(url, args.speed, verbose=not args.quiet)
    except KeyboardInterrupt:
        print("\n[GPS] Stopped.")


if __name__ == "__main__":
    main()
