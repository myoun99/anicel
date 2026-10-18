import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_effect.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/models/timeline_row_address.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/editor_workspace.dart';
import 'package:anicel/src/ui/home_page.dart';
import 'package:anicel/src/ui/timeline/effect_lane_policy.dart'
    show effectGroupLaneId;

import '../../helpers/app_icon_button_probe.dart';
import '../../helpers/named_finders.dart';

/// 🚨F-87, reopened (유저 2026-10-18): 「이미지든 애니메이션레이어든 fx 무언가
/// 하나 추가하고, 그 fx행 선택범위로 선택하고, 삭제버튼누르면 레이어의
/// 프레임이 삭제됨. 프레임이 없는 상태에선 삭제버튼이 회색임. 즉 삭제버튼의
/// 대상이 선택된 fx로 안가고있는듯. fx를 넘어서 뭐든 선택된 대상으로 버튼의
/// 대상이 바껴야하는데 법 통일해서 해결하도록」.
///
/// 🧪Measured on master (2026-10-18, a real mouse on the rail): a sweep along
/// the fx header row alone draws a LANE range and the press takes the fx. A
/// sweep that also crosses the layer's own row draws a cell BAND over both,
/// and the band read every row as its layer's blocks — the fx row was never
/// asked. So the press took the layer's frames in the band and left the fx;
/// with no frame in the band the button stayed grey; and a sweep begun on the
/// fx row, whose press stood there, lit the button and then did nothing.
///
/// ★The law is 08-12's: 「선택 객체 하나가 종류 섞인 행들을 담고, 각 동사가
/// 행 종류별로 알아서 처리」 — each swept row is deleted for what it holds.
const _a = LayerId('band-a');
const _b = LayerId('band-b');
const _s1 = LayerId('band-s1');
const _s2 = LayerId('band-s2');

/// A row holding one three-frame block from frame 0.
Layer _row(LayerId id, {LayerKind kind = LayerKind.animation}) => Layer(
  id: id,
  name: id.value,
  kind: kind,
  frames: [
    Frame(
      id: FrameId('${id.value}-f'),
      duration: 3,
      name: '',
      strokes: const [],
    ),
  ],
  timeline: {
    0: TimelineExposure.drawing(FrameId('${id.value}-f'), length: 3),
  },
);

Project _project() => Project(
  id: const ProjectId('band-project'),
  name: 'Band',
  createdAt: DateTime.utc(2026, 10, 18),
  tracks: [
    Track(
      id: const TrackId('band-track'),
      name: 'V',
      cuts: [
        Cut(
          id: const CutId('band-cut'),
          name: '1',
          duration: 12,
          canvasSize: const CanvasSize(width: 32, height: 32),
          layers: [_row(_a), _row(_b)],
        ),
      ],
      seLayers: [
        _row(_s1, kind: LayerKind.se),
        _row(_s2, kind: LayerKind.se),
      ],
    ),
  ],
);

