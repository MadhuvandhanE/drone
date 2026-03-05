/// Mission Progress Widget
/// =======================
/// Displays current mission progress with a styled progress bar
/// and waypoint counter.
library;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class MissionProgress extends StatelessWidget {
  final int currentWaypoint;
  final int totalWaypoints;
  final String status;

  const MissionProgress({
    super.key,
    required this.currentWaypoint,
    required this.totalWaypoints,
    required this.status,
  });

  double get progress =>
      totalWaypoints > 0 ? currentWaypoint / totalWaypoints : 0.0;

  Color get statusColor {
    switch (status.toUpperCase()) {
      case 'ACTIVE':
        return const Color(0xFF00E676);
      case 'COMPLETED':
        return const Color(0xFF00E5FF);
      case 'PAUSED':
        return const Color(0xFFFFAB40);
      default:
        return Colors.white54;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            const Color(0xFF1A1A2E).withValues(alpha: 0.95),
            const Color(0xFF16213E).withValues(alpha: 0.95),
          ],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: statusColor.withValues(alpha: 0.3),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: statusColor.withValues(alpha: 0.1),
            blurRadius: 20,
            spreadRadius: 0,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'MISSION PROGRESS',
                style: GoogleFonts.rajdhani(
                  color: Colors.white70,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 2,
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: statusColor.withValues(alpha: 0.4),
                  ),
                ),
                child: Text(
                  status.toUpperCase(),
                  style: GoogleFonts.rajdhani(
                    color: statusColor,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // Waypoint counter
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '$currentWaypoint',
                style: GoogleFonts.orbitron(
                  color: Colors.white,
                  fontSize: 42,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  ' / $totalWaypoints',
                  style: GoogleFonts.orbitron(
                    color: Colors.white38,
                    fontSize: 20,
                    fontWeight: FontWeight.w400,
                  ),
                ),
              ),
              const Spacer(),
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  '${(progress * 100).toInt()}%',
                  style: GoogleFonts.orbitron(
                    color: statusColor,
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Progress bar
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: progress,
              backgroundColor: Colors.white10,
              valueColor: AlwaysStoppedAnimation<Color>(statusColor),
              minHeight: 8,
            ),
          ),
          const SizedBox(height: 12),

          // Waypoint labels
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'WAYPOINT $currentWaypoint',
                style: GoogleFonts.rajdhani(
                  color: Colors.white54,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                'TARGET: WP $totalWaypoints',
                style: GoogleFonts.rajdhani(
                  color: Colors.white54,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
