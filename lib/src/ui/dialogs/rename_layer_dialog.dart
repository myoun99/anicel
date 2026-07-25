import 'package:flutter/material.dart';

import 'app_prompt_dialog.dart';

/// Rename dialog for a layer. Pops the trimmed new name, or nothing on
/// cancel. Rejects an empty name inline.
class RenameLayerDialog extends StatelessWidget {
  const RenameLayerDialog({super.key, required this.initialName});

  final String initialName;

  @override
  Widget build(BuildContext context) {
    return AppPromptDialog(
      windowKey: const ValueKey<String>('rename-layer-dialog'),
      title: 'Rename layer',
      titleIcon: Icons.drive_file_rename_outline,
      fieldLabel: 'Layer name',
      initialValue: initialName,
      confirmLabel: 'Rename',
      emptyError: 'Layer name cannot be empty.',
      fieldKey: const ValueKey<String>('rename-layer-text-field'),
      cancelKey: const ValueKey<String>('rename-layer-cancel-button'),
      confirmKey: const ValueKey<String>('rename-layer-ok-button'),
    );
  }
}
