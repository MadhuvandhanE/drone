/// Location Service
/// ================
/// Reads the phone real GPS via geolocator and exposes it as a ChangeNotifier.
/// Used to simulate drone location with the phone GPS while the real drone
/// is not yet connected.
///
/// Usage
/// -----
///   ChangeNotifierProvider(create: (_) => LocationService()),  // in MultiProvider
///   context.read<LocationService>().startTracking();            // in initState
///   final svc = context.watch<LocationService>();
///   if (svc.hasPosition) print('${svc.latitude}, ${svc.longitude}');
library;

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import '../models/location_model.dart';

class LocationService extends ChangeNotifier {
  // --- State ----------------------------------------------------------------
  LocationModel? _location;
  bool _tracking = false;
  String? _error;

  StreamSubscription<Position>? _sub;

  // --- Getters --------------------------------------------------------------

  LocationModel? get location  => _location;
  double?  get latitude  => _location?.latitude;
  double?  get longitude => _location?.longitude;
  double?  get accuracy  => _location?.accuracy;
  double?  get altitude  => _location?.altitude;
  double?  get heading   => _location?.heading;
  double?  get speed     => _location?.speed;

  /// True once at least one real GPS fix has arrived.
  bool    get hasPosition => _location != null;
  bool    get isTracking  => _tracking;
  String? get error       => _error;

  // --- Public API -----------------------------------------------------------

  /// Request permission and start streaming GPS fixes (~1 Hz).
  /// Safe to call multiple times; subsequent calls are no-ops.
  Future<void> startTracking() async {
    if (_tracking) return;
    final ok = await _requestPermission();
    if (!ok) return;

    const settings = LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 0, // fire every update regardless of movement
    );

    _sub = Geolocator.getPositionStream(locationSettings: settings).listen(
      _onPosition,
      onError: (Object e) {
        _error = e.toString();
        notifyListeners();
      },
    );

    _tracking = true;
    notifyListeners();
  }

  /// Cancel the GPS stream.
  void stopTracking() {
    _sub?.cancel();
    _sub = null;
    _tracking = false;
    notifyListeners();
  }

  @override
  void dispose() {
    stopTracking();
    super.dispose();
  }

  // --- Internals ------------------------------------------------------------

  Future<bool> _requestPermission() async {
    final enabled = await Geolocator.isLocationServiceEnabled();
    if (!enabled) {
      _error = 'Location services are disabled on this device.';
      notifyListeners();
      return false;
    }

    LocationPermission perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
    }
    if (perm == LocationPermission.deniedForever) {
      _error = 'Location permanently denied. Open Settings -> App -> Location.';
      notifyListeners();
      return false;
    }
    if (perm == LocationPermission.denied) {
      _error = 'Location permission denied.';
      notifyListeners();
      return false;
    }
    _error = null;
    return true;
  }

  void _onPosition(Position pos) {
    _location = LocationModel(
      latitude:  pos.latitude,
      longitude: pos.longitude,
      accuracy:  pos.accuracy,
      altitude:  pos.altitude,
      heading:   pos.heading,
      speed:     pos.speed,
      timestamp: pos.timestamp,
    );
    _error = null;
    notifyListeners();
  }
}
