import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/ui/home_page.dart';

/// The stage planes must clip to their own box, and the reason is memory
/// rather than appearance.
///
/// 🚨 The quad is built in VIEWPORT coordinates, so it reaches as far as
/// the pasteboard does — five canvas widths and heights, 9600 x 5400
/// units at the default project size. A `CustomPaint` clips nothing, so
/// the display list's BOUNDS were that whole quad, and the engine sizes a
/// raster cache entry from bounds x transform:
///
///     197.75 MiB  x  zoom²  x  dpr²
///
/// Measured on the real app: the picture cache reached ~1 GB on an EMPTY
/// project, tracked zoom² exactly, and fell off a cliff where the
/// allocation finally failed. Closing one panel that mounts a
/// `BrushCanvasPanel` gave back 369 MB.
///
/// ⚠️ **A pixel test cannot see this.** Everything past the box is
/// composited away either way, so a screenshot is identical before and
/// after — which is exactly why it survived so long. The assertion has to
/// be about what the painter RECORDS, so this drives it with a spy canvas
/// and asks two things: that the clip is pushed before anything is drawn,
/// and that the path it clips genuinely escapes the box. The second is
/// the anti-vacuity half: if the quad already fitted, the clip would be
/// decoration and this test would prove nothing.
class _SpyCanvas implements Canvas {
  final List<String> ops = <String>[];
  Rect? clip;
  Rect? pathBounds;

  @override
  void save() => ops.add('save');

  @override
  void restore() => ops.add('restore');

  @override
  void clipRect(
    Rect rect, {
    ui.ClipOp clipOp = ui.ClipOp.intersect,
    bool doAntiAlias = true,
  }) {
    ops.add('clipRect');
    clip ??= rect;
  }

  @override
  void drawRect(Rect rect, Paint paint) => ops.add('drawRect');

  @override
  void drawPath(Path path, Paint paint) {
    ops.add('drawPath');
    pathBounds ??= path.getBounds();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) {
    ops.add(invocation.memberName.toString());
    return null;
  }
}

Iterable<CustomPainter> _stagePlanesPainters(WidgetTester tester) sync* {
  for (final paint in tester.widgetList<CustomPaint>(find.byType(CustomPaint))) {
    final painter = paint.painter;
    if (painter != null &&
        painter.runtimeType.toString().contains('StagePlanesPainter')) {
      yield painter;
    }
  }
}

void main() {
  testWidgets('the stage planes clip to their own box before drawing', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1400, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const MaterialApp(home: HomePage()));
    await tester.pumpAndSettle();

    final painters = _stagePlanesPainters(tester).toList();
    expect(
      painters,
      isNotEmpty,
      reason:
          'no stage planes painter was mounted, so nothing below is being '
          'tested — the workspace must show at least one canvas panel',
    );

    // A box much smaller than the pasteboard, which is the situation on
    // screen: the panel is a few hundred logical pixels and the quad is
    // nine thousand canvas units across.
    const box = Size(400, 300);

    for (final painter in painters) {
      final spy = _SpyCanvas();
      painter.paint(spy, box);

      expect(
        spy.clip,
        Offset.zero & box,
        reason:
            '$painter recorded a display list whose bounds are the whole '
            'pasteboard. The engine sizes a raster cache entry from those '
            'bounds times the transform, which measured at hundreds of MB '
            'for one drawPath.\nOps: ${spy.ops}',
      );

      final firstClip = spy.ops.indexOf('clipRect');
      final firstDraw = spy.ops.indexWhere((op) => op.startsWith('draw'));
      expect(
        firstClip,
        lessThan(firstDraw),
        reason: 'the clip has to be pushed before anything is recorded',
      );

      // The anti-vacuity half.
      final bounds = spy.pathBounds;
      if (bounds != null) {
        expect(
          bounds.width > box.width || bounds.height > box.height,
          isTrue,
          reason:
              'the quad already fitted inside the box, so the clip above is '
              'not what makes the bounds small and this test is not '
              'measuring anything. Bounds: $bounds vs box: $box',
        );
      }
    }
  });
}
