import 'package:flutter/material.dart';

import '../input/control_press_claim.dart' show ControlPressClaim, silentPress;
import '../theme/app_theme.dart' show AppShapes;
import '../widgets/pill_strip.dart';
import 'tool_settings_section.dart' show ToolSettingsSection;

/// A setting that is ONE OF A FEW ANSWERS, as the app's one grouped choice
/// ([PillStrip]) at the end of its line: the answer it is at lit, each
/// answer taking a press or refusing it as [onPick] says of that answer.
///
/// ONE ROW FOR EVERY TOOL'S SETTINGS. The text tool's rows were the first
/// drawn this way; the shape tool's are drawn by this same widget, not by
/// one like it.
class ToolSettingChoiceRow<T> extends StatelessWidget {
  const ToolSettingChoiceRow({
    super.key,
    required this.tool,
    required this.name,
    required this.label,
    required this.answers,
    required this.current,
    required this.onPick,
  });

  /// What the strip and its pills are keyed by: `<tool>-<name>`, and
  /// `<tool>-<name>-<key>` for each answer.
  final String tool;
  final String name;
  final String label;
  final List<({T value, String key, String label})> answers;

  /// The answer the setting is at — null where it is at none of them, and
  /// no pill is lit.
  final T? current;

  /// What a press on [answer] does; null where that answer is refused —
  /// the pill keeps its place and loses its tap.
  final VoidCallback? Function(T answer) onPick;

  @override
  Widget build(BuildContext context) => ToolSettingRow(
    label: label,
    child: PillStrip(
      key: ValueKey<String>('$tool-$name'),
      items: [
        for (final answer in answers)
          PillItem(
            keyValue: '$tool-$name-${answer.key}',
            label: answer.label,
            selected: answer.value == current,
            onTap: onPick(answer.value),
          ),
      ],
    ),
  );
}

/// One row of a [ToolSettingGrid]: its name, what stands at the end of the
/// name's cell (the scale row's chain), and its two cells.
typedef ToolSettingGridRow = ({
  String label,
  Widget? labelEnd,
  Widget first,
  Widget second,
});

/// Settings in ROWS AND COLUMNS: a name column as wide as its widest name,
/// then two cells whose columns line up from row to row — X under X, Y
/// under Y.
///
/// 🗣️tool-settings-panel-tidy (유저, F-328 2026-10-10): 「특히 변형도구는
/// 그냥 이름이랑 숫자의 나열일뿐이고 정돈된 행과 열이라는 아름다움이
/// 안느껴짐」 — answered 「다 추천대로」: a pair is one row, its two values
/// side by side.
class ToolSettingGrid extends StatelessWidget {
  const ToolSettingGrid({super.key, required this.rows});

  final List<ToolSettingGridRow> rows;

  /// Between the columns — the section's one rhythm.
  static const double _gap = ToolSettingsSection.rowGap;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.labelSmall;
    return Table(
      columnWidths: const {
        0: IntrinsicColumnWidth(),
        1: FlexColumnWidth(),
        2: FlexColumnWidth(),
      },
      defaultVerticalAlignment: TableCellVerticalAlignment.middle,
      children: [
        for (final row in rows)
          TableRow(
            children: [
              Padding(
                padding: const EdgeInsets.only(right: _gap, bottom: _gap),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(row.label, style: style),
                    if (row.labelEnd case final end?) ...[
                      const SizedBox(width: 2),
                      end,
                    ],
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(bottom: _gap),
                child: row.first,
              ),
              Padding(
                padding: const EdgeInsets.only(left: _gap, bottom: _gap),
                child: row.second,
              ),
            ],
          ),
      ],
    );
  }
}

/// A BAR's row as every tool writes it: the bar, and the section's row gap
/// under it ([ToolSettingsSection.rowGap]) — the brush's rhythm.
/// ↩️The sections stood their bars apart by hand, 8 here and 16 there.
class ToolSettingBar extends StatelessWidget {
  const ToolSettingBar(this.bar, {super.key});

  final Widget bar;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: ToolSettingsSection.rowGap),
    child: bar,
  );
}

/// A tool's ACTIONS — the buttons that do something rather than set
/// something — at the end of its settings: one height, the buttons of a
/// line one width each, the one that decides filled.
///
/// 🗣️tool-settings-panel-tidy (유저 2026-10-10, 「다 추천대로」): 「동작 버튼은
/// 맨 아래 한 줄 — 같은 높이, 같은 폭. 결정하는 버튼(적용)만 채운 모양」.
/// A line holds what fits side by side; a tool with an action whose name
/// will not share a line (the stamp's 「원래 위치에 붙여넣기」) gives it a
/// line of its own above. ↩️The transform tool's four were a `Wrap` of three
/// outlined and one filled button whose heights differed, folding onto two
/// lines.
class ToolSettingActions extends StatelessWidget {
  const ToolSettingActions({super.key, required this.lines});

  /// Top to bottom, each line's buttons left to right.
  final List<List<Widget>> lines;

  /// What stands between the settings and the actions.
  static const double _above = 12;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: _above),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final (row, line) in lines.indexed) ...[
          if (row > 0) const SizedBox(height: ToolSettingsSection.rowGap),
          Row(
            children: [
              for (final (i, action) in line.indexed) ...[
                if (i > 0) const SizedBox(width: ToolSettingsSection.rowGap),
                Expanded(child: action),
              ],
            ],
          ),
        ],
      ],
    ),
  );
}

/// One button of [ToolSettingActions]. [decides] fills it — the action the
/// others lead up to (적용).
class ToolSettingAction extends StatelessWidget {
  const ToolSettingAction({
    super.key,
    required this.keyValue,
    required this.label,
    required this.onPressed,
    this.decides = false,
  });

  final String keyValue;
  final String label;
  final VoidCallback? onPressed;
  final bool decides;

  /// Both kinds at the dialog action's height and corner
  /// ([AppShapes.controlMedium]), so the outlined and the filled one stand
  /// the same size side by side.
  static final ButtonStyle _size = ButtonStyle(
    minimumSize: const WidgetStatePropertyAll(
      Size(0, AppShapes.controlMedium),
    ),
    padding: const WidgetStatePropertyAll(
      EdgeInsets.symmetric(horizontal: 8),
    ),
    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    shape: WidgetStatePropertyAll(
      AppShapes.control(AppShapes.controlMedium),
    ),
  );

  /// The press is the button's ([ControlPressClaim]): a drag that starts on
  /// it never scrolls the panel. ↩️The transform tool's buttons were bare
  /// Material buttons, firing from the tap a scroll could take.
  @override
  Widget build(BuildContext context) {
    final words = Text(label, maxLines: 1, overflow: TextOverflow.ellipsis);
    final key = ValueKey<String>(keyValue);
    final look = silentPress(onPressed);
    return ControlPressClaim(
      onPressed: onPressed,
      child: decides
          ? FilledButton(key: key, style: _size, onPressed: look, child: words)
          : OutlinedButton(
              key: key,
              style: _size,
              onPressed: look,
              child: words,
            ),
    );
  }
}

/// A setting whose control stands at the end of its line — a swatch, a
/// strip of pills — its name where the line begins: the row the brush's
/// settings write a labelled picker in.
class ToolSettingRow extends StatelessWidget {
  const ToolSettingRow({super.key, required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: ToolSettingsSection.rowGap),
    child: Row(
      children: [
        Text(label, style: Theme.of(context).textTheme.labelSmall),
        const SizedBox(width: 8),
        Expanded(
          child: Align(alignment: Alignment.centerRight, child: child),
        ),
      ],
    ),
  );
}
