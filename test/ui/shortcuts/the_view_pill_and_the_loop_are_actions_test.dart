import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/canvas_viewport.dart';
import 'package:anicel/src/ui/brush/brush_canvas_panel.dart';
import 'package:anicel/src/ui/brush/brush_edit_cache_invalidation_sink.dart';
import 'package:anicel/src/ui/brush/canvas_floor_insets.dart';
import 'package:anicel/src/ui/brush/canvas_view_commands.dart';
import 'package:anicel/src/ui/brush/main_canvas_brush_host.dart';
import 'package:anicel/src/ui/editor_canvas_area.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/home_page.dart';
import 'package:anicel/src/ui/shortcuts/editor_action_registry.dart';
import 'package:anicel/src/ui/shortcuts/editor_shortcut_bindings.dart';
import 'package:anicel/src/ui/shortcuts/editor_shortcut_scope.dart';
import 'package:anicel/src/ui/theme/app_theme.dart';
import 'package:anicel/src/ui/widgets/app_icon_button.dart';

import '../../helpers/brush_canvas_fixture.dart';
import '../../helpers/panel_finders.dart';

/// 🗣️I-40 — the view pill's other four (↕, the straighten, fit and 1:1)
/// and the playback bar's loop are actions: a key presses what the button
/// presses, and the button says the key.
///
/// The keys are recorded here: none of the five ships with one.
const k = LogicalKeyboardKey.keyK;

