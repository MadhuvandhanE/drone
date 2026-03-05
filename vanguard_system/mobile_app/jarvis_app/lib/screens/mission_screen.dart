/// Mission Screen
/// ==============
/// Displays detailed mission information including:
/// • Current waypoint progress
/// • Mission timeline
/// • Detection results
/// • Action buttons (refresh, view detections)
library;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../services/telemetry_service.dart';
import '../widgets/mission_progress.dart';

class MissionScreen extends StatefulWidget {
  const MissionScreen({super.key});

  @override
  State<MissionScreen> createState() => _MissionScreenState();
}

class _MissionScreenState extends State<MissionScreen> {
  @override
  void initState() {
    super.initState();
    // Fetch mission data when screen opens
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<TelemetryService>().fetchMission();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<TelemetryService>(
      builder: (context, service, _) {
        final t = service.telemetry;
        final mission = service.mission;
        final detections = service.detections;

        return CustomScrollView(
          physics: const BouncingScrollPhysics(),
          slivers: [
            // -- Mission Header --
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
                child: Text(
                  'MISSION CONTROL',
                  style: GoogleFonts.orbitron(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 2,
                  ),
                ),
              ),
            ),

            // -- Mission Progress Card --
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: MissionProgress(
                  currentWaypoint:
                      mission?['current_waypoint'] as int? ?? t.currentWaypoint,
                  totalWaypoints:
                      mission?['total_waypoints'] as int? ?? t.totalWaypoints,
                  status: mission?['mission_status'] as String? ?? 'UNKNOWN',
                ),
              ),
            ),

            // -- Waypoint Timeline --
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: _buildWaypointTimeline(
                  current:
                      mission?['current_waypoint'] as int? ?? t.currentWaypoint,
                  total:
                      mission?['total_waypoints'] as int? ?? t.totalWaypoints,
                ),
              ),
            ),

            // -- Action Buttons --
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Expanded(
                      child: _buildActionButton(
                        icon: Icons.refresh,
                        label: 'REFRESH MISSION',
                        color: const Color(0xFF00E5FF),
                        isLoading: service.isLoading,
                        onTap: () => service.fetchMission(),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _buildActionButton(
                        icon: Icons.person_search,
                        label: 'VIEW DETECTIONS',
                        color: const Color(0xFFFF6E40),
                        isLoading: service.isLoading,
                        onTap: () => service.fetchDetections(),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // -- Detections Panel --
            if (detections != null)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: _buildDetectionsSection(detections),
                ),
              ),

            // -- Mission Stats --
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: _buildMissionStats(service),
              ),
            ),

            // Bottom padding
            const SliverToBoxAdapter(
              child: SizedBox(height: 24),
            ),
          ],
        );
      },
    );
  }

  Widget _buildWaypointTimeline({required int current, required int total}) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A2E).withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: const Color(0xFF00E5FF).withValues(alpha: 0.1),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'WAYPOINT TIMELINE',
            style: GoogleFonts.rajdhani(
              color: Colors.white54,
              fontSize: 12,
              fontWeight: FontWeight.w700,
              letterSpacing: 2,
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 60,
            child: Row(
              children: List.generate(total > 0 ? total : 1, (index) {
                final wpNum = index + 1;
                final isCompleted = wpNum < current;
                final isCurrent = wpNum == current;
                final isUpcoming = wpNum > current;

                return Expanded(
                  child: Column(
                    children: [
                      // Node
                      Container(
                        width: 24,
                        height: 24,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: isCompleted
                              ? const Color(0xFF00E676)
                              : isCurrent
                                  ? const Color(0xFF00E5FF)
                                  : Colors.white12,
                          border: Border.all(
                            color: isCurrent
                                ? const Color(0xFF00E5FF)
                                : Colors.transparent,
                            width: 2,
                          ),
                          boxShadow: isCurrent
                              ? [
                                  BoxShadow(
                                    color: const Color(0xFF00E5FF)
                                        .withValues(alpha: 0.4),
                                    blurRadius: 10,
                                  ),
                                ]
                              : null,
                        ),
                        child: Center(
                          child: isCompleted
                              ? const Icon(Icons.check,
                                  color: Colors.white, size: 14)
                              : Text(
                                  '$wpNum',
                                  style: GoogleFonts.sourceCodePro(
                                    color: isCurrent
                                        ? Colors.white
                                        : Colors.white38,
                                    fontSize: 10,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        isCurrent
                            ? 'ACTIVE'
                            : isCompleted
                                ? 'DONE'
                                : '',
                        style: GoogleFonts.rajdhani(
                          color: isCurrent
                              ? const Color(0xFF00E5FF)
                              : const Color(0xFF00E676),
                          fontSize: 8,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                );
              }),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required Color color,
    required bool isLoading,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: isLoading ? null : onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              color.withValues(alpha: 0.15),
              color.withValues(alpha: 0.05),
            ],
          ),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withValues(alpha: 0.4)),
          boxShadow: [
            BoxShadow(
              color: color.withValues(alpha: 0.1),
              blurRadius: 10,
            ),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (isLoading)
              SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(color),
                ),
              )
            else
              Icon(icon, color: color, size: 18),
            const SizedBox(width: 8),
            Text(
              label,
              style: GoogleFonts.rajdhani(
                color: color,
                fontSize: 12,
                fontWeight: FontWeight.w700,
                letterSpacing: 1,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDetectionsSection(Map<String, dynamic> detections) {
    final victims = detections['victims'] as List<dynamic>? ?? [];
    final totalCount = detections['total_count'] as int? ?? 0;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            const Color(0xFFFF6E40).withValues(alpha: 0.08),
            const Color(0xFF1A1A2E).withValues(alpha: 0.6),
          ],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: const Color(0xFFFF6E40).withValues(alpha: 0.3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: const Color(0xFFFF6E40).withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.person_pin_circle,
                    color: Color(0xFFFF6E40), size: 18),
              ),
              const SizedBox(width: 10),
              Text(
                'VICTIM DETECTIONS',
                style: GoogleFonts.rajdhani(
                  color: const Color(0xFFFF6E40),
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.5,
                ),
              ),
              const Spacer(),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFFFF6E40).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '$totalCount found',
                  style: GoogleFonts.rajdhani(
                    color: const Color(0xFFFF6E40),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          ...victims.map<Widget>((v) {
            final victim = v as Map<String, dynamic>;
            return Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.03),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.05),
                ),
              ),
              child: Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: const Color(0xFFFF6E40).withValues(alpha: 0.15),
                    ),
                    child: const Icon(
                      Icons.person,
                      color: Color(0xFFFF6E40),
                      size: 18,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          victim['id'] as String? ?? 'Unknown',
                          style: GoogleFonts.sourceCodePro(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${(victim['lat'] as num?)?.toStringAsFixed(5) ?? '?'}°N, '
                          '${(victim['lon'] as num?)?.toStringAsFixed(5) ?? '?'}°E',
                          style: GoogleFonts.sourceCodePro(
                            color: Colors.white54,
                            fontSize: 10,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        '${((victim['confidence'] as num?) != null ? ((victim['confidence'] as num) * 100).toInt() : 0)}%',
                        style: GoogleFonts.orbitron(
                          color: const Color(0xFFFF6E40),
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        'confidence',
                        style: GoogleFonts.rajdhani(
                          color: Colors.white38,
                          fontSize: 10,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildMissionStats(TelemetryService service) {
    final t = service.telemetry;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A2E).withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: const Color(0xFF7C4DFF).withValues(alpha: 0.15),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'MISSION STATISTICS',
            style: GoogleFonts.rajdhani(
              color: Colors.white54,
              fontSize: 12,
              fontWeight: FontWeight.w700,
              letterSpacing: 2,
            ),
          ),
          const SizedBox(height: 16),
          _statRow('Drone ID', t.droneId),
          _statRow('Flight Mode', t.mode),
          _statRow('Altitude', '${t.altitude.toStringAsFixed(1)} m'),
          _statRow('Ground Speed', '${t.speed.toStringAsFixed(1)} m/s'),
          _statRow('Battery Level', '${t.battery}%'),
          _statRow('Signal Strength', '${t.signalStrength}%'),
          _statRow('Water Depth', '${t.waterDepth.toStringAsFixed(2)} m'),
          _statRow('Last Update', _formatTime(t.timestamp)),
        ],
      ),
    );
  }

  Widget _statRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: GoogleFonts.rajdhani(
              color: Colors.white54,
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
          Text(
            value,
            style: GoogleFonts.sourceCodePro(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  String _formatTime(DateTime dt) {
    return '${dt.hour.toString().padLeft(2, '0')}:'
        '${dt.minute.toString().padLeft(2, '0')}:'
        '${dt.second.toString().padLeft(2, '0')} UTC';
  }
}
