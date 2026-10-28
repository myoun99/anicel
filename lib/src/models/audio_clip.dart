import 'frame_id.dart';
import 'media_asset.dart' show normalizedMediaPath;

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
///
/// ↩️It carried fades, their curve and a volume envelope of its own
/// (AUDIO-PRO R1), shaped on the audio lane's waveform strip. 유저 I-140
/// (2026-10-28, Q1 「행에 늘 있는 「오디오」 그룹」) moved the shaping onto the
/// row's own keyed volume (`SeSound`): what a sound keeps is its gain.
class AudioClip {
  AudioClip({
    required String filePath,
    required this.frameId,
    this.offsetFrames = 0,
    this.gain = 1.0,
    this.clipped = false,
  }) : filePath = normalizedMediaPath(filePath),
       assert(offsetFrames >= 0, 'offsetFrames must be non-negative'),
       assert(gain >= 0, 'gain must be non-negative');

  /// In the pool's one spelling ([normalizedMediaPath]).
  final String filePath;

  /// The SE frame (instance) this sound belongs to.
  final FrameId frameId;

  /// Frames skipped INTO the sound file where the carrying block starts —
  /// the block edit window's offset. 0 = the file plays from its
  /// beginning; never negative (a sound cannot start before its block:
  /// move the block instead).
  final int offsetFrames;

  /// Volume multiplier; 1.0 = the file's own level — the level an import
  /// or a take brings with this sound (a pro tool's clip gain), under the
  /// row's own volume. Playback clamps the effective volume into what the
  /// platform supports; export applies it exactly.
  final double gain;

  /// A recorded take that hit the ceiling (REC1-D): the capture chain
  /// detected digital clipping baked into this file. Display material —
  /// the block's warning marker; playback ignores it.
  final bool clipped;

  AudioClip copyWith({
    String? filePath,
    FrameId? frameId,
    int? offsetFrames,
    double? gain,
    bool? clipped,
  }) {
    return AudioClip(
      filePath: filePath ?? this.filePath,
      frameId: frameId ?? this.frameId,
      offsetFrames: offsetFrames ?? this.offsetFrames,
      gain: gain ?? this.gain,
      clipped: clipped ?? this.clipped,
    );
  }

  Map<String, dynamic> toJson() => {
    'file': filePath,
    'frame': frameId.value,
    if (offsetFrames != 0) 'offset': offsetFrames,
    if (gain != 1.0) 'gain': gain,
    if (clipped) 'clipped': true,
  };

  factory AudioClip.fromJson(Map<String, dynamic> json) {
    return AudioClip(
      filePath: json['file'] as String,
      frameId: FrameId(json['frame'] as String),
      offsetFrames: json['offset'] as int? ?? 0,
      gain: (json['gain'] as num?)?.toDouble() ?? 1.0,
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
          other.clipped == clipped;

  @override
  int get hashCode =>
      Object.hash(filePath, frameId, offsetFrames, gain, clipped);

  @override
  String toString() =>
      'AudioClip(filePath: $filePath, frameId: $frameId, '
      'offsetFrames: $offsetFrames, gain: $gain, clipped: $clipped)';
}
