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

/// THE STORYBOARD CURSOR'S DELETE IS MEASURED.
///
/// `deleteBlockAtStoryboardCursor` removes whatever block the storyboard
/// cursor stands on — an SE block, a cut block, a panel, a transition span.
/// When the storyboard cursor was carved out of the session as
/// `_StoryboardCursor` (2026-09-02), the adversarial check made the verb
/// return before doing anything and 437 tests stayed green: `can…` had a
/// test (a_global_row_needs_no_cut, H11) and the verb itself had none. So
/// the verb is asked here, on the same fixture, for the answer the model
/// gives — the block is gone.
void main() {
  const trackId = TrackId('sc-track');
  const seLayerId = LayerId('sc-se');

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

  /// cut-1 covers [0,8); a gap at [8,12); cut-2 covers [12,18). The S row
  /// carries one sound at [2,5).
  EditorSessionManager session() {
    final manager = EditorSessionManager(
      initialProject: Project(
        id: const ProjectId('sc'),
        name: 'SC',
        createdAt: DateTime.utc(2026, 9, 2),
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

  EditorSessionManager standingOnSeAt(int globalFrame) {
    final s = session();
    s.selectRow(const LayerRowAddress(seLayerId));
    s.selectGlobalFrame(globalFrame);
    return s;
  }

  test('the fixture: standing inside the sound, the cursor holds a block', () {
    final s = standingOnSeAt(3);
    expect(s.trackSeGlobalLayerById(seLayerId)!.timeline.keys, [2]);
    expect(s.storyboardCursor.canDeleteBlockAtStoryboardCursor, isTrue);
  });

  test('deleting the SE block under the cursor removes it from the row', () {
    final s = standingOnSeAt(3);
    s.storyboardCursor.deleteBlockAtStoryboardCursor();
    expect(
      s.trackSeGlobalLayerById(seLayerId)!.timeline.keys,
      isEmpty,
      reason: 'the sound at [2,5) was the block under the cursor',
    );
    expect(
      s.storyboardCursor.canDeleteBlockAtStoryboardCursor,
      isFalse,
      reason: 'nothing stands under the cursor now',
    );
  });

  test('a block the cursor authored in the gap deletes the same way', () {
    final s = standingOnSeAt(10);
    s.storyboardCursor.createSeEntryAtStoryboardCursor();
    expect(s.trackSeGlobalLayerById(seLayerId)!.timeline.keys, [2, 10]);
    expect(s.storyboardCursor.canDeleteBlockAtStoryboardCursor, isTrue, reason: 'H11 — lit');
    s.storyboardCursor.deleteBlockAtStoryboardCursor();
    expect(
      s.trackSeGlobalLayerById(seLayerId)!.timeline.keys,
      [2],
      reason: 'H11 — 「각 행들은 독립적인 글로벌행이라 뭐든 가능해야함」: the '
          'gate lit the verb, so the verb acts; a gap is not a reason. The '
          'verb used to keep a fourth copy of the retired sentence 「a parked '
          'playhead has no cut to lens through」 and returned without deleting',
    );
  });

  test('a block inside a cut that does not start at 0 deletes the same way',
      () {
    // cut-2 covers [12,18): global 14 is cut-local 2 — the lens is 12, and
    // a global row must not be read through it twice.
    final s = standingOnSeAt(14);
    s.storyboardCursor.createSeEntryAtStoryboardCursor();
    expect(s.trackSeGlobalLayerById(seLayerId)!.timeline.keys, [2, 14]);
    s.storyboardCursor.deleteBlockAtStoryboardCursor();
    expect(
      s.trackSeGlobalLayerById(seLayerId)!.timeline.keys,
      [2],
      reason: 'the block under the cursor is the one at global 14',
    );
  });
}
