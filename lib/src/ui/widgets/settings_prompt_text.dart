import 'package:flutter/material.dart';

/// The settings panels' muted prompt line — what a panel says when there
/// is nothing selected for it to edit ("pick a guide", "nothing held").
///
/// One styled line: top-left, the small body style in the muted surface
/// colour. The slot around it (the padding, the key that reserves the
/// panel's place) belongs to the caller; this widget is only the text.
class SettingsPromptText extends StatelessWidget {
  const SettingsPromptText(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Align(
      alignment: Alignment.topLeft,
      child: Text(
        text,
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}
