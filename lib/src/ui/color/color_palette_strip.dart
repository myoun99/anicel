import 'package:flutter/material.dart';

import '../../services/color_palette_file_service.dart';

/// The palette rows under the color wheel (P4): recent colors (newest
/// first, read-only) and the pinned palette (tap = pick; the + chip pins
/// the CURRENT color).
///
/// R10 R3: unpinning left with the long press. It comes back in R10 R5,
/// when the colour window gets its Palette tab — the round that owns this
/// strip's shape.
class ColorPaletteStrip extends StatelessWidget {
  const ColorPaletteStrip({
    super.key,
    required this.palette,
    required this.currentColor,
    required this.onColorSelected,
    required this.onPaletteChanged,
  });

  final ColorPaletteState palette;
  final int currentColor;
  final ValueChanged<int> onColorSelected;
  final ValueChanged<ColorPaletteState> onPaletteChanged;

  Widget _swatch({required Key key, required int color}) {
    return InkWell(
      key: key,
      onTap: () => onColorSelected(color),
      child: Container(
        width: 20,
        height: 20,
        decoration: BoxDecoration(
          color: Color(color),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: const Color(0x33000000)),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (palette.recent.isNotEmpty) ...[
          Text('Recent', style: theme.textTheme.labelSmall),
          const SizedBox(height: 4),
          Wrap(
            spacing: 4,
            runSpacing: 4,
            children: [
              for (var i = 0; i < palette.recent.length; i += 1)
                _swatch(
                  key: ValueKey<String>('palette-recent-$i'),
                  color: palette.recent[i],
                ),
            ],
          ),
          const SizedBox(height: 8),
        ],
        Text('Palette', style: theme.textTheme.labelSmall),
        const SizedBox(height: 4),
        Wrap(
          spacing: 4,
          runSpacing: 4,
          children: [
            for (var i = 0; i < palette.pinned.length; i += 1)
              _swatch(
                key: ValueKey<String>('palette-swatch-$i'),
                color: palette.pinned[i],
              ),
            InkWell(
              key: const ValueKey<String>('palette-add-button'),
              onTap: palette.pinned.contains(currentColor)
                  ? null
                  : () => onPaletteChanged(
                      palette.copyWith(
                        pinned: [...palette.pinned, currentColor],
                      ),
                    ),
              child: Container(
                width: 20,
                height: 20,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: theme.colorScheme.outline),
                ),
                child: const Icon(Icons.add, size: 14),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
