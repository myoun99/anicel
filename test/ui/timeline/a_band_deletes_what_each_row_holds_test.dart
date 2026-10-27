import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_effect.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/pill_subject.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/property_track.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/models/timeline_row_address.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/models/transform_track.dart';
import 'package:anicel/src/models/working_panel.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/timeline/axis_turn.dart'
    show offsetAlong, partAcross, partAlong;
import 'package:anicel/src/ui/timeline/effect_lane_policy.dart'
    show effectGroupLaneId, effectLaneId;
import 'package:anicel/src/ui/timeline/timeline_zoom_limits.dart';
import 'package:anicel/src/ui/timeline/toolbar_panel_context.dart'
    show StoryboardToolbarPanelContext;
import 'package:anicel/src/ui/timeline/transform_lane_editing.dart'
    show transformLaneKeyFrames;

import '../../helpers/app_icon_button_probe.dart';
import '../../helpers/named_finders.dart';
import '../../helpers/timeline_host.dart';

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

/// A row holding one three-frame block from frame 0 — and a Position key at
/// each of [positionKeys].
Layer _row(
  LayerId id, {
  LayerKind kind = LayerKind.animation,
  List<int> positionKeys = const [],
}) => Layer(
  id: id,
  name: id.value,
  kind: kind,
  transformTrack: positionKeys.isEmpty
      ? null
      : TransformTrack.empty().copyWith(
          position: positionKeys.fold<PropertyTrack<CanvasPoint>>(
            PropertyTrack<CanvasPoint>.empty(),
            (track, frame) => track.withKey(frame, CanvasPoint(x: 1, y: 1)),
          ),
        ),
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

Project _project({List<int> aPositionKeys = const []}) => Project(
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
          layers: [_row(_a, positionKeys: aPositionKeys), _row(_b)],
        ),
      ],
      seLayers: [
        _row(_s1, kind: LayerKind.se),
        _row(_s2, kind: LayerKind.se),
      ],
    ),
  ],
);

const _cel2 = LayerId('band-cel-2');

