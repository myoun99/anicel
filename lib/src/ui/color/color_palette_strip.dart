import 'package:flutter/material.dart';

import '../../services/color_palette_file_service.dart';

/// The palette rows under the color wheel (P4): recent colors (newest
/// first, read-only) and the pinned palette (tap = pick; the + chip pins
/// the CURRENT color; − unpins it).
///
/// R10 R5: the − chip is how unpinning came back after R10 R3 deleted
/// the long-press that used to do it.
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

  /// A palette ACTION chip — same 20px cell as a swatch so the row reads
  /// as one strip. A null [onTap] dims it: the + has nothing to pin when
  /// the colour is already there, the − nothing to remove when it is not.
  Widget _chip({
    required ThemeData theme,
    required String keyValue,
    required IconData icon,
    required VoidCallback? onTap,
  }) {
    final enabled = onTap != null;
    return InkWell(
      key: ValueKey<String>(keyValue),
      onTap: onTap,
      child: Container(
        width: 20,
        height: 20,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: enabled
                ? theme.colorScheme.outline
                : theme.colorScheme.outlineVariant,
          ),
        ),
        child: Icon(
          icon,
          size: 14,
          color: enabled ? null : theme.disabledColor,
        ),
      ),
    );
  }

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
            _chip(
              theme: theme,
              keyValue: 'palette-add-button',
              icon: Icons.add,
              onTap: palette.pinned.contains(currentColor)
                  ? null
                  : () => onPaletteChanged(
                      palette.copyWith(
                        pinned: [...palette.pinned, currentColor],
                      ),
                    ),
            ),
            // The − chip is the + chip's mirror, and the way unpinning
            // came back (R10 R5). R10 R3 deleted the long-press that used
            // to do it — a gesture that could never fire inside a scroll
            // view — and left the palette append-only in between.
            //
            // It removes the CURRENT colour, so the way to unpin a swatch
            // is to tap it and then tap this: two taps, no new gesture,
            // and "tap = pick" stays true of every swatch.
            _chip(
              theme: theme,
              keyValue: 'palette-remove-button',
              icon: Icons.remove,
              onTap: palette.pinned.contains(currentColor)
                  ? () => onPaletteChanged(
                      palette.copyWith(
                        pinned: [
                          for (final pinned in palette.pinned)
                            if (pinned != currentColor) pinned,
                        ],
                      ),
                    )
                  : null,
            ),
          ],
        ),
      ],
    );
  }
}
