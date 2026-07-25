import 'package:flutter/material.dart';

import 'app_prompt_dialog.dart';

/// Rename dialog for a cut. Pops the trimmed new name, or nothing on
/// cancel. Rejects an empty name inline — the cut's name IS its number on
/// every sheet and storyboard page that prints it.
class RenameCutDialog extends StatelessWidget {
  const RenameCutDialog({super.key, required this.initialName});

  final String initialName;

  @override
  Widget build(BuildContext context) {
    return AppPromptDialog(
      windowKey: const ValueKey<String>('rename-cut-dialog'),
      title: 'Rename cut',
      titleIcon: Icons.drive_file_rename_outline,
      fieldLabel: 'Cut name',
      initialValue: initialName,
      confirmLabel: 'Rename',
      emptyError: 'Cut name cannot be empty.',
      fieldKey: const ValueKey<String>('rename-cut-text-field'),
      cancelKey: const ValueKey<String>('rename-cut-cancel-button'),
      confirmKey: const ValueKey<String>('rename-cut-confirm-button'),
    );
  }
}
