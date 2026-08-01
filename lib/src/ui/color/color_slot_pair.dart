import 'package:flutter/material.dart';

/// The Photoshop-style overlapped foreground/background swatch pair.
///
/// R10 R5 promoted it out of the colour wheel panel and onto the TOOL
/// RAIL. It was inside the window, which meant the two colours you paint
/// with were only visible once you had opened something — and the rail,
/// where a hand actually rests, showed the foreground alone as a plain
/// circle. The rail is the main swatch now and the window carries none.
///
/// Its extent is exactly [extent] = 42, which is the rail's button cell,
/// so the pair drops into the rail without the rail learning a new size.
class ColorSlotPair extends StatelessWidget {
  const ColorSlotPair({
    super.key,
    required this.foreground,
    required this.background,
    required this.onBackgroundTap,
    this.keyPrefix = 'color-wheel',
  });

  final Color foreground;
  final Color background;

  /// Tapping the BACKGROUND slot swaps the two — the Photoshop gesture,
  /// kept because it is the one every user of this app already knows.
  final VoidCallback onBackgroundTap;

  /// Namespaces the two swatch keys, so the rail and any other host can
  /// both mount one without their tests colliding.
  final String keyPrefix;

  static const double _slot = 26;
  static const double _overlap = 10;

  /// The pair's square extent — 2 slots less their overlap.
  static const double extent = _slot * 2 - _overlap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    Widget swatch(String key, Color color) {
      return Container(
        key: ValueKey<String>(key),
        width: _slot,
        height: _slot,
        decoration: BoxDecoration(
          color: color,
          border: Border.all(color: colorScheme.outlineVariant),
          borderRadius: BorderRadius.circular(4),
        ),
      );
    }

    return SizedBox(
      width: extent,
      height: extent,
      child: Stack(
        children: [
          Positioned(
            right: 0,
            bottom: 0,
            child: Tooltip(
              message: 'Background Color (Tap to Swap)',
              child: GestureDetector(
                onTap: onBackgroundTap,
                child: swatch('$keyPrefix-background-swatch', background),
              ),
            ),
          ),
          Positioned(
            left: 0,
            top: 0,
            child: swatch('$keyPrefix-foreground-swatch', foreground),
          ),
        ],
      ),
    );
  }
}
