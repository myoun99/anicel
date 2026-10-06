import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/app_input_settings.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_viewport.dart';
import 'package:anicel/src/models/tile_coord.dart';
import 'package:anicel/src/services/brush_frame_editing_coordinator.dart';
import 'package:anicel/src/services/cut_piece_slot.dart';
import 'package:anicel/src/services/input/raw_pen_input_service.dart';
import 'package:anicel/src/native/qa_tablet_bridge.dart';
import 'package:anicel/src/ui/brush/brush_canvas_panel.dart';
import 'package:anicel/src/ui/brush/brush_edit_cache_invalidation_sink.dart';
import 'package:anicel/src/ui/brush/brush_tool_state.dart';
import 'package:anicel/src/ui/brush/canvas_selection_commands.dart';
import 'package:anicel/src/ui/brush/temporary_tool.dart';
import 'package:anicel/src/ui/canvas/canvas_pan_hold.dart';
import 'package:anicel/src/ui/input/control_press_claim.dart';
import 'package:anicel/src/ui/shortcuts/editor_action_registry.dart';

import '../helpers/brush_canvas_fixture.dart';
import '../helpers/device_viewport.dart';

/// 🚨★★★**WHAT A MAPPED BUTTON DOES THAT IS NOT DRAWING ANSWERS UNDER
/// EVERY TOOL, WITH OR WITHOUT A CEL** (F-299, 유저 2026-10-05: 「어떤 도구
/// 들고있던 규칙 만들지말고 법 통일해서 작동하도록」).
///
/// A pen's barrel button and the mouse's right button are mapped on the
/// canvas (Input Settings ▸ Canvas — the eyedropper by default; undo and
/// redo by choice). ↩️The drawing view read them, and it hears a press only
/// while a drawing tool is armed over a cel: measured 2026-10-06, the held
/// eyedropper answered under the brush, the eraser and the bucket and under
/// none of the other seven tools, and under no tool at all on a frame with
/// no cel.
///
/// The panel reads them now, where every press on the canvas passes. These
/// drive a panel wired as the shell wires one — a hold goes through the
/// real [TemporaryTool] — across the whole matrix: ten tools × three
/// grounds × the roads a button is pressed by.
///
/// 🚨★★★**AND A PRESS THAT ERASES ERASES UNDER EVERY TOOL** — the other
/// half of the same table (`mapped-eraser-and-pen-tail-under-every-tool`).
/// A button mapped to the eraser and the pen's tail DRAW, so their stroke
/// is the drawing view's; 🧪measured 2026-10-07, their four roads (a mouse
/// button · a pen's barrel pressed in hover and then touched down · a
/// barrel down at the contact · the pen turned over) erased under the
/// brush, the eraser, the bucket and the guide, and under none of the six
/// tools whose own layer lies over that view. The panel reads the tail in
/// the air and hands the view the press it could not hear.
void main() {
  tearDown(() {
    AppInput.settings.value = AppInputSettings.testCorpusBaseline;
    CanvasPanHold.held.value = false;
  });

  for (final ground in _Ground.values) {
    for (final tool in CanvasTool.values) {
      final where = '${tool.name}, ${ground.said}';

      testWidgets('🚨a held RIGHT button is the eyedropper: the tool is '
          'taken, it picks at the press and along the drag, and the tool '
          'comes back ($where)', (tester) async {
        final shell = await _Shell.pump(tester, tool: tool, ground: ground);

        final right = await tester.startGesture(
          shell.at(const Offset(10, 10)),
          kind: PointerDeviceKind.mouse,
          buttons: kSecondaryMouseButton,
        );
        await tester.pump();
        expect(shell.tool, CanvasTool.eyedropper, reason: 'while it is held');
        expect(shell.picked, [const Offset(10, 10)], reason: 'at the press');

        await right.moveTo(shell.at(const Offset(40, 12)));
        await tester.pump();
        expect(
          shell.picked,
          [const Offset(10, 10), const Offset(40, 12)],
          reason: 'live along the drag — and ONCE a move, whatever layer '
              'the tool switch put under the pointer',
        );

        await right.up();
        await tester.pump();
        expect(shell.tool, tool, reason: 'let go, and the tool is back');
        expect(shell.holds, [CanvasTool.eyedropper]);
        expect(shell.releases, [false], reason: 'returnToTool = spring back');
        expect(shell.drewSomething, isFalse, reason: 'a pick writes nothing');
      });

      testWidgets('🚨a pen\'s BARREL pressed in hover is the eyedropper too, '
          'with no contact at all — and let go in hover gives the tool back '
          '($where)', (tester) async {
        final shell = await _Shell.pump(tester, tool: tool, ground: ground);

        await shell.hover(tester, const Offset(20, 20), buttons: 0);
        expect(shell.tool, tool, reason: '⛔premise: hovering holds nothing');
        await shell.hover(
          tester,
          const Offset(20, 20),
          buttons: kPrimaryStylusButton,
        );
        expect(shell.tool, CanvasTool.eyedropper, reason: 'on the press edge');
        expect(shell.picked, isEmpty, reason: 'the pick waits for contact');

        await shell.hover(tester, const Offset(24, 20), buttons: 0);
        expect(shell.tool, tool, reason: 'on the release edge');
        expect(shell.releases, [false]);
      });

      testWidgets('🚨a button mapped to UNDO fires it once at the press '
          '($where)', (tester) async {
        AppInput.settings.value = const AppInputSettings(
          canvasRightClick: CanvasPointerMapping(
            action: CanvasPointerAction.undo,
          ),
        );
        final shell = await _Shell.pump(tester, tool: tool, ground: ground);

        final right = await tester.startGesture(
          shell.at(const Offset(10, 10)),
          kind: PointerDeviceKind.mouse,
          buttons: kSecondaryMouseButton,
        );
        await tester.pump();
        await right.moveTo(shell.at(const Offset(30, 10)));
        await right.up();
        await tester.pump();

        expect(shell.invoked, [EditorActionIds.undo]);
        expect(shell.holds, isEmpty, reason: 'a one-shot holds no tool');
        expect(shell.tool, tool);
        expect(shell.drewSomething, isFalse);
      });
    }
  }

  for (final tool in CanvasTool.values) {
    group('a press that ERASES, with the ${tool.name} in hand', () {
      const eraserOnTheBarrel = AppInputSettings(
        canvasRightClick: CanvasPointerMapping(
          action: CanvasPointerAction.eraser,
        ),
      );
      const tipAndBarrel = kPrimaryButton | kPrimaryStylusButton;

      /// The whole of what an erasing press may do: one hold on the eraser,
      /// given back, the ink under it gone — and nothing of the tool that
      /// was in hand.
      void expectItErasedAndNothingElse(_Shell shell) {
        expect(shell.inkAt(40, 30), 0, reason: 'erased along the drag');
        expect(shell.holds, [CanvasTool.eraser], reason: 'ONE hold');
        expect(shell.releases, [false], reason: 'spring back');
        expect(shell.tool, tool, reason: 'and the tool is back');
        expect(shell.picked, isEmpty, reason: 'no pick');
        expect(shell.selection.region, isNull, reason: 'no marquee');
        expect(_tester(shell).takeException(), isNull);
      }

      testWidgets('🚨a MOUSE button mapped to the eraser erases with that '
          'very press, along its drag', (tester) async {
        AppInput.settings.value = eraserOnTheBarrel;
        final shell = await _Shell.inked(tester, tool: tool);

        final right = await tester.startGesture(
          shell.at(const Offset(20, 30)),
          kind: PointerDeviceKind.mouse,
          buttons: kSecondaryMouseButton,
        );
        await tester.pump();
        expect(shell.tool, CanvasTool.eraser, reason: 'while it is held');
        await right.moveTo(shell.at(const Offset(40, 30)));
        await tester.pump();
        await right.moveTo(shell.at(const Offset(60, 30)));
        await tester.pump();
        await right.up();
        await tester.pump();

        expectItErasedAndNothingElse(shell);
      });

      testWidgets("🚨a pen's BARREL pressed in hover and then touched down "
          'erases from the contact — the hover alone takes no tool, as under '
          'the brush', (tester) async {
        AppInput.settings.value = eraserOnTheBarrel;
        final shell = await _Shell.inked(tester, tool: tool);

        await shell.hover(tester, const Offset(20, 30), buttons: 0);
        await shell.hover(
          tester,
          const Offset(20, 30),
          buttons: kPrimaryStylusButton,
        );
        expect(shell.holds, isEmpty, reason: 'the eraser arrives with a press');
        await shell.contact(
          tester,
          const Offset(20, 30),
          buttons: tipAndBarrel,
        );
        expect(shell.tool, CanvasTool.eraser);
        await shell.contactMoves(
          tester,
          const Offset(60, 30),
          buttons: tipAndBarrel,
        );
        await shell.contactLifts(tester, const Offset(60, 30));
        await shell.hover(tester, const Offset(60, 30), buttons: 0);

        expectItErasedAndNothingElse(shell);
      });

      testWidgets('🚨a barrel already DOWN at the contact erases with it', (
        tester,
      ) async {
        AppInput.settings.value = eraserOnTheBarrel;
        final shell = await _Shell.inked(tester, tool: tool);

        await shell.contact(
          tester,
          const Offset(20, 30),
          buttons: tipAndBarrel,
        );
        expect(shell.tool, CanvasTool.eraser);
        await shell.contactMoves(
          tester,
          const Offset(60, 30),
          buttons: tipAndBarrel,
        );
        await shell.contactLifts(tester, const Offset(60, 30));

        expectItErasedAndNothingElse(shell);
      });

      testWidgets('🚨the pen turned TAIL-DOWN is the eraser from the flip — '
          'in the air, before it touches — and until it is turned back',
          (tester) async {
        final shell = await _Shell.inked(tester, tool: tool);
        final raw = _rawPen();

        // HID Invert with nothing touching: turned over in the air.
        raw.debugInjectState(const QaPenRawState(flags: 0x08, sequence: 1));
        await shell.hover(tester, const Offset(20, 30), buttons: 0);
        expect(shell.tool, CanvasTool.eraser, reason: 'at the flip');
        expect(shell.inkAt(40, 30), 255, reason: '⛔premise: nothing yet');

        // The tail touches: HID Eraser beside the Invert.
        raw.debugInjectState(
          const QaPenRawState(flags: 0x08 | 0x04, sequence: 2),
        );
        await shell.contact(
          tester,
          const Offset(20, 30),
          buttons: kPrimaryButton,
        );
        await shell.contactMoves(
          tester,
          const Offset(60, 30),
          buttons: kPrimaryButton,
        );
        await shell.contactLifts(tester, const Offset(60, 30));
        raw.debugInjectState(const QaPenRawState(flags: 0x08, sequence: 3));
        await shell.hover(tester, const Offset(60, 30), buttons: 0);
        expect(shell.tool, CanvasTool.eraser, reason: 'lifted, still turned');
        expect(shell.releases, isEmpty, reason: 'one flip, one erasing pass');

        raw.debugInjectState(const QaPenRawState(flags: 0, sequence: 4));
        await shell.hover(tester, const Offset(60, 30), buttons: 0);

        expectItErasedAndNothingElse(shell);
        raw.debugReset();
      });

      testWidgets('🚨a tail whose FIRST report is the contact erases with '
          'that contact — and it is not a press of the tool in hand', (
        tester,
      ) async {
        final shell = await _Shell.inked(tester, tool: tool);
        final raw = _rawPen();

        // No hover came first: the driver reports nothing in the air.
        raw.debugInjectState(
          const QaPenRawState(flags: 0x08 | 0x04, sequence: 1),
        );
        await shell.contact(
          tester,
          const Offset(20, 30),
          buttons: kPrimaryButton,
        );
        expect(shell.holds, [CanvasTool.eraser], reason: 'at the contact');
        await shell.contactMoves(
          tester,
          const Offset(60, 30),
          buttons: kPrimaryButton,
        );
        await shell.contactLifts(tester, const Offset(60, 30));
        raw.debugInjectState(const QaPenRawState(flags: 0, sequence: 2));
        await shell.hover(tester, const Offset(60, 30), buttons: 0);

        expectItErasedAndNothingElse(shell);
        raw.debugReset();
      });

      for (final ground in [_Ground.emptyFrame, _Ground.nothingDrawn]) {
        testWidgets('with no cel to erase (${ground.said}), the button '
            'holds nothing — and the frame is asked for as often as under '
            'any other tool', (tester) async {
          AppInput.settings.value = eraserOnTheBarrel;
          final shell = await _Shell.pump(tester, tool: tool, ground: ground);

          final right = await tester.startGesture(
            shell.at(const Offset(20, 30)),
            kind: PointerDeviceKind.mouse,
            buttons: kSecondaryMouseButton,
          );
          await tester.pump();
          await right.moveTo(shell.at(const Offset(60, 30)));
          await right.up();
          await tester.pump();

          expect(shell.holds, isEmpty);
          expect(shell.tool, tool);
          expect(
            shell.cellAsks,
            ground == _Ground.emptyFrame ? 1 : 0,
            reason: 'ONCE where a view stands down on the frame, whether it '
                'heard the press or was handed it; never where none is built',
          );
          expect(shell.drewSomething, isFalse);
          expect(tester.takeException(), isNull);
        });

        testWidgets('with no cel to erase (${ground.said}), the tail still '
            'holds the tool from the flip', (tester) async {
          final shell = await _Shell.pump(tester, tool: tool, ground: ground);
          final raw = _rawPen();

          raw.debugInjectState(const QaPenRawState(flags: 0x08, sequence: 1));
          await shell.hover(tester, const Offset(20, 30), buttons: 0);
          expect(shell.tool, CanvasTool.eraser);

          raw.debugInjectState(const QaPenRawState(flags: 0, sequence: 2));
          await shell.hover(tester, const Offset(20, 30), buttons: 0);
          expect(shell.tool, tool);
          expect(shell.holds, [CanvasTool.eraser]);
          expect(shell.releases, [false]);
          expect(tester.takeException(), isNull);
          raw.debugReset();
        });
      }
    });
  }

  group('a press handed to the drawing view', () {
    const eraserOnTheBarrel = AppInputSettings(
      canvasRightClick: CanvasPointerMapping(
        action: CanvasPointerAction.eraser,
      ),
    );

    testWidgets('a 「keep」 release leaves the eraser in hand', (tester) async {
      AppInput.settings.value = const AppInputSettings(
        canvasRightClick: CanvasPointerMapping(
          action: CanvasPointerAction.eraser,
          release: CanvasPointerRelease.keep,
        ),
      );
      final shell = await _Shell.inked(tester, tool: CanvasTool.select);

      final right = await tester.startGesture(
        shell.at(const Offset(20, 30)),
        kind: PointerDeviceKind.mouse,
        buttons: kSecondaryMouseButton,
      );
      await tester.pump();
      await right.moveTo(shell.at(const Offset(60, 30)));
      await right.up();
      await tester.pump();

      expect(shell.inkAt(40, 30), 0);
      expect(shell.releases, [true]);
      expect(shell.tool, CanvasTool.eraser, reason: 'kept');
    });

    testWidgets('🚨ONE at a time: a second erasing press while one is being '
        'drawn waits its turn, and the first still lands and lets go', (
      tester,
    ) async {
      AppInput.settings.value = eraserOnTheBarrel;
      final shell = await _Shell.inked(tester, tool: CanvasTool.select);

      final right = await tester.startGesture(
        shell.at(const Offset(20, 30)),
        kind: PointerDeviceKind.mouse,
        buttons: kSecondaryMouseButton,
      );
      await right.moveTo(shell.at(const Offset(40, 30)));
      // A pen comes down beside it with its barrel held.
      await shell.contact(
        tester,
        const Offset(20, 60),
        buttons: kPrimaryButton | kPrimaryStylusButton,
      );
      await right.moveTo(shell.at(const Offset(60, 30)));
      await right.up();
      await tester.pump();

      expect(shell.inkAt(40, 30), 0, reason: 'the first stroke landed');
      expect(shell.holds, [CanvasTool.eraser], reason: 'one hold, not two');
      expect(shell.releases, [false], reason: 'and it let go');
      await shell.contactLifts(tester, const Offset(20, 60));
      expect(shell.tool, CanvasTool.select);
    });

    testWidgets('🚨a marquee being dragged is not taken from under the hand '
        'by a barrel that goes down in the middle of it', (tester) async {
      AppInput.settings.value = eraserOnTheBarrel;
      final shell = await _Shell.inked(tester, tool: CanvasTool.select);

      await shell.contact(
        tester,
        const Offset(10, 10),
        buttons: kPrimaryButton,
      );
      await shell.contactMoves(
        tester,
        const Offset(50, 40),
        buttons: kPrimaryButton,
      );
      await shell.contactMoves(
        tester,
        const Offset(70, 50),
        buttons: kPrimaryButton | kPrimaryStylusButton,
      );
      await shell.contactLifts(tester, const Offset(70, 50));

      expect(shell.holds, isEmpty);
      expect(shell.inkAt(40, 30), 255, reason: 'nothing was erased');
      expect(shell.selection.region, isNotNull, reason: 'the marquee landed');
    });
  });

  testWidgets('a contact TAKES OVER a hover-engaged hold: one hold session, '
      'one release, and it picks from the contact on (R26 #19/#20)', (
    tester,
  ) async {
    final shell = await _Shell.pump(tester, tool: CanvasTool.select);
    await shell.hover(tester, const Offset(20, 20), buttons: 0);
    await shell.hover(
      tester,
      const Offset(20, 20),
      buttons: kPrimaryStylusButton,
    );
    expect(shell.tool, CanvasTool.eyedropper);

    // The tip touches with the barrel still held.
    final tip = await tester.startGesture(
      shell.at(const Offset(20, 20)),
      kind: PointerDeviceKind.stylus,
      buttons: kPrimaryButton | kPrimaryStylusButton,
    );
    await tester.pump();
    await tip.moveTo(shell.at(const Offset(50, 20)));
    await tester.pump();
    expect(shell.picked, [const Offset(20, 20), const Offset(50, 20)]);

    await tip.up();
    await tester.pump();
    expect(shell.tool, CanvasTool.select, reason: 'the lift ends the hold');
    expect(shell.releases, [false], reason: '⛔one session, ONE release');

    // The barrel coming up afterwards, in hover, has nothing left to end.
    await shell.hover(tester, const Offset(50, 20), buttons: 0);
    expect(shell.releases, [false]);
  });

  testWidgets('a barrel bit that RISES during contact is picked up — a '
      'driver that reports it a moment after the tip lands (R27 #17)', (
    tester,
  ) async {
    final shell = await _Shell.pump(
      tester,
      tool: CanvasTool.move,
      ground: _Ground.nothingDrawn,
    );
    await shell.contact(tester, const Offset(20, 20), buttons: kPrimaryButton);
    expect(shell.holds, isEmpty, reason: '⛔premise: a plain contact');

    await shell.contactMoves(
      tester,
      const Offset(22, 20),
      buttons: kPrimaryButton | kPrimaryStylusButton,
    );
    expect(shell.tool, CanvasTool.eyedropper);
    expect(shell.picked, [const Offset(22, 20)]);

    await shell.contactLifts(tester, const Offset(22, 20));
    expect(shell.tool, CanvasTool.move);
  });

  /// ⛔Only while nothing is in flight: a stroke, or a drag, is never taken
  /// over mid-line by a button that comes down during it.
  group('a button that goes down DURING a gesture leaves it alone', () {
    testWidgets('a stroke goes on to its end, and lands', (tester) async {
      final shell = await _Shell.pump(tester, tool: CanvasTool.brush);
      await shell.contact(
        tester,
        const Offset(20, 20),
        buttons: kPrimaryButton,
      );
      await shell.contactMoves(
        tester,
        const Offset(40, 20),
        buttons: kPrimaryButton,
      );

      await shell.contactMoves(
        tester,
        const Offset(60, 20),
        buttons: kPrimaryButton | kPrimaryStylusButton,
      );
      expect(shell.holds, isEmpty);
      expect(shell.tool, CanvasTool.brush);

      await shell.contactLifts(tester, const Offset(60, 20));
      expect(shell.drewSomething, isTrue, reason: 'the stroke landed');
      expect(shell.picked, isEmpty);
    });

    testWidgets('a marquee being dragged stays the marquee\'s', (tester) async {
      final shell = await _Shell.pump(tester, tool: CanvasTool.select);
      await shell.contact(
        tester,
        const Offset(20, 20),
        buttons: kPrimaryButton,
      );
      await shell.contactMoves(
        tester,
        const Offset(60, 50),
        buttons: kPrimaryButton,
      );

      await shell.contactMoves(
        tester,
        const Offset(80, 60),
        buttons: kPrimaryButton | kPrimaryStylusButton,
      );
      expect(shell.holds, isEmpty);
      expect(shell.tool, CanvasTool.select);

      await shell.contactLifts(tester, const Offset(80, 60));
    });
  });

  /// A hold takes the tool, a change of tool takes the tool's own layer
  /// away — and a pointer goes on reporting to the layer its down was
  /// hit-tested on. Under a held button that is every press on a selection
  /// tool (the matrix above); a tool key in the middle of a drag is the same
  /// fact with something still in hand.
  testWidgets('🚨the tool changed under a marquee still being dragged: the '
      'layer that is gone reads nothing of the rest of the drag', (
    tester,
  ) async {
    final shell = await _Shell.pump(tester, tool: CanvasTool.select);
    final drag = await tester.startGesture(
      shell.at(const Offset(20, 20)),
      kind: PointerDeviceKind.mouse,
      buttons: kPrimaryButton,
    );
    await tester.pump();
    await drag.moveTo(shell.at(const Offset(60, 50)));
    await tester.pump();

    shell.take(CanvasTool.brush);
    await tester.pump();
    await drag.moveTo(shell.at(const Offset(90, 70)));
    await tester.pump();
    await drag.up();
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(shell.drewSomething, isFalse, reason: 'the brush heard no press');
  });

  testWidgets('a button pressed in hover that fired UNDO does not fire it '
      'again when the tip touches with it held — and fires again on the '
      'next press (PEN-11)', (tester) async {
    AppInput.settings.value = const AppInputSettings(
      canvasRightClick: CanvasPointerMapping(action: CanvasPointerAction.undo),
    );
    final shell = await _Shell.pump(tester, tool: CanvasTool.cut);

    await shell.hover(tester, const Offset(10, 10), buttons: 0);
    await shell.hover(
      tester,
      const Offset(10, 10),
      buttons: kPrimaryStylusButton,
    );
    expect(shell.invoked, [EditorActionIds.undo], reason: 'with no contact');

    final tip = await tester.startGesture(
      shell.at(const Offset(10, 10)),
      kind: PointerDeviceKind.stylus,
      buttons: kPrimaryButton | kPrimaryStylusButton,
    );
    await tester.pump();
    await tip.up();
    await tester.pump();
    expect(shell.invoked, [EditorActionIds.undo], reason: '⛔no double');

    await shell.hover(tester, const Offset(10, 10), buttons: 0);
    await shell.hover(
      tester,
      const Offset(10, 10),
      buttons: kPrimaryStylusButton,
    );
    expect(shell.invoked, [EditorActionIds.undo, EditorActionIds.undo]);
  });

  testWidgets('REDO is read the same way, and a 「keep」 release leaves the '
      'eyedropper in hand', (tester) async {
    AppInput.settings.value = const AppInputSettings(
      canvasRightClick: CanvasPointerMapping(action: CanvasPointerAction.redo),
      canvasWheelClick: CanvasPointerMapping(
        action: CanvasPointerAction.eyedropper,
        release: CanvasPointerRelease.keep,
      ),
    );
    final shell = await _Shell.pump(tester, tool: CanvasTool.fillShape);

    final right = await tester.startGesture(
      shell.at(const Offset(10, 10)),
      kind: PointerDeviceKind.mouse,
      buttons: kSecondaryMouseButton,
    );
    await right.up();
    await tester.pump();
    expect(shell.invoked, [EditorActionIds.redo]);

    final wheel = await tester.startGesture(
      shell.at(const Offset(10, 10)),
      kind: PointerDeviceKind.mouse,
      buttons: kMiddleMouseButton,
    );
    await tester.pump();
    await wheel.up();
    await tester.pump();
    expect(shell.releases, [true]);
    expect(shell.tool, CanvasTool.eyedropper, reason: 'keep = it stays');
  });

  group('what stands a mapped button down', () {
    testWidgets('a button mapped to 「none」 does nothing under any tool', (
      tester,
    ) async {
      AppInput.settings.value = const AppInputSettings(
        canvasRightClick: CanvasPointerMapping(
          action: CanvasPointerAction.none,
        ),
      );
      for (final tool in CanvasTool.values) {
        final shell = await _Shell.pump(tester, tool: tool);
        final right = await tester.startGesture(
          shell.at(const Offset(10, 10)),
          kind: PointerDeviceKind.mouse,
          buttons: kSecondaryMouseButton,
        );
        await tester.pump();
        await right.moveTo(shell.at(const Offset(30, 10)));
        await right.up();
        await tester.pump();

        expect(shell.holds, isEmpty, reason: tool.name);
        expect(shell.invoked, isEmpty, reason: tool.name);
        expect(shell.picked, isEmpty, reason: tool.name);
        expect(shell.drewSomething, isFalse, reason: tool.name);
      }
    });

    testWidgets('🚨a press that landed on a CONTROL is that control\'s — the '
        'button over it holds nothing', (tester) async {
      var pressed = 0;
      final shell = await _Shell.pump(
        tester,
        tool: CanvasTool.brush,
        controls: (context, viewport) => Align(
          alignment: Alignment.topLeft,
          child: ControlPressClaim(
            onPressed: () => pressed += 1,
            child: const ColoredBox(
              key: ValueKey<String>('a-control-on-the-canvas'),
              color: Color(0xFF808080),
              child: SizedBox(width: 60, height: 60),
            ),
          ),
        ),
      );
      final onTheControl = tester.getCenter(
        find.byKey(const ValueKey<String>('a-control-on-the-canvas')),
      );

      final right = await tester.startGesture(
        onTheControl,
        kind: PointerDeviceKind.mouse,
        buttons: kSecondaryMouseButton,
      );
      await tester.pump();
      await right.moveTo(onTheControl + const Offset(4, 0));
      await right.up();
      await tester.pump();

      expect(shell.holds, isEmpty);
      expect(shell.picked, isEmpty);

      // …nor a barrel that comes down while the pen is pressing the control.
      final onIt = onTheControl - shell.at(Offset.zero);
      await shell.contact(tester, onIt, buttons: kPrimaryButton);
      await shell.contactMoves(
        tester,
        onIt + const Offset(3, 0),
        buttons: kPrimaryButton | kPrimaryStylusButton,
      );
      expect(shell.holds, isEmpty, reason: 'the press is still the control\'s');
      await shell.contactLifts(tester, onIt);

      // ⛔Not because the button is dead here: beside the control it holds.
      final beside = await tester.startGesture(
        shell.at(const Offset(200, 200)),
        kind: PointerDeviceKind.mouse,
        buttons: kSecondaryMouseButton,
      );
      await tester.pump();
      expect(shell.holds, [CanvasTool.eyedropper]);
      await beside.up();
      await tester.pump();
    });

    testWidgets('🚨content that takes no tool takes no mapped button either '
        '— playback (T28-c 「뭘 누르든 입력이 존재하면 정지」)', (tester) async {
      final shell = await _Shell.pump(
        tester,
        tool: CanvasTool.brush,
        ground: _Ground.nothingDrawn,
        toolInput: false,
      );
      await shell.hover(tester, const Offset(10, 10), buttons: 0);
      await shell.hover(
        tester,
        const Offset(10, 10),
        buttons: kPrimaryStylusButton,
      );
      final right = await tester.startGesture(
        shell.at(const Offset(10, 10)),
        kind: PointerDeviceKind.mouse,
        buttons: kSecondaryMouseButton,
      );
      await tester.pump();
      await right.up();
      await tester.pump();

      expect(shell.holds, isEmpty);
      expect(shell.picked, isEmpty);
    });

    testWidgets('🚨while the 「이동」 key is held every tool stands down for '
        'the pan — a mapped button with them (I-15)', (tester) async {
      final shell = await _Shell.pump(tester, tool: CanvasTool.select);
      CanvasPanHold.held.value = true;
      await tester.pump();

      final right = await tester.startGesture(
        shell.at(const Offset(10, 10)),
        kind: PointerDeviceKind.mouse,
        buttons: kSecondaryMouseButton,
      );
      await tester.pump();
      await right.up();
      await tester.pump();

      expect(shell.holds, isEmpty);
      expect(shell.picked, isEmpty);
    });

    testWidgets('a FINGER has no buttons: a touch holds nothing', (
      tester,
    ) async {
      final shell = await _Shell.pump(
        tester,
        tool: CanvasTool.move,
        ground: _Ground.nothingDrawn,
      );
      // Whatever bits a touch event carries, at its down or along its way.
      await shell.contact(
        tester,
        const Offset(10, 10),
        buttons: kSecondaryButton,
        kind: PointerDeviceKind.touch,
      );
      await shell.contactMoves(
        tester,
        const Offset(14, 10),
        buttons: kPrimaryButton | kSecondaryButton,
        kind: PointerDeviceKind.touch,
      );
      await shell.contactLifts(
        tester,
        const Offset(14, 10),
        kind: PointerDeviceKind.touch,
      );

      expect(shell.holds, isEmpty);
    });

    testWidgets('🚨a pen turned TAIL-DOWN holds the tool, and a barrel press '
        'does not take it from under the tail', (tester) async {
      final raw = RawPenInputService.instance;
      addTearDown(raw.debugReset);
      RawPenInputService.debugClockOverride = () => DateTime(2024);
      raw.debugPollOverride = () => null; // reports are injected below
      raw.start();
      final shell = await _Shell.pump(tester, tool: CanvasTool.brush);

      // ⚠️While the raw pen service runs, ITS report is the buttons to
      // believe (`canvasPressButtons`) — the hover event's own are not read.
      // HID Invert with nothing touching: the pen is turned over in the air.
      raw.debugInjectState(const QaPenRawState(flags: 0x08, sequence: 1));
      await shell.hover(tester, const Offset(20, 20), buttons: 0);
      expect(shell.tool, CanvasTool.eraser, reason: '⛔premise: the tail');

      // …and the barrel goes down with the pen still turned over.
      raw.debugInjectState(
        const QaPenRawState(flags: 0x08 | 0x02, sequence: 2),
      );
      await shell.hover(
        tester,
        const Offset(20, 20),
        buttons: kPrimaryStylusButton,
      );
      expect(shell.tool, CanvasTool.eraser, reason: 'the tail keeps the tool');
      expect(shell.holds, [CanvasTool.eraser]);

      raw.debugReset();
    });

    testWidgets('…and a pen turned over under a held pick does not take the '
        'tool from under the button either', (tester) async {
      final raw = RawPenInputService.instance;
      addTearDown(raw.debugReset);
      RawPenInputService.debugClockOverride = () => DateTime(2024);
      raw.debugPollOverride = () => null;
      raw.start();
      final shell = await _Shell.pump(tester, tool: CanvasTool.brush);

      raw.debugInjectState(const QaPenRawState(flags: 0, sequence: 1));
      await shell.hover(tester, const Offset(20, 20), buttons: 0);
      // The barrel, as the driver reports it — and the flip in the SAME
      // frame. ⚠️That is the whole case: a frame later the eyedropper's own
      // layer lies over the drawing view, which then hears no hover and
      // reads no tail at all (the first form of this pin pumped between
      // the two, and passed with the guard taken out — measured).
      raw.debugInjectState(const QaPenRawState(flags: 0x02, sequence: 2));
      await shell.hover(
        tester,
        const Offset(20, 20),
        buttons: kPrimaryStylusButton,
        settle: false,
      );
      expect(shell.holds, [CanvasTool.eyedropper], reason: '⛔premise: held');

      // Turned over with the barrel still held.
      raw.debugInjectState(
        const QaPenRawState(flags: 0x08 | 0x02, sequence: 3),
      );
      await shell.hover(
        tester,
        const Offset(22, 20),
        buttons: kPrimaryStylusButton,
      );
      expect(shell.holds, [CanvasTool.eyedropper], reason: 'no second hold');
      expect(shell.tool, CanvasTool.eyedropper);

      raw.debugReset();
    });
  });

  /// The eyedropper's own layer hears every pointer that crosses it. A
  /// press it refused at its down is not its press, and a move alone never
  /// said whose it was.
  group('the eyedropper tool, with a mapped button down', () {
    testWidgets('🚨a button mapped to the PAN picks no colour along its '
        'drag', (tester) async {
      AppInput.settings.value = const AppInputSettings(
        canvasRightClick: CanvasPointerMapping(action: CanvasPointerAction.pan),
      );
      final shell = await _Shell.pump(tester, tool: CanvasTool.eyedropper);

      final right = await tester.startGesture(
        shell.at(const Offset(10, 10)),
        kind: PointerDeviceKind.mouse,
        buttons: kSecondaryMouseButton,
      );
      await tester.pump();
      await right.moveTo(shell.at(const Offset(60, 10)));
      await tester.pump();
      await right.up();
      await tester.pump();

      expect(shell.picked, isEmpty);
    });

    testWidgets('…and its own PRIMARY press still picks, at the press and '
        'all along the drag (TS7)', (tester) async {
      final shell = await _Shell.pump(tester, tool: CanvasTool.eyedropper);

      final left = await tester.startGesture(
        shell.at(const Offset(10, 10)),
        kind: PointerDeviceKind.mouse,
        buttons: kPrimaryButton,
      );
      await tester.pump();
      await left.moveTo(shell.at(const Offset(60, 10)));
      await tester.pump();
      await left.up();
      await tester.pump();

      expect(shell.picked, [const Offset(10, 10), const Offset(60, 10)]);
    });

    testWidgets('…and a finger\'s drag that had DECLARED itself keeps '
        'sampling when a palm comes to rest beside it (PEN-12 #4)', (
      tester,
    ) async {
      // One finger draws — the corpus baseline.
      AppInput.settings.value = AppInputSettings.testCorpusBaseline;
      final shell = await _Shell.pump(tester, tool: CanvasTool.eyedropper);

      final finger = await tester.startGesture(
        shell.at(const Offset(100, 100)),
        kind: PointerDeviceKind.touch,
      );
      await tester.pump();
      await finger.moveTo(shell.at(const Offset(140, 100)));
      await tester.pump();
      final before = shell.picked.length;
      expect(before, greaterThan(0), reason: '⛔premise: past the slop');

      final palm = await tester.startGesture(
        shell.at(const Offset(300, 300)),
        kind: PointerDeviceKind.touch,
      );
      await tester.pump();
      await finger.moveTo(shell.at(const Offset(180, 100)));
      await tester.pump();
      expect(shell.picked.length, greaterThan(before));

      await finger.up();
      await palm.up();
      await tester.pump();
    });

    testWidgets('🚨a tap that turned out to be a PINCH picks nothing, '
        'however its fingers move', (tester) async {
      // One finger draws — the corpus baseline.
      AppInput.settings.value = AppInputSettings.testCorpusBaseline;
      final shell = await _Shell.pump(tester, tool: CanvasTool.eyedropper);

      final first = await tester.startGesture(
        shell.at(const Offset(100, 100)),
        kind: PointerDeviceKind.touch,
      );
      await tester.pump();
      final second = await tester.startGesture(
        shell.at(const Offset(160, 100)),
        kind: PointerDeviceKind.touch,
      );
      await tester.pump();
      await first.moveTo(shell.at(const Offset(60, 100)));
      await second.moveTo(shell.at(const Offset(220, 100)));
      await tester.pump();
      await first.up();
      await second.up();
      await tester.pump();

      expect(shell.picked, isEmpty);
    });
  });
}

