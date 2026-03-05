// Conditional export: selects the web or stub implementation at compile time.
// On web:     MjpegView wraps a native HTML <img> element — browser decodes
//             MJPEG in a persistent TCP connection at full camera fps.
// Non-web:    MjpegView polls /video/snapshot with cache-busting (Image.network).
export 'mjpeg_view_stub.dart' if (dart.library.html) 'mjpeg_view_web.dart';
