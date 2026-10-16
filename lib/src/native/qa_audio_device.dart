import 'dart:async';
import 'dart:ffi';
import 'dart:io' show Platform;
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import '../services/audio/audio_mixer_reference.dart';
import 'qa_audio_native.dart';
import 'qa_engine_abi.dart';

/// Where the device's buffers come from, as one isolate tells another: its
/// maker and its release, by their functions' addresses
/// ([QaAudioDevice.buffers]). [audioBuffersHere] binds them.
///
/// 🚨A worker filling buffers for [QaAudioDevice.adoptSamples] takes them
/// from the isolate that ADOPTS them: the release its lists' finalizer runs
/// is that isolate's, and a worker's own probe can load another binary, or
/// none — a test's path override is a static, and statics do not cross
/// isolates (`TileBlocks`, the same shape for a tile's pixels).
typedef AudioBuffers = ({int make, int release});

/// What fills the device's buffers where [AudioBuffers] were sent: where a
/// buffer comes from, and where it goes back when the work it was for
/// fails.
typedef AudioBufferHands = ({
  Pointer<Float> Function(int floats) make,
  void Function(Pointer<Float> samples) release,
});

/// [buffers] bound in the isolate they were sent to — whose [make] throws
/// when the memory is not there, failing the work it was for whole.
AudioBufferHands audioBuffersHere(AudioBuffers buffers) {
  final make =
      Pointer<NativeFunction<Pointer<Float> Function(Int64)>>.fromAddress(
        buffers.make,
      ).asFunction<Pointer<Float> Function(int)>();
  final release =
      Pointer<NativeFunction<Void Function(Pointer<Void>)>>.fromAddress(
        buffers.release,
      ).asFunction<void Function(Pointer<Void>)>();
  return (
    make: (floats) {
      final samples = make(floats);
      if (samples == nullptr) {
        throw StateError('qa_audio_buffer_new failed for $floats floats');
      }
      return samples;
    },
    release: (samples) => release(samples.cast()),
  );
}

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
      Pointer<QaAudioEnvelopeKeyStruct>,
      Int32,
    ),
    int Function(
      Pointer<QaAudioClipStruct>,
      int,
      Pointer<QaAudioSourceStruct>,
      int,
      Pointer<QaAudioEnvelopeKeyStruct>,
      int,
    )
  >('qa_audio_device_set_schedule');
  late final _bufferNewNative = _library
      .lookup<NativeFunction<Pointer<Float> Function(Int64)>>(
        'qa_audio_buffer_new',
      );
  late final _bufferNew = _bufferNewNative
      .asFunction<Pointer<Float> Function(int)>();
  late final _bufferReleaseNative = _library
      .lookup<NativeFunction<Void Function(Pointer<Void>)>>(
        'qa_audio_buffer_release',
      );
  late final _bufferRelease = _bufferReleaseNative
      .asFunction<void Function(Pointer<Void>)>();

  late final _bufferRetain = _library
      .lookupFunction<
        Pointer<Float> Function(Pointer<Float>),
        Pointer<Float> Function(Pointer<Float>)
      >('qa_audio_buffer_retain', isLeaf: true);
  late final _bufferHolds = _library
      .lookupFunction<
        Int32 Function(Pointer<Float>),
        int Function(Pointer<Float>)
      >('qa_audio_buffer_holds', isLeaf: true);

  /// The buffers [newSamples] made, by the list that is their samples.
  final Expando<Pointer<Float>> _made = Expando<Pointer<Float>>(
    'device buffers',
  );
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
  late final _clock = _library
      .lookupFunction<Int32 Function(Pointer<Int64>), int Function(Pointer<Int64>)>(
        'qa_audio_device_clock',
      );
  late final _clockNow = _library
      .lookupFunction<Int64 Function(), int Function()>(
        'qa_audio_clock_now_us',
      );

  /// Where [clockPoint] has the native side write its two numbers. One
  /// block for the life of the binding: the clock is read every tick.
  late final Pointer<Int64> _clockOut = calloc<Int64>(2);
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
  late final _captureFrames = _library
      .lookupFunction<Int64 Function(), int Function()>(
        'qa_audio_capture_frames',
      );
  late final _captureClock = _library
      .lookupFunction<Int32 Function(Pointer<Int64>), int Function(Pointer<Int64>)>(
        'qa_audio_capture_clock',
      );

  /// Where [readCaptureClock] has the native side write its two numbers.
  late final Pointer<Int64> _captureClockOut = calloc<Int64>(2);

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
  }) {
    _onNullBackend |= useNullBackend;
    return _open(sampleRate, channels, useNullBackend ? 1 : 0, deviceIndex);
  }

  /// Whether this device has been opened on the null backend — a bench's,
  /// never the program's — so every open after it is on the null backend
  /// too ([openAudioOutput]): 🚨a bench that hands a transport its null
  /// device has it opened again AHEAD, by the program's own road
  /// ([openAudioOutputAhead]), and that road must not find the speakers.
  bool _onNullBackend = false;

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

  /// The output setting [openAudioOutput] opened this device for — a name,
  /// or null for the system default — while [isOpen]. An unattached name
  /// opens the default and is still what it was opened for, so a changed
  /// setting is told by this, whoever opened it: ↩️the transport kept a copy
  /// of its own, and a device the scrubber or a cue had opened under a named
  /// setting read to it as one to reopen.
  String? get openedFor => _openedFor;
  String? _openedFor;

  /// Whether the output is being opened off this thread
  /// ([openAudioOutputAhead]) — what an arm stands down on, rather than
  /// open it here again and wait for the worker's open to let go of the C.
  bool get isOpening => _opening != null;
  Future<void>? _opening;

  /// Who keeps the output open: a session's transport from when it opens it
  /// ahead — as its project opens (play-press-first-frame-stall-Q2 a) — or
  /// first plays on it, and a cue while it sounds. ↩️Each transport closed
  /// it as it went, under every other open project's next play.
  final Set<Object> _keepers = {};

  void keep(Object keeper) => _keepers.add(keeper);

  /// [keeper] lets go, and the output closes once nobody keeps it — after
  /// an open under way, which would otherwise leave it open and unkept.
  void letGo(Object keeper) {
    _keepers.remove(keeper);
    final opening = _opening;
    if (opening == null) {
      _closeUnkept();
    } else {
      unawaited(opening.whenComplete(_closeUnkept));
    }
  }

  void _closeUnkept() {
    if (_keepers.isEmpty && isOpen) {
      stop();
      close();
    }
  }

  int get sampleRate => _sampleRate();
  int get channels => _channels();

  /// The device's reported output latency in samples — how far ahead of
  /// what is heard the buffer runs, and therefore how much the picture has
  /// to be pulled forward. What this cannot account for is the residual
  /// the user's A/V offset removes.
  int get latencySamples => _latency();

  /// [floats] samples in a buffer of the device's own, which a schedule
  /// plays where it lies ([setSchedule]) — let go when the list goes. Null
  /// when the memory is not there.
  Float32List? newSamples(int floats) {
    final pointer = _bufferNew(floats);
    return pointer == nullptr ? null : _listOver(pointer, floats);
  }

  /// [newSamples]' maker and the release its lists' finalizer runs, by
  /// address — for a worker that fills buffers this isolate adopts
  /// ([audioBuffersHere], [adoptSamples]).
  AudioBuffers get buffers => (
    make: _bufferNewNative.address,
    release: _bufferReleaseNative.address,
  );

  /// The [floats] samples a worker made with [buffers] and filled, at
  /// [address] — the list over them, holding them as if [newSamples] had
  /// made them here: the worker's hold is the list's now.
  Float32List adoptSamples(int address, int floats) =>
      _listOver(Pointer<Float>.fromAddress(address), floats);

  /// The list over the buffer at [pointer], holding it until the list goes.
  Float32List _listOver(Pointer<Float> pointer, int floats) {
    final samples = pointer.asTypedList(
      floats,
      finalizer: _bufferReleaseNative,
      token: pointer.cast(),
    );
    _made[samples] = pointer;
    return samples;
  }

  /// How many hold the buffer [samples] lie in — the list that made them,
  /// and each source of a schedule that plays them. -1 for a list
  /// [newSamples] did not make.
  int debugHoldsOf(Float32List samples) {
    final made = _made[samples];
    return made == null ? -1 : _bufferHolds(made);
  }

  /// Uploads the schedule — legal at ANY time (AUDIO-PRO R3): the C builds
  /// the replacement in a standby slot and flips atomically, so a swap
  /// during playback is heard within one mixed block, with the old arrays
  /// freed only after the callback provably abandoned them.
  ///
  /// 🚨THE SCHEDULE NAMES THE DEVICE'S OWN PCM; IT COPIES NONE OF IT
  /// (play-press-first-frame-stall, 10-15). Samples [newSamples] made are
  /// played where they lie, and the slot that plays them holds them past
  /// their list. Any other list is copied into a buffer made for this
  /// schedule alone — the callback must never chase a pointer into
  /// Dart-managed memory, nor one whose life nobody holds. ↩️Every upload
  /// flattened ALL the PCM into one block here, and the C copied the block
  /// again (🔬33ms on the AMMI OP press). False uploads nothing: the old
  /// schedule plays on.
  bool setSchedule({
    required List<AudioMixClip> clips,
    required List<AudioMixSource> sources,
  }) {
    // The clips' envelopes flatten into one shared key array, exactly as
    // the mixer FFI does — one scope builds that whole layout for both
    // paths.
    final arrays = QaAudioScheduleArrays(clips, sources);
    final holds = <Pointer<Float>>[];
    try {
      for (var index = 0; index < sources.length; index += 1) {
        final source = sources[index];
        final played = _playedFrom(source.samples, holds);
        if (played == null) {
          return false;
        }
        arrays.writeSource(index, source, played);
      }
      return _setSchedule(
            arrays.clipArray,
            clips.length,
            arrays.sourceArray,
            sources.length,
            arrays.envelopeArray,
            arrays.envelopeTotal,
          ) !=
          0;
    } finally {
      // The slot holds what it plays; this call's holds were its own.
      for (final hold in holds) {
        _bufferRelease(hold.cast());
      }
      arrays.free();
    }
  }

  /// Where the device plays [samples] from — the buffer [newSamples] made
  /// them in, or a copy made for this call — held for the call in [holds].
  /// Null when the memory for a copy is not there.
  ///
  /// ⚠️A made list that goes takes its maker's hold with it, so the call
  /// takes a hold of its own, and the buffer lives until the slot holds
  /// it. The list cannot go before that hold lands: [setSchedule] reads
  /// it again after this, writing its source.
  Pointer<Float>? _playedFrom(
    Float32List samples,
    List<Pointer<Float>> holds,
  ) {
    if (samples.isEmpty) {
      return nullptr;
    }
    final made = _made[samples];
    if (made != null && _bufferRetain(made) != nullptr) {
      holds.add(made);
      return made;
    }
    final copy = _bufferNew(samples.length);
    if (copy == nullptr) {
      return null;
    }
    holds.add(copy);
    copy.asTypedList(samples.length).setAll(0, samples);
    return copy;
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
  ///
  /// ⚠️A STAIR: it climbs one audio callback at a time. Between two
  /// callbacks it says what was handed at the last one, and the device has
  /// gone on playing since — see [clockPoint] for the line through it.
  int get positionSamples => _position();

  /// The latest point of the clock's LINE: the samples that had been
  /// handed when a callback returned, and when that callback was asked, in
  /// microseconds on [clockNowMicros]'s clock. Null when no callback has
  /// spoken since the transport was last armed — then there is only the
  /// stair ([positionSamples]).
  ({int positionSamples, int atMicros})? get clockPoint =>
      _clock(_clockOut) == 0
      ? null
      : (positionSamples: _clockOut[0], atMicros: _clockOut[1]);

  /// The time now on the clock [clockPoint] is stamped with — monotonic,
  /// and no other clock's.
  int get clockNowMicros => _clockNow();

  /// The clock, read in the ONE order that makes sense of it: the point
  /// first, then the stair — which can then only stand at its point or past
  /// it — then the time, which can then only be after both. Read the other
  /// way round, a callback landing between the reads puts the point past
  /// the stair, and a looping device's stair a lap behind it.
  ({
    ({int positionSamples, int atMicros})? point,
    int stairSamples,
    int nowMicros,
  })
  readClock() {
    final point = clockPoint;
    return (point: point, stairSamples: _position(), nowMicros: _clockNow());
  }

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

  /// The capture's clock, read in [readClock]'s order — the latest
  /// callback's word (the frames the ring had been given when it returned,
  /// and when it was asked, on [clockNowMicros]'s clock; null before the
  /// capture's first callback), then the frames given as they stand, then
  /// the time. The playback's shape, so the two lines are read alike.
  ({
    ({int positionSamples, int atMicros})? point,
    int stairSamples,
    int nowMicros,
  })
  readCaptureClock() {
    final point = _captureClock(_captureClockOut) == 0
        ? null
        : (
            positionSamples: _captureClockOut[0],
            atMicros: _captureClockOut[1],
          );
    return (
      point: point,
      stairSamples: _captureFrames(),
      nowMicros: _clockNow(),
    );
  }
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
  bool useNullBackend = false,
}) {
  // 🧪Mutating this guard away leaves every ANSWER unchanged — the loop
  // below finds no device named null and returns -1 anyway. It stays as an
  // early-out: no saved device is the common case, and it skips an FFI
  // enumeration plus a 256-byte calloc on every open.
  if (name == null) {
    return -1;
  }
  final devices = device.devicesOf(
    capture: capture,
    useNullBackend: useNullBackend,
  );
  for (var index = 0; index < devices.length; index += 1) {
    if (devices[index].name == name) {
      return index;
    }
  }
  return -1;
}

