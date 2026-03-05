/// Drone Marker Widget
/// ===================
/// Custom animated marker widget for the drone on the map.
/// Features a pulsing glow effect to indicate active tracking.
library;

import 'package:flutter/material.dart';

class DroneMarkerIcon extends StatefulWidget {
  final double heading;

  const DroneMarkerIcon({super.key, this.heading = 0.0});

  @override
  State<DroneMarkerIcon> createState() => _DroneMarkerIconState();
}

class _DroneMarkerIconState extends State<DroneMarkerIcon>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(begin: 0.8, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _pulseAnimation,
      builder: (context, child) {
        return Transform.scale(
          scale: _pulseAnimation.value,
          child: Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: const Color(0xFF00E5FF).withValues(alpha: 0.2),
              border: Border.all(
                color: const Color(0xFF00E5FF),
                width: 2,
              ),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF00E5FF).withValues(alpha: 0.4),
                  blurRadius: 16,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: const Center(
              child: Icon(
                Icons.flight,
                color: Color(0xFF00E5FF),
                size: 24,
              ),
            ),
          ),
        );
      },
    );
  }
}
