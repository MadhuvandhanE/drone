/// Drone Map Panel
/// ===============
/// Dashboard map widget using flutter_map + OpenStreetMap tiles.
/// Free, no API key required.
///
/// Data priority for drone position simulation
/// -------------------------------------------
/// 1. Phone GPS (LocationService)             – real device, best accuracy
/// 2. Backend GPS (DroneLocationService)      – phone_client.py simulation
/// 3. Simulated telemetry (TelemetryService)  – offline fallback
library;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../services/telemetry_service.dart';
import '../services/location_service.dart';
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

  /// Trail of up to 200 GPS positions -- drawn as a cyan polyline.
  final List<LatLng> _trail = [];

  LatLng _dronePos = LatLng(AppConfig.mapInitialLat, AppConfig.mapInitialLng);

  // --- Position helpers ----------------------------------------------------

  LatLng _resolvePosition() {
    final gps = context.read<LocationService>();
    if (gps.hasPosition) return LatLng(gps.latitude!, gps.longitude!);

    final backend = context.read<DroneLocationService>();
    if (backend.hasLocation) return LatLng(backend.latitude!, backend.longitude!);

    final t = widget.service.telemetry;
    return LatLng(t.latitude, t.longitude);
  }

  String _sourceLabel() {
    final gps = context.read<LocationService>();
    if (gps.hasPosition) return 'GPS LIVE';
    final b = context.read<DroneLocationService>();
    if (b.hasLocation && b.source != 'default') return 'PHONE SIM';
    return 'SIMULATED';
  }

  Color _sourceColor() {
    final gps = context.read<LocationService>();
    if (gps.hasPosition) return const Color(0xFF00E676);
    final b = context.read<DroneLocationService>();
    if (b.hasLocation && b.source != 'default') return const Color(0xFFFFD740);
    return const Color(0xFF00E5FF);
  }

  // --- Map update ----------------------------------------------------------

  void _updateMap(LatLng pos) {
    if (!mounted) return;
    if (_trail.isEmpty || _trail.last != pos) {
      _trail.add(pos);
      if (_trail.length > 200) _trail.removeAt(0);
    }
    setState(() => _dronePos = pos);
    _mapController.move(pos, _mapController.camera.zoom);
  }

  // --- Build ---------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    context.watch<LocationService>();
    context.watch<DroneLocationService>();

    final pos   = _resolvePosition();
    final label = _sourceLabel();
    final color = _sourceColor();

    WidgetsBinding.instance.addPostFrameCallback((_) => _updateMap(pos));

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF0D1B2A),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF00E5FF).withValues(alpha: 0.3)),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.5), blurRadius: 10)],
      ),
      clipBehavior: Clip.hardEdge,
      child: Stack(
        children: [
          // -- OpenStreetMap tile layer -------------------------------------
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: _dronePos,
              initialZoom: AppConfig.mapInitialZoom,
              interactionOptions: const InteractionOptions(
                flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
              ),
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.example.jarvis_app',
              ),

              // Trail polyline
              if (_trail.length >= 2)
                PolylineLayer(
                  polylines: [
                    Polyline(
                      points: List.from(_trail),
                      color: const Color(0xFF00E5FF),
                      strokeWidth: 3,
                    ),
                  ],
                ),

              // Drone marker
              MarkerLayer(
                markers: [
                  Marker(
                    point: _dronePos,
                    width: 36,
                    height: 36,
                    child: const Icon(
                      Icons.location_on,
                      color: Color(0xFF2196F3),
                      size: 36,
                      shadows: [Shadow(color: Colors.black54, blurRadius: 6)],
                    ),
                  ),
                ],
              ),
            ],
          ),

          // -- GPS source badge ---------------------------------------------
          Positioned(
            top: 10, left: 10,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.65),
                border: Border.all(color: color.withValues(alpha: 0.5)),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.satellite_alt, color: color, size: 12),
                  const SizedBox(width: 6),
                  Text(
                    label,
                    style: GoogleFonts.rajdhani(
                      color: color,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1,
                    ),
                  ),
                ],
              ),
            ),
          ),

          // -- Coordinates readout ------------------------------------------
          Positioned(
            bottom: 10, left: 10,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.6),
                border: Border.all(color: Colors.white24),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                '${pos.latitude.toStringAsFixed(5)},  ${pos.longitude.toStringAsFixed(5)}',
                style: GoogleFonts.sourceCodePro(
                  color: Colors.white70,
                  fontSize: 9,
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
