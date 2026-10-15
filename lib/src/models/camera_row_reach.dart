import 'dart:math' as math;

import 'storyboard_timeline_layout.dart';
import 'transition_geometry.dart';

/// Which of the camera row's lines a frame of a cut is drawn on.
///
/// 🗣️유저 2026-10-08 (I-73 ④): 「카메라행은 ol떄 2줄로 만드는거 ok」 — where
/// two cuts' own frames run at once (an O.L), the row splits in two: the
/// cut LEAVING on the upper line, the cut ARRIVING on the lower; everywhere
/// else a cut is drawn on the one line in the middle.
enum CameraRowLine { middle, upper, lower }

/// ONE CUT'S REACH ON ITS TRACK'S CAMERA ROW: the track frames its own
/// frames are drawn on, and the stretches of them it shares with the cut
/// before it and the cut after it.
///
/// A cut's own frame 0 is its MEDIA START — its place on the track less the
/// のりしろ an O.L arriving into it asks (`TrackFrameAxis`, F-227) — and it
/// is drawn through its place and the のりしろ an O.L leaving it asks after:
/// `[mediaStart, mediaEnd)`. Its camera's keys count from [mediaStart], and
/// a key outside the reach is not drawn.
class CameraRowReach {
  const CameraRowReach({
    required this.entry,
    required this.mediaStart,
    required this.mediaEnd,
    required this.arrivingUntil,
    required this.leavingFrom,
  });

  /// The cut, as the layout placed it.
  final StoryboardTimelineLayoutEntry entry;

  /// The track frame the cut's own frame 0 is drawn at.
  final int mediaStart;

  /// The track frame past the cut's last own frame.
  final int mediaEnd;

  /// Where the stretch this cut shares with the cut BEFORE it ends — it
  /// runs from [mediaStart]; [mediaStart] itself when they share none. This
  /// cut is the ARRIVING one there, drawn on the lower line.
  final int arrivingUntil;

  /// Where the stretch this cut shares with the cut AFTER it begins — it
  /// runs to [mediaEnd]; [mediaEnd] itself when they share none. This cut is
  /// the LEAVING one there, drawn on the upper line.
  final int leavingFrom;

  /// The same cut laid alike ([StoryboardTimelineLayoutEntry.==]) over the
  /// same frames — what the camera row is kept while (I-57, 10-14).
  @override
  bool operator ==(Object other) =>
      other is CameraRowReach &&
      other.entry == entry &&
      other.mediaStart == mediaStart &&
      other.mediaEnd == mediaEnd &&
      other.arrivingUntil == arrivingUntil &&
      other.leavingFrom == leavingFrom;

  @override
  int get hashCode =>
      Object.hash(entry, mediaStart, mediaEnd, arrivingUntil, leavingFrom);

  /// Whether [trackFrame] is one of the cut's own frames.
  bool reaches(int trackFrame) =>
      trackFrame >= mediaStart && trackFrame < mediaEnd;

  /// The line the cut is drawn on at [trackFrame] — one of its own frames.
  CameraRowLine lineAt(int trackFrame) => trackFrame < arrivingUntil
      ? CameraRowLine.lower
      : trackFrame >= leavingFrom
      ? CameraRowLine.upper
      : CameraRowLine.middle;

  /// The track frame the cut's own [frame] is drawn at.
  int trackFrameOf(int frame) => mediaStart + frame;

  /// [trackFrame] as a frame of the cut's own — held to them: a frame past
  /// either end names that end, so a sweep that runs on into the next cut
  /// stops at this one's last frame (「컷 클램핑만 되도록」, 유저
  /// 2026-10-08), as the conte's does at its last panel.
  int ownFrameAt(int trackFrame) =>
      math.max(mediaStart, math.min(trackFrame, mediaEnd - 1)) - mediaStart;

  /// The cut's own frames from [start] to [endExclusive] on the track, held
  /// inside them, a stretch for each line they are drawn on — what a band
  /// over them lays down, a piece a line. Empty where none of them are the
  /// cut's: a selection the timeline made past the cut's end names frames
  /// the row does not draw.
  List<CameraRowStretch> stretchesOf(int start, int endExclusive) {
    final from = trackFrameOf(math.max(0, start));
    final to = math.min(mediaEnd, trackFrameOf(endExclusive));
    if (to <= from) {
      return const [];
    }
    final edges = {
      from,
      for (final edge in [arrivingUntil, leavingFrom])
        if (edge > from && edge < to) edge,
      to,
    }.toList()..sort();
    return [
      for (var index = 0; index + 1 < edges.length; index += 1)
        (
          from: edges[index],
          to: edges[index + 1],
          line: lineAt(edges[index]),
        ),
    ];
  }
}

/// A run of track frames `[from, to)` of one cut's own, drawn on one [line]
/// ([CameraRowReach.stretchesOf]).
typedef CameraRowStretch = ({int from, int to, CameraRowLine line});

/// Every cut of [entries] — ONE track's, in its order — with its reach on
/// the camera row: its own frames under the のりしろ [spans] (the track's
/// transitions) ask of it ([cutTransitionHandles], the answer every reader
/// of a cut's drawn frames takes), and the stretches two neighbours share.
List<CameraRowReach> cameraRowReachesOf(
  List<StoryboardTimelineLayoutEntry> entries,
  Iterable<TransitionSpan> spans,
) {
  final own = [
    for (final entry in entries)
      () {
        final handles = cutTransitionHandles(
          cutStart: entry.startFrame,
          cutEnd: entry.endFrame,
          spans: spans,
        );
        return (
          start: entry.startFrame - handles.head,
          end: entry.endFrame + handles.tail,
        );
      }(),
  ];
  // Two neighbours' own frames never run past each other: a span reaching
  // past a cut's far end owes that cut a のりしろ as long
  // ([cutTransitionHandles]), so the stretch they share ends where the one
  // before ends and begins where the one after begins.
  return [
    for (var index = 0; index < entries.length; index += 1)
      CameraRowReach(
        entry: entries[index],
        mediaStart: own[index].start,
        mediaEnd: own[index].end,
        arrivingUntil: index == 0
            ? own[index].start
            : math.max(own[index].start, own[index - 1].end),
        leavingFrom: index == entries.length - 1
            ? own[index].end
            : math.min(own[index].end, own[index + 1].start),
      ),
  ];
}
