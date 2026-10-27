import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_camera.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/property_track.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/models/timeline_row_address.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/models/transform_track.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/timeline/axis_turn.dart'
    show offsetAlong, partAcross, partAlong;
import 'package:anicel/src/ui/timeline/timeline_drag_preview.dart'
    show BlockMoveDragPreview;
import 'package:anicel/src/ui/timeline/timeline_zoom_limits.dart';

import '../../helpers/named_finders.dart';
import '../../helpers/timeline_host.dart';

/// 🚨H20 (유저 2026-08-23): 「fx랑 블록이랑 같이 움직이게할거면 둘다 유저가
/// 선택하게 할거니까 … 선택한 곳만 움직이게하라고」 — and 08-12's 「선택 객체
/// 하나가 종류 섞인 행들을 담고, 각 동사가 행 종류별로 알아서 처리」.
///
/// 🧪Measured on master `762726858` (2026-10-25, a real mouse on both grids):
/// a sweep from a layer's cells down into its Position lane draws ONE band
/// over the layer row and its lane rows, and a lane selection over the same
/// frames beside it. Dragged by a lane cell inside it, the band went at the
/// press and only the keys moved; dragged by a layer cell, only the block
/// moved, and the moved band forgot its lane rows. Each press moved the kind
/// it was pressed on.
///
/// ★Wherever it is pressed, the band moves what each of its rows holds — the
/// layer row its block, the lane rows their keys — and the band stands where
/// they went (one band since 유저 2026-10-25; ↩️the lane selection beside it
/// rode along).
const _a = LayerId('a');
const _b = LayerId('b');
const _c = LayerId('c');
const _d = LayerId('d');
const _cell = TimelineZoomLimits.referencePixelsPerFrame;
const _position = LaneRowAddress(_a, 'position');

/// [id] holding one three-frame block from frame 0 — and, when [keyed],
/// Position keys at 0 and 2.
Layer _layer(LayerId id, {bool keyed = false, bool exposed = true}) => Layer(
  id: id,
  name: id.value,
  transformTrack: keyed
      ? TransformTrack.empty().copyWith(
          position: PropertyTrack<CanvasPoint>()
              .withKey(0, CanvasPoint(x: 1, y: 1))
              .withKey(2, CanvasPoint(x: 5, y: 5)),
        )
      : null,
  frames: [
    Frame(
      id: FrameId('${id.value}-f'),
      duration: 3,
      name: id.value,
      strokes: const [],
    ),
  ],
  timeline: exposed
      ? {0: TimelineExposure.drawing(FrameId('${id.value}-f'), length: 3)}
      : const {},
);

/// B, empty, stands right before A (above it on the rail) — no lane row
/// between them — and C, empty, before B, where a carry onto B lands when
/// its rows are counted from anywhere but the row pressed. D, empty, stands
/// after A's lanes. Their drawings are named apart, so a carry asks nothing
/// (F-413).
Project _project() => Project(
  id: const ProjectId('p'),
  name: 'P',
  createdAt: DateTime.utc(2026, 10, 25),
  tracks: [
    Track(
      id: const TrackId('t'),
      name: 'V',
      cuts: [
        Cut(
          id: const CutId('c'),
          name: 'C',
          duration: 12,
          canvasSize: const CanvasSize(width: 64, height: 64),
          camera: CutCamera.empty(),
          layers: [
            _layer(_d, exposed: false),
            _layer(_a, keyed: true),
            _layer(_b, exposed: false),
            _layer(_c, exposed: false),
          ],
        ),
      ],
    ),
  ],
);

typedef _Grid = ({
  EditorSessionManager session,
  Axis axis,
  Finder cells,
  Finder lane,
  Offset Function(Finder row, int frame) at,
});

/// The grid on [axis] with A's Transform lanes open, swept from A's cell
/// at frame 0 down to its Position lane at frame 2 — or on past them to
/// [pastTheLanesTo]'s cells.
Future<_Grid> _sweptBand(
  WidgetTester tester,
  Axis axis, {
  LayerId? pastTheLanesTo,
}) async {
  final session = await pumpTimelineHost(
    tester,
    _project(),
    surface: const Size(1200, 800),
  );
  final sheet = axis == Axis.vertical;
  if (sheet) {
    await tester.tap(
      find.byKey(const ValueKey<String>('timeline-orientation-toggle-button')),
    );
    await tester.pumpAndSettle();
  }
  session.layerSwitches.toggleLayerLanes(_a);
  await tester.pumpAndSettle();
  final lane = find.byKey(
    const ValueKey<String>('timeline-lane-range-layer-a-position'),
  );
  if (lane.evaluate().isEmpty) {
    await tester.tap(
      find.named(
        '${sheet ? 'xsheet' : 'timeline'}-lane-group-toggle-a-transform-group',
      ),
    );
    await tester.pumpAndSettle();
  }
  Offset at(Finder row, int frame) => offsetAlong(
    axis,
    along: partAlong(axis, tester.getTopLeft(lane)) + _cell * frame + _cell / 2,
    across: partAcross(axis, tester.getCenter(row)),
  );
  final cells = _cellsOf(axis, _a);
  final sweep = await tester.startGesture(
    at(cells, 0),
    kind: PointerDeviceKind.mouse,
  );
  await sweep.moveBy(offsetAlong(axis, along: _cell, across: 0));
  await tester.pump();
  final past = pastTheLanesTo;
  await sweep.moveTo(at(past == null ? lane : _cellsOf(axis, past), 2));
  await tester.pump();
  await sweep.up();
  await tester.pumpAndSettle();
  return (session: session, axis: axis, cells: cells, lane: lane, at: at);
}

