/// Map Screen â€“ Google Maps Integration
/// ======================================
/// Full-screen tactical map using the Google Maps Flutter SDK.
///
/// â€¢ Satellite imagery + dark tactical style overlay
/// â€¢ Live drone position marker (blue, updates every second)
/// â€¢ Flight path trail (cyan polyline)
/// â€¢ Planned waypoint route (purple polyline)
/// â€¢ Numbered waypoint markers
/// â€¢ Detected victim markers (orange)
/// â€¢ Speed / altitude / battery HUD overlay
/// â€¢ Center-on-drone and show-route buttons
library;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
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
  GoogleMapController? _mapController;

  final List<LatLng> _trail = [];
  late final List<LatLng> _waypoints;

  final Map<MarkerId,   Marker>   _markers   = {};
  final Map<PolylineId, Polyline> _polylines = {};

  @override
  void initState() {
    super.initState();
    _waypoints = AppConfig.patrolWaypoints
        .map((wp) => LatLng(wp[0], wp[1]))
        .toList();
  }

  @override
  void dispose() {
    _mapController?.dispose();
    super.dispose();
  }

  // â”€â”€ Position resolution â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  LatLng _resolvePosition() {
    final gps = context.read<LocationService>();
    if (gps.hasPosition) return LatLng(gps.latitude!, gps.longitude!);

    final backend = context.read<DroneLocationService>();
    if (backend.hasLocation) return LatLng(backend.latitude!, backend.longitude!);

    final t = context.read<TelemetryService>().telemetry;
    return LatLng(t.latitude, t.longitude);
  }

  // â”€â”€ Map â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  void _onMapCreated(GoogleMapController c) {
    _mapController = c;
    _rebuildOverlays();
  }

  void _rebuildOverlays() {
    if (!mounted) return;
    final pos = _resolvePosition();

    // Update trail
    if (_trail.isEmpty || _trail.last != pos) {
      _trail.add(pos);
      if (_trail.length > 300) _trail.removeAt(0);
    }

    final newMarkers   = <MarkerId,   Marker>{};
    final newPolylines = <PolylineId, Polyline>{};

    // Drone marker
    newMarkers[const MarkerId('drone')] = Marker(
      markerId: const MarkerId('drone'),
      position: pos,
      icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
      infoWindow: const InfoWindow(title: 'Drone', snippet: 'Live position'),
      zIndexInt: 20,
    );

    // Waypoint markers
    for (int i = 0; i < _waypoints.length; i++) {
      final mid = MarkerId('wp_$i');
      newMarkers[mid] = Marker(
        markerId: mid,
        position: _waypoints[i],
        icon: BitmapDescriptor.defaultMarkerWithHue(
          i == 0 ? BitmapDescriptor.hueGreen : BitmapDescriptor.hueViolet,
        ),
        infoWindow: InfoWindow(title: 'WP $i'),
        zIndexInt: 5,
      );
    }

    // Victim markers from detections
    final detections = context.read<TelemetryService>().detections;
    if (detections != null) {
      final victims = detections['victims'] as List<dynamic>? ?? [];
      for (int i = 0; i < victims.length; i++) {
        final v   = victims[i] as Map<String, dynamic>;
        final lat = (v['lat'] as num?)?.toDouble() ?? 0;
        final lon = (v['lon'] as num?)?.toDouble() ?? 0;
        final mid = MarkerId('victim_$i');
        newMarkers[mid] = Marker(
          markerId: mid,
          position: LatLng(lat, lon),
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueOrange),
          infoWindow: InfoWindow(
            title: 'Victim ${i + 1}',
            snippet:
                '${((v['confidence'] as num?)?.toDouble() ?? 0) * 100 ~/ 1}% confidence',
          ),
          zIndexInt: 15,
        );
      }
    }

    // Planned route polyline (purple)
    if (_waypoints.length >= 2) {
      newPolylines[const PolylineId('route')] = Polyline(
        polylineId: const PolylineId('route'),
        points: _waypoints,
        color: const Color(0xFF7C4DFF).withValues(alpha: 0.7),
        width: 2,
        patterns: [PatternItem.dash(20), PatternItem.gap(10)],
      );
    }

    // Flight trail (cyan)
    if (_trail.length >= 2) {
      newPolylines[const PolylineId('trail')] = Polyline(
        polylineId: const PolylineId('trail'),
        points: List.from(_trail),
        color: const Color(0xFF00E5FF).withValues(alpha: 0.85),
        width: 3,
      );
    }

    setState(() {
      _markers.clear();
      _markers.addAll(newMarkers);
      _polylines.clear();
      _polylines.addAll(newPolylines);
    });

    _mapController?.animateCamera(CameraUpdate.newLatLng(pos));
  }

  void _centerOnDrone() {
    final pos = _resolvePosition();
    _mapController?.animateCamera(
      CameraUpdate.newCameraPosition(
        CameraPosition(target: pos, zoom: AppConfig.mapInitialZoom),
      ),
    );
  }

  void _showRoute() {
    if (_waypoints.isEmpty) return;
    final bounds = _latLngBounds(_waypoints);
    _mapController?.animateCamera(
      CameraUpdate.newLatLngBounds(bounds, 60),
    );
  }

  LatLngBounds _latLngBounds(List<LatLng> points) {
    double minLat = points.first.latitude,  maxLat = points.first.latitude;
    double minLng = points.first.longitude, maxLng = points.first.longitude;
    for (final p in points) {
      if (p.latitude  < minLat) minLat = p.latitude;
      if (p.latitude  > maxLat) maxLat = p.latitude;
      if (p.longitude < minLng) minLng = p.longitude;
      if (p.longitude > maxLng) maxLng = p.longitude;
    }
    return LatLngBounds(
      southwest: LatLng(minLat, minLng),
      northeast: LatLng(maxLat, maxLng),
    );
  }

  // â”€â”€ Build â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  @override
  Widget build(BuildContext context) {
    context.watch<LocationService>();
    context.watch<DroneLocationService>();

    return Consumer<TelemetryService>(
      builder: (context, service, _) {
        final t   = service.telemetry;
        final pos = _resolvePosition();

        WidgetsBinding.instance.addPostFrameCallback(
          (_) => _rebuildOverlays(),
        );

        return Stack(
          children: [
            // â”€â”€ Google Map â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
            GoogleMap(
              onMapCreated: _onMapCreated,
              initialCameraPosition: CameraPosition(
                target: LatLng(AppConfig.mapInitialLat, AppConfig.mapInitialLng),
                zoom: AppConfig.mapInitialZoom,
              ),
              mapType: MapType.satellite,
              style: _darkMapStyle,
              markers: Set<Marker>.of(_markers.values),
              polylines: Set<Polyline>.of(_polylines.values),
              myLocationEnabled: false,
              zoomControlsEnabled: false,
              mapToolbarEnabled: false,
              compassEnabled: true,
            ),

            // â”€â”€ Top status bar â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
            Positioned(
              top: 16, left: 16, right: 16,
              child: _TopBar(telemetry: t, isConnected: service.isConnected, pos: pos),
            ),

            // â”€â”€ Right HUD â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
            Positioned(
              top: 90, right: 16,
              child: _TelemetryHUD(telemetry: t),
            ),

            // â”€â”€ Bottom controls â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
            Positioned(
              bottom: 20, left: 16, right: 16,
              child: _BottomControls(
                onCenter:    _centerOnDrone,
                onRoute:     _showRoute,
                onVictims:   () => service.fetchDetections(),
              ),
            ),

            // â”€â”€ Detections panel â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
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

// â”€â”€ Reusable sub-widgets â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

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
        const Icon(Icons.satellite_alt, color: Color(0xFF00E5FF), size: 18),
        const SizedBox(width: 10),
        Text('GOOGLE MAPS  Â·  SATELLITE',
            style: GoogleFonts.rajdhani(
                color: const Color(0xFF00E5FF),
                fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 1.5)),
        const Spacer(),
        Column(crossAxisAlignment: CrossAxisAlignment.end, mainAxisSize: MainAxisSize.min, children: [
          Text('${pos.latitude.toStringAsFixed(5)}Â° N',
              style: GoogleFonts.sourceCodePro(color: Colors.white60, fontSize: 9)),
          Text('${pos.longitude.toStringAsFixed(5)}Â° E',
              style: GoogleFonts.sourceCodePro(color: Colors.white60, fontSize: 9)),
        ]),
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
          _row(Icons.speed,      '${telemetry.speed.toStringAsFixed(1)}', 'm/s', 'SPD', const Color(0xFF00E5FF)),
          const SizedBox(height: 8),
          _row(Icons.height,     '${telemetry.altitude.toStringAsFixed(1)}', 'm', 'ALT', const Color(0xFF7C4DFF)),
          const SizedBox(height: 8),
          _row(Icons.battery_std,'${telemetry.battery}', '%', 'BAT',
              telemetry.battery > 30 ? const Color(0xFF00E676) : const Color(0xFFFF5252)),
          const SizedBox(height: 8),
          _row(Icons.route,      '${telemetry.currentWaypoint}/${telemetry.totalWaypoints}', '', 'WP', const Color(0xFFFFAB40)),
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
            if (unit.isNotEmpty) ...[
              const SizedBox(width: 2),
              Text(unit, style: GoogleFonts.rajdhani(color: c, fontSize: 10)),
            ],
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
            Text(label, style: GoogleFonts.rajdhani(color: color, fontSize: 11,
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
                style: GoogleFonts.rajdhani(color: const Color(0xFFFF6E40),
                    fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 1.5)),
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
                Text('${(victim['lat'] as num?)?.toStringAsFixed(4) ?? '?'}Â°N  '
                     '${(victim['lon'] as num?)?.toStringAsFixed(4) ?? '?'}Â°E',
                    style: GoogleFonts.sourceCodePro(color: Colors.white60, fontSize: 10)),
                const Spacer(),
                Text('${conf.toInt()}%',
                    style: GoogleFonts.orbitron(color: const Color(0xFFFF6E40),
                        fontSize: 10, fontWeight: FontWeight.w600)),
              ]),
            );
          }),
        ],
      ),
    );
  }
}

