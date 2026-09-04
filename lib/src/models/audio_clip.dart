import '../core/collection_equality.dart';
import 'frame_id.dart';

/// The shape a fade ramp takes (AUDIO-PRO R1).
///
/// [linear] is the historical ramp. [equalPower] follows sqrt(t) — the
/// crossfade convention where the sum of SQUARES stays constant, so two
/// overlapped fades hold perceived loudness instead of dipping ~3 dB at
/// the middle. sqrt on purpose rather than sin: IEEE 754 requires sqrt to
/// be correctly rounded, so the C mixer and the Dart reference produce
/// the same bits — a libm sin can differ by an ulp between the two.
enum AudioFadeCurve { linear, equalPower }

/// One point of a clip's volume envelope (AUDIO-PRO R1): at [frame]
/// (clip-local, from the audible span's start) the envelope passes
/// [gain]. Between points the value interpolates linearly; before the
/// first and after the last it holds. An empty envelope is unity.
///
/// Authored keys are non-negative; the playback schedule reuses this type
/// with keys SHIFTED by a trim, which may land negative — that is a
/// position before the audible window, not an error.
class AudioVolumeKey {
  const AudioVolumeKey({required this.frame, required this.gain})
    : assert(gain >= 0, 'gain must be non-negative');

  final int frame;
  final double gain;

  Map<String, dynamic> toJson() => {'frame': frame, 'gain': gain};

  factory AudioVolumeKey.fromJson(Map<String, dynamic> json) =>
      AudioVolumeKey(
        frame: json['frame'] as int,
        gain: (json['gain'] as num).toDouble(),
      );

  @override
  bool operator ==(Object other) =>
      other is AudioVolumeKey && other.frame == frame && other.gain == gain;

  @override
  int get hashCode => Object.hash(frame, gain);

  @override
  String toString() => 'AudioVolumeKey(frame: $frame, gain: $gain)';
}

/// One sound linked to an SE layer FRAME — exactly like drawings link to
/// frames: the sound belongs to the instance, every timeline block exposing
/// that frame carries it (block start = sound start, block length clamps
/// playback), and removing the block removes the sound with it. Linked
/// blocks sharing the frame share the sound (footsteps reuse).
///
/// The clip's own length comes from the file (the waveform/peaks pipeline
/// measures it) — the model stores the link only.
///
/// v1 stores the ABSOLUTE path (the first file reference a project
/// carries); relative-to-project paths arrive with project bundling.
class AudioClip {
  const AudioClip({
    required this.filePath,
    required this.frameId,
    this.offsetFrames = 0,
    this.gain = 1.0,
    this.fadeInFrames = 0,
    this.fadeOutFrames = 0,
    this.fadeCurve = AudioFadeCurve.linear,
    this.volumeKeys = const [],
    this.clipped = false,
  }) : assert(offsetFrames >= 0, 'offsetFrames must be non-negative'),
       assert(gain >= 0, 'gain must be non-negative'),
       assert(fadeInFrames >= 0, 'fadeInFrames must be non-negative'),
       assert(fadeOutFrames >= 0, 'fadeOutFrames must be non-negative');

  final String filePath;

  /// The SE frame (instance) this sound belongs to.
  final FrameId frameId;

  /// Frames skipped INTO the sound file where the carrying block starts —
  /// the audio lane's slide-the-sound trim. 0 = the file plays from its
  /// beginning; never negative (a sound cannot start before its block:
  /// move the block instead).
  final int offsetFrames;

  /// Volume multiplier; 1.0 = the file's own level. Playback clamps the
  /// effective volume into what the platform supports; export applies it
  /// exactly (ffmpeg `volume`).
  final double gain;

  /// Frames over which the clip ramps from silence to [gain], anchored at
  /// the audible span's start (the carrying block's start).
  final int fadeInFrames;

  /// Frames over which the clip ramps from [gain] to silence, anchored at
  /// the audible span's end (block/cut end — where playback stops it).
  final int fadeOutFrames;

  /// The shape both fades take (AUDIO-PRO R1).
  final AudioFadeCurve fadeCurve;

