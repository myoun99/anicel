import 'dart:ffi';

import 'package:ffi/ffi.dart';

import '../services/audio/audio_mixer_reference.dart';
import 'qa_audio_native.dart';
import 'qa_engine_abi.dart';

/// The output device and the transport (audio program 2C).
///
/// This is where "audio is the master clock" stops being a design note.
/// [positionSamples] counts samples HANDED TO THE DEVICE, so it advances
/// only when audio actually leaves — it cannot run ahead of what is heard,
/// which a free-running timer can and does.
///
/// Dart's whole job here is upload, transport control, and polling. No Dart
/// runs in the callback; that is the rule the realtime thread is built on.
///
/// Absence is graceful: no binary, or a device that refuses to open,
/// leaves [isOpen] false and the caller on its existing path. Silence is
/// never an acceptable outcome for audio.
final class QaAudioDevice {
  QaAudioDevice._(this._library);

  final DynamicLibrary _library;

  static QaAudioDevice? _instance;
  static bool _tried = false;

  static void debugResetForTests() {
    _instance = null;
    _tried = false;
  }

  /// The device, or null when no binary loads, the binary speaks a
  /// different ABI, or it disagrees about the audio struct layout.
  ///
  /// That last check matters more here than anywhere else: this class
  /// hands [QaAudioClipStruct] and friends — declared next door in
  /// `qa_audio_native.dart` — straight to the C on the path that reaches
  /// a real speaker. Until the AUDIO-PRO ABI consolidation it was the one
  /// loader with NO gate at all, so a layout change would have stood the
  /// verification mixer down correctly while the device kept pushing
  /// misread fields at someone's headphones.
  static QaAudioDevice? get instance {
    if (!_tried) {
      _tried = true;
      final library = openQaEngineLibrary();
      _instance = library == null || !qaAudioStructLayoutsMatch(library)
          ? null
          : QaAudioDevice._(library);
    }
    return _instance;
  }

  late final _open = _library
      .lookupFunction<
        Int32 Function(Int32, Int32, Int32, Int32),
        int Function(int, int, int, int)
      >('qa_audio_device_open');
  late final _deviceCount = _library
      .lookupFunction<Int32 Function(Int32, Int32), int Function(int, int)>(
        'qa_audio_device_count',
      );
  late final _deviceDescribe = _library.lookupFunction<
    Int32 Function(Int32, Int32, Pointer<Utf8>, Int32, Pointer<Int32>),
    int Function(int, int, Pointer<Utf8>, int, Pointer<Int32>)
  >('qa_audio_device_describe');
  late final _close = _library
      .lookupFunction<Void Function(), void Function()>('qa_audio_device_close');
  late final _isOpen = _library
      .lookupFunction<Int32 Function(), int Function()>('qa_audio_device_is_open');
  late final _sampleRate = _library
      .lookupFunction<Int32 Function(), int Function()>(
        'qa_audio_device_sample_rate',
      );
  late final _channels = _library
      .lookupFunction<Int32 Function(), int Function()>(
        'qa_audio_device_channels',
      );
  late final _latency = _library
      .lookupFunction<Int64 Function(), int Function()>(
        'qa_audio_device_latency_samples',
      );
  late final _setSchedule = _library.lookupFunction<
    Int32 Function(
      Pointer<QaAudioClipStruct>,
      Int32,
      Pointer<QaAudioSourceStruct>,
      Int32,
      Pointer<Float>,
      Int64,
      Pointer<Int64>,
      Pointer<QaAudioEnvelopeKeyStruct>,
      Int32,
    ),
    int Function(
      Pointer<QaAudioClipStruct>,
      int,
      Pointer<QaAudioSourceStruct>,
      int,
      Pointer<Float>,
      int,
      Pointer<Int64>,
      Pointer<QaAudioEnvelopeKeyStruct>,
      int,
    )
  >('qa_audio_device_set_schedule');
  late final _play = _library
      .lookupFunction<Int32 Function(Int64, Int64, Int32), int Function(int, int, int)>(
        'qa_audio_device_play',
      );
  late final _stop = _library
      .lookupFunction<Void Function(), void Function()>('qa_audio_device_stop');
  late final _isPlaying = _library
      .lookupFunction<Int32 Function(), int Function()>(
        'qa_audio_device_is_playing',
      );
  late final _position = _library
      .lookupFunction<Int64 Function(), int Function()>(
        'qa_audio_device_position',
      );
  late final _seek = _library
      .lookupFunction<Void Function(Int64), void Function(int)>(
        'qa_audio_device_seek',
      );
  late final _peak = _library
      .lookupFunction<Double Function(Int32), double Function(int)>(
        'qa_audio_device_peak',
      );
  late final _captureStart = _library
      .lookupFunction<
        Int32 Function(Int32, Int32, Int32),
        int Function(int, int, int)
      >('qa_audio_capture_start');
  late final _captureRead = _library
      .lookupFunction<
        Int32 Function(Pointer<Float>, Int32),
        int Function(Pointer<Float>, int)
      >('qa_audio_capture_read');
  late final _captureStop = _library
      .lookupFunction<Void Function(), void Function()>('qa_audio_capture_stop');
  late final _captureIsOpen = _library
      .lookupFunction<Int32 Function(), int Function()>(
        'qa_audio_capture_is_open',
      );
  late final _captureChannels = _library
      .lookupFunction<Int32 Function(), int Function()>(
        'qa_audio_capture_channels',
      );
  late final _captureDroppedFrames = _library
      .lookupFunction<Int64 Function(), int Function()>(
        'qa_audio_capture_dropped_frames',
      );
  late final _captureLatency = _library
      .lookupFunction<Int64 Function(), int Function()>(
        'qa_audio_capture_latency_samples',
      );

