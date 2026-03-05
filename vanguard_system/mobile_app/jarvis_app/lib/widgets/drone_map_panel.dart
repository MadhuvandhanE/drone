/// Drone Map Panel
/// ===============
/// Tactical satellite map using the Google Maps Flutter SDK.
///
/// Data priority
/// -------------
/// 1. Phone GPS (LocationService)  â€” real device, best accuracy
/// 2. Backend GPS (DroneLocationService) â€” phone_client.py simulation
/// 3. Simulated telemetry (TelemetryService) â€” offline fallback
library;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
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
  GoogleMapController? _mapController;

  /// Up to 200 consecutive GPS positions â†’ drawn as cyan polyline trail.
  final List<LatLng> _trail = [];

  /// Last position placed on the map (avoids redundant camera moves).
  LatLng _dronePos = LatLng(AppConfig.mapInitialLat, AppConfig.mapInitialLng);

  final Map<MarkerId,   Marker>   _markers   = {};
  final Map<PolylineId, Polyline> _polylines = {};
  bool _mapReady = false;

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

  // â”€â”€ Map update â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  void _updateMap(LatLng pos) {
    if (!mounted || !_mapReady) return;

    if (_trail.isEmpty || _trail.last != pos) {
      _trail.add(pos);
      if (_trail.length > 200) _trail.removeAt(0);
    }

    const mid = MarkerId('drone');
    setState(() {
      _dronePos = pos;
      _markers[mid] = Marker(
        markerId: mid,
        position: pos,
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
        infoWindow: const InfoWindow(title: 'Drone', snippet: 'Live position'),
        zIndexInt: 10,
      );
      if (_trail.length >= 2) {
        const pid = PolylineId('trail');
        _polylines[pid] = Polyline(
          polylineId: pid,
          points: List.from(_trail),
          color: const Color(0xFF00E5FF),
          width: 3,
        );
      }
    });

    _mapController?.animateCamera(CameraUpdate.newLatLng(pos));
  }

  void _onMapCreated(GoogleMapController c) {
    _mapController = c;
    setState(() => _mapReady = true);
    _updateMap(_dronePos);
  }

  // â”€â”€ Build â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

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
          // â”€â”€ Google Map â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
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
            compassEnabled: false,
          ),

          // â”€â”€ GPS source badge â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
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

          // â”€â”€ Coordinates readout â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
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

          // â”€â”€ Loading overlay â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
          if (!_mapReady)
            Container(
              color: const Color(0xFF0D1B2A),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const CircularProgressIndicator(
                      valueColor: AlwaysStoppedAnimation(Color(0xFF00E5FF)),
                      strokeWidth: 2,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'LOADING MAPâ€¦',
                      style: GoogleFonts.sourceCodePro(
                        color: const Color(0xFF00E5FF).withValues(alpha: 0.7),
                        fontSize: 11,
                        letterSpacing: 2,
                      ),
                    ),
                  ],
                ),
              ),
            ),
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
