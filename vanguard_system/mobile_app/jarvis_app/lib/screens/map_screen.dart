/// Map Screen -- OpenStreetMap Tactical View
/// ==========================================
/// Full-screen map using flutter_map + OpenStreetMap (free, no API key).
///
/// Features
/// --------
/// * OSM tile layer (https://tile.openstreetmap.org/{z}/{x}/{y}.png)
/// * Blue drone marker (Icons.location_on) that follows phone GPS
/// * Cyan flight-trail polyline (last 300 positions)
/// * Planned waypoint route (dotted purple polyline + numbered markers)
/// * Speed / Altitude / Battery HUD overlay
/// * CENTER and ROUTE control buttons
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

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  final MapController _mapController = MapController();

  final List<LatLng> _trail = [];
  late final List<LatLng> _waypoints;

  LatLng _dronePos = LatLng(AppConfig.mapInitialLat, AppConfig.mapInitialLng);

  @override
  void initState() {
    super.initState();
    _waypoints = AppConfig.patrolWaypoints
        .map((wp) => LatLng(wp[0], wp[1]))
        .toList();
  }

  // --- Position resolution -------------------------------------------------

  LatLng _resolvePosition() {
    final gps = context.read<LocationService>();
    if (gps.hasPosition) return LatLng(gps.latitude!, gps.longitude!);

    final backend = context.read<DroneLocationService>();
    if (backend.hasLocation) return LatLng(backend.latitude!, backend.longitude!);

    final t = context.read<TelemetryService>().telemetry;
    return LatLng(t.latitude, t.longitude);
  }

  // --- Map update ----------------------------------------------------------

  void _updateMap(LatLng pos) {
    if (!mounted) return;
    if (_trail.isEmpty || _trail.last != pos) {
      _trail.add(pos);
      if (_trail.length > 300) _trail.removeAt(0);
    }
    setState(() => _dronePos = pos);
    _mapController.move(pos, _mapController.camera.zoom);
  }

  void _centerOnDrone() {
    _mapController.move(
      _dronePos,
      AppConfig.mapInitialZoom,
    );
  }

  void _showRoute() {
    if (_waypoints.isEmpty) return;
    final bounds = LatLngBounds.fromPoints(_waypoints);
    _mapController.fitCamera(
      CameraFit.bounds(bounds: bounds, padding: const EdgeInsets.all(60)),
    );
  }

  // --- Build ---------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    context.watch<LocationService>();
    context.watch<DroneLocationService>();

    return Consumer<TelemetryService>(
      builder: (context, service, _) {
        final t   = service.telemetry;
        final pos = _resolvePosition();

        WidgetsBinding.instance.addPostFrameCallback((_) => _updateMap(pos));

        return Stack(
          children: [
            // --- OSM map ---------------------------------------------------
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
                // OSM tiles
                TileLayer(
                  urlTemplate:
                      'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.example.jarvis_app',
                ),

                // Waypoint route (purple dashed)
                if (_waypoints.length >= 2)
                  PolylineLayer(
                    polylines: [
                      Polyline(
                        points: _waypoints,
                        color: const Color(0xFF7C4DFF).withValues(alpha: 0.7),
                        strokeWidth: 2,
                      ),
                    ],
                  ),

                // Flight trail (cyan)
                if (_trail.length >= 2)
                  PolylineLayer(
                    polylines: [
                      Polyline(
                        points: List.from(_trail),
                        color: const Color(0xFF00E5FF).withValues(alpha: 0.85),
                        strokeWidth: 3,
                      ),
                    ],
                  ),

                // Waypoint numbered markers
                MarkerLayer(
                  markers: List.generate(_waypoints.length, (i) {
                    return Marker(
                      point: _waypoints[i],
                      width: 28,
                      height: 28,
                      child: Container(
                        decoration: BoxDecoration(
                          color: i == 0
                              ? const Color(0xFF00E676)
                              : const Color(0xFF7C4DFF),
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 1.5),
                        ),
                        child: Center(
                          child: Text(
                            '$i',
                            style: GoogleFonts.rajdhani(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                    );
                  }),
                ),

                // Drone marker
                MarkerLayer(
                  markers: [
                    Marker(
                      point: _dronePos,
                      width: 42,
                      height: 42,
                      child: const Icon(
                        Icons.location_on,
                        color: Color(0xFF2196F3),
                        size: 42,
                        shadows: [
                          Shadow(color: Colors.black54, blurRadius: 8),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),

            // --- Top status bar --------------------------------------------
            Positioned(
              top: 16, left: 16, right: 16,
              child: _TopBar(telemetry: t, isConnected: service.isConnected, pos: pos),
            ),

            // --- Right HUD ------------------------------------------------
            Positioned(
              top: 90, right: 16,
              child: _TelemetryHUD(telemetry: t),
            ),

            // --- Bottom controls ------------------------------------------
            Positioned(
              bottom: 20, left: 16, right: 16,
              child: _BottomControls(
                onCenter:  _centerOnDrone,
                onRoute:   _showRoute,
                onVictims: () => service.fetchDetections(),
              ),
            ),

            // --- Detections panel -----------------------------------------
            if (service.detections != null)
              Positioned(
                bottom: 100, left: 16, right: 16,
                child: _DetectionsPanel(detections: service.detections!),
              ),
          ],
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Sub-widgets
// ---------------------------------------------------------------------------

class _TopBar extends StatelessWidget {
  final dynamic telemetry;
  final bool isConnected;
  final LatLng pos;
  const _TopBar({required this.telemetry, required this.isConnected, required this.pos});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF0D1B2A).withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF00E5FF).withValues(alpha: 0.2)),
      ),
      child: Row(children: [
        const Icon(Icons.map, color: Color(0xFF00E5FF), size: 18),
        const SizedBox(width: 10),
        Text('OSM LIVE TRACKING',
            style: GoogleFonts.rajdhani(
                color: const Color(0xFF00E5FF),
                fontSize: 12,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.5)),
        const Spacer(),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('${pos.latitude.toStringAsFixed(5)} N',
                style: GoogleFonts.sourceCodePro(color: Colors.white60, fontSize: 9)),
            Text('${pos.longitude.toStringAsFixed(5)} E',
                style: GoogleFonts.sourceCodePro(color: Colors.white60, fontSize: 9)),
          ],
        ),
      ]),
    );
  }
}

class _TelemetryHUD extends StatelessWidget {
  final dynamic telemetry;
  const _TelemetryHUD({required this.telemetry});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF0D1B2A).withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF00E5FF).withValues(alpha: 0.15)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisSize: MainAxisSize.min,
        children: [
          _row(Icons.speed,       '${telemetry.speed.toStringAsFixed(1)}',    'm/s', 'SPD', const Color(0xFF00E5FF)),
          const SizedBox(height: 8),
          _row(Icons.height,      '${telemetry.altitude.toStringAsFixed(1)}', 'm',   'ALT', const Color(0xFF7C4DFF)),
          const SizedBox(height: 8),
          _row(Icons.battery_std, '${telemetry.battery}',                     '%',   'BAT',
              telemetry.battery > 30 ? const Color(0xFF00E676) : const Color(0xFFFF5252)),
          const SizedBox(height: 8),
          _row(Icons.route,
              '${telemetry.currentWaypoint}/${telemetry.totalWaypoints}', '', 'WP',
              const Color(0xFFFFAB40)),
        ],
      ),
    );
  }

  Widget _row(IconData icon, String val, String unit, String label, Color c) =>
      Row(mainAxisSize: MainAxisSize.min, children: [
        Column(crossAxisAlignment: CrossAxisAlignment.end, mainAxisSize: MainAxisSize.min, children: [
          Text(label, style: GoogleFonts.rajdhani(color: Colors.white30, fontSize: 9, letterSpacing: 1)),
          Row(mainAxisSize: MainAxisSize.min, children: [
            Text(val, style: GoogleFonts.orbitron(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
            if (unit.isNotEmpty) ...[const SizedBox(width: 2),
              Text(unit, style: GoogleFonts.rajdhani(color: c, fontSize: 10))],
          ]),
        ]),
        const SizedBox(width: 8),
        Icon(icon, color: c, size: 16),
      ]);
}

class _BottomControls extends StatelessWidget {
  final VoidCallback onCenter;
  final VoidCallback onRoute;
  final VoidCallback onVictims;
  const _BottomControls({required this.onCenter, required this.onRoute, required this.onVictims});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    decoration: BoxDecoration(
      color: const Color(0xFF0D1B2A).withValues(alpha: 0.92),
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: const Color(0xFF00E5FF).withValues(alpha: 0.2)),
    ),
    child: Row(children: [
      Expanded(child: _btn(Icons.my_location,   'CENTER',  const Color(0xFF00E5FF), onCenter)),
      const SizedBox(width: 10),
      Expanded(child: _btn(Icons.route,         'ROUTE',   const Color(0xFF7C4DFF), onRoute)),
      const SizedBox(width: 10),
      Expanded(child: _btn(Icons.person_search, 'VICTIMS', const Color(0xFFFF6E40), onVictims)),
    ]),
  );

  Widget _btn(IconData icon, String label, Color color, VoidCallback onTap) =>
      GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: color.withValues(alpha: 0.3)),
          ),
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(icon, color: color, size: 15),
            const SizedBox(width: 6),
            Text(label, style: GoogleFonts.rajdhani(
                color: color, fontSize: 11,
                fontWeight: FontWeight.w700, letterSpacing: 1)),
          ]),
        ),
      );
}

