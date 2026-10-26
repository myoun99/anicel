import 'package:flutter/gestures.dart'
    show PointerDeviceKind, kPrimaryButton, kPrimaryStylusButton;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/app_input_settings.dart';
import 'package:anicel/src/models/brush_frame_key.dart';
import 'package:anicel/src/ui/canvas/stroke_in_flight.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/editor_workspace.dart';
import 'package:anicel/src/ui/home_page.dart';
import 'package:anicel/src/ui/session/layer_stack.dart';

import '../helpers/panel_finders.dart' show visibleCanvasPoint;

/// F-482 (유저 2026-10-27): 「지우개로 지우는 동작도 빈 블록에서 클릭시작시
/// 블록 채워지고 끝나면 빈블록됨. 없던 블록에서 지우는 동작은 블록 채우지
/// 않도록 근본/구조적으로」.
///
/// A cel counts as drawn from pen-down, and that asked only whether a
/// stroke was in flight — so an eraser on an empty block turned it white
/// until the pen lifted.
///
/// The collaborator the answer lives in, named so `tool/mutation_run.dart`
/// runs this file for it.
LayerStack layerStackOf(EditorSessionManager s) => s.layerStack;

void main() {
  /// The app on the bare project, standing on a cel made empty at frame 0.
  Future<EditorSessionManager> openOnAnEmptyCel(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1600, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(home: HomePage(initialProject: createDefaultProject())),
    );
    await tester.pumpAndSettle();
    final session = tester
        .widget<EditorWorkspace>(find.byType(EditorWorkspace))
        .session;
    session.selectFrameIndex(0);
    session.createDrawingAtCurrentFrame();
    await tester.pumpAndSettle();
    return session;
  }

  BrushFrameKey standingKey(EditorSessionManager s) => s.brushFrameKeyForCut(
    s.requireActiveCut,
    s.activeLayerId!,
    s.selectedFrame!.id,
  );

  bool blockIsWhite(EditorSessionManager s) =>
      layerStackOf(s).celHasContentForLayer(s.activeLayer!, 0);

  bool storeHoldsAPicture(EditorSessionManager s) =>
      s.renderCaches.brushFrameStore.celHasRenderableContent(standingKey(s));

  /// A stroke from the pen down to it lifting, [whileDown] asked twice on
  /// the way — at the press and after a move.
  Future<void> stroke(
    WidgetTester tester, {
    int buttons = kPrimaryButton,
    required void Function(String when) whileDown,
  }) async {
    final press = await tester.startGesture(
      visibleCanvasPoint(tester),
      kind: PointerDeviceKind.stylus,
      buttons: buttons,
    );
    await tester.pump();
    await press.moveBy(const Offset(40, 30));
    await tester.pump();
    whileDown('at the press');
    await press.moveBy(const Offset(30, 20));
    await tester.pump();
    whileDown('along the line');
    await press.up();
    await tester.pumpAndSettle();
  }

  testWidgets('a brush on an empty block turns it white at pen-down — the '
      'control the eraser is held against', (tester) async {
    final s = await openOnAnEmptyCel(tester);
    expect(blockIsWhite(s), isFalse, reason: 'premise: an empty cel');

    await stroke(
      tester,
      whileDown: (when) {
        expect(s.canvasStroke.value, StrokeInFlight.paints, reason: when);
        expect(blockIsWhite(s), isTrue, reason: when);
      },
    );
    expect(storeHoldsAPicture(s), isTrue, reason: 'premise: it landed');
    expect(blockIsWhite(s), isTrue);

    s.playbackRig.prerenderScheduler.cancel();
  });

  testWidgets('the eraser on an empty block leaves it grey from pen-down '
      'to pen-up, and moves no row', (tester) async {
    final s = await openOnAnEmptyCel(tester);
    await tester.tap(find.byKey(const ValueKey<String>('tool-eraser-button')));
    await tester.pumpAndSettle();
    expect(blockIsWhite(s), isFalse, reason: 'premise: an empty cel');
    final tint = layerStackOf(s).celTintRevision;
    final before = tint.value;

    await stroke(
      tester,
      whileDown: (when) {
        expect(
          s.brushInputActive.value,
          isTrue,
          reason: 'premise: a stroke is in flight $when',
        );
        expect(s.canvasStroke.value, StrokeInFlight.erases, reason: when);
        expect(blockIsWhite(s), isFalse, reason: 'still grey $when');
        expect(s.pixelVerbs.canOpenColourEdit, isFalse, reason: when);
      },
    );
    expect(s.canvasStroke.value, StrokeInFlight.none, reason: 'premise');
    expect(storeHoldsAPicture(s), isFalse, reason: 'nothing to erase');
    expect(blockIsWhite(s), isFalse);
    expect(
      tint.value,
      before,
      reason: 'no block changed, so no row is painted again',
    );

    s.playbackRig.prerenderScheduler.cancel();
  });

  testWidgets('a press the pen\'s button maps to the eraser leaves the block '
      'grey the same way — the stroke erases by its own settings while the '
      'tool is still the brush', (tester) async {
    final kept = AppInput.settings.value;
    addTearDown(() => AppInput.settings.value = kept);
    AppInput.settings.value = const AppInputSettings(
      canvasRightClick: CanvasPointerMapping(
        action: CanvasPointerAction.eraser,
      ),
    );
    final s = await openOnAnEmptyCel(tester);
    expect(blockIsWhite(s), isFalse, reason: 'premise: an empty cel');

    await stroke(
      tester,
      buttons: kPrimaryButton | kPrimaryStylusButton,
      whileDown: (when) {
        expect(s.canvasStroke.value, StrokeInFlight.erases, reason: when);
        expect(blockIsWhite(s), isFalse, reason: 'still grey $when');
      },
    );
    expect(blockIsWhite(s), isFalse);

    s.playbackRig.prerenderScheduler.cancel();
  });
}
