import 'dart:math' as math;

import 'package:anicel/src/models/key_mark.dart';
import 'package:anicel/src/models/key_side.dart';
import 'package:anicel/src/ui/timeline/key_mark_glyph.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/drawn_shapes.dart';

/// 🗣️a-live-dock-frame-costs-a-whole-draw-Q9 (유저 2026-11-08, 2): the key
/// marks the engine can fill by an exact formula — the diamond, the box — are
/// drawn so, their selection's ring by fills too, so a still row's image and
/// the screen agree (🔬the Surface, 11-08 04:40: a path 51/255, the diamond
/// as a turned rectangle 0~1). Every other mark stays its path.
void main() {
  const key = Color(0xFFE6E8EB);
  const accent = Color(0xFF4F8DF5);
  const center = Offset(20, 20);
  const diamond = SidesKeyMark(
    incoming: KeySideKind.linear,
    outgoing: KeySideKind.linear,
  );
  const held = SidesKeyMark(
    incoming: KeySideKind.hold,
    outgoing: KeySideKind.hold,
  );

  Future<RenderObject> markOf(
    WidgetTester tester,
    KeyMark mark, {
    Color color = key,
    ({Color color, double width})? ring,
    bool standing = false,
  }) async {
    await tester.pumpWidget(
      Center(
        child: CustomPaint(
          size: const Size(40, 40),
          painter: _Mark(mark, color, ring, standing),
        ),
      ),
    );
    return tester.renderObject(find.byType(CustomPaint).first);
  }

  testWidgets('a diamond is a turned rectangle, not a path', (tester) async {
    final mark = await markOf(tester, diamond);
    expect(mark, paintsExactlyCountTimes(#drawPath, 0));
    expect(mark, paintsExactlyCountTimes(#drawRect, 1));
    expect(mark, paints..rect(color: key));
  });

  // ↩️A Container turned 45° and squeezed across was a turned RECTANGLE —
  // a lozenge, its points off the box's edges (timeline_lane_rows). Turned
  // FIRST and stretched after, the square's corners land on the middle of
  // each of the box's edges, however narrow the box.
  testWidgets('the diamond is turned before it is stretched, so its points '
      'touch the middle of each edge of its box', (tester) async {
    final mark = await markOf(tester, diamond);
    expect(
      mark,
      paints
        ..save()
        ..translate(x: 20, y: 20)
        ..scale(x: 5, y: 6)
        ..rotate(angle: math.pi / 4)
        ..rect(
          rect: Rect.fromCenter(
            center: Offset.zero,
            width: math.sqrt2,
            height: math.sqrt2,
          ),
        )
        ..restore(),
    );
  });

  testWidgets('a held key is its box', (tester) async {
    final mark = await markOf(tester, held);
    expect(mark, paintsExactlyCountTimes(#drawPath, 0));
    expect(
      mark,
      paints
        ..rect(
          rect: Rect.fromCenter(center: center, width: 10, height: 12),
          color: key,
        ),
    );
  });

  testWidgets('a held key standing is its box turned on its side', (
    tester,
  ) async {
    final mark = await markOf(tester, held, standing: true);
    expect(
      mark,
      paints..rect(rect: Rect.fromCenter(center: center, width: 12, height: 10)),
    );
  });

  testWidgets('its ring is fills: the ring over the mark, the key the '
      'ring\'s width in — no clip, no stroke', (tester) async {
    final mark = await markOf(
      tester,
      held,
      ring: (color: accent, width: 1.5),
    );
    final whole = Rect.fromCenter(center: center, width: 10, height: 12);
    expect(
      mark,
      paints
        ..rect(rect: whole, color: accent)
        ..rect(rect: whole.deflate(1.5), color: key),
    );
    expect(mark, paintsExactlyCountTimes(#drawPath, 0));
    expect(mark, paintsExactlyCountTimes(#clipPath, 0));
  });

  testWidgets('a diamond\'s ring comes in at its points by the side\'s lean', (
    tester,
  ) async {
    final mark = await markOf(
      tester,
      diamond,
      ring: (color: accent, width: 1),
    );
    expect(mark, paintsExactlyCountTimes(#drawRect, 2));
    expect(mark, paintsExactlyCountTimes(#drawPath, 0));
    final [ring, inside] = DrawnShapes.of(mark);
    expect(ring.paint.color, isSameColorAs(accent));
    expect(inside.paint.color, isSameColorAs(key));
    // How far a diamond's sides lie from its middle, by its half-sides.
    double toSides(Rect box) {
      final (a, b) = (box.width / 2, box.height / 2);
      return a * b / math.sqrt(a * a + b * b);
    }

    // To a float's precision: a path keeps its points in floats.
    final whole = ring.outline.getBounds();
    final inner = inside.outline.getBounds();
    expect(
      whole,
      rectMoreOrLessEquals(
        Rect.fromCenter(center: center, width: 10, height: 12),
        epsilon: 1e-6,
      ),
    );
    expect(inner.center, offsetMoreOrLessEquals(center, epsilon: 1e-6));
    expect(
      toSides(whole) - toSides(inner),
      moreOrLessEquals(1, epsilon: 1e-6),
      reason: 'every side the ring\'s width in',
    );
    expect(
      inner.width / inner.height,
      moreOrLessEquals(10 / 12, epsilon: 1e-6),
      reason: 'the same diamond, smaller',
    );
  });

  testWidgets('a translucent ring lies over the key, as its stroke did', (
    tester,
  ) async {
    final mark = await markOf(
      tester,
      held,
      ring: (color: accent.withValues(alpha: 0.5), width: 1),
    );
    expect(
      mark,
      paints
        ..rect(color: key)
        ..rect(color: accent.withValues(alpha: 0.5))
        ..rect(color: key),
    );
  });

  testWidgets('a translucent key under a ring keeps its path — the ring '
      'would show through it', (tester) async {
    final mark = await markOf(
      tester,
      held,
      color: key.withValues(alpha: 0.4),
      ring: (color: accent, width: 1),
    );
    expect(mark, paintsExactlyCountTimes(#drawRect, 0));
    expect(mark, paintsExactlyCountTimes(#drawPath, 2));
  });

  testWidgets('every other mark stays its path', (tester) async {
    for (final mark in [
      const SidesKeyMark(incoming: KeySideKind.ease, outgoing: KeySideKind.ease),
      const SidesKeyMark(
        incoming: KeySideKind.linear,
        outgoing: KeySideKind.hold,
      ),
      const SidesKeyMark(incoming: KeySideKind.auto, outgoing: KeySideKind.auto),
      KeyMark.roving,
    ]) {
      final painted = await markOf(tester, mark);
      expect(
        painted,
        paintsExactlyCountTimes(#drawPath, 1),
        reason: '$mark is no rectangle',
      );
      expect(painted, paintsExactlyCountTimes(#drawRect, 0));
    }
  });
}

class _Mark extends CustomPainter {
  _Mark(this.mark, this.color, this.ring, this.standing);

  final KeyMark mark;
  final Color color;
  final ({Color color, double width})? ring;
  final bool standing;

  @override
  void paint(Canvas canvas, Size size) => paintKeyMark(
    canvas,
    mark,
    center: const Offset(20, 20),
    box: const Size(10, 12),
    standing: standing,
    color: color,
    ring: ring,
  );

  @override
  bool shouldRepaint(_Mark oldDelegate) => true;
}
