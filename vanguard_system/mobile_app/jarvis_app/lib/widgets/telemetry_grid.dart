import 'package:flutter/material.dart';
import '../services/telemetry_service.dart';
import 'telemetry_card.dart';

class TelemetryGrid extends StatelessWidget {
  final TelemetryService service;

  const TelemetryGrid({super.key, required this.service});

  @override
  Widget build(BuildContext context) {
    final t = service.telemetry;

    return LayoutBuilder(
      builder: (context, constraints) {
        int crossAxisCount = 2; // Mobile
        if (constraints.maxWidth > 800) {
          crossAxisCount = 4; // Desktop
        } else if (constraints.maxWidth > 600) {
          crossAxisCount = 3; // Tablet
        }

        return GridView.count(
          physics: const NeverScrollableScrollPhysics(),
          shrinkWrap: true,
          crossAxisCount: crossAxisCount,
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          childAspectRatio: 2.2,
          children: [
            TelemetryCard(
              label: 'Battery',
              value: '${t.battery}',
              unit: '%',
              icon: Icons.battery_charging_full,
              accentColor: _batteryColor(t.battery),
              progress: t.battery / 100,
            ),
            TelemetryCard(
              label: 'Altitude',
              value: t.altitude.toStringAsFixed(1),
              unit: 'm',
              icon: Icons.height,
              accentColor: const Color(0xFF7C4DFF),
            ),
            TelemetryCard(
              label: 'Speed',
              value: t.speed.toStringAsFixed(1),
              unit: 'm/s',
              icon: Icons.speed,
              accentColor: const Color(0xFF00E5FF),
            ),
            TelemetryCard(
              label: 'Signal',
              value: '${t.signalStrength}',
              unit: '%',
              icon: Icons.signal_cellular_alt,
              accentColor: _signalColor(t.signalStrength),
              progress: t.signalStrength / 100,
            ),
            TelemetryCard(
              label: 'Phantom Depth',
              value: t.waterDepth.toStringAsFixed(1),
              unit: 'm',
              icon: Icons
                  .camera_front, // Reflecting it comes from the camera feed
              accentColor: const Color(0xFF448AFF),
            ),
            TelemetryCard(
              label: 'Coordinates',
              value: '${t.latitude.toStringAsFixed(4)}°',
              unit: 'lat',
              icon: Icons.location_on,
              accentColor: const Color(0xFFFF6E40),
            ),
            TelemetryCard(
              label: 'Mission WP',
              value: '${t.currentWaypoint}/${t.totalWaypoints}',
              unit: '',
              icon: Icons.route,
              accentColor: const Color(0xFF00E676),
              progress: t.totalWaypoints > 0
                  ? t.currentWaypoint / t.totalWaypoints
                  : 0,
            ),
          ],
        );
      },
    );
  }

  Color _batteryColor(int level) {
    if (level > 60) return const Color(0xFF00E676);
    if (level > 30) return const Color(0xFFFFAB40);
    return const Color(0xFFFF5252);
  }

  Color _signalColor(int strength) {
    if (strength > 70) return const Color(0xFF00E676);
    if (strength > 40) return const Color(0xFFFFAB40);
    return const Color(0xFFFF5252);
  }
}
