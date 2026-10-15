import 'package:anicel/src/ui/audio/audio_conform_store.dart';
import 'package:anicel/src/ui/media/viewer_sound.dart';

/// A [ViewerSound] that records what a run asked of it, and whose device
/// clock the test moves by hand — for every surface that runs one: the
/// media viewer and the import window's preview ask the same things of the
/// same sound ([MediaRun]).
///
/// ⚠️The clock stands still until a test moves it ([at], [playOn]): a
/// position that ran on its own would decide when a run of pictures ends —
/// and since a movie's pictures follow its sound (`MediaRun`), so it does.
/// It starts where a play or a resume asks, as a device does.
class RecordingViewerSound extends ViewerSound {
  RecordingViewerSound(AudioConformStore store) : super(conformStore: store);

  /// Each file a press played, the second it asked to start from, and how
  /// loud.
  final List<String> played = [];
  final List<double> from = [];
  final List<double> gains = [];

  int holds = 0;
  int resumes = 0;
  int stops = 0;
  int keeps = 0;

  /// Where the device has got to while it carries a sound.
  double at = 0;

  /// Whether the device has reached the end of the file it was given.
  bool hasEnded = false;

  /// How long the file is, when a test says: [playOn] stops there and the
  /// device has ended, as one does at the end of what it was handed.
  double? length;

  bool _carrying = false;
  bool _held = false;

  /// The device plays on by [time] — while it carries a sound and is not
  /// held.
  void playOn(Duration time) {
    if (!_carrying || _held) {
      return;
    }
    at += time.inMicroseconds / Duration.microsecondsPerSecond;
    final end = length;
    if (end != null && at >= end) {
      at = end;
      hasEnded = true;
    }
  }

  @override
  bool get isCarrying => _carrying;

  @override
  bool play(String sourcePath, {double fromSeconds = 0, double gain = 1}) {
    played.add(sourcePath);
    from.add(fromSeconds);
    gains.add(gain);
    _carrying = true;
    _held = false;
    at = fromSeconds;
    hasEnded = false;
    return true;
  }

  @override
  void hold() {
    holds += 1;
    _held = true;
  }

  /// Each second a held sound was picked back up from.
  final List<double> resumedFrom = [];

  @override
  void resume(double fromSeconds) {
    resumes += 1;
    resumedFrom.add(fromSeconds);
    _held = false;
    at = fromSeconds;
  }

  @override
  void keepStreaming() => keeps += 1;

  @override
  void stop() {
    stops += 1;
    _carrying = false;
  }

  /// The frame time each reading of the clock was asked for.
  final List<Duration?> askedAt = [];

  /// How far what is heard trails where the device has got to — the
  /// latency a real device holds back. None unless a test says.
  double lag = 0;

  @override
  ({double seconds, bool ended})? heardAt({Duration? frameTime}) {
    askedAt.add(frameTime);
    return _carrying ? (seconds: at - lag, ended: hasEnded) : null;
  }

  @override
  double? get handedSeconds => _carrying ? at : null;
}
