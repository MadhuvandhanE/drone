import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../services/telemetry_service.dart';
import '../services/drone_location_service.dart';
import '../core/config.dart';

class DroneMapPanel extends StatefulWidget {
  final TelemetryService service;

  const DroneMapPanel({super.key, required this.service});

  @override
  State<DroneMapPanel> createState() => _DroneMapPanelState();
}

class _DroneMapPanelState extends State<DroneMapPanel> {
  final MapController _mapController = MapController();
  final List<LatLng> _positionHistory = [];
  late final List<LatLng> _waypoints;
  DroneLocationService? _locationService;

  @override
  void initState() {
    super.initState();
    _waypoints =
        AppConfig.patrolWaypoints.map((wp) => LatLng(wp[0], wp[1])).toList();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Re-attach listener whenever the dependency tree changes.
    _locationService?.removeListener(_onGpsUpdate);
    _locationService = context.read<DroneLocationService>();
    _locationService!.addListener(_onGpsUpdate);
  }

  /// Called by DroneLocationService whenever a new GPS fix arrives.
  void _onGpsUpdate() {
    if (!mounted) return;
    final loc = _locationService;
    if (loc == null || !loc.hasLocation) return;

    final pos = LatLng(loc.latitude!, loc.longitude!);
    if (_positionHistory.isEmpty || _positionHistory.last != pos) {
      setState(() {
        _positionHistory.add(pos);
        if (_positionHistory.length > 150) _positionHistory.removeAt(0);
      });
    }
    // Smoothly follow the drone whenever GPS updates.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _mapController.move(pos, _mapController.camera.zoom);
      }
    });
  }

  @override
  void didUpdateWidget(covariant DroneMapPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Phone GPS takes priority — only update trail from telemetry as a fallback.
    if (_locationService?.hasLocation ?? false) return;
    if (!widget.service.isConnected) return;

    final t = widget.service.telemetry;
    final pos = LatLng(t.latitude, t.longitude);
    if (_positionHistory.isEmpty || _positionHistory.last != pos) {
      _positionHistory.add(pos);
      if (_positionHistory.length > 50) _positionHistory.removeAt(0);
    }
  }

  @override
  void dispose() {
    _locationService?.removeListener(_onGpsUpdate);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.service.telemetry;

    // Phone GPS has priority; fall back to simulated telemetry when offline.
    final loc = context.watch<DroneLocationService>();
    final hasRealGps = loc.hasLocation;
    final dronePos = hasRealGps
        ? LatLng(loc.latitude!, loc.longitude!)
        : LatLng(t.latitude, t.longitude);
    final hasTelemetry = hasRealGps || widget.service.isConnected;

    // When no phone GPS, auto-follow simulated drone.
    if (!hasRealGps && widget.service.isConnected) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _mapController.move(dronePos, _mapController.camera.zoom);
      });
    }

    // Build Victims markers
    final victimMarkers = <Marker>[];
    if (widget.service.detections != null) {
      final victims =
          widget.service.detections!['victims'] as List<dynamic>? ?? [];
      for (var v in victims) {
        final victim = v as Map<String, dynamic>;
        final lat = (victim['lat'] as num?)?.toDouble() ?? 0;
        final lon = (victim['lon'] as num?)?.toDouble() ?? 0;

        victimMarkers.add(Marker(
          point: LatLng(lat, lon),
          width: 30,
          height: 30,
          child: const Icon(
            Icons.person_pin_circle,
            color: Color(0xFFFF6E40),
            size: 24,
          ),
        ));
      }
    }

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF0D1B2A),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: const Color(0xFF00E5FF).withValues(alpha: 0.3),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.5),
            blurRadius: 10,
          ),
        ],
      ),
      clipBehavior: Clip.hardEdge,
      child: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter:
                  LatLng(AppConfig.mapInitialLat, AppConfig.mapInitialLng),
              initialZoom: AppConfig.mapInitialZoom,
              interactionOptions: const InteractionOptions(
                  flags: InteractiveFlag
                      .none), // Locking interaction for dashboard
            ),
            children: [
              TileLayer(
                urlTemplate: AppConfig.mapTileUrl,
                subdomains: const ['a', 'b', 'c', 'd'],
                maxZoom: 20,
              ),

              // Planned route (Dashed)
              PolylineLayer<Object>(
                polylines: [
                  Polyline<Object>(
                    points: _waypoints,
                    color: const Color(0xFF7C4DFF).withValues(alpha: 0.6),
                    strokeWidth: 2,
                  ),
                ],
              ),

              // Drone trail (Actual path)
              if (_positionHistory.length >= 2)
                PolylineLayer<Object>(
                  polylines: [
                    Polyline<Object>(
                      points: List.from(_positionHistory),
                      color: const Color(0xFF00E5FF).withValues(alpha: 0.8),
                      strokeWidth: 4,
                    ),
                  ],
                ),

              // Rescue Waypoints (Current & Target)
              MarkerLayer(
                markers: [
                  // Currently moving towards
                  if (t.currentWaypoint > 0 &&
                      t.currentWaypoint <= _waypoints.length)
                    Marker(
                      point: _waypoints[t.currentWaypoint - 1],
                      width: 20,
                      height: 20,
                      child: Container(
                        decoration: BoxDecoration(
                          color: const Color(0xFF00E676).withValues(alpha: 0.3),
                          shape: BoxShape.circle,
                          border: Border.all(
                              color: const Color(0xFF00E676), width: 2),
                        ),
                        child: const Center(
                          child: Icon(Icons.location_searching,
                              size: 12, color: Colors.white),
                        ),
                      ),
                    ),
                ],
              ),

              // Victims
              if (victimMarkers.isNotEmpty) MarkerLayer(markers: victimMarkers),

              // Drone Marker
              if (hasTelemetry)
                MarkerLayer(
                  markers: [
                    Marker(
                      point: dronePos,
                      width: 40,
                      height: 40,
                      child: Icon(
                        Icons.flight,
                        color: const Color(0xFF00E5FF),
                        size: 28,
                      ),
                    ),
                  ],
                ),
            ],
          ),

          // Label Overlay
          Positioned(
            top: 10,
            left: 10,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.6),
                border: Border.all(
                    color: const Color(0xFF00E5FF).withValues(alpha: 0.3)),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Row(
                children: [
                  const Icon(Icons.satellite_alt,
                      color: Color(0xFF00E5FF), size: 12),
                  const SizedBox(width: 6),
                  Text(
                    hasRealGps ? 'GPS LIVE' : 'TACTICAL MAP',
                    style: GoogleFonts.rajdhani(
                      color: hasRealGps
                          ? const Color(0xFF00E676)
                          : const Color(0xFF00E5FF),
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1,
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Stats Minimap Overlay
          Positioned(
            bottom: 10,
            left: 10,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.6),
                border: Border.all(color: Colors.white24),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                'TARGET WP: ${t.currentWaypoint}',
                style: GoogleFonts.sourceCodePro(
                  color: Colors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
