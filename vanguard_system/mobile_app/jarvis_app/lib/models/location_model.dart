/// Location Model
/// ==============
/// Immutable snapshot of a single GPS fix from the device.
library;

class LocationModel {
  final double latitude;
  final double longitude;
  final double accuracy;    // metres
  final double altitude;    // metres above sea level
  final double heading;     // degrees from north (0–360)
  final double speed;       // m/s
  final DateTime timestamp;

  const LocationModel({
    required this.latitude,
    required this.longitude,
    required this.accuracy,
    required this.altitude,
    required this.heading,
    required this.speed,
    required this.timestamp,
  });

  @override
  String toString() =>
      'LocationModel(lat=$latitude, lon=$longitude, '
      'acc=${accuracy.toStringAsFixed(1)}m, '
      'alt=${altitude.toStringAsFixed(1)}m, '
      'spd=${speed.toStringAsFixed(1)}m/s)';
}
