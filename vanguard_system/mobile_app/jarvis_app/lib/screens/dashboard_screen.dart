/// Dashboard Screen
/// ================
/// Primary situational awareness interface.
/// Prioritizes live video feed and tactical map over telemetry metrics.
library;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../services/telemetry_service.dart';
import '../widgets/live_feed_panel.dart';
import '../widgets/drone_map_panel.dart';
import '../widgets/telemetry_grid.dart';

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<TelemetryService>(
      builder: (context, service, _) {
        final t = service.telemetry;
        final isOnline = service.isConnected;

        return Scaffold(
          backgroundColor:
              Colors.transparent, // Background handled by main.dart
          body: Column(
            children: [
              // ── Top Action/Status Bar ──
              _buildTopStatusBar(t, isOnline, service),

              // ── Main Content Area ──
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final isDesktop = constraints.maxWidth > 900;

                    if (isDesktop) {
                      return _buildDesktopLayout(service, constraints);
                    } else {
                      return _buildMobileTabletLayout(service, constraints);
                    }
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // ──────────────────────────────────────────────────────────────
  // Layouts
  // ──────────────────────────────────────────────────────────────

  Widget _buildDesktopLayout(
      TelemetryService service, BoxConstraints constraints) {
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      child: Column(
        children: [
          // Top Section: Video & Map side-by-side
          SizedBox(
            height: constraints.maxHeight * 0.65, // ~65% height
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Left: Video Feed (65%)
                Expanded(
                  flex: 65,
                  child: const LiveFeedPanel(),
                ),
                const SizedBox(width: 16),
                // Right: Map (35%)
                Expanded(
                  flex: 35,
                  child: DroneMapPanel(service: service),
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),

          // Bottom Section: Telemetry Grid
          TelemetryGrid(service: service),

          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _buildMobileTabletLayout(
      TelemetryService service, BoxConstraints constraints) {
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        children: [
          // Live Feed
          SizedBox(
            height: constraints.maxHeight * 0.35 > 250
                ? constraints.maxHeight * 0.35
                : 250,
            width: double.infinity,
            child: const LiveFeedPanel(),
          ),

          const SizedBox(height: 16),

          // Tactical Map
          SizedBox(
            height: constraints.maxHeight * 0.35 > 250
                ? constraints.maxHeight * 0.35
                : 250,
            width: double.infinity,
            child: DroneMapPanel(service: service),
          ),

          const SizedBox(height: 16),

          // Telemetry
          TelemetryGrid(service: service),

          const SizedBox(height: 20),
        ],
      ),
    );
  }

  // ──────────────────────────────────────────────────────────────
  // Components
  // ──────────────────────────────────────────────────────────────

  Widget _buildTopStatusBar(
      dynamic t, bool isOnline, TelemetryService service) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
      child: Row(
        children: [
          // Status indicator
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color:
                  isOnline ? const Color(0xFF00E676) : const Color(0xFFFF5252),
              boxShadow: [
                BoxShadow(
                  color: (isOnline
                          ? const Color(0xFF00E676)
                          : const Color(0xFFFF5252))
                      .withValues(alpha: 0.6),
                  blurRadius: 8,
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Text(
            isOnline ? t.droneId : 'DISCONNECTED',
            style: GoogleFonts.orbitron(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
          const Spacer(),
          // Connection Error Banner (Compact)
          if (service.error != null)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Row(
                children: [
                  const Icon(Icons.warning, color: Color(0xFFFF5252), size: 14),
                  const SizedBox(width: 4),
                  Text(
                    'RECONNECTING...',
                    style: GoogleFonts.rajdhani(
                      color: const Color(0xFFFF5252),
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          // Flight mode badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            decoration: BoxDecoration(
              color: _modeColor(t.mode).withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: _modeColor(t.mode).withValues(alpha: 0.5),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  _modeIcon(t.mode),
                  color: _modeColor(t.mode),
                  size: 14,
                ),
                const SizedBox(width: 6),
                Text(
                  t.mode,
                  style: GoogleFonts.rajdhani(
                    color: _modeColor(t.mode),
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Color _modeColor(String mode) {
    switch (mode.toUpperCase()) {
      case 'AUTO':
        return const Color(0xFF00E676);
      case 'RTL':
        return const Color(0xFFFF5252);
      case 'LOITER':
        return const Color(0xFFFFAB40);
      default:
        return Colors.white54;
    }
  }

  IconData _modeIcon(String mode) {
    switch (mode.toUpperCase()) {
      case 'AUTO':
        return Icons.auto_mode;
      case 'RTL':
        return Icons.home;
      case 'LOITER':
        return Icons.pause_circle_outline;
      default:
        return Icons.help_outline;
    }
  }
}
