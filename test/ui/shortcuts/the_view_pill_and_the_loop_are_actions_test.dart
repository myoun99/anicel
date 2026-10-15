import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/canvas_viewport.dart';
import 'package:anicel/src/ui/brush/brush_canvas_panel.dart';
import 'package:anicel/src/ui/brush/brush_edit_cache_invalidation_sink.dart';
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

  /// Somewhere other than where fit and 1:1 land.
  Future<void> zoomAway(WidgetTester tester) async {
    await pressKeyOf(tester, EditorActionIds.canvasZoomIn);
    await pressKeyOf(tester, EditorActionIds.canvasZoomIn);
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

  testWidgets('fit and 1:1, by key, land where their buttons land', (
    tester,
  ) async {
    await pumpEditor(tester);

    for (final (button, action) in const [
      ('canvas-viewport-fit', EditorActionIds.canvasFit),
      ('canvas-viewport-reset', EditorActionIds.canvasResetView),
    ]) {
      await tapOnPill(tester, button);
      final landed = viewOf(tester);
      await zoomAway(tester);
      expect(viewOf(tester), isNot(landed), reason: 'fixture: moved away');

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
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 900,
              height: 600,
              child: BrushCanvasPanel(
                coordinator: BrushCanvasFixture.createCoordinator(
                  frameKeys: frameKeys,
                  canvasSize: const CanvasSize(width: 300, height: 300),
                ),
                availableFrameKeys: frameKeys,
                cacheInvalidationSink: BrushEditCacheInvalidationSink(),
                floorCover: EdgeInsets.zero,
                canvasSize: const CanvasSize(width: 300, height: 300),
                viewCommands: viewCommands,
              ),
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

    testWidgets('⛔any other canvas: the key would move the editor\'s canvas, '
        'so its fit says none', (tester) async {
      await pumpPanel(tester);
      expect(keysOn(tester, 'canvas-viewport-fit'), isEmpty);
    });
  });
}