/// A press of [kind] at [from], carried to [to] in four steps, [held] read
/// there, and let go.
Future<void> _carry(
  WidgetTester tester,
  Offset from,
  Offset to, {
  void Function()? held,
  PointerDeviceKind kind = PointerDeviceKind.mouse,
}) async {
  final hand = await tester.startGesture(from, kind: kind);
  await tester.pump();
  final travel = to - from;
  for (var step = 1; step <= 4; step += 1) {
    await hand.moveTo(from + travel * (step / 4));
    await tester.pump();
  }
  held?.call();
  await hand.up();
  await tester.pumpAndSettle();
}

Finder _cellsOf(Axis axis, LayerId id) => find.named(
  axis == Axis.horizontal
      ? 'timeline-row-${id.value}-cells'
      : 'xsheet-column-${id.value}-cells',
);

List<int> _blocksOf(EditorSessionManager session, LayerId id) =>
    session.commitLayerById(id)!.timeline.keys.toList();

List<int> _keysOf(EditorSessionManager session) =>
    session.commitLayerById(_a)!.transformTrack.position.keys.keys.toList();

void main() {
  for (final axis in Axis.values) {
    for (final onLane in [true, false]) {
      final grid = axis == Axis.horizontal ? 'rail' : 'sheet';
      final pressed = onLane ? 'a lane cell' : 'a layer cell';
      testWidgets('on the $grid, a band dragged by $pressed carries the '
          'block and the keys, and stands where they went', (tester) async {
        final g = await _sweptBand(tester, axis);
        final s = g.session;
        expect(s.frameRangeSelection.value?.coversRow(_position), isTrue);

        final row = onLane ? g.lane : g.cells;
        await _carry(
          tester,
          g.at(row, 1),
          g.at(row, 3),
          // The drag shows both going, not the press's kind alone.
          held: () {
            final shown = s.dragPreview.value;
            expect(shown, isA<BlockMoveDragPreview>());
            final a = (shown! as BlockMoveDragPreview).previewLayers[_a]!;
            expect(a.timeline.keys, [2]);
            expect(a.transformTrack.position.keys.keys, [2, 4]);
          },
        );

        expect(_blocksOf(s, _a), [2]);
        expect(_keysOf(s), [2, 4]);
        final band = s.frameRangeSelection.value!;
        expect((band.startIndex, band.endIndexExclusive), (2, 5));
        expect(band.coversRow(const LayerRowAddress(_a)), isTrue);
        expect(band.coversRow(_position), isTrue);

        s.undo();
        expect(_blocksOf(s, _a), [0]);
        expect(_keysOf(s), [0, 2]);
      });
    }
    // A sweep that runs on past A's lanes holds them too. A press on one is
    // the band's still, and steps as the band's does: on the frame a move
    // would land on (F-238 「1콤마만 바로바로」), not on leaving the cell it
    // pressed.
    testWidgets('on the ${axis == Axis.horizontal ? 'rail' : 'sheet'}, a '
        'band swept past a row\'s lanes goes a frame on a short touch drag '
        'of one of them', (tester) async {
      final g = await _sweptBand(tester, axis, pastTheLanesTo: _d);
      final s = g.session;
      expect(s.frameRangeSelection.value?.coversRow(_position), isTrue);

      final from = g.at(g.lane, 1) -
          offsetAlong(axis, along: _cell * 0.3, across: 0);
      await _carry(
        tester,
        from,
        from + offsetAlong(axis, along: _cell * 0.6, across: 0),
        kind: PointerDeviceKind.touch,
      );

      expect(_blocksOf(s, _a), [1]);
      expect(_keysOf(s), [1, 3]);
    });
    // 🗣️유저 2026-08-12: 「어딘가 클릭하면 사라지도록 … 근데 선택된 내 물건
    // 클릭해도 사라지도록」 — a click on a lane the band holds is a click on
    // the band.
    testWidgets('on the ${axis == Axis.horizontal ? 'rail' : 'sheet'}, a '
        'click on a lane inside the band lets it go', (tester) async {
      final g = await _sweptBand(tester, axis);
      final s = g.session;

      final hand = await tester.startGesture(
        g.at(g.lane, 1),
        kind: PointerDeviceKind.mouse,
      );
      await tester.pump();
      await hand.up();
      await tester.pumpAndSettle();

      expect(s.frameRangeSelection.value, isNull);
      expect(s.laneRangeSelection.value, isNull);
      expect(_keysOf(s), [0, 2]);
    });
    // 🗣️「a-lane-press-clears-a-mixed-run-Q1」 (유저 2026-10-25): 「블록은 다른
    // 행으로, 키는 제 레인에서 프레임으로만」 — what the riders of a hop
    // already did (R27 #8).
    for (final onLane in [true, false]) {
      final grid = axis == Axis.horizontal ? 'rail' : 'sheet';
      final pressed = onLane ? 'a lane cell' : 'a layer cell';
      testWidgets('on the $grid, a band carried by $pressed onto another '
          'row takes its block there and its keys along their own lane — '
          'the rows counted from the row pressed', (tester) async {
        final g = await _sweptBand(tester, axis);
        final s = g.session;
        final row = onLane ? g.lane : g.cells;

        await _carry(tester, g.at(row, 1), g.at(_cellsOf(axis, _b), 3));

        expect(_blocksOf(s, _b), [2]);
        expect(_blocksOf(s, _c), isEmpty);
        expect(_blocksOf(s, _a), isEmpty);
        expect(_keysOf(s), [2, 4]);
        final band = s.frameRangeSelection.value!;
        expect((band.startIndex, band.endIndexExclusive), (2, 5));
        expect(band.coversRow(const LayerRowAddress(_b)), isTrue);
        expect(band.coversRow(const LayerRowAddress(_a)), isFalse);
        expect(band.coversRow(_position), isTrue);
      });
    }
  }
}
