import 'package:flutter/material.dart';

import '../editor_session_manager.dart';
import '../../models/app_accents.dart';
import '../theme/app_theme.dart' show AppColors, AppShapes;
import '../text/app_strings.dart';
import '../widgets/settings_rows.dart';
import '../input/control_press_claim.dart';

/// A compact swatch palette (hue sweep + the historical teal first).
const List<Color> _presetAccents = [
  AppAccentSettings.defaultAccent,
  Color(0xFF5B9BD5),
  Color(0xFF7E6BD9),
  Color(0xFFC85C9E),
  Color(0xFFD96A5B),
  Color(0xFFD9A45B),
  Color(0xFF9BBF4E),
  Color(0xFF4EBF7E),
];

/// The two-accent settings (UI-R22 #5): accent 1 (selection, playhead,
/// active toggles) and accent 2 (the secondary highlight — repeat pattern
/// spans, selected union diamonds). Accent 2 follows accent 1's COMPLEMENT
/// automatically unless overridden; both apply and persist immediately.
/// Dialog-free: SAVE-1 made the Preferences dialog its one home (the
/// standalone dialog that wrapped it went with its caller).
class AccentSettingsSection extends StatelessWidget {
  const AccentSettingsSection({super.key, required this.session});

  final EditorSessionManager session;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<AppAccentSettings>(
      valueListenable: AppColors.accentSettings,
      builder: (context, settings, _) {
        final strings = AppText.strings;
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _AccentRow(
              keyPrefix: 'settings-accent1',
              label: strings.accent1Label,
              help: strings.accent1Help,
              value: settings.accent,
              onChanged: (color) =>
                  session.setAccentSettings(settings.copyWith(accent: color)),
            ),
          ],
        );
      },
    );
  }
}

class _AccentRow extends StatelessWidget {
  const _AccentRow({
    required this.keyPrefix,
    required this.label,
    required this.help,
    required this.value,
    required this.onChanged,
  });

  final String keyPrefix;
  final String label;
  final String help;
  final Color value;
  final ValueChanged<Color> onChanged;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              key: ValueKey<String>('$keyPrefix-swatch'),
              width: 22,
              height: 22,
              decoration: ShapeDecoration(
                color: value,
                shape: AppShapes.container(
                  AppShapes.wellRadius,
                  side: BorderSide(color: colorScheme.outline),
                ),
              ),
            ),
            const SizedBox(width: 8),
            // F-2: what this accent colours is a TOOLTIP on its name now,
            // not a caption under it.
            settingsHelpTooltip(
              help,
              Text(label, style: Theme.of(context).textTheme.titleSmall),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final preset in _presetAccents)
              ControlPressClaim(
                onPressed: () => onChanged(preset),
                child: InkWell(
                  key: ValueKey<String>(
                    '$keyPrefix-preset-${preset.toARGB32().toRadixString(16)}',
                  ),
                  onTap: silentPress(() => onChanged(preset)),
                  customBorder: AppShapes.container(AppShapes.wellRadius),
                  child: Container(
                    width: 24,
                    height: 24,
                    decoration: ShapeDecoration(
                      color: preset,
                      shape: AppShapes.container(
                        AppShapes.wellRadius,
                        side: BorderSide(
                          color: preset == value
                              ? colorScheme.onSurface
                              : colorScheme.outlineVariant,
                          width: preset == value ? 2 : 1,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}
