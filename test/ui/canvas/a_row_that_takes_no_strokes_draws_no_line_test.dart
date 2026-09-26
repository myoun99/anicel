import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/app_input_settings.dart';
import 'package:anicel/src/models/brush_frame_key.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_effect.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/models/timeline_row_address.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/services/editing/default_cut_helpers.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/editor_workspace.dart';
import 'package:anicel/src/ui/home_page.dart';
import 'package:anicel/src/ui/timeline/effect_lane_policy.dart'
    show effectGroupLaneId, effectLaneId;

import '../../helpers/panel_finders.dart';

/// 🗣️F-196 (유저 2026-09-27): 「fx행에 서있는데 그림이 그려지고 커밋시
/// 사라짐. 애초에 도구조작 알아서 막고 조작은 해당 행에대한 조작이
/// 기본임. 그러니 안그려져야 하는곳은 통일해서 선 안나오게」 — and after it,
/// 「타임라인이 잠금상태? 룰러쪽 드래그 안먹는데 위아래 이동은 먹힘」.
///
/// A property lane takes no strokes (H19: the ROW decides what a press may
/// do). The press used to begin a stroke anyway, the live line showed, and
/// the commit threw at pen-up — which skipped the stroke's end, so the
/// session went on refusing every seek as if the pen were still down.
void main() {
  const layerId = LayerId('fx-layer');
  const frameA = FrameId('fx-frame-a');
  const frameB = FrameId('fx-frame-b');

  Project project() => Project(
    id: const ProjectId('fx-project'),
    name: 'Fx',
    createdAt: DateTime.utc(2026),
    tracks: [
      Track(
        id: const TrackId('fx-track'),
        name: 'Video Track',
        cuts: [
          Cut(
            id: const CutId('fx-cut'),
            name: 'fx-cut',
            duration: defaultCutDuration,
            canvasSize: defaultCutCanvasSize,
            layers: [
              Layer(
                id: layerId,
                name: 'A',
                frames: [
                  Frame(id: frameA, name: 'A', duration: 1, strokes: const []),
                  Frame(id: frameB, name: 'B', duration: 1, strokes: const []),
                ],
                timeline: {
                  0: const TimelineExposure.drawing(frameA, length: 1),
                  1: const TimelineExposure.drawing(frameB, length: 1),
                },
              ),
            ],
          ),
        ],
      ),
    ],
  );

  BrushFrameKey keyFor(FrameId frameId) => BrushFrameKey(
    projectId: const ProjectId('fx-project'),
    trackId: const TrackId('fx-track'),
    cutId: const CutId('fx-cut'),
    layerId: layerId,
    frameId: frameId,
  );

  EditorSessionManager sessionOf(WidgetTester tester) =>
      tester.widget<EditorWorkspace>(find.byType(EditorWorkspace)).session;

  Layer layerOf(EditorSessionManager session) =>
      session.requireActiveCut.layers.byId(layerId)!;

  bool inked(EditorSessionManager session, FrameId frameId) => session
      .renderCaches
      .brushFrameStore
      .celHasRenderableContent(keyFor(frameId));

  /// The app with a blur on the layer — the row's fx header and its
  /// parameters are the lanes a press is refused on.
  Future<(EditorSessionManager, EffectId)> pumpWithAnFx(
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(home: HomePage(initialProject: project())),
    );
    await tester.pumpAndSettle();
    final session = sessionOf(tester);
    addTearDown(() => AppInput.settings.value = const AppInputSettings());
    session.selectLayer(layerId);
    session.effectsAndFx.addEffectToActiveLayer(EffectKind.blur);
    await tester.pumpAndSettle();
    return (session, layerOf(session).effects.single.id);
  }

  Future<void> standOn(
    WidgetTester tester,
    EditorSessionManager session,
    TimelineRowAddress row, {
    required int frameIndex,
  }) async {
    session.standOnRow(row, frameIndex: frameIndex);
    await tester.pumpAndSettle();
    expect(
      session.standing.currentRowListenable.value,
      row,
      reason: 'premise: standing where the case says',
    );
    expect(session.currentFrameIndex, frameIndex);
  }

  /// A pen stroke across what the artist can see. [whileDown] runs with
  /// the pen still on the paper.
  Future<void> stroke(
    WidgetTester tester, {
    void Function()? whileDown,
  }) async {
    final gesture = await tester.startGesture(
      visibleCanvasPoint(tester),
      kind: PointerDeviceKind.stylus,
    );
    await tester.pump();
    await gesture.moveBy(const Offset(24, 12));
    await tester.pump();
    whileDown?.call();
    await gesture.moveBy(const Offset(24, 12));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();
  }

  Future<void> drain(WidgetTester tester) async {
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
  }

  testWidgets('on the fx row over a cel no line starts, nothing lands, and '
      'the playhead is free afterwards', (tester) async {
    final (session, blur) = await pumpWithAnFx(tester);
    final lanes = [effectGroupLaneId(blur), effectLaneId(blur, 'blurX')];
    for (final lane in lanes) {
      await standOn(
        tester,
        session,
        LaneRowAddress(layerId, lane),
        frameIndex: 0,
      );
      await stroke(
        tester,
        whileDown: () => expect(
          session.brushInputActive.value,
          isFalse,
          reason: '$lane: no stroke began, so there is no line to see',
        ),
      );
      expect(tester.takeException(), isNull, reason: '$lane: pen-up is quiet');
      expect(inked(session, frameA), isFalse, reason: '$lane: nothing landed');
      session.selectFrameIndex(1);
      expect(
        session.currentFrameIndex,
        1,
        reason: '$lane: nothing is left holding the playhead',
      );
    }

    // LIVENESS — the same stroke on the layer's own row draws, so the
    // silence above is the lane's answer and not a stroke that never
    // reached the canvas.
    await standOn(
      tester,
      session,
      const LayerRowAddress(layerId),
      frameIndex: 0,
    );
    await stroke(tester);
    expect(inked(session, frameA), isTrue, reason: 'the layer row takes it');
    await drain(tester);
  });

  testWidgets('on the fx row over an empty frame the auto-frame makes no '
      'block', (tester) async {
    final (session, blur) = await pumpWithAnFx(tester);
    session.setInputSettings(
      AppInput.settings.value.copyWith(autoCreateFrameOnDraw: true),
    );
    await tester.pumpAndSettle();
    const emptyFrame = 4;
    final before = layerOf(session);
    expect(before.timeline.containsKey(emptyFrame), isFalse);

    await standOn(
      tester,
      session,
      LaneRowAddress(layerId, effectGroupLaneId(blur)),
      frameIndex: emptyFrame,
    );
    await stroke(tester);
    expect(tester.takeException(), isNull);
    expect(
      layerOf(session).frames.length,
      before.frames.length,
      reason: 'the lane refuses the stroke, so it makes nothing to draw in',
    );
    expect(layerOf(session).timeline, before.timeline);

    // LIVENESS — on the layer row the same press makes the block.
    await standOn(
      tester,
      session,
      const LayerRowAddress(layerId),
      frameIndex: emptyFrame,
    );
    await stroke(tester);
    expect(
      layerOf(session).frames.length,
      before.frames.length + 1,
      reason: 'the auto-frame is on and the layer row takes strokes',
    );
    await drain(tester);
  });
}
