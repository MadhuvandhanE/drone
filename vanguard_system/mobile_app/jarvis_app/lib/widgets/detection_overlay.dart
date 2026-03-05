import 'dart:math';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class DetectionOverlay extends StatefulWidget {
  final Map<String, dynamic>? detections;

  const DetectionOverlay({super.key, required this.detections});

  @override
  State<DetectionOverlay> createState() => _DetectionOverlayState();
}

class _DetectionOverlayState extends State<DetectionOverlay>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  final Random _rnd = Random(42); // Seeded for consistent simulation

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.detections == null) return const SizedBox.shrink();

    final victims = widget.detections!['victims'] as List<dynamic>? ?? [];

    return LayoutBuilder(
      builder: (context, constraints) {
        return Stack(
          clipBehavior: Clip.none,
          children: victims.map((v) {
            final victim = v as Map<String, dynamic>;
            final confidence = (victim['confidence'] as num?)?.toDouble() ?? 0.0;
            // Simulated screen coordinates since backend is GPS-only right now
            // We use the victim ID hash to give them a consistent pseudo-random spot on screen
            final label = RegExp(r'\d+$').stringMatch(victim['id'] ?? '') ?? '0';
            final intHash = int.tryParse(label) ?? 0;
            
            // Generate position roughly in the middle 60% of the screen
            final top = constraints.maxHeight * 0.2 + (intHash * 37 % (constraints.maxHeight * 0.5));
            final left = constraints.maxWidth * 0.2 + (intHash * 11 % (constraints.maxWidth * 0.5));
            
            final rectWidth = 80.0;
            final rectHeight = 120.0;

            return Positioned(
              top: top,
              left: left,
              width: rectWidth,
              height: rectHeight,
              child: AnimatedBuilder(
                animation: _pulseController,
                builder: (context, child) {
                  return Container(
                    decoration: BoxDecoration(
                      border: Border.all(
                        color: const Color(0xFFFF6E40).withValues(alpha: 0.5 + 0.5 * _pulseController.value),
                        width: 2,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFFFF6E40).withValues(alpha: 0.1 * _pulseController.value),
                          blurRadius: 10,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Positioned(
                          top: -16,
                          left: -2,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                            color: const Color(0xFFFF6E40),
                            child: Text(
                              'PERSON ${(confidence * 100).toStringAsFixed(0)}%',
                              style: GoogleFonts.rajdhani(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 1,
                              ),
                            ),
                          ),
                        ),
                        // Corner brackets for tactical look
                        _buildCorner(Alignment.topLeft),
                        _buildCorner(Alignment.topRight),
                        _buildCorner(Alignment.bottomLeft),
                        _buildCorner(Alignment.bottomRight),
                      ],
                    ),
                  );
                },
              ),
            );
          }).toList(),
        );
      },
    );
  }

  Widget _buildCorner(Alignment alignment) {
    return Align(
      alignment: alignment,
      child: Container(
        width: 10,
        height: 10,
        decoration: BoxDecoration(
          border: Border(
            top: alignment.y < 0 ? const BorderSide(color: Colors.white, width: 2) : BorderSide.none,
            bottom: alignment.y > 0 ? const BorderSide(color: Colors.white, width: 2) : BorderSide.none,
            left: alignment.x < 0 ? const BorderSide(color: Colors.white, width: 2) : BorderSide.none,
            right: alignment.x > 0 ? const BorderSide(color: Colors.white, width: 2) : BorderSide.none,
          ),
        ),
      ),
    );
  }
}