// â”€â”€ Dark tactical Google Maps style â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
const String _darkMapStyle = '''
[
  {"elementType":"geometry","stylers":[{"color":"#0d1117"}]},
  {"elementType":"labels.text.fill","stylers":[{"color":"#4a6377"}]},
  {"elementType":"labels.text.stroke","stylers":[{"color":"#080d14"}]},
  {"featureType":"administrative","elementType":"geometry","stylers":[{"color":"#1a2942"}]},
  {"featureType":"administrative.country","elementType":"labels.text.fill","stylers":[{"color":"#5c8aaa"}]},
  {"featureType":"administrative.locality","elementType":"labels.text.fill","stylers":[{"color":"#6fa8c8"}]},
  {"featureType":"poi","elementType":"labels.text.fill","stylers":[{"color":"#3a5468"}]},
  {"featureType":"poi.park","elementType":"geometry","stylers":[{"color":"#0a1a10"}]},
  {"featureType":"road","elementType":"geometry","stylers":[{"color":"#1a2942"}]},
  {"featureType":"road.highway","elementType":"geometry","stylers":[{"color":"#1f4068"}]},
  {"featureType":"transit","elementType":"geometry","stylers":[{"color":"#0f1f30"}]},
  {"featureType":"water","elementType":"geometry","stylers":[{"color":"#0a111a"}]}
]
''';
