import 'package:flutter/material.dart';

import '../widgets/pill_strip.dart';

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

/// A setting whose control stands at the end of its line — a swatch, a
/// strip of pills — its name where the line begins: the row the brush's
/// settings write a labelled picker in.
class ToolSettingRow extends StatelessWidget {
  const ToolSettingRow({super.key, required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
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
