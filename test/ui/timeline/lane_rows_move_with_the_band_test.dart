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
          frames: const [],
          timeline: const {},
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
        session.beginTrackRangeMoveDrag(_se1),
        isTrue,
        reason:
            'the anchor is a lane row of S1, so the move machine reads '
            'S1. Refusing here is the silent re-select',
      );
    });

    test('and the lane row does not cost the span its own layer', () {
      final session = sessionFor();
      selectLaneAnchoredBand(session);

      expect(session.beginTrackRangeMoveDrag(_se1), isTrue);
      session.updateFrameRangeMoveDrag(frameDelta: 1, targetLayerId: _se1);
      session.endFrameRangeMoveDrag();

      final se1 = session.repository
          .requireProject()
          .tracks
          .single
          .seLayers
          .firstWhere((layer) => layer.id == _se1);
      expect(
        se1.timeline.keys.toList(),
        [3],
        reason:
            'S1 owns the sound, the anchor row is one of S1 lanes, and '
            'the move slid it a frame. A dropped lane row leaves the sound '
            'where it was',
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
      expect(
        RegExp(r'row\.owningLayerId').allMatches(text).length,
        greaterThanOrEqualTo(3),
        reason:
            'isInSelection, onSelectUpdate and onMoveBegin each need '
            'it — a builder that keeps one type test keeps one third of the '
            'bug',
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

    for (final path in [
      'lib/src/ui/timeline/layer_timeline_grid.dart',
      'lib/src/ui/timeline/xsheet_timeline_grid.dart',
    ]) {
      test('$path calls the builder and keeps no type test of its own', () {
        final text = source(path);
        expect(
          text,
          contains('timelineGridRangeCallbacks('),
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