/// What the playhead stands on.
enum _Ground {
  cel('on a cel'),
  emptyFrame('on a frame with no cel'),
  nothingDrawn('with nothing ever drawn');

  const _Ground(this.said);

  final String said;
}

/// A canvas panel wired as the shell wires one: the tool lives on a
/// notifier, and a hold goes through the real [TemporaryTool].
class _Shell {
  _Shell._(this._tester, this._brush, this._coordinator);

  final WidgetTester _tester;
  final ValueNotifier<BrushToolState> _brush;
  final BrushFrameEditingCoordinator _coordinator;

  final holds = <CanvasTool>[];
  final releases = <bool>[];
  final invoked = <String>[];

  /// Where each pick was sampled, on the CANVAS.
  final picked = <Offset>[];

  /// The canvas's selection — a tool layer that acted on a press it should
  /// have left alone shows here.
  final selection = CanvasSelectionCommands();

  /// How often a press asked the shell for a cel (I-10).
  int cellAsks = 0;

  /// The alpha of the cel's pixel at ([x], [y]) — 0 where nothing is drawn
  /// or what was drawn is erased.
  int inkAt(int x, int y) {
    final surface = _coordinator.frameStore.hotBakedSurfaceOrNull(
      _coordinator.activeFrameKey,
    );
    if (surface == null) {
      return 0;
    }
    final size = surface.tileSize;
    final tile = surface.tileAt(TileCoord(x: x ~/ size, y: y ~/ size));
    return tile == null
        ? 0
        : tile.pixels[tile.byteOffsetForPixel(x: x % size, y: y % size) + 3];
  }

