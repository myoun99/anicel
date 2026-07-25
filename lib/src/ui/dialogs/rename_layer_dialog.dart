import 'package:flutter/material.dart';

import '../text/app_strings.dart';
import 'app_prompt_dialog.dart';

/// Rename dialog for a layer. Pops the trimmed new name, or nothing on
/// cancel. Rejects an empty name inline.
class RenameLayerDialog extends StatelessWidget {
  const RenameLayerDialog({super.key, required this.initialName});

  final String initialName;

  @override
  Widget build(BuildContext context) {
    final strings = AppText.strings;
    return AppPromptDialog(
      windowKey: const ValueKey<String>('rename-layer-dialog'),
      title: strings.renameLayerTitle,
      titleIcon: Icons.drive_file_rename_outline,
      fieldLabel: strings.renameLayerField,
      initialValue: initialName,
      confirmLabel: strings.commonRename,
      emptyError: strings.renameLayerEmpty,
      fieldKey: const ValueKey<String>('rename-layer-text-field'),
      cancelKey: const ValueKey<String>('rename-layer-cancel-button'),
      confirmKey: const ValueKey<String>('rename-layer-ok-button'),
    );
  }
}