  /// Opens the output device, returning its ACTUAL sample rate (0 = the
  /// device could not be opened).
  ///
  /// The rate comes back rather than being assumed because a device may
  /// refuse the one asked for, and conforming to a rate the device is not
  /// running at would put every sound at the wrong speed.
  ///
  /// [useNullBackend] runs miniaudio's null device: a real callback on a
  /// real thread with no hardware. That is how the transport is exercised
  /// on a CI runner with no sound card.
  ///
  /// [deviceIndex] picks from the last [devicesOf] enumeration (AUDIO-PRO
  /// R4); -1 = the system default. A bad index fails rather than opening
  /// something else — retry with -1 to fall back deliberately.
  int open({
    int sampleRate = 48000,
    int channels = 2,
    bool useNullBackend = false,
    int deviceIndex = -1,
  }) => _open(sampleRate, channels, useNullBackend ? 1 : 0, deviceIndex);

  /// Enumerates output ([capture] false) or input devices, in the index
  /// order [open]'s `deviceIndex` refers to. Empty on any failure —
  /// callers fall back to the system default, never crash a picker.
  List<({String name, bool isDefault})> devicesOf({
    required bool capture,
    bool useNullBackend = false,
  }) {
    final kind = capture ? 1 : 0;
    final count = _deviceCount(kind, useNullBackend ? 1 : 0);
    if (count <= 0) {
      return const [];
    }
    final nameBuffer = calloc<Uint8>(256);
    final isDefaultOut = calloc<Int32>();
    try {
      final devices = <({String name, bool isDefault})>[];
      for (var index = 0; index < count; index += 1) {
        final length = _deviceDescribe(
          kind,
          index,
          nameBuffer.cast<Utf8>(),
          256,
          isDefaultOut,
        );
        if (length < 0) {
          continue;
        }
        devices.add(
          (
            name: nameBuffer.cast<Utf8>().toDartString(),
            isDefault: isDefaultOut.value != 0,
          ),
        );
      }
      return devices;
    } finally {
      calloc.free(isDefaultOut);
      calloc.free(nameBuffer);
    }
  }

  void close() => _close();
  bool get isOpen => _isOpen() != 0;
  int get sampleRate => _sampleRate();
  int get channels => _channels();

  /// The device's reported output latency in samples — how far ahead of
  /// what is heard the buffer runs, and therefore how much the picture has
  /// to be pulled forward. What this cannot account for is the residual
  /// the user's A/V offset removes.
  int get latencySamples => _latency();

