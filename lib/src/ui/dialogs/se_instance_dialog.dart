import 'package:flutter/material.dart';

import '../widgets/app_window.dart';
import 'instance_edit_dialog.dart';
import 'instance_edit_preview.dart';

/// What the SE instance dialog resolved to: the (possibly empty) speaker
/// name and the dialogue text.
class SeInstanceDialogResult {
  const SeInstanceDialogResult({required this.seName, required this.dialogue});

  final String seName;
  final String dialogue;
}

/// The SE layer's instance editor — name (speaker/effect, accent box) +
/// dialogue (can run long → multiline) with the live paper-block preview.
/// New entries are created ONE frame long, like drawing cels — the comma
/// grips own the length afterwards (the R3 length input is retired). Pops
/// a [SeInstanceDialogResult], or nothing on cancel.
class SeInstanceDialog extends StatefulWidget {
  const SeInstanceDialog({
    super.key,
    this.initialSeName = '',
    this.initialDialogue = '',
    this.creating = false,
    this.previewAxis = Axis.horizontal,
  });

  final String initialSeName;
  final String initialDialogue;

  /// Whether a new entry is being created (title wording only).
  final bool creating;

  /// Follows the timeline orientation so the preview matches what the
  /// user is looking at.
  final Axis previewAxis;

  @override
  State<SeInstanceDialog> createState() => _SeInstanceDialogState();
}

class _SeInstanceDialogState extends State<SeInstanceDialog> {
  late final TextEditingController _seNameController = TextEditingController(
    text: widget.initialSeName,
  );
  late final TextEditingController _dialogueController = TextEditingController(
    text: widget.initialDialogue,
  );

  @override
  void initState() {
    super.initState();
    // Live preview: repaint on every keystroke.
    _seNameController.addListener(_onFieldsChanged);
    _dialogueController.addListener(_onFieldsChanged);
  }

  void _onFieldsChanged() => setState(() {});

  @override
  void dispose() {
    _seNameController.dispose();
    _dialogueController.dispose();
    super.dispose();
  }

  void _submit() {
    Navigator.of(context).pop(
      SeInstanceDialogResult(
        seName: _seNameController.text.trim(),
        dialogue: _dialogueController.text.trim(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return InstanceEditDialogShell(
      title: widget.creating ? 'New SE' : 'Edit SE',
      titleIcon: Icons.music_note_outlined,
      body: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppWindowField(
            label: 'Name (speaker — blank hides the box)',
            child: TextField(
              key: const ValueKey<String>('se-name-field'),
              controller: _seNameController,
            ),
          ),
          const SizedBox(height: 12),
          AppWindowField(
            label: 'Dialogue',
            emphasized: true,
            child: TextField(
              key: const ValueKey<String>('se-dialogue-field'),
              controller: _dialogueController,
              autofocus: true,
              minLines: 2,
              maxLines: null,
            ),
          ),
        ],
      ),
      preview: InstanceEditPreview.se(
        axis: widget.previewAxis,
        dialogue: _dialogueController.text.trim(),
        seName: _seNameController.text.trim(),
      ),
      onSubmit: _submit,
    );
  }
}
