import 'package:anicel/src/ui/playback/audio_recorder.dart';

/// A microphone that hands back [recording] when it is stopped — once — and
/// nothing when it was never started.
///
/// One for every take test: five of them spelled this recorder out
/// privately, line for line.
class CannedAudioRecorder extends AudioRecorder {
  CannedAudioRecorder(this.recording);

  final AudioRecording recording;
  bool _started = false;

  @override
  bool get isRecording => _started;

  @override
  int start({
    required int sampleRate,
    bool useNullBackend = false,
    int deviceIndex = -1,
  }) {
    _started = true;
    return recording.sampleRate;
  }

  @override
  AudioRecording? stop() {
    if (!_started) {
      return null;
    }
    _started = false;
    return recording;
  }
}
