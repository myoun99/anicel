import 'package:flutter/material.dart';

import '../editor_session_manager.dart';
import '../theme/app_accents.dart';
import '../theme/app_theme.dart' show AppColors;
import '../widgets/app_window.dart';

/// The two-accent settings dialog (UI-R22 #5): accent 1 (selection,
/// playhead, active toggles) and accent 2 (the secondary highlight —
/// repeat pattern spans, selected union diamonds). Accent 2 follows
/// accent 1's COMPLEMENT automatically unless overridden; both apply and
/// persist immediately.
Future<void> showAccentSettingsDialog(
  BuildContext context, {
  required EditorSessionManager session,
}) {
  return showDialog<void>(
    context: context,
    builder: (context) => _AccentSettingsDialog(session: session),
  );
}

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

class _AccentSettingsDialog extends StatelessWidget {
  const _AccentSettingsDialog({required this.session});

  final EditorSessionManager session;

  @override
  Widget build(BuildContext context) {
    return AppWindow(
      windowKey: const ValueKey<String>('accent-settings-dialog'),
      title: 'Accent colors',
      titleIcon: Icons.palette_outlined,
      onClose: () => Navigator.of(context).pop(),
      width: 420,
      body: AccentSettingsSection(session: session),
      actions: [
        AppWindowAction(
          label: 'Close',
          actionKey: const ValueKey<String>('settings-accent-close'),
          emphasis: AppWindowActionEmphasis.primary,
          onPressed: () => Navigator.of(context).pop(),
        ),
      ],
    );
  }
}

/// The accent-settings CONTENT, dialog-free (SAVE-1: the Preferences
/// dialog embeds it as a section; the standalone dialog wraps it).
class AccentSettingsSection extends StatelessWidget {
  const AccentSettingsSection({super.key, required this.session});

  final EditorSessionManager session;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<AppAccentSettings>(
      valueListenable: AppColors.accentSettings,
      builder: (context, settings, _) {
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _AccentRow(
              keyPrefix: 'settings-accent1',
              label: 'Accent 1',
              help: 'Selection, playhead, active toggles.',
              value: settings.accent,
              onChanged: (color) =>
                  session.setAccentSettings(settings.copyWith(accent: color)),
            ),
            const SizedBox(height: 16),
            CheckboxListTile(
              key: const ValueKey<String>('settings-accent2-auto'),
              contentPadding: EdgeInsets.zero,
              dense: true,
              controlAffinity: ListTileControlAffinity.leading,
              title: const Text('Accent 2 follows the complement'),
              subtitle: const Text(
                'Repeat patterns and selected key diamonds use accent 2.',
              ),
              value: settings.accent2FollowsComplement,
              onChanged: (auto) => session.setAccentSettings(
                auto ?? true
                    ? settings.copyWith(clearAccent2: true)
                    : settings.copyWith(accent2: settings.accent2),
              ),
            ),
            _AccentRow(
              keyPrefix: 'settings-accent2',
              label: 'Accent 2',
              help: settings.accent2FollowsComplement
                  ? 'Automatic: the complement of accent 1.'
                  : 'Custom accent 2.',
              value: settings.accent2,
              enabled: !settings.accent2FollowsComplement,
              onChanged: (color) =>
                  session.setAccentSettings(settings.copyWith(accent2: color)),
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
    this.enabled = true,
  });

  final String keyPrefix;
  final String label;
  final String help;
  final Color value;
  final ValueChanged<Color> onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Opacity(
      opacity: enabled ? 1 : 0.45,
      child: IgnorePointer(
        ignoring: !enabled,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  key: ValueKey<String>('$keyPrefix-swatch'),
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                    color: value,
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: colorScheme.outline),
                  ),
                ),
                const SizedBox(width: 8),
                Text(label, style: Theme.of(context).textTheme.titleSmall),
              ],
            ),
            const SizedBox(height: 4),
            Text(help, style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final preset in _presetAccents)
                  InkWell(
                    key: ValueKey<String>(
                      '$keyPrefix-preset-${preset.toARGB32().toRadixString(16)}',
                    ),
                    onTap: () => onChanged(preset),
                    borderRadius: BorderRadius.circular(4),
                    child: Container(
                      width: 24,
                      height: 24,
                      decoration: BoxDecoration(
                        color: preset,
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(
                          color: preset == value
                              ? colorScheme.onSurface
                              : colorScheme.outlineVariant,
                          width: preset == value ? 2 : 1,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
