/// Web MJPEG View
/// ==============
/// Embeds a native HTML <img> element pointing at the MJPEG stream URL.
///
/// Why this is fast
/// ----------------
/// Browsers decode MJPEG natively: a single persistent HTTP connection
/// delivers frames as a multipart byte stream and the browser paints each
/// JPEG boundary immediately — no polling, no per-frame HTTP overhead.
/// This gives true real-time performance limited only by the backend fps.
///
/// Flutter web's Image.network() does NOT do this — it reads the response
/// as one giant blob and never finishes, leaving the widget blank.
/// HtmlElementView bypasses Flutter completely and lets the DOM handle it.
// ignore_for_file: avoid_web_libraries_in_flutter
library;

import 'dart:html' as html;
import 'dart:ui_web' as ui_web;

import 'package:flutter/material.dart';

// Track which viewType IDs have already been registered so we never call
// registerViewFactory twice (that throws a StateError).
final _registeredTypes = <String>{};

class MjpegView extends StatefulWidget {
  final String streamUrl;
  const MjpegView({required this.streamUrl, super.key});

  @override
  State<MjpegView> createState() => _MjpegViewWebState();
}

class _MjpegViewWebState extends State<MjpegView> {
  late final String _viewType;

  @override
  void initState() {
    super.initState();
    // Use a stable, URL-derived type name so hot-reload doesn't duplicate it.
    _viewType = 'jarvis-mjpeg-${widget.streamUrl.hashCode.abs()}';

    if (!_registeredTypes.contains(_viewType)) {
      _registeredTypes.add(_viewType);
      final url = widget.streamUrl;
      ui_web.platformViewRegistry.registerViewFactory(_viewType, (int id) {
        return html.ImageElement()
          ..src = url
          ..style.width = '100%'
          ..style.height = '100%'
          ..style.objectFit = 'cover'
          ..style.display = 'block'
          ..style.background = '#080D14';
      });
    }
  }

  @override
  Widget build(BuildContext context) => HtmlElementView(viewType: _viewType);
}