  /// Uploads the schedule and its PCM — legal at ANY time (AUDIO-PRO R3):
  /// the C builds the replacement in a standby slot and flips atomically,
  /// so a swap during playback is heard within one mixed block, with the
  /// old arrays freed only after the callback provably abandoned them.
  ///
  /// The PCM is flattened into one block and COPIED on the C side: the
  /// callback must never chase a pointer into Dart-managed memory.
  bool setSchedule({
    required List<AudioMixClip> clips,
    required List<AudioMixSource> sources,
  }) {
    var totalFloats = 0;
    final offsets = <int>[];
    for (final source in sources) {
      offsets.add(totalFloats);
      totalFloats += source.samples.length;
    }

    // The clips' envelopes flatten into one shared key array, exactly as
    // the mixer FFI does (the C copies it beside the PCM) — one scope
    // builds that whole layout for both paths.
    final arrays = QaAudioScheduleArrays(clips, sources);
    final pcm = calloc<Float>(totalFloats <= 0 ? 1 : totalFloats);
    final offsetArray = calloc<Int64>(offsets.isEmpty ? 1 : offsets.length);
    try {
      for (var index = 0; index < sources.length; index += 1) {
        final source = sources[index];
        // repointed at the C copy
        arrays.writeSource(index, source, nullptr);
        offsetArray[index] = offsets[index];
        if (source.samples.isNotEmpty) {
          pcm
              .asTypedList(totalFloats)
              .setRange(
                offsets[index],
                offsets[index] + source.samples.length,
                source.samples,
              );
        }
      }
      return _setSchedule(
            arrays.clipArray,
            clips.length,
            arrays.sourceArray,
            sources.length,
            pcm,
            totalFloats,
            offsetArray,
            arrays.envelopeArray,
            arrays.envelopeTotal,
          ) !=
          0;
    } finally {
      calloc.free(offsetArray);
      calloc.free(pcm);
      arrays.free();
    }
  }

  /// Starts at [startSample]. [stopSample] is exclusive; pass a value at
  /// or below the start for "no end".
  bool play({
    required int startSample,
    int stopSample = -1,
    bool looping = false,
  }) => _play(startSample, stopSample, looping ? 1 : 0) != 0;

  void stop() => _stop();
  bool get isPlaying => _isPlaying() != 0;

  /// Samples handed to the device — **the clock**. The picture reads this
  /// and shows whatever frame it lands in; when rendering falls behind,
  /// frames are dropped rather than the sound being made to wait.
  int get positionSamples => _position();

  /// Moves the transport without restarting anything. Because the mixer
  /// builds a mix rather than starting clips, a seek is just a change of
  /// where the next block is read from.
  void seek(int sample) => _seek(sample);

  /// The last mixed block's PRE-CLIP bus peak (0 = left, 1 = right; mono
  /// mirrors left) — the level meter's feed (AUDIO-PRO R2). A value past
  /// 1.0 means the output stage is clipping, which is exactly what the
  /// meter exists to make visible.
  double peakFor(int channel) => _peak(channel);

  /// Opens the capture device and starts delivering into the C-side ring
  /// (AUDIO-PRO R5). Returns the delivered sample rate ([sampleRate] — the
  /// C converts from the device's native rate) or 0 on failure, which on
  /// mobile/macOS includes "no microphone permission". Channels are the
  /// device's own — read [captureChannels] after a successful start.
  ///
  /// Independent of the playback device: recording runs DURING playback.
  int captureStart({
    required int sampleRate,
    bool useNullBackend = false,
    int deviceIndex = -1,
  }) => _captureStart(sampleRate, useNullBackend ? 1 : 0, deviceIndex);

  /// Drains up to [maxFloats] captured floats into [out], returning how
  /// many were copied. Call from a timer while recording, and once more
  /// before [captureStop] for the tail.
  int captureRead(Pointer<Float> out, int maxFloats) =>
      _captureRead(out, maxFloats);

  void captureStop() => _captureStop();
  bool get captureIsOpen => _captureIsOpen() != 0;
  int get captureChannels => _captureChannels();

