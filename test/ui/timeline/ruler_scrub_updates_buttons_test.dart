import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';

/// 🚨★★★ 유저 #6 (2026-08-14): 「룰러로 이동할때, **블록이 있으면 사용가능**
/// 타임라인버튼 활성화되는식으로 버튼 상태 바꼈으면 좋겠는데 안바뀜.
/// **효율좋게** 하는데 바뀌게 하고싶음. 갱신을 매 룰러 드래그마다가 아니라
/// **해당 인덱스에 버튼이 있으면 한번, 없으면 한번** 이런식으로?」
///
/// ★Both halves are the contract, and the second is the harder one: a scrub
/// raises no session notify on purpose (that is what keeps a ruler drag
/// cheap), so nothing re-asks unless something says the playhead moved.
///
/// ## 🚨 #10 (2026-08-21) — the first answer was a PROXY, and it was wrong
///
/// This file used to pin `playheadHasCel`: one boolean standing in for a
/// whole toolbar, on the argument that the buttons 「거의 다 “플레이헤드
/// 밑에 셀이 있나”로 환원된다」. Measured, it failed twice over —
///
///  * it was synced ONLY from [EditorSessionManager.scrubFrameIndex], so a
///    committed seek left it holding the previous drag's answer. At a frame
///    that HAS a cel it read false, and the next drag's first crossing
///    could not flip it;
///  * one boolean cannot carry twenty-five buttons: a scrub from a drawn
///    frame to an empty one moves NINE of them.
///
/// The proxy is retired. [EditorSessionManager.playheadMoved] says only
/// what it knows — the playhead moved — and every subscriber re-derives its
/// OWN answer, rebuilding only if that answer changed. The efficiency half
/// survives exactly, and this file pins it where it now lives: the ANSWER
/// changes twice across a drag that crosses one block, not twenty times.
void main() {
  EditorSessionManager session() {
    final manager = EditorSessionManager(
      initialProject: Project(
        id: const ProjectId('p'),
        name: 'P',
        createdAt: DateTime.utc(2026, 8, 14),
        tracks: [
          Track(
            id: const TrackId('default-track'),
            name: 'Track',
            cuts: [
              Cut(
                id: const CutId('cut-a'),
                name: 'A',
                duration: 24,
                canvasSize: const CanvasSize(width: 64, height: 64),
                layers: [
                  Layer(
                    id: const LayerId('draw'),
                    name: 'A',
                    frames: [
                      Frame(
                        id: const FrameId('cel'),
                        duration: 4,
                        strokes: const [],
                      ),
                    ],
                    // A block over frames 10..13 and nothing anywhere else,
                    // so a drag from 0 crosses exactly two boundaries.
                    timeline: {
                      10: const TimelineExposure.drawing(
                        FrameId('cel'),
                        length: 4,
                      ),
                    },
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
    addTearDown(manager.dispose);
    manager.selectLayer(const LayerId('draw'));
    return manager;
  }

  /// What the bar's frame and shared buttons actually read — the toolbar's
  /// own token, restated here so this file pins the ANSWER rather than a
  /// stand-in for it. A new directly-rendered gate belongs in both places.
  Object gates(EditorSessionManager s) => (
    s.selectedFrame != null,
    s.canCreateDrawingAtCurrentFrame,
    s.canRenameFrameAtCurrentFrame,
    s.canBlankExposureAtCurrentFrame,
    s.canToggleMarkAtCurrentFrame,
    s.canCopyFrameAtCurrentFrame,
    s.canPasteLinkedFrameAtCurrentFrame,
    s.canCutRunAtCurrentFrame,
    s.canPasteIndependentFrameAtCurrentFrame,
    s.canEditCellInstanceAtCurrentFrame,
    s.canDeleteCellAtCurrentFrame,
    s.canDecreaseSelectedExposure,
    s.canIncreaseSelectedExposure,
    s.canSetCommaForSelectionOrCurrent,
  );

  test('the playhead SAYS it moved on a scrub, not only on the release', () {
    final manager = session();
    var ticks = 0;
    manager.playheadMoved.addListener(() => ticks += 1);

    manager.scrubFrameIndex(5);
    expect(
      ticks,
      greaterThan(0),
      reason:
          'a committed seek fires on the RELEASE — a bar that heard only '
          'that one was stale for the whole drag',
    );

    final duringDrag = ticks;
    manager.selectFrameIndex(5);
    expect(
      ticks,
      greaterThan(duringDrag),
      reason:
          'and the commit still speaks: a same-frame commit after a scrub '
          'must still reach the surfaces that take committed state only',
    );
  });

  test('the ANSWER flips as the ruler crosses the block', () {
    final manager = session();
    manager.scrubFrameIndex(0);
    final outside = gates(manager);

    manager.scrubFrameIndex(11);
    expect(
      gates(manager),
      isNot(outside),
      reason: 'the toolbar had no way to learn this during a drag',
    );

    manager.scrubFrameIndex(20);
    expect(gates(manager), outside, reason: 'and back out is back to before');
  });

  test('⛔and it changes ONCE per crossing, not once per frame', () {
    final manager = session();
    manager.scrubFrameIndex(0);

    final changedAt = <int>[];
    var previous = gates(manager);

    // A twenty-frame drag over one block: in at 10, out at 14.
    for (var frame = 1; frame <= 20; frame += 1) {
      manager.scrubFrameIndex(frame);
      final next = gates(manager);
      if (next != previous) {
        changedAt.add(frame);
        previous = next;
      }
    }

    expect(
      changedAt,
      [10, 11, 14],
      reason:
          'the subscribers derive on every move and REBUILD only on these — '
          'a rebuild per crossed frame would put back the cost the design '
          'avoids (「있으면 한번, 없으면 한번」). THREE, not two, and the '
          'third one is the honest part: the proxy this replaced was a '
          'boolean that could not see it. 10 enters the block, 11 leaves '
          'its START (a run head answers differently from the frames it '
          'holds — renaming, for one), 14 leaves the block',
    );
  });
}
