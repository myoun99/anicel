import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/models/timeline_row_address.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';

/// 🚨H11 (유저 2026-08-22) — **A TRACK-OWNED ROW IS NOT A CUT'S TENANT.**
///
/// > 「스토리보드패널, **S행이 컷이 없는 갭에서 프레임추가가 안됨.
/// > 버튼활성안됨.** 다시말하지만 각 행들은 **독립적인 글로벌행**이라 뭐든
/// > 가능해야함」
///
/// Three separate gates carried the same sentence — "a parked playhead has
/// no cut to lens through" — and all three were standing in for ONE lookup:
/// `TimelineController._requireLayer` asked for the cut FIRST and threw
/// without one, so its own track-SE fallback was unreachable in a gap.
///
/// The lens a track row asks for is `activeCutGlobalStartFrame`, which is 0
/// with no cut — the identity. So the gap never had any bearing on the
/// answer; it only had bearing on whether the row could be FOUND.
///
/// ⚠️There was no test on any of this, which is how it stayed put.
void main() {
  const trackId = TrackId('h11-track');
  const seLayerId = LayerId('h11-se');

  Cut cut(String id, int duration, {int leadingGap = 0}) => Cut(
    id: CutId(id),
    name: id,
    duration: duration,
    leadingGapFrames: leadingGap,
    canvasSize: const CanvasSize(width: 320, height: 180),
    layers: [
      Layer(id: LayerId('$id-cel'), name: 'A', frames: const [], timeline: {}),
    ],
  );

  /// cut-1 covers [0,8); a FOUR-FRAME GAP at [8,12); cut-2 covers [12,18).
  /// The S row carries one sound at [2,5) and nothing in the gap.
  EditorSessionManager session() {
    final manager = EditorSessionManager(
      initialProject: Project(
        id: const ProjectId('h11'),
        name: 'H11',
        createdAt: DateTime.utc(2026, 8, 22),
        tracks: [
          Track(
            id: trackId,
            name: 'Video',
            cuts: [cut('cut-1', 8), cut('cut-2', 6, leadingGap: 4)],
            seLayers: [
              Layer(
                id: seLayerId,
                name: 'S1',
                kind: LayerKind.se,
                frames: [
                  Frame(
                    id: const FrameId('se-one'),
                    duration: 3,
                    name: 'One!',
                    strokes: const [],
                  ),
                ],
                timeline: const {
                  2: TimelineExposure.drawing(FrameId('se-one'), length: 3),
                },
              ),
            ],
          ),
        ],
      ),
    );
    addTearDown(manager.dispose);
    return manager;
  }

  /// Stand on the S row at [globalFrame], the way a press on it does.
  EditorSessionManager standingAt(int globalFrame) {
    final s = session();
    s.selectRow(const LayerRowAddress(seLayerId));
    s.selectGlobalFrame(globalFrame);
    return s;
  }

  test('frame 10 really is a gap — the fixture proves the premise', () {
    final s = standingAt(10);
    expect(s.editingPlayheadInGap, isTrue);
    expect(
      s.activeCutOrNull,
      isNull,
      reason: 'parking in a gap leaves the cut, which is the whole setup',
    );
  });

  test('the ＋ is LIVE on an S row parked in a gap', () {
    expect(
      standingAt(10).canCreateSeEntryAtStoryboardCursor,
      isTrue,
      reason: '「각 행들은 독립적인 글로벌행이라 뭐든 가능해야함」',
    );
  });

  test('and it authors the entry at the GLOBAL frame, unshifted', () {
    final s = standingAt(10);
    s.createSeEntryAtStoryboardCursor();

    final row = s.trackSeGlobalLayerById(seLayerId);
    expect(row, isNotNull);
    expect(
      row!.timeline.keys,
      [2, 10],
      reason: 'the lens a track row asks for is the active cut\'s global '
          'start, which is 0 with no cut — so the global frame IS the key',
    );
    expect(row.timeline[10]!.length, 1);
  });

  test('inside a cut it still lands on the global frame — the lens is the '
      'same sentence, not a second one', () {
    final s = standingAt(14); // cut-2 covers [12,18): local 2, global 14.
    expect(s.activeCutOrNull, isNotNull, reason: 'not a gap this time');
    expect(s.canCreateSeEntryAtStoryboardCursor, isTrue);
    s.createSeEntryAtStoryboardCursor();

    expect(s.trackSeGlobalLayerById(seLayerId)!.timeline.keys, [2, 14]);
  });

  test('an occupied frame still refuses, gap or not', () {
    final s = session();
    s.selectRow(const LayerRowAddress(seLayerId));
    s.selectGlobalFrame(3); // inside the existing [2,5) sound.
    expect(
      s.canCreateSeEntryAtStoryboardCursor,
      isFalse,
      reason: 'the EMPTY-cursor half of the gate is untouched',
    );
  });

  test('delete answers in the gap too — the same law, said once', () {
    final s = standingAt(10);
    s.createSeEntryAtStoryboardCursor();
    expect(
      s.canDeleteBlockAtStoryboardCursor,
      isTrue,
      reason: 'the cursor now stands on a block it authored; a gap is not a '
          'reason it cannot be removed',
    );
  });
}