void main() {
  group('the session: a swept lane is never its layer\'s blocks', () {
    EditorSessionManager sessionWithAnFxOnA() {
      final session = EditorSessionManager(initialProject: _project());
      addTearDown(session.dispose);
      session.selectLayer(_a);
      session.effectsAndFx.addEffectToActiveLayer(EffectKind.blur);
      return session;
    }

    Layer row(EditorSessionManager session, LayerId id) =>
        session.commitLayerById(id)!;

    test('a band from A\'s fx row into B\'s row takes the fx and B\'s block '
        '— and leaves A\'s, whose row it never swept', () {
      final session = sessionWithAnFxOnA();
      final fx = effectGroupLaneId(row(session, _a).effects.single.id);
      session.updateFrameRangeSelectionDrag(
        layerId: _a,
        anchorIndex: 0,
        headIndex: 2,
        headLayerId: _b,
        spanRows: [LaneRowAddress(_a, fx), const LayerRowAddress(_b)],
      );
      expect(
        session.frameRangeSelection.value?.spanLayerIds,
        [_b],
        reason: 'the band\'s blocks are its layer rows\' — B alone',
      );
      expect(session.cells.canDeleteCellForSelection, isTrue);

      session.cells.deleteCellAtCurrentFrame();

      expect(row(session, _a).effects, isEmpty, reason: 'the fx row swept');
      expect(row(session, _b).timeline, isEmpty, reason: 'B\'s row swept');
      expect(
        row(session, _a).timeline.keys,
        [0],
        reason: 'A\'s frames were under the band, but A\'s ROW was not — '
            '「레이어의 프레임이 삭제됨」 was this',
      );

      session.undo();
      expect(row(session, _a).effects, hasLength(1), reason: 'one undo…');
      expect(row(session, _b).timeline.keys, [0], reason: '…for both');
    });

    test('a band over lanes holding nothing claims the press: the button is '
        'dark and the press takes nothing — not A\'s frames', () {
      final session = sessionWithAnFxOnA();
      session.updateFrameRangeSelectionDrag(
        layerId: _a,
        anchorIndex: 0,
        headIndex: 2,
        headLayerId: _a,
        spanRows: const [
          LaneRowAddress(_a, 'position'),
          LaneRowAddress(_a, 'scale'),
        ],
      );
      expect(session.frameRangeSelection.value, isNotNull);
      expect(session.frameRangeSelection.value!.spanLayerIds, isEmpty);
      expect(session.cells.canDeleteCellAtCurrentFrame, isFalse);

      session.cells.deleteCellAtCurrentFrame();

      expect(row(session, _a).timeline.keys, [0]);
      expect(row(session, _a).effects, hasLength(1));
    });

    test('the storyboard\'s band: an S row\'s lane is not its sounds', () {
      final session = sessionWithAnFxOnA();
      session.updateTrackRowRangeSelectionByFrame(
        layerId: _s1,
        anchorGlobalFrame: 0,
        headGlobalFrame: 2,
        anchorRow: const LaneRowAddress(_s1, 'position'),
        spanRows: const [LaneRowAddress(_s1, 'position'), LayerRowAddress(_s2)],
      );
      expect(session.cells.canDeleteCellForSelection, isTrue);

      session.cells.deleteCellAtCurrentFrame();

      Layer se(LayerId id) => session.repository
          .requireProject()
          .tracks
          .single
          .seLayers
          .firstWhere((layer) => layer.id == id);
      expect(se(_s2).timeline, isEmpty, reason: 'S2\'s row was swept');
      expect(
        se(_s1).timeline.keys,
        [0],
        reason: 'only S1\'s lane was — its sound stays',
      );
    });
  });

  Future<EditorSessionManager> openTheSheet(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1400, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(home: HomePage(initialProject: createDefaultProject())),
    );
    await tester.pumpAndSettle();
    await tester.drag(
      find.byKey(const ValueKey<String>('dock-resize-bottom')),
      const Offset(0, -520),
    );
    await tester.pumpAndSettle();
    return tester
        .widget<EditorWorkspace>(find.byType(EditorWorkspace))
        .session;
  }

  const cell = 24.0;
  final deleteButton = find.byKey(
    const ValueKey<String>('shared-delete-button'),
  );

  for (final vertical in [false, true]) {
    final where = vertical ? 'the X-sheet' : 'the timeline';
    for (final fromTheFx in [false, true]) {
      final how = fromTheFx
          ? 'from the fx row up into its layer'
          : 'from the layer down into its fx row';
      for (final kind in [LayerKind.animation, LayerKind.image]) {
        testWidgets('$where, ${kind.name} row, $how: the band deletes the fx '
            'and only the blocks the band holds', (tester) async {
          final session = await openTheSheet(tester);
          if (kind == LayerKind.image) {
            session.layerStack.addLayerOfKind(LayerKind.image);
          } else {
            session.selectLayer(session.requireActiveCut.layers.first.id);
          }
          await tester.pumpAndSettle();
          final layer = session.activeLayer!;
          expect(layer.kind, kind, reason: 'fixture: the row is active');
          if (kind == LayerKind.animation) {
            // Past the band's three frames: the band holds no block of this
            // row — the user's 「프레임이 없는 상태」, where it went grey.
            session.selectFrameIndex(3);
            session.createDrawingAtCurrentFrame();
          }
          session.effectsAndFx.addEffectToActiveLayer(EffectKind.blur);
          await tester.pumpAndSettle();
          Layer now() => session.commitLayerById(layer.id)!;
          final headerLane = effectGroupLaneId(now().effects.single.id);
          final framesBefore = now().frames.length;

          if (vertical) {
            await tester.tap(
              find.byKey(
                const ValueKey<String>('timeline-orientation-toggle-button'),
              ),
            );
            await tester.pumpAndSettle();
          }
          final toggle = find.named('timeline-lane-toggle-${layer.id.value}');
          await tester.ensureVisible(toggle);
          await tester.pumpAndSettle();
          await tester.tap(toggle);
          await tester.pumpAndSettle();
          final header = find.byKey(
            ValueKey<String>(
              'timeline-lane-range-layer-${layer.id.value}-$headerLane',
            ),
          );
          final cells = find.named(
            vertical
                ? 'xsheet-column-${layer.id}-cells'
                : 'timeline-row-${layer.id}-cells',
          );
          expect(header, findsOneWidget, reason: 'fixture: $where draws it');
          expect(cells, findsOneWidget, reason: 'fixture: and the row');
          await tester.ensureVisible(header);
          await tester.pumpAndSettle();

          /// The middle of [row] across, at [frame] along — the frame axis
          /// read off the header, which every row of the grid shares.
          Offset at(Finder row, int frame) {
            final along = tester.getTopLeft(header);
            final across = tester.getCenter(row);
            final offset = cell * frame + cell / 2;
            return vertical
                ? Offset(across.dx, along.dy + offset)
                : Offset(along.dx + offset, across.dy);
          }

          final (from, to) = fromTheFx
              ? (at(header, 0), at(cells, 2))
              : (at(cells, 0), at(header, 2));
          final finger = await tester.startGesture(
            from,
            kind: PointerDeviceKind.mouse,
          );
          await finger.moveBy(
            vertical ? const Offset(0, cell) : const Offset(cell, 0),
          );
          await tester.pump();
          await finger.moveTo(to);
          await tester.pump();
          await finger.up();
          await tester.pumpAndSettle();

          expect(
            session.frameRangeSelection.value?.rows,
            [LayerRowAddress(layer.id), LaneRowAddress(layer.id, headerLane)],
            reason: '$where: the premise — ONE band over the row and its fx, '
                'in the order the rail draws them',
          );
          expect(
            tester.appIconButton(deleteButton).onPressed,
            isNotNull,
            reason: '$where: the band holds the fx, so the button is lit — '
                'it stayed grey with no frame in the band',
          );

          await tester.ensureVisible(deleteButton);
          await tester.pumpAndSettle();
          await tester.tap(deleteButton);
          await tester.pumpAndSettle();

          expect(
            now().effects,
            isEmpty,
            reason: '$where: 「삭제버튼의 대상이 선택된 fx로」 — the fx row '
                'swept is the fx deleted',
          );
          expect(
            now().frames.length,
            kind == LayerKind.animation ? framesBefore : 0,
            reason: kind == LayerKind.animation
                ? '$where: the drawing past the band is no block of it'
                : '$where: the picture under the band is one of its blocks — '
                      'the layer row was swept too',
          );
        });
      }
    }
  }
}
