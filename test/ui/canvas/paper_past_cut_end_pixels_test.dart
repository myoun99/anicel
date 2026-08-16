import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/brush_dab.dart';
import 'package:anicel/src/models/brush_history_policy.dart';
import 'package:anicel/src/models/brush_tip_shape.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/project_background.dart';
import 'package:anicel/src/services/brush_frame_edit_session_store.dart';
import 'package:anicel/src/services/brush_frame_editing_coordinator.dart';
import 'package:anicel/src/ui/brush/brush_tool_state.dart';
import 'package:anicel/src/ui/editor_canvas_area.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';

/// 🚨The PIXELS this time, not the wiring. Three earlier tests measured the
/// session (`past_cut_end_is_ordinary_test`) and the widget's inputs
/// (`past_cut_end_paints_test`, `paper_past_cut_end_test`) and all three were
/// green while the user's screen showed 「캔버스가 용지나 그림이 사라짐」 past
/// the end line — because the paper WAS painted, and then the cut-fade wash
/// painted an opaque backdrop plate straight over it: `cutOpacityAt` answers
/// the compositor's material question (0 outside the media range), and the
/// unclamped playhead (T12) stands outside that range on every frame past the
/// end line. Only a capture of what the canvas area actually shows can catch
/// a correct picture being covered up, so this file asserts colors.
///
/// The law (유저): 컷 길이는 소재와 관계없다 — past the end line is ordinary
/// space. A GAP parking stays the paperless void (R16-⑥), and the second
/// test here pins that the fix did not disturb it.
void main() {
  const paperArgb = 0xFF00FF00; // sentinel green — nothing else paints this
  const inkArgb = 0xFFFF0000; // sentinel red

  bool isPaper(int r, int g, int b) => g > 200 && r < 80 && b < 80;
  bool isInk(int r, int g, int b) => r > 200 && g < 80 && b < 80;

  /// Cut duration 4 with a drawn cel exposed at index 6 — the arrangement
  /// the user reported from. Paper is the green sentinel, the cel's ink the
  /// red one, so the capture can name what it sees.
  (EditorSessionManager, int) sessionPastEnd() {
    final s = EditorSessionManager(initialProject: createDefaultProject());
    final cut = s.requireActiveCut;
    s.repository.updateCutDuration(cutId: cut.id, duration: 4);
    s.setProjectBackground(const ProjectBackground.color(paperArgb));

    final layer = s.requireActiveCut.layers.firstWhere(
      (candidate) => candidate.kind == LayerKind.animation,
    );
    s.selectLayer(layer.id);
    s.selectFrameIndex(6);
    s.createDrawingAtCurrentFrame();
    final frame = s.selectedFrame!;
    // Ink through the same commit funnel a pen stroke lands with, into the
    // session's own store — the canvas must show it back.
    BrushFrameEditingCoordinator(
      initialFrameKey: s.brushFrameKeyForCut(
        s.requireActiveCut,
        layer.id,
        frame.id,
      ),
      frameStore: s.brushFrameStore,
      sessionStore: BrushFrameEditSessionStore(
        canvasSize: s.requireActiveCut.canvasSize,
      ),
      historyPolicy: const BrushHistoryPolicy(
        userUndoLimit: 8,
        deferredBakeRatio: 0,
      ),
    ).commitSourceStroke(
      sourceDabs: [
        // A diagonal spray: whatever region of the canvas the viewport
        // shows, several dabs land in it.
        for (var index = 0; index < 12; index += 1)
          BrushDab(
            center: CanvasPoint(x: 100.0 + index * 160, y: 100.0 + index * 110),
            color: inkArgb,
            size: 120,
            opacity: 1,
            flow: 1,
            hardness: 1,
            tipShape: BrushTipShape.round,
            pressure: 1,
            sequence: index,
          ),
      ],
    );
    return (s, 6);
  }

  Future<void> pumpArea(WidgetTester tester, EditorSessionManager session) async {
    final brushTool = ValueNotifier<BrushToolState>(BrushToolState.defaults);
    final cameraView = ValueNotifier<bool>(false);
    final cameraDim = ValueNotifier<double>(0.5);
    addTearDown(brushTool.dispose);
    addTearDown(cameraView.dispose);
    addTearDown(cameraDim.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: EditorCanvasArea(
            session: session,
            brushToolState: brushTool,
            cameraViewEnabled: cameraView,
            cameraDimOpacity: cameraDim,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// Drains the prerender scheduler's debounced warming (the established
  /// EditorCanvasArea test epilogue — its Future.delayed timers cannot be
  /// cancelled by dispose).
  Future<void> drainWarming(WidgetTester tester) async {
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
  }

  /// What the canvas area actually shows, as (paper, ink) pixel counts.
  Future<(int, int)> countColors(WidgetTester tester) async {
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find
          .descendant(
            of: find.byType(EditorCanvasArea),
            matching: find.byType(RepaintBoundary),
          )
          .first,
    );
    final image = (await tester.runAsync(() => boundary.toImage()))!;
    final bytes = (await tester.runAsync(
      () => image.toByteData(format: ui.ImageByteFormat.rawRgba),
    ))!;
    image.dispose();
    var paper = 0;
    var ink = 0;
    for (var offset = 0; offset < bytes.lengthInBytes; offset += 4) {
      final r = bytes.getUint8(offset);
      final g = bytes.getUint8(offset + 1);
      final b = bytes.getUint8(offset + 2);
      if (isPaper(r, g, b)) {
        paper += 1;
      } else if (isInk(r, g, b)) {
        ink += 1;
      }
    }
    return (paper, ink);
  }

  /// [countColors], giving asynchronous tile decodes a bounded number of
  /// real-async rounds to land — the committed ink reaches the screen when
  /// its tile images decode, and that is engine work a fake clock cannot run.
  Future<(int, int)> settledColors(WidgetTester tester) async {
    var counts = await countColors(tester);
    for (var round = 0; round < 20 && counts.$2 == 0; round += 1) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump();
      counts = await countColors(tester);
    }
    return counts;
  }

  testWidgets('standing past the end line, the canvas SHOWS the paper and '
      'the cel\'s ink — not just receives them', (tester) async {
    final (s, frameIndex) = sessionPastEnd();
    addTearDown(s.dispose);
    await pumpArea(tester, s);

    // The state the capture is a picture of, restated so a failure below
    // cannot be blamed on the session.
    expect(s.currentFrameIndex, frameIndex);
    expect(s.requireActiveCut.duration, 4);
    expect(s.editingPlayheadInGap, isFalse);

    final (paper, ink) = await settledColors(tester);
    expect(
      paper,
      greaterThan(5000),
      reason: 'the paper rectangle must be visible where the canvas is — it '
          'was painted all along and then covered by the cut-fade wash, '
          'which read "no material to compose" as "fade to backdrop"',
    );
    expect(
      ink,
      greaterThan(20),
      reason: 'the cel exposed past the end line draws like any other cel',
    );
    await drainWarming(tester);
  });

  testWidgets('the counter-pin: a REAL gap parking still shows NO paper', (
    tester,
  ) async {
    final (s, _) = sessionPastEnd();
    addTearDown(s.dispose);
    await pumpArea(tester, s);

    // Far past the cut AND past its authored extent, via the GLOBAL verb —
    // the one place "no cut here" is literally true (R16-⑥).
    s.selectGlobalFrame(50);
    await tester.pump();

    expect(s.editingPlayheadInGap, isTrue);
    final (paper, ink) = await countColors(tester);
    expect(
      paper,
      0,
      reason: 'a gap has no cut, so the void shows no paper — the fix must '
          'not resurrect it',
    );
    expect(ink, 0, reason: 'and no cel either');
    await drainWarming(tester);
  });
}
