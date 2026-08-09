import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/property_track.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/models/transform_track.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';

/// UI-R5 ③b — the SE row's lane span lives on the TRACK's global axis.
///
/// User, 2026-08-09: **"글로벌 트랙이 메인이고 컷 타임라인 내부에서는 그걸
/// 알기 쉽게 보여주기만 할 뿐"** — so the span is stated globally, the verbs
/// reach every key it covers (cuts the panel is not showing included), the
/// cut panel shows the overlapping part on its own numbers, and switching
/// cuts moves the window rather than the selection.
void main() {
  const trackId = TrackId('t');
  const seId = LayerId('se-1');

  Cut cut(String id, int duration) => Cut(
    id: CutId(id),
    name: id,
    duration: duration,
    canvasSize: const CanvasSize(width: 100, height: 100),
    layers: [
      Layer(
        id: LayerId('$id-cel'),
        name: 'A',
        frames: const [],
        timeline: const {},
      ),
    ],
  );

  /// Cut 1 is frames 0..10, cut 2 is 10..20. The SE row carries a Position
  /// key in EACH cut — 4 (inside cut 1) and 14 (inside cut 2) — so a span
  /// that crosses the boundary has something to reach on both sides.
  EditorSessionManager session() {
    final manager = EditorSessionManager(
      initialProject: Project(
        id: const ProjectId('p'),
        name: 'p',
        createdAt: DateTime.utc(2026, 8, 9),
        tracks: [
          Track(
            id: trackId,
            name: 'V',
            cuts: [cut('cut-1', 10), cut('cut-2', 10)],
            seLayers: [
              Layer(
                id: seId,
                name: 'S1',
                kind: LayerKind.se,
                frames: const [],
                timeline: const {},
                transformTrack: TransformTrack.empty().copyWith(
                  position: PropertyTrack<CanvasPoint>.empty()
                      .withKey(4, CanvasPoint(x: 1, y: 1))
                      .withKey(14, CanvasPoint(x: 2, y: 2)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
    addTearDown(manager.dispose);
    return manager;
  }

  List<int> positionKeysOf(EditorSessionManager manager) => manager
      .activeTrack
      .seLayers
      .firstWhere((layer) => layer.id == seId)
      .transformTrack
      .position
      .keys
      .keys
      .toList();

  test('a span the storyboard states in GLOBAL frames deletes the keys it '
      'covers, in cuts the open panel is not showing', () {
    final manager = session();
    expect(positionKeysOf(manager), [4, 14]);

    // The storyboard rail IS the global axis, so it says so.
    manager.updateLaneRangeSelectionDrag(
      layerId: seId,
      laneId: 'position',
      anchorIndex: 0,
      headIndex: 19,
      framesAreGlobal: true,
    );
    expect(manager.laneRangeSelection.value!.startIndex, 0);
    expect(manager.laneRangeSelection.value!.endIndexExclusive, 20);

    manager.deleteCellAtCurrentFrame();

    expect(
      positionKeysOf(manager),
      isEmpty,
      reason:
          'the span covers both cuts, and the verb follows the span — the '
          'key at 14 is not in the open cut and dies all the same',
    );
  });

  test('the SAME drag from a CUT panel lands on the global axis', () {
    final manager = session();
    // Open the second cut: its window starts at global 10.
    manager.selectCut(manager.activeTrack.cuts[1].id);

    // The cut panel counts from its own edge: local 3..5 = global 13..15.
    manager.updateLaneRangeSelectionDrag(
      layerId: seId,
      laneId: 'position',
      anchorIndex: 3,
      headIndex: 5,
    );

    final span = manager.laneRangeSelection.value!;
    expect(
      [span.startIndex, span.endIndexExclusive],
      [13, 16],
      reason: 'the window offset is added on the way in',
    );

    manager.deleteCellAtCurrentFrame();
    expect(
      positionKeysOf(manager),
      [4],
      reason: 'only the key the span really covers (14) is gone',
    );
  });

  test('the cut panel shows the OVERLAP, on its own numbers, and switching '
      'cuts moves the window instead of the selection', () {
    final manager = session();

    // A span across both cuts, stated globally.
    manager.updateLaneRangeSelectionDrag(
      layerId: seId,
      laneId: 'position',
      anchorIndex: 6,
      headIndex: 15,
      framesAreGlobal: true,
    );

    // Cut 1 is open: it sees 6..10 as 6..10 of its own.
    final inFirst = manager.cutLocalLaneRangeSelection.value!;
    expect([inFirst.startIndex, inFirst.endIndexExclusive], [6, 10]);

    manager.selectCut(manager.activeTrack.cuts[1].id);
    final inSecond = manager.cutLocalLaneRangeSelection.value!;
    expect(
      [inSecond.startIndex, inSecond.endIndexExclusive],
      [0, 6],
      reason: 'global 10..16 is 0..6 of the second cut',
    );
    expect(
      manager.laneRangeSelection.value!.startIndex,
      6,
      reason: 'the selection itself never moved — only the window did',
    );
  });

  test(
    'a cut with no overlap shows no band, and the selection survives it',
    () {
      final manager = session();
      manager.updateLaneRangeSelectionDrag(
        layerId: seId,
        laneId: 'position',
        anchorIndex: 12,
        headIndex: 15,
        framesAreGlobal: true,
      );
      // Cut 1 (0..10) cannot see 12..16 at all.
      expect(manager.cutLocalLaneRangeSelection.value, isNull);
      expect(manager.laneRangeSelection.value, isNotNull);

      manager.selectCut(manager.activeTrack.cuts[1].id);
      final inSecond = manager.cutLocalLaneRangeSelection.value!;
      expect([inSecond.startIndex, inSecond.endIndexExclusive], [2, 6]);
    },
  );
}