  /// A shell on a cel with a line of ink along y = 30 — drawn with the
  /// brush by a mouse, through the panel — and [tool] then put in hand.
  static Future<_Shell> inked(
    WidgetTester tester, {
    required CanvasTool tool,
  }) async {
    final shell = await pump(tester, tool: CanvasTool.brush);
    const mouse = PointerDeviceKind.mouse;
    await shell.contact(
      tester,
      const Offset(20, 30),
      buttons: kPrimaryButton,
      kind: mouse,
    );
    await shell.contactMoves(
      tester,
      const Offset(60, 30),
      buttons: kPrimaryButton,
      kind: mouse,
    );
    await shell.contactLifts(tester, const Offset(60, 30), kind: mouse);
    await tester.pump(const Duration(milliseconds: 50));
    expect(shell.inkAt(40, 30), 255, reason: '⛔premise: the ink is there');
    shell.take(tool);
    await tester.pump();
    return shell;
  }

  CanvasTool get tool => _brush.value.tool;

  /// Puts [tool] in hand, as the toolbar or a tool key would.
  void take(CanvasTool tool) =>
      _brush.value = _brush.value.copyWith(tool: tool);

  bool get drewSomething => _coordinator.frameStore.celHasRenderableContent(
    _coordinator.activeFrameKey,
  );

