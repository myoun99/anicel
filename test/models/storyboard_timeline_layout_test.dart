import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/models/storyboard_timeline_layout.dart';

void main() {
  test('cutGlobalStartFrameIn reads the same walk the layout makes', () {
    // The session manager kept a second copy of this walk until 2026-09-03;
    // one loop now, and this pin says the two askers agree by construction.
    final track = Track(
      id: const TrackId('track-a'),
      name: 'Track A',
      cuts: [
        _cut('cut-a', duration: 24, leadingGap: 3),
        _cut('cut-b', duration: 12),
        _cut('cut-c', duration: 36, leadingGap: 5),
      ],
    );
    final layout = buildStoryboardTimelineLayout(_project([track]));
    expect(layout, hasLength(3));
    for (final entry in layout) {
      expect(
        cutGlobalStartFrameIn(track, entry.cutId),
        entry.startFrame,
        reason: '${entry.cutId}',
      );
    }
    expect(cutGlobalStartFrameIn(track, const CutId('zz')), isNull);
    expect(cutGlobalStartFrameIn(track, null), isNull);
  });
  test('single track with one cut starts at zero and ends at duration', () {
    final cut = _cut('cut-a', duration: 24);
    final project = _project([
      Track(id: const TrackId('track-a'), name: 'Track A', cuts: [cut]),
    ]);

    final layout = buildStoryboardTimelineLayout(project);

    expect(layout, hasLength(1));
    expect(layout.single.trackId, const TrackId('track-a'));
    expect(layout.single.cutId, const CutId('cut-a'));
    expect(layout.single.trackIndex, 0);
    expect(layout.single.cutIndex, 0);
    expect(layout.single.startFrame, 0);
    expect(layout.single.endFrame, 24);
    expect(layout.single.duration, 24);
    expect(identical(layout.single.cut, cut), isTrue);
  });

  test('single track with multiple cuts accumulates frame ranges', () {
    final project = _project([
      Track(
        id: const TrackId('track-a'),
        name: 'Track A',
        cuts: [
          _cut('cut-a', duration: 24),
          _cut('cut-b', duration: 12),
          _cut('cut-c', duration: 36),
        ],
      ),
    ]);

    final layout = buildStoryboardTimelineLayout(project);

    expect(layout.map((entry) => entry.cutId.value), [
      'cut-a',
      'cut-b',
      'cut-c',
    ]);
    expect(layout.map((entry) => entry.startFrame), [0, 24, 36]);
    expect(layout.map((entry) => entry.endFrame), [24, 36, 72]);
    expect(layout.map((entry) => entry.duration), [24, 12, 36]);
    expect(layout.map((entry) => entry.cutIndex), [0, 1, 2]);
  });

  test('multiple tracks each calculate independently from zero', () {
    final project = _project([
      Track(
        id: const TrackId('track-a'),
        name: 'Track A',
        cuts: [_cut('cut-a', duration: 24), _cut('cut-b', duration: 12)],
      ),
      Track(
        id: const TrackId('track-b'),
        name: 'Track B',
        cuts: [_cut('cut-x', duration: 36), _cut('cut-y', duration: 6)],
      ),
    ]);

    final layout = buildStoryboardTimelineLayout(project);

    final trackA = layout.where(
      (entry) => entry.trackId == const TrackId('track-a'),
    );
    final trackB = layout.where(
      (entry) => entry.trackId == const TrackId('track-b'),
    );

    expect(trackA.map((entry) => entry.startFrame), [0, 24]);
    expect(trackA.map((entry) => entry.endFrame), [24, 36]);
    expect(trackB.map((entry) => entry.startFrame), [0, 36]);
    expect(trackB.map((entry) => entry.endFrame), [36, 42]);
    expect(trackB.map((entry) => entry.trackIndex), [1, 1]);
  });

  test('leading gaps push cut starts back without breaking accumulation', () {
    final project = _project([
      Track(
        id: const TrackId('track-a'),
        name: 'Track A',
        cuts: [
          _cut('cut-a', duration: 10, leadingGap: 3),
          _cut('cut-b', duration: 5),
          _cut('cut-c', duration: 4, leadingGap: 2),
        ],
      ),
    ]);

    final layout = buildStoryboardTimelineLayout(project);

    // cut-a: 3 empty frames first; cut-b adjacent; cut-c after 2 more.
    expect(layout.map((entry) => entry.startFrame), [3, 13, 20]);
    expect(layout.map((entry) => entry.endFrame), [13, 18, 24]);
  });

  test('zero duration follows cut duration without inventing extra rules', () {
    final project = _project([
      Track(
        id: const TrackId('track-a'),
        name: 'Track A',
        cuts: [_cut('cut-a', duration: 0), _cut('cut-b', duration: 12)],
      ),
    ]);

    final layout = buildStoryboardTimelineLayout(project);

    expect(layout.map((entry) => entry.startFrame), [0, 0]);
    expect(layout.map((entry) => entry.endFrame), [0, 12]);
    expect(layout.map((entry) => entry.duration), [0, 12]);
  });

  test('building layout does not mutate project', () {
    final project = _project([
      Track(
        id: const TrackId('track-a'),
        name: 'Track A',
        cuts: [_cut('cut-a', duration: 24), _cut('cut-b', duration: 12)],
      ),
    ]);
    final beforeJson = project.toJson().toString();

    buildStoryboardTimelineLayout(project);

    expect(project.toJson().toString(), beforeJson);
  });

  test('a bare cut LIST walks the same axis as a track', () {
    final cuts = [
      _cut('cut-a', duration: 24, leadingGap: 3),
      _cut('cut-b', duration: 12),
      _cut('cut-c', duration: 8, leadingGap: 5),
    ];
    final track = Track(id: const TrackId('t'), name: 'T', cuts: cuts);

    expect(
      cutSpansOfCuts(cuts).map((placed) => placed.startFrame).toList(),
      cutSpansOf(track).map((placed) => placed.startFrame).toList(),
    );
    expect(
      cutSpansOfCuts(cuts).map((placed) => placed.startFrame).toList(),
      [3, 27, 44],
      reason: 'a cut begins AFTER its own leading gap',
    );
  });

  /// 🚨THE AXIS IS WALKED IN ONE PLACE.
  ///
  /// Four call sites had re-typed the `start += leadingGap; … start +=
  /// duration` loop — the playback schedule, the export audio plan, the
  /// export dialog's sheet origin and the transition warning — while this
  /// file's own doc said it was THE walk. Each copy was one
  /// `leadingGapFrames` away from putting a sound or a wipe on a
  /// different frame than the one that plays.
  ///
  /// ⛔Noticing the fifth is not a plan: the scan is.
  test('nothing outside this file accumulates the track axis by hand', () {
    final offenders = <String>[];
    final byHand = RegExp(r'\+=[^;]*leadingGapFrames');
    var scanned = 0;

    for (final entry
        in Directory('lib')
            .listSync(recursive: true)
            .whereType<File>()
            .where((file) => file.path.endsWith('.dart'))) {
      final relative = entry.path.replaceAll(r'\', '/');
      final key = relative.substring(relative.indexOf('lib/'));
      // The walk itself, and the ONE deliberate exception: the cut-move
      // drag walks CutMoveSlots rather than Cuts (보류, 3의 규칙) and
      // measures a LANDED extent whose gaps come from the plan rather
      // than from the slot. Both say so at the loop.
      if (key == 'lib/src/models/storyboard_timeline_layout.dart' ||
          key == 'lib/src/ui/session/drags/cut_move_drag.dart') {
        continue;
      }
      scanned += 1;
      final lines = entry.readAsLinesSync();
      for (var i = 0; i < lines.length; i += 1) {
        if (byHand.hasMatch(lines[i])) {
          offenders.add('$key:${i + 1}  ${lines[i].trim()}');
        }
      }
    }

    expect(scanned, greaterThan(500), reason: 'the scan read the real tree');
    expect(
      offenders,
      isEmpty,
      reason:
          'use cutSpansOf / cutSpansOfCuts — a second walk cannot promise '
          'that the storyboard, the SE window and the export agree',
    );
  });
}

Project _project(List<Track> tracks) {
  return Project(
    id: const ProjectId('project-a'),
    name: 'Project A',
    tracks: tracks,
    createdAt: DateTime.utc(2026, 6, 14),
  );
}

Cut _cut(String id, {required int duration, int leadingGap = 0}) {
  return Cut(
    id: CutId(id),
    name: id,
    layers: const [],
    duration: duration,
    leadingGapFrames: leadingGap,
    canvasSize: const CanvasSize(width: 1280, height: 720),
  );
}
