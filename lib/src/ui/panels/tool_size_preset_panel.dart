import 'package:flutter/material.dart';

import '../input/app_input_settings.dart';
import '../theme/app_theme.dart';

/// **The tool's sizes, as buttons** (I-2).
///
/// 유저 2026-08-24: 「클튜처럼 툴 사이즈 패널 만들고싶음. **프리셋으로서 툴
/// 사이즈.** 브러시면 브러시 사이즈들이 여러개 존재해서 그거 누르면 브러시
/// 사이즈 바뀌는 패널」.
///
/// 🚨★A panel of its own, and the FIRST exception to 「툴 전용 패널을 새로
/// 만들지 않는다」 — 유저 결정 2026-08-25: 「새 패널로 만든다 — 이번은
/// 예외」. The rule stands for tool SETTINGS; this is not a setting, it is a
/// rack of values you reach for while drawing, and a rack has to be visible
/// at the same time as the canvas.
///
/// ⚠️**The sizes are the SNAP list** ([AppInputSettings.brushSizeSnaps]),
/// which is already a user-editable list of "my sizes" — the size drag snaps
/// to exactly these. Two lists of the same thing would drift the day someone
/// edited one, and the app has no other list of sizes to draw from. Editing
/// is where it already is (Input settings 」snap tables), so this panel adds
/// no editor of its own.
class ToolSizePresetPanel extends StatelessWidget {
  const ToolSizePresetPanel({
    super.key,
    required this.size,
    required this.onSizeSelected,
  });

  /// The tool's size right now — the chip matching it reads as selected.
  final double size;
  final ValueChanged<double> onSizeSelected;

  /// How close a size has to be to a preset to read as that preset. The
  /// list is integral and the drag snaps to it, so this only absorbs the
  /// float error of a snap.
  static const double _match = 0.01;

  static String label(double value) =>
      value == value.roundToDouble() ? '${value.round()}' : '$value';

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return ValueListenableBuilder<AppInputSettings>(
      valueListenable: AppInput.settings,
      builder: (context, settings, _) => SingleChildScrollView(
        padding: const EdgeInsets.all(8),
        child: Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final preset in settings.brushSizeSnaps)
              _SizeChip(
                key: ValueKey<String>('tool-size-preset-${label(preset)}'),
                label: label(preset),
                // Selection reads by COLOUR only, the app rule — no
                // checkmark, no border swap.
                selected: (preset - size).abs() < _match,
                colorScheme: colorScheme,
                onTap: () => onSizeSelected(preset),
              ),
          ],
        ),
      ),
    );
  }
}

class _SizeChip extends StatelessWidget {
  const _SizeChip({
    super.key,
    required this.label,
    required this.selected,
    required this.colorScheme,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final ColorScheme colorScheme;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected
          ? colorScheme.primaryContainer
          : colorScheme.surfaceContainerHighest,
      // The app's ONE corner (CLAUDE.md: 「모서리는 AppShapes 만 쓴다」) — a
      // chip is a small control, so it takes the small control's shape
      // rather than a radius of its own.
      shape: AppShapes.control(AppShapes.controlSmall),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          width: 44,
          height: 28,
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: selected
                    ? colorScheme.onPrimaryContainer
                    : colorScheme.onSurface,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
