import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/ui/text/vertical_writing_text.dart';
import 'package:anicel/src/ui/timeline/axis_turn.dart';

/// The four turns, both ways. Each case fixes the DIRECTION a number goes —
/// a helper that turned only one of them would still make every caller's
/// layout wrong on exactly one surface.
void main() {
  const child = SizedBox.shrink();

  group('alongBox / acrossBox', () {
    test('along the horizontal axis is a width; across it is a height', () {
      final along = alongBox(Axis.horizontal, 16, child: child);
      final across = acrossBox(Axis.horizontal, 26, child: child);
      expect((along.width, along.height), (16, null));
      expect((across.width, across.height), (null, 26));
    });

    test('along the vertical axis is a height; across it is a width', () {
      final along = alongBox(Axis.vertical, 16, child: child);
      final across = acrossBox(Axis.vertical, 26, child: child);
      expect((along.width, along.height), (null, 16));
      expect((across.width, across.height), (26, null));
    });
  });

  group('placedAlong', () {
    test('horizontal: along is left/width, across is top/height', () {
      final p = placedAlong(
        Axis.horizontal,
        along: 100,
        across: 28,
        alongExtent: 48,
        acrossExtent: 56,
        child: child,
      );
      expect((p.left, p.top, p.width, p.height), (100, 28, 48, 56));
      expect((p.right, p.bottom), (null, null));
    });

    test('vertical: along is top/height, across is left/width', () {
      final p = placedAlong(
        Axis.vertical,
        along: 100,
        across: 28,
        alongExtent: 48,
        acrossExtent: 56,
        child: child,
      );
      expect((p.top, p.left, p.height, p.width), (100, 28, 48, 56));
      expect((p.right, p.bottom), (null, null));
    });
  });

  group('stripAcross', () {
    test('horizontal: spans left..right at a top and height', () {
      final p = stripAcross(
        Axis.horizontal,
        across: 84,
        acrossExtent: 28,
        child: child,
      );
      expect((p.left, p.right, p.top, p.height), (0, 0, 84, 28));
      expect((p.bottom, p.width), (null, null));
    });

    test('vertical: spans top..bottom at a left and width', () {
      final p = stripAcross(
        Axis.vertical,
        across: 84,
        acrossExtent: 28,
        child: child,
      );
      expect((p.top, p.bottom, p.left, p.width), (0, 0, 84, 28));
      expect((p.right, p.height), (null, null));
    });
  });

  group('stripAlong', () {
    test('horizontal: spans top..bottom at a left and width', () {
      final p = stripAlong(
        Axis.horizontal,
        along: 120,
        alongExtent: 12,
        child: child,
      );
      expect((p.top, p.bottom, p.left, p.width), (0, 0, 120, 12));
      expect((p.right, p.height), (null, null));
    });

    test('vertical: spans left..right at a top and height', () {
      final p = stripAlong(
        Axis.vertical,
        along: 120,
        alongExtent: 12,
        child: child,
      );
      expect((p.left, p.right, p.top, p.height), (0, 0, 120, 12));
      expect((p.bottom, p.width), (null, null));
    });
  });

  group('readableText', () {
    test('across the strip it is one ellipsising line', () {
      final w = readableText(Axis.horizontal, 'Position');
      expect(w, isA<Text>());
      expect((w as Text).overflow, TextOverflow.ellipsis);
    });

    test('down a column the letters stand up from the top', () {
      final w = readableText(Axis.vertical, 'Position');
      expect(w, isA<ClipRect>());
      final text = (w as ClipRect).child! as VerticalWritingText;
      expect(text.latinForm, VerticalLatinForm.upright);
      expect(text.mainAlignment, 0);
    });
  });

  group('sizedAlong', () {
    test('horizontal: along is the width, across the height', () {
      final b = sizedAlong(
        Axis.horizontal,
        along: 96,
        across: 28,
        child: child,
      );
      expect((b.width, b.height), (96, 28));
    });

    test('vertical: along is the height, across the width', () {
      final b = sizedAlong(Axis.vertical, along: 96, across: 28, child: child);
      expect((b.width, b.height), (28, 96));
    });
  });

  group('stripAlong from the far end', () {
    test('horizontal: measured from the right', () {
      final p = stripAlong(
        Axis.horizontal,
        along: 30,
        alongExtent: 2,
        fromEnd: true,
        child: child,
      );
      expect((p.right, p.width, p.top, p.bottom), (30, 2, 0, 0));
      expect((p.left, p.height), (null, null));
    });

    test('vertical: measured from the bottom', () {
      final p = stripAlong(
        Axis.vertical,
        along: 30,
        alongExtent: 2,
        fromEnd: true,
        child: child,
      );
      expect((p.bottom, p.height, p.left, p.right), (30, 2, 0, 0));
      expect((p.top, p.width), (null, null));
    });
  });

  group('the painter twins: extentAlong / extentAcross / offsetAlong', () {
    const size = Size(120, 30);

    test('horizontal: along is the width, across the height; a point is '
        '(along, across)', () {
      expect(extentAlong(Axis.horizontal, size), 120);
      expect(extentAcross(Axis.horizontal, size), 30);
      expect(
        offsetAlong(Axis.horizontal, along: 100, across: 7),
        const Offset(100, 7),
      );
    });

    test('vertical: along is the height, across the width; a point is '
        '(across, along)', () {
      expect(extentAlong(Axis.vertical, size), 30);
      expect(extentAcross(Axis.vertical, size), 120);
      expect(
        offsetAlong(Axis.vertical, along: 100, across: 7),
        const Offset(7, 100),
      );
    });
  });
}