/// Cut 1 is frames 0..10, cut 2 is 10..20, and S1 holds a Position key in
/// each — 4 and 14 on the track — so a band in cut 2 names S1's keys on
/// numbers that are not the band's own. In cut 1 the two coincide, and a
/// band read on the wrong axis passes there.
Project _twoCuts() => Project(
  id: const ProjectId('band-two-cuts'),
  name: 'Two',
  createdAt: DateTime.utc(2026, 10, 18),
  tracks: [
    Track(
      id: const TrackId('band-track'),
      name: 'V',
      cuts: [
        for (final (cut, cel) in [
          ('band-cut-1', const LayerId('band-cel-1')),
          ('band-cut-2', _cel2),
        ])
          Cut(
            id: CutId(cut),
            name: cut,
            duration: 10,
            canvasSize: const CanvasSize(width: 32, height: 32),
            layers: [_row(cel)],
          ),
      ],
      seLayers: [
        Layer(
          id: _s1,
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
      expect(
        session.frameRangeSelection.value?.layerId,
        _b,
        reason: 'the row a single-row flow reads is the drag\'s own only '
            'where its blocks were swept — else the first whose were',
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

    // A lane's keys are points, so a band of lanes alone is the cells it
    // swept; and it covers no row a press on A lands on, so X, the mark and
    // the rename refuse rather than take A's frame.
    test('a band over A\'s fx row alone is the cells it swept, and covers '
        'no row of A\'s blocks', () {
      final session = sessionWithAnFxOnA();
      final fx = effectGroupLaneId(row(session, _a).effects.single.id);
      session.updateFrameRangeSelectionDrag(
        layerId: _a,
        anchorIndex: 1,
        headIndex: 1,
        headLayerId: _a,
        spanRows: [LaneRowAddress(_a, fx)],
      );
      final band = session.frameRangeSelection.value!;
      expect(
        (band.startIndex, band.endIndexExclusive),
        (1, 2),
        reason: 'A\'s block runs 0..3, and a band over A\'s row snaps to it',
      );
      expect(
        session.bandNamesRowsThisPressWouldMiss,
        isTrue,
        reason: 'a press on A lands on A\'s row, which the band never swept',
      );
    });

    // Standing on a header is no range: the press takes the keys at the
    // playhead, as it always did.
    test('standing on A\'s fx header takes its key at the playhead and '
        'leaves the fx', () {
      final session = sessionWithAnFxOnA();
      final effect = row(session, _a).effects.single;
      session.laneVerbs.toggleLaneKeyAt(
        _a,
        effectLaneId(effect.id, 'blurX'),
        1,
        frameIsGlobal: false,
        description: 'Key blur',
      );
      session.standOnRow(
        LaneRowAddress(_a, effectGroupLaneId(effect.id)),
        frameIndex: 1,
      );
      expect(
        session.cells.canDeleteCellAtCurrentFrame,
        isTrue,
        reason: 'fixture: the key at 1 is under the header stood on',
      );

      session.cells.deleteCellAtCurrentFrame();

      final kept = row(session, _a).effects;
      expect(kept, hasLength(1), reason: 'standing is no range: the fx stays');
      expect(kept.single.parameterOf('blurX').isAnimated, isFalse);
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

    List<int> positionKeysOf(Layer layer) =>
        layer.transformTrack.position.keys.keys.toList();

    // R27 #14: a cell drag that reaches its anchor's own transform lanes
    // stops there, one band (유저 2026-10-25). ↩️It published them as a lane
    // range beside the band too — the TAIL — and asked before the band, the
    // tail took the keys and left the blocks.
    test('a band reaching its own transform lanes takes the blocks AND the '
        'keys', () {
      final session = EditorSessionManager(
        initialProject: _project(aPositionKeys: [1]),
      );
      addTearDown(session.dispose);
      session.updateFrameRangeSelectionDrag(
        layerId: _a,
        anchorIndex: 0,
        headIndex: 2,
        spanRows: const [
          LayerRowAddress(_a),
          LaneRowAddress(_a, 'anchor-point'),
          LaneRowAddress(_a, 'position'),
        ],
      );

      session.cells.deleteCellAtCurrentFrame();

      expect(row(session, _a).timeline, isEmpty, reason: 'A\'s row swept');
      expect(
        positionKeysOf(row(session, _a)),
        isEmpty,
        reason: 'A\'s Position lane swept',
      );
    });

    // The press's order, said of the gate too: a band up claims it, so the
    // lane stood on answers nothing — neither the button nor the delete.
    test('with a band up, the lane stood on does not answer for it', () {
      final session = EditorSessionManager(
        initialProject: _project(aPositionKeys: [1]),
      );
      addTearDown(session.dispose);
      session.standOnRow(const LaneRowAddress(_a, 'position'), frameIndex: 1);
      session.updateFrameRangeSelectionDrag(
        layerId: _b,
        anchorIndex: 5,
        headIndex: 6,
        headLayerId: _b,
        spanRows: const [LayerRowAddress(_b)],
      );
      expect(
        session.cells.canDeleteCellAtCurrentFrame,
        isFalse,
        reason: 'the band holds nothing, and the key under the lane stood '
            'on is no row of it',
      );

      session.cells.deleteCellAtCurrentFrame();

      expect(positionKeysOf(row(session, _a)), [1]);
    });

    // F-17/F-84 (유저 2026-09-11): the camera row IS its transform header —
    // swept by a band it is deleted as that header is, alone or beside a
    // drawing row.
    for (final withDrawing in [false, true]) {
      test('a band over the camera row takes its keys'
          '${withDrawing ? ' beside a drawing row' : ''}', () {
        final session = EditorSessionManager(
          initialProject: createDefaultProject(),
        );
        addTearDown(session.dispose);
        LayerId rowOf(LayerKind kind) =>
            session.layers.firstWhere((layer) => layer.kind == kind).id;
        final camera = rowOf(LayerKind.camera);
        for (final frame in [1, 5]) {
          session.standOnRow(LayerRowAddress(camera), frameIndex: frame);
          session.camera.setCameraKeyframeAtCurrentFrame(
            session.camera.cameraPoseAtCurrentFrame,
          );
        }
        final drawing = rowOf(LayerKind.animation);
        session.updateFrameRangeSelectionDrag(
          layerId: camera,
          anchorIndex: 0,
          headIndex: 2,
          headLayerId: withDrawing ? drawing : camera,
          spanRows: [
            LayerRowAddress(camera),
            if (withDrawing) LayerRowAddress(drawing),
          ],
        );
        expect(
          session.cells.canDeleteCellAtCurrentFrame,
          isTrue,
          reason: 'the band holds the camera\'s key at 1',
        );

        session.cells.deleteCellAtCurrentFrame();

        expect(
          transformLaneKeyFrames(
            session.requireActiveCut.camera.track,
            'position',
          ),
          {5},
          reason: 'the key at 1 was under the band; the one at 5 was not',
        );
      });
    }

    test('a band\'s lane is read on its row\'s own axis — an S row\'s keys '
        'live on the track\'s frames', () {
      final session = EditorSessionManager(initialProject: _twoCuts());
      addTearDown(session.dispose);
      session.selectCut(session.activeTrack.cuts[1].id);
      session.updateFrameRangeSelectionDrag(
        layerId: _cel2,
        anchorIndex: 3,
        headIndex: 5,
        headLayerId: _s1,
        spanRows: const [
          LayerRowAddress(_cel2),
          LaneRowAddress(_s1, 'position'),
        ],
      );

      session.cells.deleteCellAtCurrentFrame();

      expect(
        positionKeysOf(session.activeTrack.seLayers.single),
        [4],
        reason: 'cut 2\'s frames 3..5 are the track\'s 13..15 — the key at '
            '14 goes, and the one at 4, in cut 1, stays',
      );
    });

    test('the storyboard: a lane RANGE claims the press — with no key under '
        'it, the sound under the cursor stays', () {
      final session = sessionWithAnFxOnA();
      session.selectFrameIndex(1);
      session.updateLaneRangeSelectionDrag(
        layerId: _s1,
        laneId: 'position',
        anchorIndex: 0,
        headIndex: 2,
        spanLaneIds: const [],
        panel: WorkingPanel.storyboard,
      );
      final panel = StoryboardToolbarPanelContext(session);
      expect(
        panel.deleteSubject,
        PillSubject.nothing,
        reason: 'the range holds nothing to delete, so the button is dark',
      );

      panel.deleteSelectionSubject();

      expect(
        session.activeTrack.seLayers.first.timeline.keys,
        [0],
        reason: 'S1\'s sound is its ROW\'s, which the range never swept',
      );
    });
  });

  /// The timeline tab alone ([pumpTimelineHost]), as tall as the app's
  /// window of 1400 × 2000 laid it — far enough that the X-sheet, whose rail
  /// stands over its frames, still shows a dozen frames: a sweep ending near
  /// the frames' edge pans the sheet under the finger, and the band reaches
  /// a frame further than the finger was put (measured 10-18).
  Future<EditorSessionManager> openTheSheet(WidgetTester tester) =>
      pumpTimelineHost(
        tester,
        createDefaultProject(),
        surface: const Size(870, 610),
      );

  // The cell a cut opens at (F-403).
  const cell = TimelineZoomLimits.referencePixelsPerFrame;
  final deleteButton = find.byKey(
    const ValueKey<String>('shared-delete-button'),
  );

  for (final vertical in [false, true]) {
    final where = vertical ? 'the X-sheet' : 'the timeline';
    // The frame axis: down the sheet, across the timeline.
    final axis = vertical ? Axis.vertical : Axis.horizontal;
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
          // The add shows the row's lanes, its header open (F-396).
          final toggle = find.named(
            '${vertical ? 'xsheet' : 'timeline'}-lane-toggle-${layer.id.value}',
          );
          await tester.ensureVisible(toggle);
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
          Offset at(Finder row, int frame) => offsetAlong(
            axis,
            along:
                partAlong(axis, tester.getTopLeft(header)) +
                cell * frame +
                cell / 2,
            across: partAcross(axis, tester.getCenter(row)),
          );

          final (from, to) = fromTheFx
              ? (at(header, 0), at(cells, 2))
              : (at(cells, 0), at(header, 2));
          final finger = await tester.startGesture(
            from,
            kind: PointerDeviceKind.mouse,
          );
          await finger.moveBy(offsetAlong(axis, along: cell, across: 0));
          await tester.pump();
          await finger.moveTo(to);
          await tester.pump();
          await finger.up();
          await tester.pumpAndSettle();

          if (kind == LayerKind.animation) {
            expect(
              (
                session.frameRangeSelection.value?.startIndex,
                session.frameRangeSelection.value?.endIndexExclusive,
              ),
              (0, 3),
              reason: '$where: the premise — the band is frames 0..2, short '
                  'of the drawing at 3',
            );
          }
          expect(
            session.frameRangeSelection.value?.rows,
            unorderedEquals([
              LayerRowAddress(layer.id),
              LaneRowAddress(layer.id, headerLane),
            ]),
            reason: '$where: the premise — ONE band over the row and its fx, '
                'in whichever order this surface draws the two',
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
