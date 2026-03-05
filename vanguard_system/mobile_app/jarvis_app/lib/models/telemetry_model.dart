/// Telemetry Data Model
/// ====================
/// Dart representation of the telemetry payload from the Hive API.
library;

class TelemetryData {
  final String droneId;
  final double latitude;
  final double longitude;
  final double altitude;
  final double speed;
  final int battery;
  final String mode;
  final int currentWaypoint;
  final int totalWaypoints;
  final int signalStrength;
  final double waterDepth;
  final DateTime timestamp;

  TelemetryData({
    required this.droneId,
    required this.latitude,
    required this.longitude,
    required this.altitude,
    required this.speed,
    required this.battery,
    required this.mode,
    required this.currentWaypoint,
    required this.totalWaypoints,
    required this.signalStrength,
    required this.waterDepth,
    required this.timestamp,
  });

  /// Parse from JSON map returned by the API.
  factory TelemetryData.fromJson(Map<String, dynamic> json) {
    return TelemetryData(
      droneId: json['drone_id'] as String? ?? 'UNKNOWN',
      latitude: (json['latitude'] as num?)?.toDouble() ?? 0.0,
      longitude: (json['longitude'] as num?)?.toDouble() ?? 0.0,
      altitude: (json['altitude'] as num?)?.toDouble() ?? 0.0,
      speed: (json['speed'] as num?)?.toDouble() ?? 0.0,
      battery: (json['battery'] as num?)?.toInt() ?? 0,
      mode: json['mode'] as String? ?? 'UNKNOWN',
      currentWaypoint: (json['current_waypoint'] as num?)?.toInt() ?? 0,
      totalWaypoints: (json['total_waypoints'] as num?)?.toInt() ?? 0,
      signalStrength: (json['signal_strength'] as num?)?.toInt() ?? 0,
      waterDepth: (json['water_depth'] as num?)?.toDouble() ?? 0.0,
      timestamp: DateTime.tryParse(json['timestamp'] as String? ?? '') ??
          DateTime.now(),
    );
  }

  /// Default empty telemetry for initial state.
  factory TelemetryData.empty() {
    return TelemetryData(
      droneId: '---',
      latitude: 0.0,
      longitude: 0.0,
      altitude: 0.0,
      speed: 0.0,
      battery: 0,
      mode: 'OFFLINE',
      currentWaypoint: 0,
      totalWaypoints: 0,
      signalStrength: 0,
      waterDepth: 0.0,
      timestamp: DateTime.now(),
    );
  }

  /// Whether this telemetry has real data (not the empty placeholder).
  bool get isConnected => droneId != '---';
}