void main() {
  Future<EditorSessionManager> pumpEditor(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1600, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(theme: buildAppTheme(), home: const HomePage()),
    );
    await tester.pumpAndSettle();
    return tester
        .widget<EditorCanvasArea>(find.byType(EditorCanvasArea))
        .session;
  }

  EditorShortcutBindings keys(WidgetTester tester) =>
      EditorShortcutScope.peek(tester.element(find.byType(EditorCanvasArea)))!;

  CanvasViewport viewOf(WidgetTester tester) => tester
      .widget<MainCanvasBrushHost>(find.byType(MainCanvasBrushHost))
      .publishedViewport;

  String? held;

  /// Records [k] for [actionId] — alone — and presses it.
  Future<void> pressKeyOf(WidgetTester tester, String actionId) async {
    if (held case final before? when before != actionId) {
      keys(tester).resetAction(before);
    }
    held = actionId;
    keys(tester).setActivators(actionId, const [SingleActivator(k)]);
    await tester.pump();
    await tester.sendKeyEvent(k);
    await tester.pumpAndSettle();
  }

  Future<void> tapOnPill(WidgetTester tester, String key) async {
    await tester.tap(inMainCanvas(find.byKey(ValueKey<String>(key))));
    await tester.pumpAndSettle();
  }

  /// One place other than where fit and 1:1 land, reached the same way
  /// each time: fit frames from the window alone, and the steps after it
  /// are the same steps. Out, not in: the steps up from this fit pass
  /// through 100%, where 1:1 has nothing to do.
  ///
  /// ⚠️The button and the key both start from IT. 1:1 changes the zoom
  /// alone, about the middle of the view (F-381), so a 1:1 from two views
  /// a zoom apart meets the other only to the float: the floor under the
  /// tool settings' rail moved that middle, and they landed 2e-13 apart.
  Future<CanvasViewport> standAway(WidgetTester tester) async {
    await tapOnPill(tester, 'canvas-viewport-fit');
    await pressKeyOf(tester, EditorActionIds.canvasZoomOut);
    await pressKeyOf(tester, EditorActionIds.canvasZoomOut);
    return viewOf(tester);
  }

  testWidgets('↕ and the straighten, by key, do what their buttons do', (
    tester,
  ) async {
    await pumpEditor(tester);

    await pressKeyOf(tester, EditorActionIds.canvasFlipVertical);
    expect(viewOf(tester).flipVertical, isTrue);
    await pressKeyOf(tester, EditorActionIds.canvasFlipVertical);
    expect(viewOf(tester).flipVertical, isFalse);

    await pressKeyOf(tester, EditorActionIds.canvasRotateCw);
    expect(viewOf(tester).rotationDegrees, 15, reason: 'fixture: tilted');
    await pressKeyOf(tester, EditorActionIds.canvasStraighten);
    expect(viewOf(tester).rotationDegrees, 0);
  });

  // F-391: the keys press the pill's ⟲ / ⟳ step, each its own way.
  testWidgets('⟲ and ⟳, by key, turn the way their buttons do', (
    tester,
  ) async {
    await pumpEditor(tester);

    await pressKeyOf(tester, EditorActionIds.canvasRotateCcw);
    expect(viewOf(tester).rotationDegrees, -15);
    await pressKeyOf(tester, EditorActionIds.canvasRotateCw);
    expect(viewOf(tester).rotationDegrees, 0);
  });

  testWidgets('fit and 1:1, by key, land where their buttons land', (
    tester,
  ) async {
    await pumpEditor(tester);

    for (final (button, action) in const [
      ('canvas-viewport-fit', EditorActionIds.canvasFit),
      ('canvas-viewport-reset', EditorActionIds.canvasResetView),
    ]) {
      final away = await standAway(tester);
      await tapOnPill(tester, button);
      final landed = viewOf(tester);
      expect(landed, isNot(away), reason: '$button presses');

      expect(await standAway(tester), away, reason: 'fixture: one place');
      await pressKeyOf(tester, action);
      expect(viewOf(tester), landed, reason: action);
    }
  });

  testWidgets('the loop, by key, is the bar\'s loop — and the bar says the '
      'key', (tester) async {
    final session = await pumpEditor(tester);
    final playback = session.playbackRig.playback;
    final before = playback.loopMode;

    await pressKeyOf(tester, EditorActionIds.playbackLoopToggle);
    expect(playback.loopMode, isNot(before));
    await pressKeyOf(tester, EditorActionIds.playbackLoopToggle);
    expect(playback.loopMode, before);

    final loop = tester.widget<AppIconButton>(
      find.byWidgetPredicate(
        (widget) =>
            widget is AppIconButton && widget.keyValue == 'playback-loop-toggle',
      ),
    );
    expect(loop.shortcuts, [EditorActionIds.playbackLoopToggle]);
  });

  group('a pill names the view keys only on the canvas they drive', () {
    Future<void> pumpPanel(
      WidgetTester tester, {
      CanvasViewCommands? viewCommands,
    }) async {
      final frameKeys = BrushCanvasFixture.createFrameKeys();
      final panel = BrushCanvasPanel(
        coordinator: BrushCanvasFixture.createCoordinator(
          frameKeys: frameKeys,
          canvasSize: const CanvasSize(width: 300, height: 300),
        ),
        availableFrameKeys: frameKeys,
        cacheInvalidationSink: BrushEditCacheInvalidationSink(),
        canvasSize: const CanvasSize(width: 300, height: 300),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 900,
              height: 600,
              child: switch (viewCommands) {
                null => panel,
                // The view keys drive the panel lying on the floor (F-623).
                final commands => CanvasFloorInsets(
                  insets: EdgeInsets.zero,
                  viewCommands: commands,
                  child: panel,
                ),
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    List<String> keysOn(WidgetTester tester, String keyValue) => tester
        .widget<AppIconButton>(
          find.byWidgetPredicate(
            (widget) => widget is AppIconButton && widget.keyValue == keyValue,
          ),
        )
        .shortcuts;

    testWidgets('the canvas the keys drive: its fit says the key', (
      tester,
    ) async {
      await pumpPanel(tester, viewCommands: CanvasViewCommands());
      expect(keysOn(tester, 'canvas-viewport-fit'), [
        EditorActionIds.canvasFit,
      ]);
    });

    testWidgets('⛔a canvas off the floor: the key moves what lies there, so '
        'its fit says none', (tester) async {
      await pumpPanel(tester);
      expect(keysOn(tester, 'canvas-viewport-fit'), isEmpty);
    });
  });
}