class _DetectionsPanel extends StatelessWidget {
  final Map<String, dynamic> detections;
  const _DetectionsPanel({required this.detections});

  @override
  Widget build(BuildContext context) {
    final victims = detections['victims'] as List<dynamic>? ?? [];
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF0D1B2A).withValues(alpha: 0.95),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFFF6E40).withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(children: [
            const Icon(Icons.person_pin_circle, color: Color(0xFFFF6E40), size: 16),
            const SizedBox(width: 6),
            Text('DETECTIONS (${victims.length})',
                style: GoogleFonts.rajdhani(
                    color: const Color(0xFFFF6E40),
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.5)),
          ]),
          const SizedBox(height: 8),
          ...victims.take(4).map<Widget>((v) {
            final victim = v as Map<String, dynamic>;
            final conf   = ((victim['confidence'] as num?)?.toDouble() ?? 0) * 100;
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(children: [
                Container(width: 5, height: 5,
                    decoration: const BoxDecoration(shape: BoxShape.circle, color: Color(0xFFFF6E40))),
                const SizedBox(width: 8),
                Text('${(victim['lat'] as num?)?.toStringAsFixed(4) ?? '?'} N  '
                     '${(victim['lon'] as num?)?.toStringAsFixed(4) ?? '?'} E',
                    style: GoogleFonts.sourceCodePro(color: Colors.white60, fontSize: 10)),
                const Spacer(),
                Text('${conf.toInt()}%',
                    style: GoogleFonts.orbitron(
                        color: const Color(0xFFFF6E40),
                        fontSize: 10,
                        fontWeight: FontWeight.w600)),
              ]),
            );
          }),
        ],
      ),
    );
  }
}
