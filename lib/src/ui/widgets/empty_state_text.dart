import 'package:flutter/material.dart';

/// Where a panel's one empty line sits — 유저 2026-09-15
/// (empty-state-placement-Q1): 「내용이 올 자리에」.
enum EmptyStatePlace {
  /// A list or a column that fills from the top — the layer rail, the
  /// X-sheet, the render queue, the saved setups, the media pool, a tool's
  /// settings: the line sits where the first row would.
  list,

  /// A stage whose content sits in the middle — the viewer, a timeline or a
  /// timesheet with no cut: the line sits in the middle.
  stage,
}

/// What a panel says when it has nothing to show — ONE short line, one look.
///
/// 🚨유저 2026-09-15 (empty-state-law-Q1): 「공용 위젯 하나 + 짧은 한 줄」.
/// Every panel said it its own way — centred or top-left, in the default
/// size, bodySmall, 10 or 12 — and three said it in English whatever the
/// language. The size and the colour are this widget's, never the caller's;
/// what a panel says is the line and which [EmptyStatePlace] it is.
///
/// ⛔One line: no usage sentence under it (「설명 문구 금지」). The slot around
/// it — the padding, the key that reserves the panel's place — stays the
/// caller's, so a panel keeps its space whether it is empty or not.
///
/// ↩️It grew out of `SettingsPromptText`, the settings panels' muted prompt
/// line, which was already this look for [EmptyStatePlace.list].
class EmptyStateText extends StatelessWidget {
  const EmptyStateText(this.text, {super.key, required this.place});

  final String text;
  final EmptyStatePlace place;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final stage = place == EmptyStatePlace.stage;
    return Align(
      alignment: stage ? Alignment.center : Alignment.topLeft,
      child: Text(
        text,
        textAlign: stage ? TextAlign.center : TextAlign.start,
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}