  /// The screen point that shows canvas point [onCanvas].
  Offset at(Offset onCanvas) =>
      _tester.getTopLeft(
        find.byKey(const ValueKey<String>('brush-canvas-editor-viewport')),
      ) +
      onCanvas;

  /// [settle] false = no frame after it: the next event arrives while the
  /// tree is still the one this event found.
  Future<void> hover(
    WidgetTester tester,
    Offset onCanvas, {
    required int buttons,
    bool settle = true,
  }) async {
    tester.binding.handlePointerEvent(
      PointerHoverEvent(
        kind: PointerDeviceKind.stylus,
        position: at(onCanvas),
        buttons: buttons,
      ),
    );
    if (settle) {
      await tester.pump();
    }
  }

  /// The pen's one contact, event by event — its buttons can change while
  /// it is down, which a test gesture's own moves cannot say.
  static const _pen = 31;

  Future<void> contact(
    WidgetTester tester,
    Offset onCanvas, {
    required int buttons,
    PointerDeviceKind kind = PointerDeviceKind.stylus,
  }) async {
    tester.binding.handlePointerEvent(
      PointerDownEvent(
        pointer: _pen,
        kind: kind,
        position: at(onCanvas),
        buttons: buttons,
        pressure: 1,
        pressureMin: 0,
        pressureMax: 1,
      ),
    );
    await tester.pump();
  }

