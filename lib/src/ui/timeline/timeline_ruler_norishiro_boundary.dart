import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// The のりしろ boundary in the frame ruler: where the cut is DRAWN to, past
/// the red line that says where it plays to.
///
/// 📐 The visual contract (user 2026-08-09, revised 2026-08-11):
/// - the red cut-end line stays exactly as it is; this adds ONE line
/// - the ruler spells the word across the handle's own width, so a longer
///   handle spaces its letters further apart
/// - line and letters share one colour, and it is the app ACCENT
/// - the letters sit at the TOP of the ruler, not centred: centred put them
///   behind the frame numbers, where they were hard to read (user 2026-08-11)
/// - ⚠️a short handle (0+2) cannot hold the word: below the threshold the
///   letters are dropped and the line stands alone
/// - the line runs the full cross-axis in the BODY too
///   ([TimelineBodyNoriShiroBoundary]) — one continuous mark like the red
///   line, not a stub that stops at the ruler — and the outside-cut wash
///   begins BEHIND it, because のりしろ frames are drawn material rather than
///   outside-the-cut emptiness
///
/// The letters are spread by laying them out `spaceEvenly` in the region
/// rather than by computing a letterSpacing — "spread it over the width" is
/// literally that layout, and it keeps working when the word's length changes
/// with the language.
class TimelineRulerNoriShiroBoundary extends StatelessWidget {
  const TimelineRulerNoriShiroBoundary({
    super.key = const ValueKey<String>('timeline-norishiro-boundary-ruler'),
    required this.cutEnd,
    required this.drawnEnd,
    required this.label,
    this.axis = Axis.horizontal,
  });

  /// Main-axis offset of the cut's END (the red line) — where the handle
  /// starts.
  final double cutEnd;

  /// Main-axis offset of the DRAWN end — where the blue line goes. Equal to
  /// [cutEnd] when nothing is drawn past the cut, and then nothing is drawn
  /// here either.
  final double drawnEnd;

  /// What to spell across the handle: the TERM that asked for the margin and
  /// then the word — "O.L のりしろ", "O.L 여백". Empty keeps the line and drops
  /// the letters.
  final String label;

  /// The frame axis direction: a vertical line in the horizontal ruler, a
  /// horizontal line in the X-sheet frame-number rail.
  final Axis axis;

  /// Room one glyph needs before the spread stops reading as spacing and
  /// starts reading as a collision. Multiplied by the glyph COUNT rather than
  /// compared against a fixed width: the label carries a term now and its
  /// length changes with both the term and the language.
  static const double _minGlyphExtent = 11;

  /// Non-const because the accent is LIVE (UI-R22 #5) — the app root rebuilds
  /// when the accent setting changes, and a `const` colour would strand this
  /// mark on the default teal.
  static TextStyle get _labelStyle => TextStyle(
    fontSize: 9,
    height: 1,
    color: AppColors.noriShiro,
    fontWeight: FontWeight.w600,
  );

  @override
  Widget build(BuildContext context) {
    if (drawnEnd <= cutEnd) {
      return const SizedBox.shrink();
    }
    final line = IgnorePointer(
      child: DecoratedBox(decoration: BoxDecoration(color: AppColors.noriShiro)),
    );
    final extent = drawnEnd - cutEnd;
    final glyphs = label.characters;
    final spelled =
        glyphs.isNotEmpty && extent >= glyphs.length * _minGlyphExtent
        ? IgnorePointer(
            key: const ValueKey<String>('timeline-norishiro-label'),
            child: Flex(
              direction: axis,
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              // TOP of the ruler (user 2026-08-11): centred sat the letters
              // right on the frame numbers.
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final glyph in glyphs) Text(glyph, style: _labelStyle),
              ],
            ),
          )
        : null;

    if (axis == Axis.vertical) {
      return Stack(
        children: [
          if (spelled != null)
            Positioned(
              top: cutEnd,
              left: 0,
              right: 0,
              height: extent,
              child: spelled,
            ),
          Positioned(top: drawnEnd, left: 0, right: 0, height: 2, child: line),
        ],
      );
    }
    return Stack(
      children: [
        if (spelled != null)
          Positioned(
            left: cutEnd,
            top: 0,
            bottom: 0,
            width: extent,
            child: spelled,
          ),
        Positioned(left: drawnEnd, top: 0, bottom: 0, width: 2, child: line),
      ],
    );
  }
}
