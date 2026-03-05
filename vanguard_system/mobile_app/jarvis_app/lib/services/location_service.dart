/// Location Service
/// ================
/// Reads the phone's real GPS via the geolocator package and exposes it
/// as a [ChangeNotifier].  Also forwards every fix to the Hive backend
/// (POST /update_location) so the tactical map stays in sync.
///
/// Usage
/// -----
///   context.read<LocationService>().startTracking();
///
/// The service is already wired into the MultiProvider tree in main.dart.
library;

import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import '../core/config.dart';

class LocationService extends ChangeNotifier {
  // ── State ──────────────────────────────────────────────────────────────────
  Position? _position;
  bool _permissionGranted = false;
  bool _tracking = false;
  String? _error;

  StreamSubscription<Position>? _posStream;

  // ── Getters ────────────────────────────────────────────────────────────────

  Position? get position        => _position;
  double?   get latitude        => _position?.latitude;
  double?   get longitude       => _position?.longitude;
  double?   get accuracy        => _position?.accuracy;
  double?   get altitude        => _position?.altitude;
  double?   get heading         => _position?.heading;
  double?   get speed           => _position?.speed;
  bool      get permissionGranted => _permissionGranted;
  bool      get isTracking      => _tracking;
  String?   get error           => _error;

  /// True once we have at least one real GPS fix.
  bool get hasPosition => _position != null;

  // ── Permission ─────────────────────────────────────────────────────────────

  /// Request (or check existing) location permission.
  /// Returns true if permission is granted.
  Future<bool> requestPermission() async {
    // Services enabled?
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      _error = 'Location services are disabled on this device.';
      notifyListeners();
      return false;
    }

    LocationPermission perm = await Geolocator.checkPermission();

    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
    }

    if (perm == LocationPermission.deniedForever) {
      _error = 'Location permission permanently denied. '
               'Open Settings → App → Location.';
      notifyListeners();
      return false;
    }

    if (perm == LocationPermission.denied) {
      _error = 'Location permission denied.';
      notifyListeners();
      return false;
    }

    _permissionGranted = true;
    _error = null;
    notifyListeners();
    return true;
  }

  // ── Tracking ───────────────────────────────────────────────────────────────

  /// Start continuous GPS tracking.  Requests permission if needed.
  Future<void> startTracking() async {
    if (_tracking) return;

    final ok = await requestPermission();
    if (!ok) return;

    const settings = LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 0,   // receive every update regardless of movement
    );

    _posStream = Geolocator.getPositionStream(locationSettings: settings)
        .listen(
          _onPosition,
          onError: (e) {
            _error = e.toString();
            notifyListeners();
          },
        );

    _tracking = true;
    notifyListeners();
  }

  /// Stop GPS tracking.
  void stopTracking() {
    _posStream?.cancel();
    _posStream = null;
    _tracking = false;
    notifyListeners();
  }

  @override
  void dispose() {
    stopTracking();
    super.dispose();
  }

  // ── Internal ───────────────────────────────────────────────────────────────

  void _onPosition(Position pos) {
    _position = pos;
    _error = null;
    notifyListeners();
    _postToBackend(pos);  // fire-and-forget
  }

  /// Push the latest GPS fix to the Hive backend so the tactical map and any
  /// other clients (e.g. recording service) get the real-time position.
  Future<void> _postToBackend(Position pos) async {
    try {
      await http
          .post(
            Uri.parse(AppConfig.updateLocationUrl),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'latitude':  pos.latitude,
              'longitude': pos.longitude,
              'accuracy':  pos.accuracy,
              'altitude':  pos.altitude,
              'heading':   pos.heading,
              'speed':     pos.speed,
              'source':    'phone_gps',
            }),
          )
          .timeout(const Duration(seconds: 2));
    } catch (_) {
      // Backend unreachable — GPS tracking continues regardless.
    }
  }
}