  Future<void> contactMoves(
    WidgetTester tester,
    Offset onCanvas, {
    required int buttons,
    PointerDeviceKind kind = PointerDeviceKind.stylus,
  }) async {
    tester.binding.handlePointerEvent(
      PointerMoveEvent(
        pointer: _pen,
        kind: kind,
        position: at(onCanvas),
        buttons: buttons,
        pressure: 1,
        pressureMin: 0,
        pressureMax: 1,
      ),
    );
    await tester.pump();
  }

  Future<void> contactLifts(
    WidgetTester tester,
    Offset onCanvas, {
    PointerDeviceKind kind = PointerDeviceKind.stylus,
  }) async {
    tester.binding.handlePointerEvent(
      PointerUpEvent(pointer: _pen, kind: kind, position: at(onCanvas)),
    );
    await tester.pump();
  }

  static Future<_Shell> pump(
    WidgetTester tester, {
    required CanvasTool tool,
    _Ground ground = _Ground.cel,
    bool toolInput = true,
    Widget Function(BuildContext context, CanvasViewport viewport)? controls,
  }) async {
    final frameKeys = BrushCanvasFixture.createFrameKeys();
    final coordinator = BrushCanvasFixture.createCoordinator(
      frameKeys: frameKeys,
    );
    final brush = ValueNotifier(BrushToolState.defaults.copyWith(tool: tool));
    addTearDown(brush.dispose);
    final shell = _Shell._(tester, brush, coordinator);
    final temporary = TemporaryTool(
      memory: ToolHoldMemory(),
      current: () => brush.value,
      change: (next) => brush.value = next,
    );
    // The pick's colour is the pixel's place, so a pick says where it read.
    final sampled = <int, Offset>{};
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BrushCanvasPanel(
            coordinator: ground == _Ground.nothingDrawn ? null : coordinator,
            celEditable: ground == _Ground.cel,
            contentOverride: ground == _Ground.nothingDrawn
                ? (context, viewport) => const SizedBox.expand()
                : null,
            availableFrameKeys: ground == _Ground.nothingDrawn
                ? const []
                : frameKeys,
            cacheInvalidationSink: BrushEditCacheInvalidationSink(),
            brushToolState: brush,
            selectionCommands: shell.selection,
            onPressNeedsCel: () {
              shell.cellAsks += 1;
              return false;
            },
            cutPieceSlot: CutPieceSlot(),
            toolInputEnabled: toolInput,
            viewportControlsBuilder: controls,
            sampleColorAt: (CanvasPoint point) {
              final color = 0xFF000000 | (sampled.length + 1);
              sampled[color] = Offset(point.x, point.y);
              return color;
            },
            onEyedropperPick: (color) => shell.picked.add(sampled[color]!),
            onTemporaryToolHold: (held) {
              shell.holds.add(held);
              temporary.hold(held);
            },
            onTemporaryToolRelease: ({required keep}) {
              shell.releases.add(keep);
              temporary.release(keep: keep);
            },
            onInvokeAction: shell.invoked.add,
            // An explicit render 1.0: these map screen offsets to canvas
            // coordinates one for one.
            viewport: seedFromRender(tester, CanvasViewport()),
          ),
        ),
      ),
    );
    await tester.pump();
    return shell;
  }
}

WidgetTester _tester(_Shell shell) => shell._tester;

/// The raw pen service running on injected reports — which end of the pen
/// is down is the driver's word, and these say it.
RawPenInputService _rawPen() {
  final raw = RawPenInputService.instance;
  addTearDown(raw.debugReset);
  RawPenInputService.debugClockOverride = () => DateTime(2024);
  raw.debugPollOverride = () => null;
  raw.start();
  return raw;
}
