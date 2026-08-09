import 'package:flutter/material.dart';

import '../text/app_strings.dart';
import '../widgets/app_window.dart';
import 'instance_edit_dialog.dart';
import 'instance_edit_preview.dart';

/// A sound the edited SE instance carries: what to show, and the opaque
/// token the host uses to find it again (R5 #19).
typedef SeInstanceAudioLink = ({String label, int token});

/// What the SE instance dialog resolved to: the (possibly empty) speaker
/// name, the dialogue text, and the sounds the user took off.
class SeInstanceDialogResult {
  const SeInstanceDialogResult({
    required this.seName,
    required this.dialogue,
    this.unlinkedAudioTokens = const {},
  });

  final String seName;
  final String dialogue;

  /// The [SeInstanceAudioLink.token]s of the sounds unlinked in this
  /// sitting. Empty on every dialog that never showed one — unlinking is a
  /// decision made HERE and applied on OK, so Cancel keeps the sound.
  final Set<int> unlinkedAudioTokens;
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
    this.linkedAudio = const [],
  });

  final String initialSeName;
  final String initialDialogue;

  /// The sounds this instance carries (R5 #19). Shown even when empty —
  /// "none" is the answer to "what is this block linked to?", and a field
  /// that appears only sometimes cannot be asked.
  final List<SeInstanceAudioLink> linkedAudio;

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

  /// Tokens struck through in this sitting, applied on OK.
  final Set<int> _unlinked = <int>{};

  void _submit() {
    Navigator.of(context).pop(
      SeInstanceDialogResult(
        seName: _seNameController.text.trim(),
        dialogue: _dialogueController.text.trim(),
        unlinkedAudioTokens: Set.unmodifiable(_unlinked),
      ),
    );
  }

  Widget _linkedAudioField(AppStrings strings) {
    final theme = Theme.of(context);
    final remaining = [
      for (final link in widget.linkedAudio)
        if (!_unlinked.contains(link.token)) link,
    ];
    return AppWindowField(
      label: strings.seLinkedAudioLabel,
      child: remaining.isEmpty
          ? Text(
              strings.seLinkedAudioNone,
              key: const ValueKey<String>('se-linked-audio-none'),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            )
          : Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final link in remaining)
                  Row(
                    children: [
                      const Icon(Icons.graphic_eq, size: 16),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          link.label,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall,
                        ),
                      ),
                      TextButton(
                        key: ValueKey<String>(
                          'se-unlink-audio-${link.token}',
                        ),
                        onPressed: () =>
                            setState(() => _unlinked.add(link.token)),
                        child: Text(strings.seUnlinkAudio),
                      ),
                    ],
                  ),
              ],
            ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppText.strings;
    return InstanceEditDialogShell(
      title: widget.creating
          ? strings.seInstanceNewTitle
          : strings.seInstanceEditTitle,
      titleIcon: Icons.music_note_outlined,
      body: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppWindowField(
            label: strings.seNameLabel,
            child: TextField(
              key: const ValueKey<String>('se-name-field'),
              controller: _seNameController,
            ),
          ),
          const SizedBox(height: 12),
          AppWindowField(
            label: strings.seDialogueLabel,
            emphasized: true,
            child: TextField(
              key: const ValueKey<String>('se-dialogue-field'),
              controller: _dialogueController,
              autofocus: true,
              minLines: 2,
              maxLines: null,
            ),
          ),
          const SizedBox(height: 12),
          _linkedAudioField(strings),
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
