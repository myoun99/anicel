import 'dart:async';
import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import '../../native/qa_audio_device.dart';

/// A finished take: what the microphone delivered, plus what it means.
class AudioRecording {
  const AudioRecording({
    required this.samples,
    required this.channels,
    required this.sampleRate,
    required this.droppedFrames,
  });

  /// Interleaved float32, exactly as captured — the device's own channel
  /// count (a mono mic records mono; a stereo interface records stereo).
  final Float32List samples;

  final int channels;
  final int sampleRate;

  /// Frames the C ring dropped because the drain fell behind. Nonzero
  /// means the take is DAMAGED and the user must be told — a silently
  /// shortened file would drift against the picture and look like a sync
  /// bug forever after.
  final int droppedFrames;

  /// Samples per channel.
  int get length => channels <= 0 ? 0 : samples.length ~/ channels;
}

/// The guide-voice recorder (AUDIO-PRO R5): drains the C capture ring on a
/// timer and accumulates the take in Dart memory.
///
/// The split of responsibilities mirrors playback: the realtime side (the
/// capture callback) only copies into a preallocated ring; THIS class is
/// the control side, and its timer can be late by tens of milliseconds
/// without loss because the ring holds seconds.
///
/// Absence is graceful: no native binary means [start] returns 0 and the
/// record button reports rather than crashes.
class AudioRecorder {
  AudioRecorder({QaAudioDevice? device}) : _device = device;

  final QaAudioDevice? _device;

  /// Live tap (REC1-C): every drained chunk (interleaved float32, the
  /// device's own channel count) also lands here — the growing-waveform
  /// preview folds peaks from it. The take itself is unaffected.
  void Function(Float32List interleaved, int channels)? onChunk;

  Timer? _timer;
  Pointer<Float>? _scratch;
  int _scratchFloats = 0;
  final List<Float32List> _chunks = [];
  int _channels = 0;
  int _sampleRate = 0;

  bool get isRecording => _timer != null;

  /// Starts capturing at [sampleRate] (the project rate — what lands in
  /// the chunks needs no conform). Returns the delivered rate, or 0 when
  /// the device could not open (no binary, no microphone, no permission).
  ///
  /// [deviceIndex] follows the R4 contract: -1 = system default, a bad
  /// index fails. Resolve a saved name with
  /// [audioDeviceIndexByName] (`capture: true`).
  int start({
    required int sampleRate,
    bool useNullBackend = false,
    int deviceIndex = -1,
  }) {
    final device = _device;
    if (device == null || isRecording || device.captureIsOpen) {
      return 0;
    }
    var rate = device.captureStart(
      sampleRate: sampleRate,
      useNullBackend: useNullBackend,
      deviceIndex: deviceIndex,
    );
    // A vanished saved microphone falls back to the system default — the
    // same deliberate, logged-in-settings fallback playback makes.
    if (rate == 0 && deviceIndex >= 0) {
      rate = device.captureStart(
        sampleRate: sampleRate,
        useNullBackend: useNullBackend,
      );
    }
    if (rate == 0) {
      return 0;
    }
    _channels = device.captureChannels;
    _sampleRate = rate;
    _chunks.clear();
    // One second of scratch: far more than a 30 ms drain ever needs, so
    // the inner loop below almost always finishes in one read.
    _scratchFloats = rate * (_channels <= 0 ? 1 : _channels);
    _scratch = calloc<Float>(_scratchFloats);
    _timer = Timer.periodic(const Duration(milliseconds: 30), (_) => _drain());
    return rate;
  }

  void _drain() {
    final device = _device;
    final scratch = _scratch;
    if (device == null || scratch == null) {
      return;
    }
    while (true) {
      final got = device.captureRead(scratch, _scratchFloats);
      if (got <= 0) {
        return;
      }
      final chunk = Float32List.fromList(scratch.asTypedList(got));
      _chunks.add(chunk);
      onChunk?.call(chunk, _channels);
    }
  }

  /// Stops the take and returns it, or null when nothing was recording.
  /// The tail still in the ring is drained BEFORE the device closes, so
  /// the last word of a line is not cut off.
  AudioRecording? stop() {
    final device = _device;
    if (device == null || !isRecording) {
      return null;
    }
    _timer?.cancel();
    _timer = null;
    _drain();
    final droppedFrames = device.captureDroppedFrames;
    device.captureStop();
    final scratch = _scratch;
    if (scratch != null) {
      calloc.free(scratch);
      _scratch = null;
    }

    var total = 0;
    for (final chunk in _chunks) {
      total += chunk.length;
    }
    final samples = Float32List(total);
    var cursor = 0;
    for (final chunk in _chunks) {
      samples.setRange(cursor, cursor + chunk.length, chunk);
      cursor += chunk.length;
    }
    _chunks.clear();
    return AudioRecording(
      samples: samples,
      channels: _channels,
      sampleRate: _sampleRate,
      droppedFrames: droppedFrames,
    );
  }

  /// Abandons an in-progress take (project closing, session disposal).
  void dispose() {
    if (isRecording) {
      stop();
    }
  }
}

/// Why a record press did (or did not) arm (REC1-B) — the button phrases
/// each refusal differently, so a bool is not enough.
enum VoiceRecordStartResult {
  started,
  alreadyRecording,

  /// The device would not open (no binary, no microphone, no OS grant).
  deviceFailed,
}