/// The device, unless a widget test is asking.
///
/// 🚨★★★**A WIDGET TEST NEVER TOUCHES THE HARDWARE.** `flutter_tester`
/// runs on a developer's machine with speakers attached, and every audio
/// path here can reach them — so the paths take their device through this
/// rather than through [QaAudioDevice.instance] directly.
///
/// ⚠️Written down once when the media viewer became the FOURTH caller
/// (2026-09-08). The transport, the scrubber and the Preferences device
/// list had each spelled the same `FLUTTER_TEST` check out, and the viewer
/// was written WITHOUT one — which is how it was found: a widget test
/// opened a real output and reported that sound was playing.
///
/// ⛔It is not a resolver a caller may skip 「just this once」. A path that
/// wants a device for a reason of its own still comes through here and
/// gets null under test; the injectable `resolveDevice` seams stay, and
/// they exist so a test can hand in a FAKE, never so one can reach the
/// real thing.
QaAudioDevice? audioOutputUnlessTesting() =>
    Platform.environment['FLUTTER_TEST'] == 'true'
    ? null
    : QaAudioDevice.instance;

/// Opens the closed [device] on the output named [preferredName], falling
/// back to the system default — true when the device is open afterwards,
/// for [preferredName] ([QaAudioDevice.openedFor]).
///
/// 🚨The named device failed to open (unplugged mid-enumeration): fall
/// back to the system default deliberately, never to silence (AUDIO-PRO
/// R4). The retry only happens when a NAMED device was actually picked;
/// a default that will not open has nowhere left to fall.
///
/// One sequence for every caller that opens a speaker — the shared arm
/// (`armAudioOutput`: the transport, the scrubber, the viewer), the
/// recording cue and the open ahead ([openAudioOutputAhead]) — which differ
/// only in the rate, the channel count and where the name comes from.
///
/// On the null backend where [device] has been on it — a worker's device
/// told so by the open that hands it the work ([openAudioOutputAhead]).
bool openAudioOutput(
  QaAudioDevice device, {
  required int sampleRate,
  required String? preferredName,
  int channels = 2,
}) {
  final onTheNullBackend = device._onNullBackend;
  final index = audioDeviceIndexByName(
    device,
    // 🧪MUTATION: flipping this to `capture: true` SURVIVES the suite —
    // never applied. Every bench here passes a name that is attached on
    // NEITHER side, so both searches answer -1 and the same default open
    // follows; only a machine with an output-only device name could tell
    // the two apart, and the kind axis itself is pinned on real hardware
    // in `qa_audio_device_test` ("a name that exists only on one side").
    capture: false,
    name: preferredName,
    useNullBackend: onTheNullBackend,
  );
  var opened = device.open(
    sampleRate: sampleRate,
    channels: channels,
    deviceIndex: index,
    useNullBackend: onTheNullBackend,
  );
  // 🧪MUTATION: this retry SURVIVES the suite — never applied. Reaching it
  // needs a device that enumerates under a name and then REFUSES to open,
  // which no bench here can stage: `QaAudioDevice` binds to the real
  // binary and cannot be faked, and the null backend's one device always
  // opens. The reachable half — an unattached name falling back to the
  // default rather than to silence — is pinned in `qa_audio_device_test`.
  if (opened <= 0 && index >= 0) {
    opened = device.open(
      sampleRate: sampleRate,
      channels: channels,
      useNullBackend: onTheNullBackend,
    );
  }
  if (opened <= 0) {
    return false;
  }
  device._openedFor = preferredName;
  return true;
}

