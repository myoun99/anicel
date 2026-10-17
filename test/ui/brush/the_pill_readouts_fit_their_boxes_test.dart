import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/ui/brush/brush_canvas_panel.dart';
import 'package:anicel/src/ui/brush/brush_edit_cache_invalidation_sink.dart';
import 'package:anicel/src/ui/theme/app_theme.dart' show buildAppTheme;
import 'package:anicel/src/ui/widgets/drag_value_label.dart';

import '../../helpers/app_faces.dart';
import '../../helpers/brush_canvas_fixture.dart';
import '../../helpers/canvas_pill.dart';

/// F-122: the pill writes every digit the view has, so its two readouts
/// have to hold the WIDEST number each can write — `1600.00%` and
/// `-179.99°` — in the face the app actually wears.
///
/// 🚨The test font cannot answer this. Every glyph in it is a square one em
/// wide, so `100%` already overflows its box there and always has; a width
/// pin against it would measure the font, not the pill. This loads BIZ
/// UDPGothic from the bundle's own file and measures with the style the
/// mounted readout really carries (the theme's letter spacing included —
/// it is 2px of a box that has 3px to spare).
///
/// 🚨And under the app's own theme, so the pill measures its boxes in that
/// face too. Without it the pill measured them in the test font's squares,
/// wider than any number in BIZ UDPGothic, and this pin held whatever the
/// measuring did (found by mutation, F-383).
void main() {
  double widthOf(
    String text,
    TextStyle style, [
    TextScaler scaler = TextScaler.noScaling,
  ]) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
      textScaler: scaler,
    )..layout();
    return painter.width;
  }

  Future<void> pumpPanel(WidgetTester tester, CanvasSize canvasSize) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(1600, 1200);
    addTearDown(tester.view.reset);
    await loadTheAppFaces();

    final frameKeys = BrushCanvasFixture.createFrameKeys();
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: Scaffold(
          body: BrushCanvasPanel(
            coordinator: BrushCanvasFixture.createCoordinator(
              frameKeys: frameKeys,
              canvasSize: canvasSize,
            ),
            availableFrameKeys: frameKeys,
            cacheInvalidationSink: BrushEditCacheInvalidationSink(),
            floorCover: EdgeInsets.zero,
            canvasSize: canvasSize,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// The box a readout was given, and the style and the scale its text is
  /// painted in — read off the mounted widgets, so the pin follows the pill.
  ({double box, TextStyle style, TextScaler scaler}) readout(
    WidgetTester tester,
    String key,
  ) {
    final label = find.ancestor(
      of: find.byKey(ValueKey<String>(key)),
      matching: find.byType(DragValueLabel),
    );
    // The FACE's writing — not its pencil's glyph beside it.
    final painted = tester.widget<RichText>(
      find.descendant(
        of: find.byKey(ValueKey<String>(key)),
        matching: find.byType(RichText),
      ),
    );
    return (
      box: tester.widget<DragValueLabel>(label).width,
      style: painted.text.style!,
      scaler: painted.textScaler,
    );
  }

  /// The widest digit, measured rather than assumed (`1` is the narrow one
  /// in this face; the rest are tabular).
  String widestDigitIn(TextStyle style) => '0123456789'
      .split('')
      .reduce((a, b) => widthOf(a, style) >= widthOf(b, style) ? a : b);

  testWidgets('🚨the widest zoom and the widest angle fit their boxes in the '
      'app\'s own face', (tester) async {
    await pumpPanel(tester, const CanvasSize(width: 300, height: 300));
    if (!tester.any(
      find.byKey(const ValueKey<String>('canvas-viewport-rotation-label')),
    )) {
      await openViewSettings(tester);
    }

    final zoom = readout(tester, 'canvas-viewport-zoom-label');
    final angle = readout(tester, 'canvas-viewport-rotation-label');
    final widest = widestDigitIn(zoom.style);
    expect(
      widthOf('8', zoom.style),
      isNot(widthOf('8', zoom.style.copyWith(fontFamily: 'FlutterTest'))),
      reason: 'fixture: the app face did not load — this would be measuring '
          'the test font\'s squares',
    );

    // 1000.00%–1600.00% is the four-digit stretch of the range, and
    // [-180, 180) the angle's.
    final widestZoom = '1$widest$widest$widest.$widest$widest%';
    final widestAngle = '-1$widest$widest.$widest$widest°';
    expect(
      widthOf(widestZoom, zoom.style),
      lessThanOrEqualTo(zoom.box),
      reason: '"$widestZoom" does not fit the zoom readout\'s ${zoom.box}px',
    );
    expect(
      widthOf(widestAngle, angle.style),
      lessThanOrEqualTo(angle.box),
      reason: '"$widestAngle" does not fit the angle readout\'s ${angle.box}px',
    );
  });

  testWidgets('🚨at twice the OS text size the widest zoom still fits its '
      'box — there the box is what that number measures, past the width '
      'drawn for it at 1×', (tester) async {
    // text-scale-fixed-height-bars (유저 2026-09-18, 「막대가 글자 크기를
    // 따라 자란다」). On a canvas this wide the zoom stays on the pill; the
    // angle goes to the settings list at this size, whose row is a card of
    // its own (`canvas-settings-view-row-runs-over-at-2x`).
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await pumpPanel(tester, const CanvasSize(width: 1200, height: 900));

    final zoom = readout(tester, 'canvas-viewport-zoom-label');
    final widest = widestDigitIn(zoom.style);
    final widestZoom = '1$widest$widest$widest.$widest$widest%';
    expect(
      widthOf(widestZoom, zoom.style, zoom.scaler),
      lessThanOrEqualTo(zoom.box),
      reason: '"$widestZoom" does not fit the zoom readout\'s ${zoom.box}px',
    );
  });
}
