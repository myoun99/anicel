import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
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
import 'package:anicel/src/services/editing/default_cut_helpers.dart';
import 'package:anicel/src/ui/brush/brush_tool_state.dart';
import 'package:anicel/src/ui/canvas/canvas_drag_in_flight.dart';
import 'package:anicel/src/ui/editor_workspace.dart';
import 'package:anicel/src/ui/home_page.dart';

import '../../helpers/dart_sources.dart';
import '../../helpers/panel_finders.dart';

/// 🚨★★★**THE EYEDROPPER ANSWERS UNDER EVERY TOOL** (F-299).
///
/// 🗣️유저 2026-10-05: 「채우기 도구인상태에서 스포이드 단축키로 도구 안바뀜.
/// **어떤 도구 들고있던 규칙 만들지말고 법 통일해서 작동하도록**」.
///
/// Through the real shell — the app's own shortcut road and keyboard, with
/// each tool's own layer mounted over the canvas — because the road was
/// never the part that differed by tool: the hold asked which tool was in
/// hand, and took only over the three the drawing view presses for.
///
/// ↩️A pen or mouse button mapped to the eyedropper is the same law, and
/// stopped at those three tools too — and at none on a frame with no cel
/// (measured 2026-10-06): it was read inside the drawing view. The panel
/// reads it now, and the two button roads are pinned here beside the keys.
void main() {
  const frameId = FrameId('pe-frame');
  const layerId = LayerId('pe-layer');

  /// A one-row project standing on a cel — or, with [cel] false, on a
  /// frame that has none.
  Project project({bool cel = true}) => Project(
    id: const ProjectId('pe-project'),
    name: 'Eyedropper',
    createdAt: DateTime.utc(2026),
    tracks: [
      Track(
        id: const TrackId('pe-track'),
        name: 'Video Track',
        cuts: [
          Cut(
            id: const CutId('pe-cut'),
            name: 'pe-cut',
            duration: defaultCutDuration,
            canvasSize: defaultCutCanvasSize,
            layers: [
              Layer(
                id: layerId,
                name: 'pe-layer',
                frames: [
                  if (cel)
                    Frame(
                      id: frameId,
                      name: 'A',
                      duration: 1,
                      strokes: const [],
                    ),
                ],
                timeline: {
                  if (cel)
                    0: const TimelineExposure.drawing(frameId, length: 1),
                },
              ),
            ],
          ),
        ],
      ),
    ],
  );

  Future<ValueNotifier<BrushToolState>> pumpShell(
    WidgetTester tester, {
    bool cel = true,
  }) async {
    await tester.binding.setSurfaceSize(const Size(1500, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(home: HomePage(initialProject: project(cel: cel))),
    );
    await tester.pumpAndSettle();
    return tester
        .widget<EditorWorkspace>(find.byType(EditorWorkspace))
        .brushTool!;
  }

  Future<void> take(
    WidgetTester tester,
    ValueNotifier<BrushToolState> brush,
    CanvasTool tool,
  ) async {
    brush.value = brush.value.copyWith(tool: tool);
    for (var i = 0; i < 4; i += 1) {
      await tester.pump(const Duration(milliseconds: 16));
    }
  }

  testWidgets('its key takes the eyedropper from every tool', (tester) async {
    final brush = await pumpShell(tester);
    for (final tool in CanvasTool.values) {
      await take(tester, brush, tool);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyI);
      await tester.pump();
      expect(brush.value.tool, CanvasTool.eyedropper, reason: tool.name);
    }
  });

  testWidgets('🚨Alt held is the eyedropper under every tool whose own drag '
      'does not read Alt, and letting go gives the tool back', (tester) async {
    // ⛔Spelled here, not asked of the predicate: an oracle that follows the
    // code it checks agrees with whatever the code says.
    const keepsItsAlt = {CanvasTool.select, CanvasTool.move};
    final brush = await pumpShell(tester);
    for (final tool in CanvasTool.values) {
      await take(tester, brush, tool);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
      await tester.pump();
      expect(
        brush.value.tool,
        keepsItsAlt.contains(tool) ? tool : CanvasTool.eyedropper,
        reason: '${tool.name}, Alt held',
      );
      await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
      await tester.pump();
      expect(brush.value.tool, tool, reason: '${tool.name}, Alt let go');
    }
  });

  // 🔎I-110 (검증/서피스 11-17, 실기): Alt pressed while a lasso fill was
  // traced painted nothing — the eyedropper took the tool from under the
  // drag. A held key waits for what the canvas is in the middle of — a
  // stroke, a drag on a selection layer — as a mapped button does, and then
  // takes the tool.
  testWidgets('🚨Alt pressed in the middle of a drag takes the tool only as '
      'the hand comes up, under every tool', (tester) async {
    // ⛔Spelled here, not asked of the code: the tools whose press is a
    // drag the canvas is in the middle of — a stroke, a selection layer's
    // outline, a text box traced, the stamp's trail (the cut before it put
    // a piece in the hand).
    const dragged = {
      CanvasTool.brush,
      CanvasTool.eraser,
      CanvasTool.fillShape,
      CanvasTool.cut,
      CanvasTool.cutStamp,
      CanvasTool.text,
      CanvasTool.shape,
    };
    const keepsItsAlt = {CanvasTool.select, CanvasTool.move};
    // Where the drag leaves the tool, Alt or none: a fresh cut arms its
    // stamp ([WorkspaceBrushPresets.armStampOnFreshCut]).
    const endsAt = {CanvasTool.cut: CanvasTool.cutStamp};
    final brush = await pumpShell(tester);
    final at = visibleCanvasPoint(tester);
    for (final tool in CanvasTool.values) {
      if (keepsItsAlt.contains(tool)) continue;
      await take(tester, brush, tool);
      final hand = await tester.startGesture(
        at,
        kind: PointerDeviceKind.mouse,
      );
      for (var step = 1; step <= 4; step += 1) {
        await hand.moveTo(at + Offset(15.0 * step, 6.0 * step));
        await tester.pump();
      }
      await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
      await tester.pump();
      expect(
        brush.value.tool,
        dragged.contains(tool) ? tool : CanvasTool.eyedropper,
        reason: '${tool.name}, Alt in the middle of the drag',
      );
      await hand.moveTo(at + const Offset(20, 60));
      await tester.pump();
      await hand.up();
      await tester.pump();
      await tester.pump();
      expect(
        brush.value.tool,
        CanvasTool.eyedropper,
        reason: '${tool.name}, the hand up with Alt held',
      );
      await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
      await tester.pump();
      expect(
        brush.value.tool,
        endsAt[tool] ?? tool,
        reason: '${tool.name}, Alt let go',
      );
      expect(tester.takeException(), isNull, reason: tool.name);
    }
  });

  // ⚠️What the keys wait for is the app's (`CanvasDragInFlight`): a canvas
  // taken down in the middle of its drag lets go of it, or every key held
  // after would wait for a hand that never comes up — the selection's
  // drag, the text's and the stamp's alike.
  testWidgets('a canvas taken down in the middle of a drag leaves no key '
      'waiting for it', (tester) async {
    Future<void> drag(TestGesture hand, Offset at, {bool up = true}) async {
      for (var step = 1; step <= 4; step += 1) {
        await hand.moveTo(at + Offset(15.0 * step, 6.0 * step));
        await tester.pump();
      }
      if (up) {
        await hand.up();
        await tester.pump();
      }
    }

    for (final tool in const [
      CanvasTool.fillShape,
      CanvasTool.text,
      CanvasTool.cutStamp,
    ]) {
      var brush = await pumpShell(tester);
      final at = visibleCanvasPoint(tester);
      if (tool == CanvasTool.cutStamp) {
        // A piece in the hand first: a stroke, and a fresh cut of it arms
        // the stamp.
        for (final pen in const [CanvasTool.brush, CanvasTool.cut]) {
          await take(tester, brush, pen);
          await drag(
            await tester.startGesture(at, kind: PointerDeviceKind.mouse),
            at,
          );
        }
      } else {
        await take(tester, brush, tool);
      }
      expect(brush.value.tool, tool, reason: 'premise');
      final hand = await tester.startGesture(
        at,
        kind: PointerDeviceKind.mouse,
      );
      await drag(hand, at, up: false);
      await tester.pumpWidget(const SizedBox());
      expect(
        CanvasDragInFlight.live.value,
        isFalse,
        reason: '${tool.name}: let go as the canvas went, before the hand',
      );
      await hand.up();

      brush = await pumpShell(tester);
      await take(tester, brush, CanvasTool.brush);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
      await tester.pump();
      expect(brush.value.tool, CanvasTool.eyedropper, reason: tool.name);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
      await tester.pump();
    }
  });

  // ⚠️Another hand can still take the tool mid drag (the rail, a tool's
  // key): the text layer, taken away under its press, hears the hand no
  // more and leaves nothing waiting for it.
  testWidgets('a tool taken from under a text drag leaves the text layer '
      'deaf to the hand and no key waiting', (tester) async {
    final brush = await pumpShell(tester);
    await take(tester, brush, CanvasTool.text);
    final at = visibleCanvasPoint(tester);
    final hand = await tester.startGesture(
      at,
      kind: PointerDeviceKind.mouse,
    );
    for (var step = 1; step <= 4; step += 1) {
      await hand.moveTo(at + Offset(15.0 * step, 6.0 * step));
      await tester.pump();
    }
    await take(tester, brush, CanvasTool.brush);
    await hand.moveTo(at + const Offset(20, 60));
    await tester.pump();
    await hand.up();
    await tester.pump();
    expect(tester.takeException(), isNull);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
    await tester.pump();
    expect(brush.value.tool, CanvasTool.eyedropper);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
    await tester.pump();
  });

  // 🚨The BUTTONS, through the real shell: every tool's own layer is
  // mounted over the canvas when the press comes, and goes away under the
  // pointer when the hold takes the tool.
  for (final cel in [true, false]) {
    final where = cel ? 'on a cel' : 'on a frame with no cel';

    testWidgets('🚨a held RIGHT button is the eyedropper under every tool, '
        '$where — and letting go gives the tool back', (tester) async {
      final brush = await pumpShell(tester, cel: cel);
      final at = visibleCanvasPoint(tester);
      for (final tool in CanvasTool.values) {
        await take(tester, brush, tool);

        final right = await tester.startGesture(
          at,
          kind: PointerDeviceKind.mouse,
          buttons: kSecondaryMouseButton,
        );
        await tester.pump();
        expect(
          brush.value.tool,
          CanvasTool.eyedropper,
          reason: '${tool.name}, held',
        );
        // The tool's layer is gone from under a pointer still down.
        await right.moveTo(at + const Offset(30, 10));
        await tester.pump();
        await right.up();
        await tester.pump();

        expect(brush.value.tool, tool, reason: '${tool.name}, let go');
        expect(tester.takeException(), isNull, reason: tool.name);
      }
    });

    testWidgets('🚨a pen\'s barrel pressed in hover is the eyedropper under '
        'every tool, $where', (tester) async {
      final brush = await pumpShell(tester, cel: cel);
      final at = visibleCanvasPoint(tester);
      Future<void> hover(int buttons) async {
        tester.binding.handlePointerEvent(
          PointerHoverEvent(
            kind: PointerDeviceKind.stylus,
            position: at,
            buttons: buttons,
          ),
        );
        await tester.pump();
      }

      for (final tool in CanvasTool.values) {
        await take(tester, brush, tool);
        await hover(0);

        await hover(kPrimaryStylusButton);
        expect(
          brush.value.tool,
          CanvasTool.eyedropper,
          reason: '${tool.name}, barrel down',
        );

        await hover(0);
        expect(brush.value.tool, tool, reason: '${tool.name}, barrel up');
        expect(tester.takeException(), isNull, reason: tool.name);
      }
    });
  }

  test('the tools that keep their Alt are the two whose drag reads it', () {
    expect(
      [
        for (final tool in CanvasTool.values)
          if (canvasToolReadsAlt(tool)) tool,
      ],
      [CanvasTool.select, CanvasTool.move],
      reason: 'the selection subtracts with it, the transform scales about '
          'the far corner — F-299-Q1',
    );
  });

  /// ⛔The predicate is a second place that has to know who reads Alt, so
  /// the first is counted: a third reader on the canvas turns this red, and
  /// whoever adds it says which tool keeps its Alt.
  test('⛔Alt is read by the selection\'s drag and the transform\'s, and by '
      'nothing else on the canvas', () {
    final readers = <String>[];
    var scanned = 0;
    for (final file in dartFilesUnder('lib/src/ui')) {
      scanned += 1;
      for (final line in file.readAsLinesSync()) {
        final comment = line.indexOf('//');
        final code = comment < 0 ? line : line.substring(0, comment);
        if (code.contains('isAltPressed')) {
          readers.add(libPath(file));
        }
      }
    }
    expect(scanned, greaterThan(300), reason: 'the scan found lib/src/ui');
    expect(readers..sort(), [
      // The transform box's scale modifier, and the marquee's combine mode.
      'lib/src/ui/canvas/canvas_selection_layer.dart',
      'lib/src/ui/canvas/canvas_selection_layer.dart',
      // Off the canvas: a notch turned with Alt zooms a sheet's frames
      // (I-155 — After Effects' and Premiere Pro's zoom of time).
      'lib/src/ui/input/wheel_law.dart',
      // The held keys: a modifier going down with Alt held, under a tool
      // that keeps its Alt by the predicate above, holds nothing — whatever
      // Alt holds (F-299-Q1, F-603). It reads the predicate; it keeps none.
      'lib/src/ui/shortcuts/editor_key_holds.dart',
      // A key that is modifiers alone, pressed with just its own held
      // (F-603) — a key, no tool's.
      'lib/src/ui/shortcuts/editor_shortcut_bindings.dart',
      // Modifiers pressed alone — Alt among them, held or not: one gone down
      // with nothing after it is a press of its own (I-19, F-603-Q1, card
      // a-held-modifiers-repeat-is-heard-as-a-press). It keeps no tool's Alt.
      'lib/src/ui/shortcuts/lone_modifiers.dart',
      // Whether a modifier's key is held, asked for every reader of one as
      // the engine may have let go of it (F-603) — no tool's.
      'lib/src/ui/shortcuts/shortcut_activator_codec.dart',
      // The shortcut window, hearing a chord being typed in.
      'lib/src/ui/shortcuts/shortcut_settings_dialog.dart',
      // Off the canvas: a header graph's Alt-click on a line, which picks
      // its keys (graph-key-pick-rest, AE's graph editor) — and its box's
      // corner pulled with Ctrl+Alt, which tapers or moves a side of it
      // (graph-box-handles-more ⓑ ⓒ, AE's transform box).
      'lib/src/ui/timeline/timeline_lane_graph.dart',
      'lib/src/ui/timeline/timeline_lane_graph.dart',
    ]);
  });
}