  /// Frames the ring dropped because the drain fell behind. Nonzero means
  /// the take is damaged — say so, never save a silently shortened file.
  int get captureDroppedFrames => _captureDroppedFrames();

  /// The capture path's own buffering in samples (typically 10-30 ms).
  int get captureLatencySamples => _captureLatency();
}

/// The enumeration index, on the [capture] side or the playback side, for
/// the device named [name].
///
/// Playback: or -1 (the system default) when [name] is null or no longer
/// attached — a missing speaker falls back to the default rather than
/// failing playback (AUDIO-PRO R4).
///
/// Capture: or -1 (the system default microphone) when [name] is null or
/// unplugged (AUDIO-PRO R5).
///
/// [capture] is the enumeration-kind axis [QaAudioDevice.devicesOf] already
/// takes (it becomes the C `kind`), not a behaviour switch: one search, one
/// question.
int audioDeviceIndexByName(
  QaAudioDevice device, {
  required bool capture,
  required String? name,
}) {
  // 🧪Mutating this guard away leaves every ANSWER unchanged — the loop
  // below finds no device named null and returns -1 anyway. It stays as an
  // early-out: no saved device is the common case, and it skips an FFI
  // enumeration plus a 256-byte calloc on every open.
  if (name == null) {
    return -1;
  }
  final devices = device.devicesOf(capture: capture);
  for (var index = 0; index < devices.length; index += 1) {
    if (devices[index].name == name) {
      return index;
    }
  }
  return -1;
}

/// Opens [device] on the output named [preferredName], falling back to the
/// system default — true when the device is open afterwards.
///
/// 🚨The named device failed to open (unplugged mid-enumeration): fall
/// back to the system default deliberately, never to silence (AUDIO-PRO
/// R4). The retry only happens when a NAMED device was actually picked;
/// a default that will not open has nowhere left to fall.
///
/// One sequence for the three callers that need a speaker — the playback
/// transport, the scrub arm and the recording cue — which differ only in
/// the rate, the channel count and where the name comes from.
bool openAudioOutput(
  QaAudioDevice device, {
  required int sampleRate,
  required String? preferredName,
  int channels = 2,
}) {
  final index = audioDeviceIndexByName(
    device,
    capture: false,
    name: preferredName,
  );
  var opened = device.open(
    sampleRate: sampleRate,
    channels: channels,
    deviceIndex: index,
  );
  // 🧪MUTATION: this retry SURVIVES the suite — never applied. Reaching it
  // needs a device that enumerates under a name and then REFUSES to open,
  // which no bench here can stage: `QaAudioDevice` binds to the real
  // binary and cannot be faked, and the null backend's one device always
  // opens. The reachable half — an unattached name falling back to the
  // default rather than to silence — is pinned in `qa_audio_device_test`.
  if (opened <= 0 && index >= 0) {
    opened = device.open(sampleRate: sampleRate, channels: channels);
  }
  return opened > 0;
}

/// Reads the played position as a frame index, pulled forward by the
/// device's own reported latency so the picture matches what is being
/// HEARD rather than what has merely been queued.
///
/// [extraOffsetSamples] is the user's A/V offset: the residual no device
/// report can account for (screen pipeline, Bluetooth, an AV receiver).
/// Every professional tool exposes this for the same reason — the part
/// that is measurable gets corrected automatically, and the rest is a
/// slider.
int audioClockFrame({
  required int positionSamples,
  required int latencySamples,
  required int extraOffsetSamples,
  required int sampleRate,
  required int frameRateNumerator,
  required int frameRateDenominator,
}) {
  if (sampleRate <= 0 || frameRateNumerator <= 0 || frameRateDenominator <= 0) {
    return 0;
  }
  final heard = positionSamples - latencySamples + extraOffsetSamples;
  if (heard <= 0) {
    return 0;
  }
  // Integer throughout, like every other frame/sample conversion in this
  // program: a double here would drift over a long timeline.
  return heard * frameRateNumerator ~/ (sampleRate * frameRateDenominator);
}