/// [openAudioOutput] on a worker, off the thread that draws — after closing
/// [device] there when it is open for another output
/// (play-press-first-frame-stall-Q1, 유저 10-15: 「프로젝트를 열면 미리
/// 연다(UI 스레드 밖에서)」 — a first play's open held the UI thread for
/// 63–272 ms). The device is one per process, so the output a worker opens
/// is the one this isolate's [device] finds open.
///
/// One at a time: an open asked for while one is under way follows it, and
/// an output already open for [preferredName] is left as it is.
Future<void> openAudioOutputAhead(
  QaAudioDevice device, {
  required int sampleRate,
  required String? preferredName,
}) {
  final opening = _openAhead(
    device,
    after: device._opening,
    sampleRate: sampleRate,
    preferredName: preferredName,
  );
  device._opening = opening;
  return opening.whenComplete(() {
    if (identical(device._opening, opening)) {
      device._opening = null;
    }
  });
}

Future<void> _openAhead(
  QaAudioDevice device, {
  required Future<void>? after,
  required int sampleRate,
  required String? preferredName,
}) async {
  await after;
  if (device.isOpen && device._openedFor == preferredName) {
    return;
  }
  final reopen = device.isOpen;
  // A worker's device is its own, so it is told the one fact a bench's
  // device carries ([QaAudioDevice._onNullBackend]).
  final onTheNullBackend = device._onNullBackend;
  bool opened;
  try {
    opened = await onAWorkerWithThisEngine(() {
      final here = QaAudioDevice.instance;
      if (here == null) {
        return false;
      }
      here._onNullBackend = onTheNullBackend;
      if (reopen) {
        here
          ..stop()
          ..close();
      }
      return openAudioOutput(
        here,
        sampleRate: sampleRate,
        preferredName: preferredName,
      );
    });
  } on Object {
    // A worker that could not open it leaves it as one that would not open:
    // closed, and opened on the next arm.
    opened = false;
  }
  if (opened) {
    device._openedFor = preferredName;
  }
}
