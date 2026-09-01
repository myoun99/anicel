import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
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
}
