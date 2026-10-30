import 'property_track.dart';
import 'transform_track.dart' show doubleKeySpace;

/// An SE row's SOUND as the row plays it: its volume over time, its total
/// volume and its pan — the 「오디오」 group every SE row's twirl-down shows,
/// a sibling of its name tag and its transform.
///
/// 🗣️I-140 (유저 2026-10-28): 「오디오 전문적으로 편집하는건 오디오fx만들어서
/// 거기서 … 프리미어프로나 그런 영상편집툴이 하는대로. 게인 조절하는것도
/// 거기서 구현해서 점점 작아진다던가」, answered Q1 「행에 늘 있는 「오디오」
/// 그룹」 · Q2 「%」 · Q3 「이번엔 한 값」. So the row's volume is keyed on the
/// row's own frames — a pro tool's track keys, which stay where they are
/// when a block moves — and read as a share of the sound (1 = 100%); the pan
/// is one value, since the mixer takes one per sound.
///
/// 🗣️I-145 (유저 2026-10-30): 「역시 s행의 촐 볼륨 넣고싶음. 위치는 전처럼
/// 스피커버튼안에 볼륨. 즉 오디오fx에서도 조절하고 스피커버튼에서도 총 볼륨
/// 조절」, answered Q1 「따로 한 값 — 두 입구」: the [totalVolume] over the
/// keyed volume — a pro tool's track fader over its keys — one value, set
/// from the group's lane and from the speaker's window alike.
///
/// ↩️The speaker's mixer held a gain and a pan of the row that nothing could
/// key, and each sound kept fades, a fade curve and a volume envelope of its
/// own: this is the one place a row's sound is shaped now. What a BLOCK
/// keeps is its own gain alone (`AudioClip.gain`) — the level an import or
/// a take brings with that sound, a pro tool's clip gain.
///
/// ⛔No static volume beside the keys: a value typed into a lane keys it
/// (R9 #18, F-407), so a slot only an unkeyed lane reads would hold 100%
/// forever — the row plays as recorded until its volume is keyed. The
/// total is no such slot: it is a lane of its own, which the mix
/// multiplies in.
class SeSound {
  const SeSound({
    this.pan = 0.0,
    this.totalVolume = 1.0,
    PropertyTrack<double>? volume,
  }) : _volume = volume;

  /// Left −1 to right +1, equal power ([equalPowerPanGains]). One value
  /// (I-140-Q3): the mixer takes one per sound.
  final double pan;

  /// The whole row's level over its keyed [volume], a share of the sound
  /// (1 = 100%, up to [maxVolume]) — one value, nothing to key (I-145-Q1).
  final double totalVolume;

  final PropertyTrack<double>? _volume;

  /// The volume's keys, on the row's own frames, each a share of the sound
  /// — 0 silent, 1 as recorded, 2 twice as loud. Empty plays it as recorded.
  PropertyTrack<double> get volume => _volume ?? PropertyTrack<double>.empty();

  /// The loudest a row is set to — the speaker's mixer fader's top, kept.
  static const double maxVolume = 2.0;

  /// The volume at [time], a frame or between two — what the lane's value
  /// reads, the graph draws and the mix plays, one reading.
  double volumeAt(double time) => volume
      .resolveAtTime(time: time, orElse: () => 1.0, space: doubleKeySpace)
      .clamp(0.0, maxVolume);

  /// Whether the volume changes over time — keyed at all.
  bool get isKeyed => volume.isNotEmpty;

  SeSound copyWith({
    double? pan,
    double? totalVolume,
    PropertyTrack<double>? volume,
  }) => SeSound(
    pan: pan ?? this.pan,
    totalVolume: totalVolume ?? this.totalVolume,
    volume: volume ?? _volume,
  );

  Map<String, dynamic> toJson() => {
    if (pan != 0.0) 'pan': pan,
    if (totalVolume != 1.0) 'totalVolume': totalVolume,
    if (isKeyed) 'volume': volume.toJson((v) => v),
  };

  factory SeSound.fromJson(Map<String, dynamic> json) => SeSound(
    pan: (json['pan'] as num?)?.toDouble() ?? 0.0,
    totalVolume: ((json['totalVolume'] as num?)?.toDouble() ?? 1.0)
        .clamp(0.0, maxVolume),
    volume: json['volume'] is List
        ? PropertyTrack.fromJson(
            json['volume'] as List?,
            (v) => (v! as num).toDouble(),
          )
        : null,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SeSound &&
          other.pan == pan &&
          other.totalVolume == totalVolume &&
          other.volume == volume;

  @override
  int get hashCode => Object.hash(pan, totalVolume, volume);
}