  /// The clip's volume envelope (AUDIO-PRO R1) — the rubber band: keyed
  /// gains at clip-local frames, linearly interpolated, held past the
  /// ends. Multiplies with [gain] and the fades. Kept SORTED by frame;
  /// empty = unity.
  final List<AudioVolumeKey> volumeKeys;

  /// A recorded take that hit the ceiling (REC1-D): the capture chain
  /// detected digital clipping baked into this file. Display material —
  /// the block's warning marker; playback ignores it.
  final bool clipped;

  AudioClip copyWith({
    String? filePath,
    FrameId? frameId,
    int? offsetFrames,
    double? gain,
    int? fadeInFrames,
    int? fadeOutFrames,
    AudioFadeCurve? fadeCurve,
    List<AudioVolumeKey>? volumeKeys,
    bool? clipped,
  }) {
    return AudioClip(
      filePath: filePath ?? this.filePath,
      frameId: frameId ?? this.frameId,
      offsetFrames: offsetFrames ?? this.offsetFrames,
      gain: gain ?? this.gain,
      fadeInFrames: fadeInFrames ?? this.fadeInFrames,
      fadeOutFrames: fadeOutFrames ?? this.fadeOutFrames,
      fadeCurve: fadeCurve ?? this.fadeCurve,
      volumeKeys: volumeKeys ?? this.volumeKeys,
      clipped: clipped ?? this.clipped,
    );
  }

  Map<String, dynamic> toJson() => {
    'file': filePath,
    'frame': frameId.value,
    if (offsetFrames != 0) 'offset': offsetFrames,
    if (gain != 1.0) 'gain': gain,
    if (fadeInFrames != 0) 'fadeIn': fadeInFrames,
    if (fadeOutFrames != 0) 'fadeOut': fadeOutFrames,
    if (fadeCurve != AudioFadeCurve.linear) 'fadeCurve': fadeCurve.name,
    if (volumeKeys.isNotEmpty)
      'volumeKeys': volumeKeys.map((key) => key.toJson()).toList(),
    if (clipped) 'clipped': true,
  };

  factory AudioClip.fromJson(Map<String, dynamic> json) {
    return AudioClip(
      filePath: json['file'] as String,
      frameId: FrameId(json['frame'] as String),
      offsetFrames: json['offset'] as int? ?? 0,
      gain: (json['gain'] as num?)?.toDouble() ?? 1.0,
      fadeInFrames: json['fadeIn'] as int? ?? 0,
      fadeOutFrames: json['fadeOut'] as int? ?? 0,
      fadeCurve: AudioFadeCurve.values.firstWhere(
        (curve) => curve.name == json['fadeCurve'],
        orElse: () => AudioFadeCurve.linear,
      ),
      volumeKeys: json['volumeKeys'] == null
          ? const []
          : [
              for (final key in json['volumeKeys'] as List<dynamic>)
                AudioVolumeKey.fromJson(key as Map<String, dynamic>),
            ],
      clipped: json['clipped'] as bool? ?? false,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AudioClip &&
          other.filePath == filePath &&
          other.frameId == frameId &&
          other.offsetFrames == offsetFrames &&
          other.gain == gain &&
          other.fadeInFrames == fadeInFrames &&
          other.fadeOutFrames == fadeOutFrames &&
          other.fadeCurve == fadeCurve &&
          other.clipped == clipped &&
          listEquals(other.volumeKeys, volumeKeys);


  @override
  int get hashCode => Object.hash(
    filePath,
    frameId,
    offsetFrames,
    gain,
    fadeInFrames,
    fadeOutFrames,
    fadeCurve,
    clipped,
    Object.hashAll(volumeKeys),
  );

  @override
  String toString() =>
      'AudioClip(filePath: $filePath, frameId: $frameId, '
      'offsetFrames: $offsetFrames, gain: $gain, '
      'fadeInFrames: $fadeInFrames, fadeOutFrames: $fadeOutFrames, '
      'fadeCurve: ${fadeCurve.name}, volumeKeys: $volumeKeys, '
      'clipped: $clipped)';
}
