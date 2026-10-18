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
import '../../helpers/library_source.dart';

/// F-5 · C3-lane-move — **A LANE ROW IS A ROW.**
///
/// The band drew across an fx row, said "these frames are selected", and then
/// the press that should have MOVED them quietly re-selected instead. Three
/// separate sites each spelled the same invented rule as
/// `row is LayerRowAddress`, and each meant something slightly different by
/// it: the move machine's span came out null, the grid did not recognise the
/// pressed row as inside its own selection, and the span dropped the lane rows
/// on the way through.
///
/// ⛔The rule was never asked for. [LaneRowAddress]'s own doc says a lane falls
/// back to its layer rather than refusing, and the user's line is older than
/// all three sites: 「선택범위는 어떤 레이어를 건너든 자유롭게, 규칙 두지 말 것」.
///
/// ★The fix is one accessor — [TimelineRowAddress.owningLayerId] — so that
/// "which layer is this row's" has ONE answer instead of three hand-written
/// switches that can drift apart again.
const _trackId = TrackId('lane-track');
const _se1 = LayerId('lane-se-1');
const _se2 = LayerId('lane-se-2');

Project _project() => Project(
  id: const ProjectId('lane-project'),
  name: 'Lane',
  createdAt: DateTime.utc(2026, 8, 25),
  tracks: [
    Track(
      id: _trackId,
      name: 'V',
      cuts: [
        Cut(
          id: const CutId('c1'),
          name: '1',
          duration: 12,
          canvasSize: const CanvasSize(width: 32, height: 32),
          layers: [
            Layer(
              id: const LayerId('cel'),
              name: 'A',
              frames: const [],
              timeline: const {},
            ),
          ],
        ),
      ],
      seLayers: [
        Layer(
          id: _se1,
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
        Layer(
          id: _se2,
          name: 'S2',
          kind: LayerKind.se,
          frames: [
            Frame(
              id: const FrameId('se-two'),
              duration: 3,
              name: 'Two!',
              strokes: const [],
            ),
          ],
          timeline: const {
            2: TimelineExposure.drawing(FrameId('se-two'), length: 3),
          },
        ),
      ],
    ),
  ],
);

void main() {
  EditorSessionManager sessionFor() {
    final session = EditorSessionManager(initialProject: _project());
    addTearDown(session.dispose);
    return session;
  }

  void selectLaneAnchoredBand(EditorSessionManager session) {
    session.updateTrackRowRangeSelectionByFrame(
      layerId: _se1,
      anchorGlobalFrame: 2,
      headGlobalFrame: 4,
      anchorRow: const LaneRowAddress(_se1, 'position'),
      spanRows: const [LaneRowAddress(_se1, 'position'), LayerRowAddress(_se2)],
    );
  }

  group('the address answers WHICH LAYER it belongs to', () {
    test('a layer row, a lane row of that layer, and a cut row', () {
      expect(const LayerRowAddress(_se1).owningLayerId, _se1);
      expect(
        const LaneRowAddress(_se1, 'position').owningLayerId,
        _se1,
        reason:
            'a lane is INSIDE its layer — standing on a property must '
            'never cost you the layer',
      );
      expect(
        const TrackRowAddress(_trackId).owningLayerId,
        isNull,
        reason: 'a cut row belongs to no layer: its blocks are cuts',
      );
    });

    // F-87 (유저 2026-10-18): 「fx를 넘어서 뭐든 선택된 대상으로」 — what a
    // SELECTION holds on a row is the other question, and a lane's answer
    // to it is never its layer.
    test('and whose BLOCKS it holds: a lane holds none', () {
      expect(const LayerRowAddress(_se1).blockLayerId, _se1);
      expect(
        const LaneRowAddress(_se1, 'position').blockLayerId,
        isNull,
        reason: 'a lane holds keys — its layer\'s sounds are its layer '
            'row\'s',
      );
      expect(const TrackRowAddress(_trackId).blockLayerId, isNull);
    });
  });

  group('a band anchored on a LANE row still moves', () {
    test('the move drag begins — it used to fall through to a re-select', () {
      final session = sessionFor();
      selectLaneAnchoredBand(session);
      expect(
        session.trackFrameRangeSelection.value,
        isNotNull,
        reason: 'the band is drawn — the premise, not the finding',
      );

      expect(
        session.rangeMove.beginTrackRangeMoveDrag(_se1),
        isTrue,
        reason:
            'the anchor is a lane row of S1 and the band holds S2\'s '
            'sound. Refusing here is the silent re-select',
      );
    });

    // ↩️It read 「the lane row does not cost the span its own layer」 and
    // asserted that S1's sound slid: a band over S1's LANE moved S1's
    // sound, which no row of the band holds. H20 (유저 2026-08-23):
    // 「선택한 곳만 움직이게하라고」, and F-87 (10-18).
    test('and what it moves is what its rows hold — the lane is not its '
        'layer\'s sound', () {
      final session = sessionFor();
      selectLaneAnchoredBand(session);

      expect(session.rangeMove.beginTrackRangeMoveDrag(_se1), isTrue);
      session.rangeMove.updateFrameRangeMoveDrag(frameDelta: 1, targetLayerId: _se1);
      session.rangeMove.endFrameRangeMoveDrag();

      Layer row(LayerId id) => session.repository
          .requireProject()
          .tracks
          .single
          .seLayers
          .firstWhere((layer) => layer.id == id);
      expect(
        row(_se2).timeline.keys.toList(),
        [3],
        reason: 'S2\'s row was swept, and its sound slid a frame',
      );
      expect(
        row(_se1).timeline.keys.toList(),
        [2],
        reason: 'only S1\'s LANE was swept — its sound stays where it was',
      );
    });
  });

  group('a span made only of lane rows still selects', () {
    test('nothing to snap to is not the same as nothing to select', () {
      final session = sessionFor();
      session.updateTrackRowRangeSelectionByFrame(
        layerId: _se1,
        anchorGlobalFrame: 6,
        headGlobalFrame: 8,
        anchorRow: const LaneRowAddress(_se1, 'position'),
        spanRows: const [
          LaneRowAddress(_se1, 'position'),
          LaneRowAddress(_se1, 'scale'),
        ],
      );

      final live = session.trackFrameRangeSelection.value;
      expect(
        live,
        isNotNull,
        reason:
            'the lane domain rule is raw cells, no block snap — so the '
            'raw span IS the answer',
      );
      expect(live!.startFrame, 6);
      expect(live.endFrameExclusive, 9);
    });
  });

  /// ⚠️Everything above drives the SESSION, and the session was one of three
  /// sites. The other two live in widget files that no selection test opens —
  /// exactly how the wiring stayed missing while the law file next door stayed
  /// green (`every_row_joins_a_selection_test.dart`, same lesson).
  group('the WIRING, which the session-level tests cannot see', () {
    // A grid is a LIBRARY — the file plus the collaborator parts the audit's
    // SRP cuts (2026-09-02) put beside it. The wiring is asked of the whole
    // library, wherever a cut moved it.
    String source(String path) => librarySource(path);

    // The three sites moved together into ONE builder both grids call (the
    // audit's clone scan, 2026-09-03): the law is asked of the builder, and
    // each grid is asked to call it rather than keep a copy.
    const builder = 'lib/src/ui/timeline/timeline_grid_range_callbacks.dart';

    test('$builder asks the address, never its type', () {
      final text = source(builder);
      // ↩️F-87: isInSelection asks the ROW itself now — the band's
      // `coversRow`, the law the storyboard's rail presses by — so a swept
      // lane is inside the band whether or not its layer's row was swept.
      expect(
        RegExp(r'row\.owningLayerId').allMatches(text).length,
        greaterThanOrEqualTo(2),
        reason:
            'onSelectUpdate and onMoveBegin each need it — a builder that '
            'keeps one type test keeps half of the bug',
      );
      expect(
        text,
        contains('selection.coversRow(row)'),
        reason: 'isInSelection asks the row, not its layer',
      );
      expect(
        text,
        isNot(contains('row is LayerRowAddress &&')),
        reason:
            'that is the invented rule, spelled the way it was spelled '
            'at every site it was typed at',
      );
      expect(
        text,
        isNot(contains('row is! LayerRowAddress')),
        reason: 'and its negation, which the x-sheet used',
      );
    });

    // Both grids reach the builder through the ONE range-gesture collaborator
    // (round 8, 2026-09-06: the rail's and the sheet's private copies were
    // the same object) — so the collaborator is asked to call the builder,
    // and each grid is asked to hold the collaborator.
    const gestures = 'lib/src/ui/timeline/timeline_grid_range_gestures.dart';

    test('$gestures calls the builder', () {
      expect(source(gestures), contains('timelineGridRangeCallbacks('));
    });

    for (final path in [
      'lib/src/ui/timeline/layer_timeline_grid.dart',
      'lib/src/ui/timeline/xsheet_timeline_grid.dart',
    ]) {
      test('$path holds the collaborator and keeps no type test of its own', () {
        final text = source(path);
        expect(
          text,
          contains('TimelineGridRangeGestures('),
          reason: '$path must reach the shared builder, not keep its own',
        );
        expect(
          text,
          isNot(contains('isInSelection:')),
          reason:
              'a grid that spells the range callbacks itself is the copy '
              'that drifted — the sheet had lost the rows it swept',
        );
        expect(
          text,
          isNot(contains('row is LayerRowAddress &&')),
          reason:
              'that is the invented rule, spelled the way it was spelled '
              'at every site it was typed at',
        );
        expect(
          text,
          isNot(contains('row is! LayerRowAddress')),
          reason: 'and its negation, which the x-sheet used',
        );
      });
    }
  });
}
