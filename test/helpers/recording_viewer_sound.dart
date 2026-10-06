import 'package:anicel/src/ui/audio/audio_conform_store.dart';
import 'package:anicel/src/ui/media/viewer_sound.dart';

/// A [ViewerSound] that records what a run asked of it, and whose device
/// clock the test moves by hand — for every surface that runs one: the
/// media viewer and the import window's preview ask the same things of the
/// same sound ([MediaRun]).
///
/// ⚠️The clock stands still until a test moves [at]: a position that ran
/// on its own would decide when a run of pictures ends.
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

  bool _carrying = false;

  @override
  bool get isCarrying => _carrying;

  @override
  bool play(String sourcePath, {double fromSeconds = 0, double gain = 1}) {
    played.add(sourcePath);
    from.add(fromSeconds);
    gains.add(gain);
    _carrying = true;
    hasEnded = false;
    return true;
  }

  @override
  void hold() => holds += 1;

  @override
  void resume(double fromSeconds) => resumes += 1;

  @override
  void keepStreaming() => keeps += 1;

  @override
  void stop() {
    stops += 1;
    _carrying = false;
  }

  @override
  double? get positionSeconds => _carrying ? at : null;

  @override
  bool get ended => _carrying && hasEnded;
}
