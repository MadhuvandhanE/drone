/// Map Screen – Mapbox Integration
/// ================================
/// Displays a real Mapbox satellite map with:
/// • Live drone position marker (updates every second)
/// • Flight path trail (polyline of position history)
/// • Planned waypoint route (dotted polyline)
/// • Waypoint markers with numbered labels
/// • Detected victim markers (orange pins)
/// • Speed & altitude HUD overlay
///
/// Uses flutter_map with Mapbox tile server.
library;

import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import '../services/telemetry_service.dart';
import '../core/config.dart';

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  final MapController _mapController = MapController();

  // Track drone position history for the flight trail
  final List<LatLng> _positionHistory = [];

  // Patrol waypoints from config
  late final List<LatLng> _waypoints;

  @override
  void initState() {
    super.initState();
    _waypoints =
        AppConfig.patrolWaypoints.map((wp) => LatLng(wp[0], wp[1])).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<TelemetryService>(
      builder: (context, service, _) {
        final t = service.telemetry;
        final dronePos = LatLng(t.latitude, t.longitude);

        // Track position history for flight trail
        if (service.isConnected) {
          if (_positionHistory.isEmpty || _positionHistory.last != dronePos) {
            _positionHistory.add(dronePos);
            if (_positionHistory.length > 200) {
              _positionHistory.removeAt(0);
            }
          }
        }

        // Build victim markers from detections
        final victimMarkers = _buildVictimMarkers(service.detections);

        return Stack(
          children: [
            // ── Mapbox Map ──────────────────────────────────────
            FlutterMap(
              mapController: _mapController,
              options: MapOptions(
                initialCenter: LatLng(
                  AppConfig.mapInitialLat,
                  AppConfig.mapInitialLng,
                ),
                initialZoom: AppConfig.mapInitialZoom,
                maxZoom: 20,
                minZoom: 10,
                backgroundColor: const Color(0xFF0A1628),
              ),
              children: [
                // CartoDB Dark Matter tile layer
                TileLayer(
                  urlTemplate: AppConfig.mapTileUrl,
                  subdomains: const ['a', 'b', 'c', 'd'],
                  maxZoom: 20,
                  userAgentPackageName: 'com.jarvis.app',
                ),

                // ── Planned waypoint route (dashed-style) ──
                PolylineLayer<Object>(
                  polylines: [
                    Polyline<Object>(
                      points: _waypoints,
                      color: const Color(0xFF7C4DFF).withValues(alpha: 0.6),
                      strokeWidth: 2.5,
                      // pattern: StrokePattern.dashed(...), can be added if needed, omitting for compatibility
                    ),
                  ],
                ),

                // ── Flight trail (actual path taken) ──
                if (_positionHistory.length >= 2)
                  PolylineLayer<Object>(
                    polylines: [
                      Polyline<Object>(
                        points: List.from(_positionHistory),
                        color: const Color(0xFF00E5FF).withValues(alpha: 0.8),
                        strokeWidth: 3,
                      ),
                    ],
                  ),

                // ── Waypoint markers ──
                MarkerLayer(
                  markers: _buildWaypointMarkers(),
                ),

                // ── Victim detection markers ──
                if (victimMarkers.isNotEmpty)
                  MarkerLayer(markers: victimMarkers),

                // ── Drone marker (on top) ──
                if (service.isConnected)
                  MarkerLayer(
                    markers: [
                      Marker(
                        point: dronePos,
                        width: 60,
                        height: 60,
                        child: _DroneMarkerWidget(
                          speed: t.speed,
                          heading: _calculateHeading(),
                        ),
                      ),
                    ],
                  ),
              ],
            ),

            // ── Top Status Bar ──────────────────────────────────
            Positioned(
              top: 16,
              left: 16,
              right: 16,
              child: _buildTopBar(t, service.isConnected),
            ),

            // ── Speed & Altitude HUD ────────────────────────────
            Positioned(
              top: 80,
              right: 16,
              child: _buildTelemetryHUD(t),
            ),

            // ── Bottom Control Panel ────────────────────────────
            Positioned(
              bottom: 16,
              left: 16,
              right: 16,
              child: _buildBottomPanel(t, service),
            ),

            // ── Detection overlay ───────────────────────────────
            if (service.detections != null)
              Positioned(
                bottom: 180,
                left: 16,
                right: 16,
                child: _buildDetectionsPanel(service.detections!),
              ),
          ],
        );
      },
    );
  }

  // ──────────────────────────────────────────────────────────────
  // Marker Builders
  // ──────────────────────────────────────────────────────────────

  /// Build numbered waypoint markers
  List<Marker> _buildWaypointMarkers() {
    return List.generate(_waypoints.length, (i) {
      final isStart = i == 0;
      return Marker(
        point: _waypoints[i],
        width: 28,
        height: 28,
        child: Container(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: isStart
                ? const Color(0xFF00E676).withValues(alpha: 0.9)
                : const Color(0xFF7C4DFF).withValues(alpha: 0.7),
            border: Border.all(color: Colors.white, width: 1.5),
            boxShadow: [
              BoxShadow(
                color: (isStart
                        ? const Color(0xFF00E676)
                        : const Color(0xFF7C4DFF))
                    .withValues(alpha: 0.4),
                blurRadius: 6,
              ),
            ],
          ),
          child: Center(
            child: Text(
              '$i',
              style: GoogleFonts.sourceCodePro(
                color: Colors.white,
                fontSize: 10,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
      );
    });
  }

  /// Build victim detection markers
  List<Marker> _buildVictimMarkers(Map<String, dynamic>? detections) {
    if (detections == null) return [];
    final victims = detections['victims'] as List<dynamic>? ?? [];

    return victims.map<Marker>((v) {
      final victim = v as Map<String, dynamic>;
      final lat = (victim['lat'] as num?)?.toDouble() ?? 0;
      final lon = (victim['lon'] as num?)?.toDouble() ?? 0;
      final confidence = (victim['confidence'] as num?)?.toDouble() ?? 0;

      return Marker(
        point: LatLng(lat, lon),
        width: 40,
        height: 48,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
              decoration: BoxDecoration(
                color: const Color(0xFFFF6E40),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                '${(confidence * 100).toInt()}%',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 8,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const Icon(
              Icons.person_pin_circle,
              color: Color(0xFFFF6E40),
              size: 30,
            ),
          ],
        ),
      );
    }).toList();
  }

  /// Calculate drone heading from position history
  double _calculateHeading() {
    if (_positionHistory.length < 2) return 0;
    final prev = _positionHistory[_positionHistory.length - 2];
    final curr = _positionHistory.last;
    return math.atan2(
          curr.longitude - prev.longitude,
          curr.latitude - prev.latitude,
        ) *
        180 /
        math.pi;
  }

  // ──────────────────────────────────────────────────────────────
  // UI Overlay Builders
  // ──────────────────────────────────────────────────────────────

  Widget _buildTopBar(telemetry, bool isConnected) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            const Color(0xFF0D1B2A).withValues(alpha: 0.95),
            const Color(0xFF1B2838).withValues(alpha: 0.95),
          ],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: const Color(0xFF00E5FF).withValues(alpha: 0.2),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.4),
            blurRadius: 12,
          ),
        ],
      ),
      child: Row(
        children: [
          const Icon(Icons.satellite_alt, color: Color(0xFF00E5FF), size: 18),
          const SizedBox(width: 10),
          Text(
            'MAPBOX LIVE TRACKING',
            style: GoogleFonts.rajdhani(
              color: const Color(0xFF00E5FF),
              fontSize: 13,
              fontWeight: FontWeight.w700,
              letterSpacing: 2,
            ),
          ),
          const Spacer(),
          // Coordinate readout
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '${telemetry.latitude.toStringAsFixed(5)}°N',
                style: GoogleFonts.sourceCodePro(
                  color: Colors.white70,
                  fontSize: 10,
                ),
              ),
              Text(
                '${telemetry.longitude.toStringAsFixed(5)}°E',
                style: GoogleFonts.sourceCodePro(
                  color: Colors.white70,
                  fontSize: 10,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTelemetryHUD(telemetry) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF0D1B2A).withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: const Color(0xFF00E5FF).withValues(alpha: 0.15),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisSize: MainAxisSize.min,
        children: [
          _hudItem(Icons.speed, '${telemetry.speed.toStringAsFixed(1)}', 'm/s',
              'SPEED', const Color(0xFF00E5FF)),
          const SizedBox(height: 10),
          _hudItem(Icons.height, '${telemetry.altitude.toStringAsFixed(1)}',
              'm', 'ALT', const Color(0xFF7C4DFF)),
          const SizedBox(height: 10),
          _hudItem(Icons.water, '${telemetry.waterDepth.toStringAsFixed(1)}',
              'm', 'DEPTH', const Color(0xFF448AFF)),
          const SizedBox(height: 10),
          _hudItem(
              Icons.battery_std,
              '${telemetry.battery}',
              '%',
              'BAT',
              telemetry.battery > 30
                  ? const Color(0xFF00E676)
                  : const Color(0xFFFF5252)),
          const SizedBox(height: 10),
          _hudItem(
              Icons.route,
              '${telemetry.currentWaypoint}/${telemetry.totalWaypoints}',
              '',
              'WP',
              const Color(0xFFFFAB40)),
        ],
      ),
    );
  }

  Widget _hudItem(
      IconData icon, String value, String unit, String label, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              label,
              style: GoogleFonts.rajdhani(
                color: Colors.white30,
                fontSize: 9,
                fontWeight: FontWeight.w600,
                letterSpacing: 1,
              ),
            ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  value,
                  style: GoogleFonts.orbitron(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (unit.isNotEmpty) ...[
                  const SizedBox(width: 2),
                  Text(
                    unit,
                    style: GoogleFonts.rajdhani(
                      color: color,
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
        const SizedBox(width: 8),
        Icon(icon, color: color, size: 16),
      ],
    );
  }

  Widget _buildBottomPanel(telemetry, TelemetryService service) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            const Color(0xFF0D1B2A).withValues(alpha: 0.95),
            const Color(0xFF1B2838).withValues(alpha: 0.95),
          ],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: const Color(0xFF00E5FF).withValues(alpha: 0.2),
        ),
      ),
      child: Row(
        children: [
          // Center on drone button
          Expanded(
            child: _actionButton(
              icon: Icons.my_location,
              label: 'CENTER',
              onTap: () {
                _mapController.move(
                  LatLng(telemetry.latitude, telemetry.longitude),
                  AppConfig.mapInitialZoom,
                );
              },
            ),
          ),
          const SizedBox(width: 10),
          // Toggle follow mode
          Expanded(
            child: _actionButton(
              icon: Icons.route,
              label: 'SHOW ROUTE',
              color: const Color(0xFF7C4DFF),
              onTap: () {
                // Zoom to fit all waypoints
                final bounds = LatLngBounds.fromPoints(_waypoints);
                _mapController.fitCamera(
                  CameraFit.bounds(
                    bounds: bounds,
                    padding: const EdgeInsets.all(60),
                  ),
                );
              },
            ),
          ),
          const SizedBox(width: 10),
          // Fetch detections
          Expanded(
            child: _actionButton(
              icon: Icons.person_search,
              label: 'VICTIMS',
              color: const Color(0xFFFF6E40),
              onTap: () => service.fetchDetections(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _actionButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    Color color = const Color(0xFF00E5FF),
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: color, size: 16),
            const SizedBox(width: 6),
            Text(
              label,
              style: GoogleFonts.rajdhani(
                color: color,
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 1,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDetectionsPanel(Map<String, dynamic> detections) {
    final victims = detections['victims'] as List<dynamic>? ?? [];
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF0D1B2A).withValues(alpha: 0.95),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: const Color(0xFFFF6E40).withValues(alpha: 0.3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              const Icon(Icons.person_pin_circle,
                  color: Color(0xFFFF6E40), size: 18),
              const SizedBox(width: 8),
              Text(
                'DETECTIONS (${victims.length})',
                style: GoogleFonts.rajdhani(
                  color: const Color(0xFFFF6E40),
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.5,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ...victims.take(4).map<Widget>((v) {
            final victim = v as Map<String, dynamic>;
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                children: [
                  Container(
                    width: 6,
                    height: 6,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      color: Color(0xFFFF6E40),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '${(victim['lat'] as num?)?.toStringAsFixed(4) ?? '?'}°N, '
                    '${(victim['lon'] as num?)?.toStringAsFixed(4) ?? '?'}°E',
                    style: GoogleFonts.sourceCodePro(
                      color: Colors.white70,
                      fontSize: 11,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    '${((victim['confidence'] as num?) != null ? ((victim['confidence'] as num) * 100).toInt() : 0)}%',
                    style: GoogleFonts.orbitron(
                      color: const Color(0xFFFF6E40),
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════
// Custom Drone Marker Widget
// ════════════════════════════════════════════════════════════════

class _DroneMarkerWidget extends StatefulWidget {
  final double speed;
  final double heading;

  const _DroneMarkerWidget({
    required this.speed,
    required this.heading,
  });

  @override
  State<_DroneMarkerWidget> createState() => _DroneMarkerWidgetState();
}

class _DroneMarkerWidgetState extends State<_DroneMarkerWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _pulseController,
      builder: (context, _) {
        final pulse = 0.8 + 0.2 * _pulseController.value;
        return Transform.scale(
          scale: pulse,
          child: Transform.rotate(
            angle: widget.heading * math.pi / 180,
            child: Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    const Color(0xFF00E5FF).withValues(alpha: 0.3),
                    const Color(0xFF00E5FF).withValues(alpha: 0.05),
                  ],
                ),
                border: Border.all(
                  color: const Color(0xFF00E5FF).withValues(alpha: 0.8),
                  width: 2,
                ),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF00E5FF).withValues(alpha: 0.5),
                    blurRadius: 20,
                    spreadRadius: 4,
                  ),
                ],
              ),
              child: const Center(
                child: Icon(
                  Icons.navigation,
                  color: Color(0xFF00E5FF),
                  size: 24,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
