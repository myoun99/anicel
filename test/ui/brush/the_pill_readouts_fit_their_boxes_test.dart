import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/ui/brush/brush_canvas_panel.dart';
import 'package:anicel/src/ui/brush/brush_edit_cache_invalidation_sink.dart';
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
void main() {
  double widthOf(String text, TextStyle style) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
    )..layout();
    return painter.width;
  }

  testWidgets('🚨the widest zoom and the widest angle fit their boxes in the '
      'app\'s own face', (tester) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(1600, 1200);
    addTearDown(tester.view.reset);
    await loadTheAppFaces();

    final frameKeys = BrushCanvasFixture.createFrameKeys();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BrushCanvasPanel(
            coordinator: BrushCanvasFixture.createCoordinator(
              frameKeys: frameKeys,
              canvasSize: const CanvasSize(width: 300, height: 300),
            ),
            availableFrameKeys: frameKeys,
            cacheInvalidationSink: BrushEditCacheInvalidationSink(),
            floorCover: EdgeInsets.zero,
            canvasSize: const CanvasSize(width: 300, height: 300),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    if (!tester.any(
      find.byKey(const ValueKey<String>('canvas-viewport-rotation-label')),
    )) {
      await openViewSettings(tester);
    }

    /// The box a readout was given, and the style its text is painted in —
    /// read off the mounted widgets, so the pin follows the pill.
    ({double box, TextStyle style}) readout(String key) {
      final label = find.ancestor(
        of: find.byKey(ValueKey<String>(key)),
        matching: find.byType(DragValueLabel),
      );
      final painted = tester.widget<RichText>(
        find.descendant(of: label, matching: find.byType(RichText)),
      );
      return (
        box: tester.widget<DragValueLabel>(label).width,
        style: painted.text.style!.copyWith(fontFamily: 'BIZ UDPGothic'),
      );
    }

    final zoom = readout('canvas-viewport-zoom-label');
    final angle = readout('canvas-viewport-rotation-label');

    // The widest digit, measured rather than assumed (`1` is the narrow
    // one in this face; the rest are tabular).
    final widest = '0123456789'
        .split('')
        .reduce((a, b) => widthOf(a, zoom.style) >= widthOf(b, zoom.style) ? a : b);
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
}
