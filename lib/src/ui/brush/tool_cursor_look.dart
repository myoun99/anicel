import 'package:flutter/material.dart';

import '../repaint_props.dart';

/// One tool cursor's LOOK: the painter that draws it, the box it draws in,
/// and where in that box the pointer's own point is.
///
/// The sprite that wears it (`tool_cursor_sprite.dart`) records the look
/// once and MOVES it: a look is what stays the same between two pointer
/// positions. The painter is the one description of the pixels — the
/// sprite draws no line of its own.
///
/// [key] is the look's identity BY VALUE: two looks with equal keys have
/// equal pixels.
class ToolCursorLook {
  const ToolCursorLook({
    required this.key,
    required this.painter,
    required this.extent,
    required this.hotspot,
  });

  final Object key;

  /// Paints the whole look into a box of [extent], at the box's origin.
  final CustomPainter painter;

  /// The box the look is painted in, logical pixels.
  final Size extent;

  /// Where in the box the pointer's point sits — the ring's centre, the
  /// bucket's spout, the dropper's tip.
  final Offset hotspot;
}

/// R26 #22 / #23: a tool ICON as the cursor — the glyph in black under the
/// same glyph in white one pixel up-left, so it reads over ink and paper
/// alike. Exactly what the `Icon` pair drew before F-130 made the look a
/// painter the sprite can move without a rebuild.
class ToolIconCursorPainter extends CustomPainter with RepaintOnProps {
  const ToolIconCursorPainter({required this.icon});

  final IconData icon;

  /// The box: the larger glyph's size.
  static const double boxSide = 22;

  @override
  void paint(Canvas canvas, Size size) {
    _glyph(canvas, 22, const Color(0x8C000000), Offset.zero);
    _glyph(canvas, 20, const Color(0xFFFFFFFF), const Offset(1, 1));
  }

  /// One glyph, centred in a square of [side] the way `Icon` centres its
  /// own: unit line height, even leading.
  void _glyph(Canvas canvas, double side, Color color, Offset at) {
    final painter = TextPainter(
      text: TextSpan(
        text: String.fromCharCode(icon.codePoint),
        style: TextStyle(
          inherit: false,
          color: color,
          fontSize: side,
          fontFamily: icon.fontFamily,
          package: icon.fontPackage,
          fontFamilyFallback: icon.fontFamilyFallback,
          height: 1.0,
          leadingDistribution: TextLeadingDistribution.even,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    painter.paint(
      canvas,
      at + Offset((side - painter.width) / 2, (side - painter.height) / 2),
    );
    painter.dispose();
  }

  @override
  Object get props => icon;
}

/// R26 #23: the fill tool wears the bucket; its spout is the hot spot.
ToolCursorLook fillCursorLook() => const ToolCursorLook(
  key: 'fill',
  painter: ToolIconCursorPainter(icon: Icons.format_color_fill),
  extent: Size(ToolIconCursorPainter.boxSide, ToolIconCursorPainter.boxSide),
  hotspot: Offset(3, 20),
);

/// R26 #22: the eyedropper wears its own icon; its tip is the hot spot, so
/// the glyph hangs up-left of the point being sampled.
ToolCursorLook eyedropperCursorLook() => const ToolCursorLook(
  key: 'eyedropper',
  painter: ToolIconCursorPainter(icon: Icons.colorize),
  extent: Size(ToolIconCursorPainter.boxSide, ToolIconCursorPainter.boxSide),
  hotspot: Offset(3, 21),
);
