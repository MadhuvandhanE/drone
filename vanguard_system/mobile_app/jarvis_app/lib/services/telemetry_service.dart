/// Telemetry Service
/// =================
/// Polls the Hive backend at regular intervals and exposes the
/// latest telemetry data via a [ChangeNotifier] for the UI to consume.
library;

import 'dart:async';
import 'package:flutter/foundation.dart';
import '../core/api_client.dart';
import '../core/config.dart';
import '../models/telemetry_model.dart';

class TelemetryService extends ChangeNotifier {
  TelemetryData _telemetry = TelemetryData.empty();
  Map<String, dynamic>? _mission;
  Map<String, dynamic>? _detections;
  bool _isLoading = false;
  String? _error;
  Timer? _pollTimer;

  // ---------------------------------------------------------------------------
  // Getters
  // ---------------------------------------------------------------------------

  TelemetryData get telemetry => _telemetry;
  Map<String, dynamic>? get mission => _mission;
  Map<String, dynamic>? get detections => _detections;
  bool get isLoading => _isLoading;
  String? get error => _error;
  bool get isConnected => _telemetry.isConnected;

  // ---------------------------------------------------------------------------
  // Lifecycle
  // ---------------------------------------------------------------------------

  /// Start polling the backend for telemetry updates.
  void startPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(
      const Duration(milliseconds: AppConfig.telemetryPollIntervalMs),
      (_) => fetchTelemetry(),
    );
    // Fetch immediately on start
    fetchTelemetry();
  }

  /// Stop the polling timer.
  void stopPolling() {
    _pollTimer?.cancel();
    _pollTimer = null;
  }

  @override
  void dispose() {
    stopPolling();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Data fetching
  // ---------------------------------------------------------------------------

  /// Fetch the latest telemetry snapshot.
  Future<void> fetchTelemetry() async {
    try {
      _error = null;
      final json = await ApiClient.get('/telemetry');
      _telemetry = TelemetryData.fromJson(json);
      notifyListeners();
    } catch (e) {
      _error = e.toString();
      notifyListeners();
    }
  }

  /// Fetch mission progress.
  Future<void> fetchMission() async {
    try {
      _isLoading = true;
      _error = null;
      notifyListeners();

      final json = await ApiClient.get('/mission');
      _mission = json;
    } catch (e) {
      _error = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Fetch victim detections.
  Future<void> fetchDetections() async {
    try {
      _isLoading = true;
      _error = null;
      notifyListeners();

      final json = await ApiClient.get('/detections');
      _detections = json;
    } catch (e) {
      _error = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }
}
