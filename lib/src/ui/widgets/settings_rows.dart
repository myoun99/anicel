import 'app_tooltip.dart';
import 'package:flutter/material.dart';

import 'app_icon_button.dart';
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
/// there; they are this row now — the ring sits on the right.
/// `one_boolean_control_test` holds the line.
///
/// 🚨★★★ONLY THE RING PRESSES; THE LABEL IS WORDS — 유저 2026-10-23 (board
/// `F-439-Q1`): 「링만 컨트롤, 라벨은 글자」. A drag that starts on the label
/// scrolls the window under it, and a press there does nothing. ↩️09-24 made
/// the whole row the control (「라벨을 눌러도 켜지고 꺼진다」), and with the
/// press law a drag that began anywhere on a row was the row's: a window of
/// switch rows (Preferences ▸ Input) left a pen almost nowhere to start a
/// scroll (F-439).
///
/// [tileKey] goes on the TILE, not on the wrapper: a key that lands on the
/// `Tooltip` would still FIND the row and no longer reach it. A test that
/// presses the row presses its ring (`pressRingIn`).
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
    this.leading,
    this.help,
    required this.value,
    required this.onChanged,
    this.mixed = false,
    this.inPickOneGroup = false,
  });

  final Key? tileKey;
  final String label;

  /// What the row IS, before its label, where the label alone does not say
  /// it — the export window's attach column marks the base and an attach
  /// row's side there (export-four-tabs).
  final Widget? leading;

  /// What the control does, for the tooltip. Null where the label says it
  /// on its own — which is most of them.
  final String? help;

  final bool value;
  final ValueChanged<bool>? onChanged;

  /// See [BooleanDot.mixed] — [value] is false with it, so a press hands
  /// [onChanged] true.
  final bool mixed;

  /// See [BooleanDot.inPickOneGroup].
  final bool inPickOneGroup;

  /// The ring's key — the tile's, said of its ring, where the tile has one
  /// a test can read.
  String get _ringKeyValue => switch (tileKey) {
    ValueKey<String>(:final value) => '$value-ring',
    _ => '$label-ring',
  };

  /// 🚨★★★The ring CLAIMS ITS PRESS, like every other control in the app —
  /// a mouse is hardcoded to a ONE PIXEL drag threshold, so a click that
  /// wobbled used to be handed to the scrolling window and the toggle
  /// cancelled. 유저 answered the shape on board `press-law-switches`:
  /// **탭만**. The ring is the app's ring as a button of its own
  /// ([BooleanDotButton], guide-sym ⑥⑧: 「앞으로 이런 불리언값 바꾸는 버튼은
  /// 이걸 공통적으로 사용」), so it claims as every button does.
  @override
  Widget build(BuildContext context) {
    final changed = onChanged;
    final enabled = changed != null;
    return settingsHelpTooltip(
      help,
      ListTile(
        key: tileKey,
        // Flush — unless the surface keeps a column at the end of its
        // rows (a tool's settings: its ring stands where the boxes end).
        contentPadding:
            ListTileTheme.of(context).contentPadding ?? EdgeInsets.zero,
        // Dense — unless the surface it stands on says otherwise. A dense
        // tile sets its name at 13 whatever its theme says, so a surface
        // whose rows are named in a style of its own (the tool settings
        // panel, tool-settings-panel-tidy 2026-10-10: 「이름 글자 하나」)
        // takes the density off with that style.
        dense: ListTileTheme.of(context).dense ?? true,
        enabled: enabled,
        leading: leading,
        minLeadingWidth: leading == null ? null : 0,
        horizontalTitleGap: leading == null ? null : 6,
        title: Text(label),
        trailing: BooleanDotButton(
          keyValue: _ringKeyValue,
          tooltip: label,
          value: value,
          mixed: mixed,
          inPickOneGroup: inPickOneGroup,
          // The ring drawn where and as it was before it pressed: a box its
          // glyph wide, so its right edge stays on the grid's end (ONE
          // GRID), and no taller than the shortest row it stands in (a
          // tool's settings row).
          size: AppIconButtonBox(
            width: IconTheme.of(context).size!,
            height: AppIconButtonSize.bar.height,
            iconSize: IconTheme.of(context).size!,
          ),
          onChanged: changed,
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
