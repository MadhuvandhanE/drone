/// Live Feed Panel
/// ===============
/// Renders the MJPEG stream served by the Hive backend at /video/feed.
/// The stream is already annotated with YOLO bounding boxes by the backend.
///
/// On first launch the widget POSTs to /video/start (camera index 0) so the
/// pipeline starts automatically — no manual step needed.
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';

import '../core/config.dart';
import '../platform/mjpeg_view.dart';
import '../services/telemetry_service.dart';
import 'detection_overlay.dart';

class LiveFeedPanel extends StatefulWidget {
  const LiveFeedPanel({super.key});

  @override
  State<LiveFeedPanel> createState() => _LiveFeedPanelState();
}

class _LiveFeedPanelState extends State<LiveFeedPanel>
    with SingleTickerProviderStateMixin {
  // ── State ──────────────────────────────────────────────────────────────────
  bool _streamStarted = false;
  bool _streamError = false;
  String _errorMsg = '';

  // Pulse animation for the LIVE dot
  late AnimationController _pulseCtrl;
  late Animation<double> _pulseAnim;

  // ── Lifecycle ───────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();

    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);

    _pulseAnim = Tween<double>(begin: 0.4, end: 1.0).animate(
      CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut),
    );

    // Auto-start the vision pipeline (camera 0) when the panel opens.
    WidgetsBinding.instance.addPostFrameCallback((_) => _startStream('0'));
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    super.dispose();
  }

  // ── Stream control ──────────────────────────────────────────────────────────

  Future<void> _startStream(String source) async {
    try {
      final res = await http
          .post(
            Uri.parse(AppConfig.videoStartUrl),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'source': source}),
          )
          .timeout(const Duration(seconds: 5));

      if (res.statusCode == 200) {
        if (mounted) {
          setState(() {
            _streamStarted = true;
            _streamError = false;
          });
        }
      } else {
        _setError('Backend error ${res.statusCode}');
      }
    } catch (e) {
      _setError('Cannot reach backend.\nIs the Hive server running?\n\n$e');
    }
  }

  void _setError(String msg) {
    if (mounted) {
      setState(() {
        _streamError = true;
        _streamStarted = false;
        _errorMsg = msg;
      });
    }
  }

  // ── Build ───────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF0D1117),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: const Color(0xFF00E5FF).withValues(alpha: 0.3),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.5),
            blurRadius: 10,
          ),
        ],
      ),
      clipBehavior: Clip.hardEdge,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // ── Main content: stream or placeholder ──
          _buildFeedContent(),

          // ── Scanlines overlay (tactical look) ──
          Positioned.fill(
            child: IgnorePointer(
              child: CustomPaint(painter: _ScanlinePainter()),
            ),
          ),

          // ── YOLO Detection overlay (from TelemetryService) ──
          Consumer<TelemetryService>(
            builder: (context, service, _) {
              return DetectionOverlay(detections: service.detections);
            },
          ),

          // ── Top-left HUD badges ──
          Positioned(
            top: 12,
            left: 12,
            child: Row(
              children: [
                // LIVE badge with pulse
                AnimatedBuilder(
                  animation: _pulseAnim,
                  builder: (_, __) => Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.redAccent
                          .withValues(alpha: _pulseAnim.value * 0.85),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 7,
                          height: 7,
                          decoration: const BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(width: 5),
                        Text(
                          'LIVE',
                          style: GoogleFonts.sourceCodePro(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                // Camera badge
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.6),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: Colors.white24),
                  ),
                  child: Text(
                    'CAM 1 · YOLO DETECT',
                    style: GoogleFonts.sourceCodePro(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // ── Centre crosshair ──
          Align(
            alignment: Alignment.center,
            child: Icon(
              Icons.add,
              color: Colors.white.withValues(alpha: 0.25),
              size: 36,
            ),
          ),

          // ── Bottom-right corner info ──
          Positioned(
            bottom: 12,
            right: 12,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(
                  color: const Color(0xFF00E5FF).withValues(alpha: 0.2),
                ),
              ),
              child: Text(
                'YOLOv8n · PERSON DETECTION',
                style: GoogleFonts.sourceCodePro(
                  color: const Color(0xFF00E5FF).withValues(alpha: 0.7),
                  fontSize: 9,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFeedContent() {
    if (_streamError) {
      return _buildErrorScreen();
    }

    if (!_streamStarted) {
      return _buildLoadingScreen();
    }

    // Web: MjpegView embeds a native HTML <img> that decodes the MJPEG
    // multipart stream in one persistent TCP connection — true real-time fps.
    // Non-web: MjpegView stubs to snapshot polling (see lib/platform/).
    return MjpegView(streamUrl: AppConfig.mjpegFeedUrl);
  }

  Widget _buildLoadingScreen() {
    return Container(
      color: const Color(0xFF080D14),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const CircularProgressIndicator(
            valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF00E5FF)),
            strokeWidth: 2,
          ),
          const SizedBox(height: 16),
          Text(
            'CONNECTING TO VISION ENGINE…',
            style: GoogleFonts.sourceCodePro(
              color: const Color(0xFF00E5FF).withValues(alpha: 0.7),
              fontSize: 11,
              letterSpacing: 2,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Loading YOLOv8n model',
            style: GoogleFonts.sourceCodePro(
              color: Colors.white24,
              fontSize: 9,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorScreen({String? msg}) {
    final message = msg ?? _errorMsg;
    return Container(
      color: const Color(0xFF080D14),
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.videocam_off_rounded,
              color: Color(0xFFFF5252), size: 40),
          const SizedBox(height: 12),
          Text(
            'NO SIGNAL',
            style: GoogleFonts.orbitron(
              color: const Color(0xFFFF5252),
              fontSize: 14,
              fontWeight: FontWeight.bold,
              letterSpacing: 3,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            message,
            textAlign: TextAlign.center,
            style: GoogleFonts.sourceCodePro(
              color: Colors.white38,
              fontSize: 9,
            ),
          ),
          const SizedBox(height: 16),
          TextButton.icon(
            onPressed: () => _startStream('0'),
            icon: const Icon(Icons.refresh, color: Color(0xFF00E5FF), size: 16),
            label: Text(
              'RETRY',
              style: GoogleFonts.sourceCodePro(
                color: const Color(0xFF00E5FF),
                fontSize: 11,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Scanline overlay painter ────────────────────────────────────────────────

class _ScanlinePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.black.withValues(alpha: 0.07)
      ..strokeWidth = 1;

    for (double y = 0; y < size.height; y += 3) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(_ScanlinePainter old) => false;
}
