/// Drone Location Service
/// ======================
/// Polls GET /drone_location every second and exposes the latest
/// GPS position as a [ChangeNotifier] for the map widget to consume.
///
/// Data flow
/// ---------
///   Phone (phone_client.py)
///     → POST /update_location  (every 1 s)
///     → Backend stores location
///     → GET  /drone_location   (this service polls)
///     → DroneMapPanel updates marker
///
/// Fallback
/// --------
/// If no GPS update has been received (backend returns source="default"),
/// [hasLocation] is false and the map falls back to simulated telemetry.
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../core/config.dart';

class DroneLocationService extends ChangeNotifier {
  // ── State ──────────────────────────────────────────────────────────────────
  double? _latitude;
  double? _longitude;
  double? _accuracy;
  double? _altitude;
  double? _heading;
  double? _speed;
  String _source = 'default';
  String? _timestamp;
  bool _isConnected = false;
  String? _error;

  Timer? _pollTimer;

  // ── Getters ────────────────────────────────────────────────────────────────

  double? get latitude    => _latitude;
  double? get longitude   => _longitude;
  double? get accuracy    => _accuracy;
  double? get altitude    => _altitude;
  double? get heading     => _heading;
  double? get speed       => _speed;
  String  get source      => _source;
  String? get timestamp   => _timestamp;
  bool    get isConnected => _isConnected;
  String? get error       => _error;

  /// True only when a real GPS update (not the default fallback) is available.
  bool get hasLocation =>
      _latitude != null && _longitude != null && _source != 'default';

  // ── Lifecycle ───────────────────────────────────────────────────────────────

  /// Start polling the backend for GPS updates.
  void startPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(
      const Duration(milliseconds: AppConfig.locationPollIntervalMs),
      (_) => _fetchLocation(),
    );
    _fetchLocation(); // immediate first fetch
  }

  /// Stop polling.
  void stopPolling() {
    _pollTimer?.cancel();
    _pollTimer = null;
  }

  @override
  void dispose() {
    stopPolling();
    super.dispose();
  }

  // ── Fetching ────────────────────────────────────────────────────────────────

  Future<void> _fetchLocation() async {
    try {
      final res = await http
          .get(Uri.parse(AppConfig.droneLocationUrl))
          .timeout(const Duration(seconds: 2));

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;

        _latitude   = (data['latitude']  as num?)?.toDouble();
        _longitude  = (data['longitude'] as num?)?.toDouble();
        _accuracy   = (data['accuracy']  as num?)?.toDouble();
        _altitude   = (data['altitude']  as num?)?.toDouble();
        _heading    = (data['heading']   as num?)?.toDouble();
        _speed      = (data['speed']     as num?)?.toDouble();
        _source     = (data['source']    as String?) ?? 'unknown';
        _timestamp  = data['timestamp']  as String?;
        _isConnected = true;
        _error = null;
      } else {
        _error = 'HTTP ${res.statusCode}';
      }
    } catch (e) {
      _isConnected = false;
      _error = e.toString();
    }

    notifyListeners();
  }
}
