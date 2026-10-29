import 'app_tooltip.dart';
import 'package:flutter/material.dart';

import 'app_icon_button.dart';
import 'boolean_dot.dart';
import 'field_slider.dart';
import 'panel_flyout.dart';

/// THE settings row: its words on the left and its control at the right
/// end — a ring ([SettingsSwitchRow]), a picker ([SettingsPickerRow]), a
/// bar, a meter, a field and its unit — in one tile, so the rows down a
/// tab stand alike whatever they hold, and the explanation is a TOOLTIP
/// ([settingsHelpTooltip]).
///
/// 🗣️F-480 (유저 2026-10-26): 「화면탭의 UI크기 이런거 그냥 리스트팝오버로
/// 하면 깔끔하잖아. 왼쪽 UI크기 텍스트, 오른쪽에 고르는거. 이렇게 다른탭도
/// 통일」. ↩️Each tab laid its rows out by hand: pills under a heading (the
/// scale, the cursor), a label over its picker (the two languages), and
/// rows of their own a few pixels shorter than the switch tiles beside
/// them, each button as wide as its words.
///
/// [tileKey] goes on the TILE, not on the wrapper — see
/// [SettingsSwitchRow].
class SettingsRow extends StatelessWidget {
  const SettingsRow({
    super.key,
    this.tileKey,
    required this.label,
    required this.control,
    this.leading,
    this.help,
    this.enabled = true,
  });

  final Key? tileKey;
  final String label;

  /// What stands at the right end of the row.
  final Widget control;

  /// See [SettingsSwitchRow.leading].
  final Widget? leading;

  /// See [SettingsSwitchRow.help].
  final String? help;

  /// False dims the words; the control dims itself.
  final bool enabled;

  @override
  Widget build(BuildContext context) => settingsHelpTooltip(
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
      trailing: control,
    ),
  );
}

/// THE settings row that picks one of several: the button at its right end
/// opens the shared list ([PanelFlyoutButton]) — 「리스트팝오버」 (F-480,
/// [SettingsRow]).
///
/// Every picker is [width] wide, so the buttons down a tab stand in one
/// column.
class SettingsPickerRow extends StatelessWidget {
  const SettingsPickerRow({
    super.key,
    required this.pickerKey,
    required this.label,
    required this.picked,
    required this.entriesBuilder,
    this.help,
    this.pickedIcon,
  });

  /// The button's key — what the list is opened by.
  final Key pickerKey;
  final String label;

  /// What the button reads: the value picked now.
  final String picked;

  /// The face of the value picked now, for a value that IS a picture: the
  /// button wears it in place of [picked], which it says as its tooltip
  /// (F-497 — 「텍스트면 뭔지 알기힘드니」).
  final IconData? pickedIcon;

  /// Null leaves the row inert — there, dimmed — as a switch row with no
  /// `onChanged` is ([SettingsSwitchRow]).
  final List<PanelFlyoutEntry> Function()? entriesBuilder;

  /// See [SettingsSwitchRow.help].
  final String? help;

  /// How wide a settings control stands at the end of its row.
  static const double width = 180;

  @override
  Widget build(BuildContext context) {
    final entries = entriesBuilder;
    return SettingsRow(
      label: label,
      help: help,
      enabled: entries != null,
      control: SizedBox(
        width: width,
        child: PanelFlyoutButton(
          key: pickerKey,
          label: pickedIcon == null ? picked : '',
          icon: pickedIcon,
          tooltip: pickedIcon == null ? null : picked,
          expand: true,
          enabled: entries != null,
          entriesBuilder: entries ?? () => const [],
        ),
      ),
    );
  }
}

/// A NUMBER on a bar at the end of its row: the bar and its hands — its ±
/// and its pencil ([FieldSlider.cell]) — fill the column a picker does,
/// and its name is the row's words.
///
/// 🗣️F-480 (유저 2026-10-26): 「이렇게 다른탭도 통일」. ↩️The input tab's
/// bars wrote their name inside the bar, 320 wide from the row's start,
/// and the audio tab's stood bare (no hands) at its end — two bars in one
/// window.
class SettingsBarRow extends StatelessWidget {
  const SettingsBarRow({
    super.key,
    required this.barKey,
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
    this.onChangeEnd,
    this.scale = FieldSliderScale.linear,
    this.divisions,
    this.unit = '',
    this.valueTextBuilder,
  });

  /// The bar's key — what a hand drags.
  final Key barKey;
  final String label;
  final double value;
  final double min;
  final double max;
  /// Null leaves the row inert — the bar dims itself — as a switch row
  /// with no `onChanged` is ([SettingsSwitchRow]).
  final ValueChanged<double>? onChanged;
  final ValueChanged<double>? onChangeEnd;
  final FieldSliderScale scale;
  final int? divisions;
  final String unit;
  final String Function(double value, String derived)? valueTextBuilder;

  @override
  Widget build(BuildContext context) => SettingsRow(
    label: label,
    enabled: onChanged != null,
    control: SizedBox(
      width: SettingsPickerRow.width,
      child: FieldSlider.cell(
        key: barKey,
        label: label,
        value: value,
        min: min,
        max: max,
        scale: scale,
        divisions: divisions,
        unit: unit,
        valueTextBuilder: valueTextBuilder,
        onChanged: onChanged,
        onChangeEnd: onChangeEnd,
      ),
    ),
  );
}

/// A [SettingsPickerRow] over an enum's [values], each row of its list
/// keyed `'<keyValue>-<name>'`.
SettingsPickerRow settingsEnumPickerRow<T extends Enum>({
  required String keyValue,
  required String label,
  required T value,
  required Iterable<T> values,
  required String Function(T value) labelOf,
  required ValueChanged<T>? onPicked,
  String? help,
  IconData Function(T value)? iconOf,
}) => SettingsPickerRow(
  pickerKey: ValueKey<String>(keyValue),
  label: label,
  help: help,
  picked: labelOf(value),
  pickedIcon: iconOf?.call(value),
  entriesBuilder: onPicked == null
      ? null
      : () => values.asFlyoutChoices(
          current: value,
          keyPrefix: '$keyValue-',
          labelOf: labelOf,
          iconOf: iconOf,
          onPicked: onPicked,
        ),
);

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
    return SettingsRow(
      tileKey: tileKey,
      label: label,
      leading: leading,
      help: help,
      enabled: changed != null,
      control: BooleanDotButton(
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
