import 'package:flutter/material.dart';

/// THE settings row pair — a label, a control, and the explanation as a
/// TOOLTIP.
///
/// 🚨F-2 (유저 2026-08-24): 「텍스트가 쓸데없이 설명적인 부분이 너무 많음. 특히
/// 환경설정은 텍스트가 너무 심함. … 쓸데없는 텍스트 싹 다 삭제하고 그 중에서
/// 필요해보이는건 툴팁으로 넣도록」. The standing rule it restates:
/// ⛔no explanatory copy under a control (warnings excepted).
///
/// ★These exist so the rule cannot be broken by writing one more
/// `subtitle:`. A settings row takes `help` and has NOWHERE to put it but a
/// tooltip — the explanation is not lost, it just stops taking a line of the
/// window. Sixteen tiles used to spell the tile out by hand, and every one of
/// them had somewhere to put a caption.
///
/// [tileKey] goes on the TILE, not on the wrapper: the keys these rows carry
/// are what tests tap and read state off (`tester.widget<SwitchListTile>`),
/// and a key that lands on a `Tooltip` breaks that read while still finding.
class SettingsSwitchRow extends StatelessWidget {
  const SettingsSwitchRow({
    super.key,
    this.tileKey,
    required this.label,
    this.help,
    required this.value,
    required this.onChanged,
  });

  final Key? tileKey;
  final String label;

  /// What the control does, for the tooltip. Null where the label says it
  /// on its own — which is most of them.
  final String? help;

  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    return settingsHelpTooltip(
      help,
      SwitchListTile(
        key: tileKey,
        contentPadding: EdgeInsets.zero,
        dense: true,
        title: Text(label),
        value: value,
        onChanged: onChanged,
      ),
    );
  }
}

/// The same law for controls that are not list tiles — a slider, a picker, a
/// swatch. Null [help] passes the child straight through, so a caller never
/// has to write the conditional.
Widget settingsHelpTooltip(String? help, Widget child) =>
    help == null || help.isEmpty
    ? child
    : Tooltip(message: help, child: child);

/// A settings SECTION heading — the words above a group of controls, with
/// whatever the group needed explaining as its tooltip.
///
/// Same law as [SettingsSwitchRow], one level up: the paragraph that used to
/// sit under each of these headings is where the Preferences window spent
/// most of its height.
class SettingsSectionHeading extends StatelessWidget {
  const SettingsSectionHeading({super.key, required this.label, this.help});

  final String label;
  final String? help;

  @override
  Widget build(BuildContext context) => settingsHelpTooltip(
    help,
    Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
  );
}
