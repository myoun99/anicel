import 'package:flutter/material.dart';

import '../dialogs/app_prompt_dialog.dart';
import '../text/app_strings.dart';

/// The cut's note. Pops the trimmed text — including an empty string,
/// which CLEARS the note; that is a real edit, not a mistake.
class CutNoteDialog extends StatelessWidget {
  const CutNoteDialog({super.key, required this.initialNote});

  final String initialNote;

  @override
  Widget build(BuildContext context) {
    final strings = AppText.strings;
    return AppPromptDialog(
      windowKey: const ValueKey<String>('cut-note-dialog'),
      title: strings.cutNoteTitle,
      titleIcon: Icons.sticky_note_2_outlined,
      fieldLabel: strings.cutNoteField,
      initialValue: initialNote,
      confirmLabel: strings.commonSave,
      multiline: true,
      fieldKey: const ValueKey<String>('cut-note-text-field'),
      cancelKey: const ValueKey<String>('cancel-cut-note-button'),
      confirmKey: const ValueKey<String>('save-cut-note-button'),
    );
  }
}
