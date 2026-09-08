import 'package:flutter/foundation.dart';
import 'package:anicel/src/ui/playback/playback_transport.dart';

/// A transport that is NOT the canvas — a media viewer, as
/// `PlaybackActuationGate` sees one — and that records what was done to it.
///
/// Shared rather than written per test file: two hand-written copies of the
/// same three members are a clone whatever the names on them
/// ([[no-copy-to-share]]).
class FakePlaybackTransport implements PlaybackTransport {
  final ValueNotifier<bool> _flips = ValueNotifier<bool>(false);

  /// Counted so a test can prove the gate did NOT stop what it no longer
  /// holds — an absence a stopped-flag alone cannot tell apart from
  /// "stopped, correctly".
  int stops = 0;

  @override
  bool get isPlaying => _flips.value;

  @override
  void stop() {
    stops += 1;
    _flips.value = false;
  }

  @override
  ValueListenable<bool> get isActiveListenable => _flips;

  void play() => _flips.value = true;

  void dispose() => _flips.dispose();
}
