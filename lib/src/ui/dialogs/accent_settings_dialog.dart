import 'package:flutter/material.dart';

import '../editor_session_manager.dart';
import '../theme/app_accents.dart';
import '../../models/layer_mark.dart';
import '../../models/layer_process.dart';
import '../theme/layer_mark_palette.dart';
import '../theme/app_theme.dart' show AppColors, AppShapes;
import '../widgets/app_window.dart';
import '../text/app_strings.dart';
import '../widgets/settings_rows.dart';

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
      title: AppText.strings.accentTitle,
      titleIcon: Icons.palette_outlined,
      onClose: () => Navigator.of(context).pop(),
      width: 420,
      body: AccentSettingsSection(session: session),
      actions: [
        AppWindowAction(
          label: AppText.strings.commonClose,
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
            const SizedBox(height: 12),
            // 색 라벨의 톤. ⚠️여기 사는 이유는 [AppAccentSettings] 에 사는
            // 이유와 같다 — 프로젝트가 아니라 에디터의 색 취향이고, 이 창이
            // 이미 그것이다.
            _MarkPaletteRow(
              value: settings.layerMarkPalette,
              onChanged: (palette) => session.setAccentSettings(
                settings.copyWith(layerMarkPalette: palette),
              ),
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
              decoration: BoxDecoration(
                color: value,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: colorScheme.outline),
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
    );
  }
}

/// The 색 라벨 tone picker — four strips of the SAME hues (I-4).
///
/// 🚨★★★EACH ROW IS THE REAL PALETTE, not a name in a dropdown. The user
/// asked for exactly this: 「ABCD 네개 다 구현해서 **프로그램 내에서 직접
/// 보면서 확인**하고싶어. 설정같은곳에서 색 고를수있게」 — a tone is chosen by
/// looking at it, and the mark paints whole frame blocks, so a swatch strip
/// is the smallest honest preview.
///
/// ⛔No caption under the control (F-2) and no checkmark on the selection —
/// the chosen row is said with colour and weight alone, which is this app's
/// law for «selected».
class _MarkPaletteRow extends StatelessWidget {
  const _MarkPaletteRow({required this.value, required this.onChanged});

  final LayerMarkPalette value;
  final ValueChanged<LayerMarkPalette> onChanged;

  /// The stages a strip previews. ⚠️Stages rather than corrections: they are
  /// what a project is mostly made of, and they carry the palette's whole
  /// range (white through orange).
  static const List<LayerProcess> _preview = LayerProcess.values;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          AppText.strings.layerMarkPaletteLabel,
          style: Theme.of(context).textTheme.titleSmall,
        ),
        const SizedBox(height: 8),
        for (final palette in LayerMarkPalette.values) ...[
          InkWell(
            key: ValueKey<String>('settings-mark-palette-${palette.jsonValue}'),
            onTap: () => onChanged(palette),
            borderRadius: const BorderRadius.all(Radius.circular(AppShapes.wellRadius)),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              decoration: BoxDecoration(
                borderRadius: const BorderRadius.all(Radius.circular(AppShapes.wellRadius)),
                border: Border.all(
                  color: palette == value
                      ? colorScheme.onSurface
                      : colorScheme.outlineVariant,
                  width: palette == value ? 2 : 1,
                ),
              ),
              child: Row(
                children: [
                  SizedBox(
                    width: 56,
                    child: Text(
                      palette.displayName,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                  for (final process in _preview)
                    Container(
                      width: 18,
                      height: 18,
                      margin: const EdgeInsets.only(right: 3),
                      decoration: BoxDecoration(
                        color: resolveLayerMarkColor(
                          LayerMark(process: process),
                          palette,
                          noneColor: colorScheme.surface,
                        ),
                        borderRadius: const BorderRadius.all(Radius.circular(AppShapes.wellRadius)),
                        border: Border.all(color: colorScheme.outlineVariant),
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 4),
        ],
      ],
    );
  }
}
