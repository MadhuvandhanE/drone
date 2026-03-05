/// Non-web MJPEG View (stub)
/// =========================
/// On desktop and mobile Flutter the MJPEG multipart stream is not
/// natively decoded by Image.network() either. This stub polls the
/// /video/snapshot endpoint (plain JPEG) with a cache-busting query
/// param at ~25 fps, which gives smooth motion on all non-web platforms.
library;

import 'dart:async';

import 'package:flutter/material.dart';

class MjpegView extends StatefulWidget {
  final String streamUrl;
  const MjpegView({required this.streamUrl, super.key});

  @override
  State<MjpegView> createState() => _MjpegViewStubState();
}

class _MjpegViewStubState extends State<MjpegView> {
  Timer? _timer;
  int _t = 0;

  /// Derive the snapshot URL from the feed URL:
  ///   http://localhost:8000/video/feed   →   http://localhost:8000/video/snapshot
  String get _snapshotUrl =>
      widget.streamUrl.replaceFirst(RegExp(r'/feed$'), '/snapshot');

  @override
  void initState() {
    super.initState();
    // 40 ms ≈ 25 fps poll rate
    _timer = Timer.periodic(const Duration(milliseconds: 40), (_) {
      if (mounted) setState(() => _t++);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Image.network(
      '$_snapshotUrl?t=$_t',
      fit: BoxFit.cover,
      gaplessPlayback: true,
      errorBuilder: (_, __, ___) => const SizedBox.shrink(),
      loadingBuilder: (_, child, progress) {
        if (progress == null || _t > 3) return child;
        return const SizedBox.shrink();
      },
    );
  }
}
