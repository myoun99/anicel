import 'package:flutter/material.dart';

import '../editor_session_manager.dart';
import '../../models/app_accents.dart';
import '../theme/app_theme.dart' show AppColors, AppCursors, AppShapes;
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

/// The accent (UI-R22 #5): accent 1 — selection, playhead, active toggles —
/// picked from the palette, and accent 2 — the secondary highlight, repeat
/// pattern spans and selected union diamonds — following its COMPLEMENT.
/// Applies and persists at once.
///
/// 🗣️F-480 (유저 2026-10-26): 「강조색상 탭, 이게 화면이랑 같이 안있고
/// 독립적으로 있는게 의문임. 화면탭에 넣도록」 — a row of the display tab
/// ([SettingsRow]), the palette where its control stands. ↩️A tab of its
/// own: the colour and its name over the palette.
class AccentSettingsRow extends StatelessWidget {
  const AccentSettingsRow({super.key, required this.session});

  final EditorSessionManager session;

  static const String _keyPrefix = 'settings-accent1';

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final strings = AppText.strings;
    return ValueListenableBuilder<AppAccentSettings>(
      valueListenable: AppColors.accentSettings,
      builder: (context, settings, _) {
        void pick(Color preset) =>
            session.setAccentSettings(settings.copyWith(accent: preset));
        return SettingsRow(
          label: strings.prefsAccent,
          help: strings.accent1Help,
          control: Row(
            mainAxisSize: MainAxisSize.min,
            spacing: 6,
            children: [
              for (final preset in _presetAccents)
                ControlPressClaim(
                  onPressed: () => pick(preset),
                  child: InkWell(
                    mouseCursor: AppCursors.press,
                    key: ValueKey<String>(
                      '$_keyPrefix-preset-'
                      '${preset.toARGB32().toRadixString(16)}',
                    ),
                    onTap: silentPress(() => pick(preset)),
                    customBorder: AppShapes.container(AppShapes.wellRadius),
                    child: Container(
                      width: 24,
                      height: 24,
                      decoration: ShapeDecoration(
                        color: preset,
                        shape: AppShapes.container(
                          AppShapes.wellRadius,
                          side: BorderSide(
                            color: preset == settings.accent
                                ? colorScheme.onSurface
                                : colorScheme.outlineVariant,
                            width: preset == settings.accent ? 2 : 1,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}
