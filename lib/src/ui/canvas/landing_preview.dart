import 'dart:ui';

/// What a pending landing will put over a surface, drawn over that
/// surface's coordinates before it lands — a selection's lifted float.
///
/// A leaf of its own so the surface pass can draw one without importing the
/// selection's files, which import the surface painter (the float carries a
/// painter of its own lift).
abstract interface class LandingPreview {
  /// Everything [paintInto] draws, in CANVAS space — [Rect.zero] when it
  /// draws nothing.
  Rect get drawnWorldRect;

  /// Draws the preview in CANVAS space, one canvas pixel to one of its own:
  /// the pixels the landing will write, as they will stand.
  void paintInto(Canvas canvas);
}
