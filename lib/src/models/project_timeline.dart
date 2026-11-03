import 'dart:math' show max;

import '../core/collection_equality.dart';
import 'timeline_id.dart';
import 'track.dart';

/// The timeline a project is made with.
const firstProjectTimelineId = TimelineId('timeline-1');

/// The number a timeline made now takes — a new one or a copy: after the
/// last of [timelines].
int timelineNumberAfter(List<ProjectTimeline> timelines) =>
    timelines.map((timeline) => timeline.number).reduce(max) + 1;

/// One TIMELINE of a project: its tracks — the cuts, the SE rows, the
/// transition row — and its trailing gap. Everything else the project holds
/// is the work's, and every timeline shares it: the media pool, the work
/// settings, the camera glossary, the link registry, the fonts, the stage.
///
/// 🗣️I-150 (유저 2026-11-03): 「새로운 타임라인을 만들수있음」 · 「새 트랙은
/// 타임라인이 완전초기화되있음. 새 프로젝트를 만드는것과 동일하게. 다만
/// 차이점은 미디어풀을 공용할수있다던가」 · 「트랙바꾸면 타임라인 완전
/// 바꿔치기됨. se던 뭐던 싹 다」. The user called it 「트랙」 for the
/// telling and left the name to us (「추천하는대로 만들어도됨」): 「트랙」
/// already names the V track ([Track]), the SE tracks and the track FX,
/// and the panel that shows one of these is the timeline panel — so it is
/// a TIMELINE, as Clip Studio names the same thing (タイムライン).
class ProjectTimeline {
  ProjectTimeline({
    required this.id,
    required this.number,
    this.name,
    required List<Track> tracks,
    int trailingFrames = 0,
  }) : tracks = List.unmodifiable(tracks),
       trailingFrames = trailingFrames < 0 ? 0 : trailingFrames;

  final TimelineId id;

  /// The count it was made at — 「타임라인 N」 until it is named.
  final int number;

  /// What it was named, or null for the name its [number] gives.
  final String? name;

  final List<Track> tracks;

  /// The movie's TRAILING GAP (UI-R20 #3): extra frames past the last
  /// cut's end — the storyboard end line drags THIS, so the final length
  /// is authored independently of the cuts (gaps are first-class on this
  /// timeline, the tail included). The movie end = the cuts' content end
  /// + this.
  final int trailingFrames;

  ProjectTimeline copyWith({List<Track>? tracks, int? trailingFrames}) =>
      ProjectTimeline(
        id: id,
        number: number,
        name: name,
        tracks: tracks ?? this.tracks,
        trailingFrames: trailingFrames ?? this.trailingFrames,
      );

  /// This timeline named [name] — null gives it back the one its [number]
  /// gives.
  ProjectTimeline named(String? name) => ProjectTimeline(
    id: id,
    number: number,
    name: name,
    tracks: tracks,
    trailingFrames: trailingFrames,
  );

  Map<String, dynamic> toJson() => {
    'id': id.toJson(),
    'number': number,
    if (name != null) 'name': name,
    'tracks': [for (final track in tracks) track.toJson()],
    if (trailingFrames != 0) 'trailingFrames': trailingFrames,
  };

  factory ProjectTimeline.fromJson(Map<String, dynamic> json) =>
      ProjectTimeline(
        id: TimelineId.fromJson(json['id'] as Map<String, dynamic>),
        number: json['number'] as int,
        name: json['name'] as String?,
        tracks: [
          for (final track in json['tracks'] as List<dynamic>)
            Track.fromJson(track as Map<String, dynamic>),
        ],
        trailingFrames: (json['trailingFrames'] as int?) ?? 0,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ProjectTimeline &&
          other.id == id &&
          other.number == number &&
          other.name == name &&
          listEquals(other.tracks, tracks) &&
          other.trailingFrames == trailingFrames;

  @override
  int get hashCode =>
      Object.hash(id, number, name, Object.hashAll(tracks), trailingFrames);
}
