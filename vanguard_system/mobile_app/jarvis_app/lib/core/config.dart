/// JARVIS App Configuration
/// ========================
/// Central configuration constants for the mobile application.
/// Update [baseUrl] to point to your Hive backend instance.
library;

class AppConfig {
  AppConfig._();

  /// Base URL of the Hive backend API.
  /// For Android emulator use 10.0.2.2 instead of localhost.
  /// For physical device use your machine's LAN IP.
  static const String baseUrl = 'http://localhost:8000';

  /// Polling interval for telemetry updates (milliseconds).
  static const int telemetryPollIntervalMs = 1000;

  /// App display name.
  static const String appName = 'JARVIS';

  /// Drone identifier.
  static const String droneId = 'VANGUARD-01';

  /// ---------------------------------------------------------------
  /// Video Stream Configuration
  /// ---------------------------------------------------------------
  /// By default, we use an HLS test stream for web compatibility.
  /// To connect the Peeper TX10 directly on mobile, use its RTSP URL.

  // Example Peeper/Skydroid TX10 RTSP URL: 'rtsp://192.168.144.108:554/stream=0'
  // WebRTC/HLS from Hive Backend (Future): 'http://localhost:8000/stream.m3u8'
  /// MJPEG stream served by the Hive backend (/video/feed).
  /// Works natively in browsers via <img> tag, but NOT via Flutter web
  /// Image.network() — use snapshotUrl for Flutter web instead.
  static String get mjpegFeedUrl => '$baseUrl/video/feed';

  /// Single JPEG snapshot endpoint — Flutter web compatible.
  /// Poll this with a cache-busting query param to simulate a live feed:
  ///   Image.network('$snapshotUrl?t=$cacheBust')
  static String get snapshotUrl => '$baseUrl/video/snapshot';

  /// Convenience: POST this URL with {"source":"0"} to start the camera.
  static String get videoStartUrl => '$baseUrl/video/start';

  /// Legacy – kept so nothing else breaks.
  static String get liveVideoUrl => mjpegFeedUrl;
  static const bool isRtspStream = false;

  /// ---------------------------------------------------------------
  /// Map Configuration (No API Key Required)
  /// ---------------------------------------------------------------
  /// Using CartoDB Dark Matter tiles for a high-contrast tactical look
  /// that works immediately without needing to sign up for tokens.

  static String get mapTileUrl =>
      'https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}{r}.png';

  /// Map initial center (Chennai flood zone).
  static const double mapInitialLat = 13.0827;
  static const double mapInitialLng = 80.2707;
  static const double mapInitialZoom = 16.0;

  /// ---------------------------------------------------------------
  /// Patrol Waypoints (must match backend simulator)
  /// ---------------------------------------------------------------
  static const List<List<double>> patrolWaypoints = [
    [13.0827, 80.2707], // WP 0 – Start / Rally Point
    [13.0835, 80.2715], // WP 1
    [13.0842, 80.2725], // WP 2
    [13.0850, 80.2718], // WP 3
    [13.0855, 80.2705], // WP 4
    [13.0848, 80.2695], // WP 5
    [13.0840, 80.2688], // WP 6
    [13.0832, 80.2695], // WP 7
    [13.0828, 80.2700], // WP 8
    [13.0827, 80.2707], // WP 9 – Loop back
  ];
}
