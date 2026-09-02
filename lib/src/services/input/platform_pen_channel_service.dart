import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// One driver-side pen sample from a platform sidecar channel (PEN-4).
class PenChannelSample {
  const PenChannelSample({
    required this.pressure,
    required this.tiltX,
    required this.tiltY,
    required this.timeMs,
    required this.eraser,
  });

  final double pressure;
  final double tiltX;
  final double tiltY;
  final double timeMs;
  final bool eraser;
}

/// The macOS/Linux pen sidecar consumer (pen program, PEN-4) — the
/// Wintab service's channel-based sibling, one class for both:
///
/// - macOS ('qa_pen/macos'): the runner's NSEvent local monitor restores
///   the tablet pressure/tilt Flutter's embedder drops
///   (flutter/flutter#146387).
/// - Linux ('qa_pen/linux'): the runner's GTK hook restores the pen data
///   the embedder flattens to a mouse (flutter/flutter#63209).
///
/// Same pressure-sidecar contract as Wintab: Flutter pointer events keep
/// driving position/gestures; this stream only supplies the DRIVER's
/// pressure, consulted per pointer sample through
/// [freshContactPressure]. Unlike Windows (a user-facing service
/// SWITCH), these start unconditionally on their platform — there is no
/// second OS path to choose between; the sidecar only restores data the
/// embedder loses today.
class PlatformPenChannelService {
  PlatformPenChannelService(
    this.channelName,
    this.label, {
    Stream<dynamic>? debugStream,
  }) : _debugStream = debugStream;

  factory PlatformPenChannelService.macos() =>
      PlatformPenChannelService('qa_pen/macos', 'mac');

  factory PlatformPenChannelService.linux() =>
      PlatformPenChannelService('qa_pen/linux', 'gdk');

  final String channelName;

  /// Short readout tag for the input inspector ('mac' / 'gdk').
  final String label;

  final Stream<dynamic>? _debugStream;

  /// A sample older than this no longer overrides pointer events.
  static const Duration freshWindow = Duration(milliseconds: 150);

  final ValueNotifier<PenChannelSample?> latest =
      ValueNotifier<PenChannelSample?>(null);

  StreamSubscription<dynamic>? _subscription;
  DateTime _lastSampleAt = DateTime.fromMillisecondsSinceEpoch(0);

  bool get running => _subscription != null;

  void start() {
    if (_subscription != null) {
      return;
    }
    final stream =
        _debugStream ?? EventChannel(channelName).receiveBroadcastStream();
    // A missing runner-side handler surfaces as a stream error — the
    // standard graceful absence, never a crash.
    _subscription = stream.listen(_onMessage, onError: (Object _) {});
  }

  void stop() {
    unawaited(_subscription?.cancel());
    _subscription = null;
    latest.value = null;
    _lastSampleAt = DateTime.fromMillisecondsSinceEpoch(0);
  }

  void _onMessage(Object? message) {
    if (message is! Map) {
      return;
    }
    final pressure = message['pressure'];
    if (pressure is! num) {
      return;
    }
    latest.value = PenChannelSample(
      pressure: pressure.toDouble().clamp(0.0, 1.0),
      tiltX: (message['tiltX'] as num?)?.toDouble() ?? 0,
      tiltY: (message['tiltY'] as num?)?.toDouble() ?? 0,
      timeMs: (message['timeMs'] as num?)?.toDouble() ?? 0,
      eraser: message['eraser'] == true,
    );
    _lastSampleAt = DateTime.now();
  }

  /// The driver's CONTACT pressure when the stream is live and fresh —
  /// null = use the pointer event's own pressure.
  double? freshContactPressure({DateTime? now}) {
    if (_subscription == null) {
      return null;
    }
    final sample = latest.value;
    if (sample == null) {
      return null;
    }
    final age = (now ?? DateTime.now()).difference(_lastSampleAt);
    if (age > freshWindow) {
      return null;
    }
    return sample.pressure;
  }
}
