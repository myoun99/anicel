import 'app_tooltip.dart';
import 'package:flutter/material.dart';

import '../input/control_press_claim.dart';
import 'boolean_dot.dart';

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
/// 🚨★★★AND IT IS EVERY LABELLED RING IN THE APP, wherever it stands —
/// 유저 2026-09-24 (board `one-boolean-row-shape-Q1`): 「설정 줄 하나로」.
/// The brush settings panel's switches pressed only at the ring, and the
/// export and import windows' put the ring on the LEFT and pressed only
/// there; they are this row now — the whole row presses, the ring sits on
/// the right, 「라벨을 눌러도 켜지고 꺼진다」. `one_boolean_control_test`
/// holds the line.
///
/// [tileKey] goes on the TILE, not on the wrapper: a key that lands on the
/// `Tooltip` would still FIND the row and no longer reach it, so a tap on it
/// would hit the tooltip.
///
/// ⚠️The row holds no value of its own — it is a plain `ListTile` around a
/// [BooleanDot]. Read the value where it lives:
///
/// ```dart
/// tester.widget<BooleanDot>(
///   find.descendant(
///     of: find.byKey(tileKey),
///     matching: find.byType(BooleanDot),
///   ),
/// ).value
/// ```
class SettingsSwitchRow extends StatelessWidget {
  const SettingsSwitchRow({
    super.key,
    this.tileKey,
    required this.label,
    this.help,
    required this.value,
    required this.onChanged,
    this.inPickOneGroup = false,
  });

  final Key? tileKey;
  final String label;

  /// What the control does, for the tooltip. Null where the label says it
  /// on its own — which is most of them.
  final String? help;

  final bool value;
  final ValueChanged<bool>? onChanged;

  /// See [BooleanDot.inPickOneGroup].
  final bool inPickOneGroup;

  /// 🚨★★★The row CLAIMS ITS PRESS, like every other control in the app —
  /// the Preferences window scrolls, and a mouse is hardcoded to a ONE PIXEL
  /// drag threshold, so a click that wobbled here used to be handed to the
  /// window and the toggle cancelled. 유저 answered the shape on board
  /// `press-law-switches`: **탭만**. The claim sits INSIDE the tooltip: a
  /// wrapper outside one is not the thing the pointer lands on.
  @override
  Widget build(BuildContext context) {
    final enabled = onChanged != null;
    return settingsHelpTooltip(
      help,
      ControlPressClaim(
        onPressed: enabled ? () => onChanged!(!value) : null,
        // 🚨THE SHARED BOOLEAN (guide-sym ⑥⑧: 「앞으로 이런 불리언값 바꾸는
        // 버튼은 이걸 공통적으로 사용」): the ring, dotted when on. The row
        // draws it and keeps the press — the whole row is the control, as
        // it always was, and a button of its own in here would fire twice.
        child: ListTile(
          key: tileKey,
          contentPadding: EdgeInsets.zero,
          dense: true,
          enabled: enabled,
          title: Text(label),
          trailing: BooleanDot(
            value: value,
            inPickOneGroup: inPickOneGroup,
            enabled: enabled,
          ),
        ),
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
    : AppTooltip(message: help, child: child);

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
