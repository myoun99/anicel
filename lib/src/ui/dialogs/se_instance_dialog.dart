import 'package:flutter/material.dart';

import '../../models/project_frame_rate.dart';
import '../../models/se_line_type.dart';
import '../../services/audio/audio_peaks_extractor.dart';
import '../text/app_strings.dart';
import '../widgets/app_window.dart';
import '../widgets/pill_strip.dart';
import 'instance_edit_dialog.dart';
import 'instance_edit_preview.dart';
import 'se_offset_strip.dart';
import '../input/control_press_claim.dart';

/// A sound the edited SE instance carries: what to show, and the opaque
/// token the host uses to find it again (R5 #19) — and, for its start
/// offset (09-27), where in the file it starts, the block it plays in, and
/// its waveform ([SeOffsetStrip]).
typedef SeInstanceAudioLink = ({
  String label,
  int token,
  int offsetFrames,
  int blockFrames,
  ProjectFrameRate frameRate,
  AudioPeaks? peaks,
});

/// What the SE instance dialog resolved to: the (possibly empty) speaker
/// name, the dialogue text, and the sounds the user took off.
class SeInstanceDialogResult {
  const SeInstanceDialogResult({
    required this.seName,
    required this.dialogue,
    this.seType = SeLineType.on,
    this.unlinkedAudioTokens = const {},
    this.audioOffsets = const {},
  });

  final String seName;
  final String dialogue;

  /// The line's delivery (I-20) — ON / OFF / MONO.
  final SeLineType seType;

  /// The [SeInstanceAudioLink.token]s of the sounds unlinked in this
  /// sitting. Empty on every dialog that never showed one — unlinking is a
  /// decision made HERE and applied on OK, so Cancel keeps the sound.
  final Set<int> unlinkedAudioTokens;

  /// The start offsets moved in this sitting, by token — only the sounds
  /// that stay linked. Applied on OK like everything else here.
  final Map<int, int> audioOffsets;
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
    this.initialSeType = SeLineType.on,
    this.creating = false,
    this.previewAxis = Axis.horizontal,
    this.linkedAudio = const [],
  });

  final String initialSeName;
  final String initialDialogue;

  /// The delivery the block has (I-20) — ON for one that never chose.
  final SeLineType initialSeType;

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

  /// The delivery picked in this sitting, applied on OK.
  late SeLineType _seType = widget.initialSeType;

  /// Tokens struck through in this sitting, applied on OK.
  final Set<int> _unlinked = <int>{};

  /// Start offsets moved in this sitting, by token, applied on OK.
  final Map<int, int> _offsets = <int, int>{};

  void _submit() {
    Navigator.of(context).pop(
      SeInstanceDialogResult(
        seName: _seNameController.text.trim(),
        dialogue: _dialogueController.text.trim(),
        seType: _seType,
        unlinkedAudioTokens: Set.unmodifiable(_unlinked),
        audioOffsets: Map.unmodifiable({
          for (final MapEntry(key: token, value: offset) in _offsets.entries)
            if (!_unlinked.contains(token)) token: offset,
        }),
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
                for (final link in remaining) ...[
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
                      ControlPressClaim(onPressed: () =>
                            setState(() => _unlinked.add(link.token)), child: TextButton(
                        key: ValueKey<String>(
                          'se-unlink-audio-${link.token}',
                        ),
                        onPressed: silentPress(() =>
                            setState(() => _unlinked.add(link.token))),
                        child: Text(strings.seUnlinkAudio),
                      )),
                    ],
                  ),
                  // Its start offset — the block's own (유저 2026-09-27).
                  SeOffsetStrip(
                    key: ValueKey<String>('se-offset-strip-${link.token}'),
                    offsetFrames: _offsets[link.token] ?? link.offsetFrames,
                    blockFrames: link.blockFrames,
                    frameRate: link.frameRate,
                    peaks: link.peaks,
                    onChanged: (offset) =>
                        setState(() => _offsets[link.token] = offset),
                  ),
                  const SizedBox(height: 6),
                ],
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
          // 🗣️I-20 (유저 2026-09-30): 「se 블록의 타입으로서 on off mono 타입
          // 추가」 — one of three, always; a grouped choice wears the pills.
          AppWindowField(
            label: strings.seTypeLabel,
            child: Align(
              alignment: Alignment.centerLeft,
              child: PillStrip(
                items: [
                  for (final type in SeLineType.values)
                    PillItem(
                      keyValue: 'se-type-${type.name}',
                      label: type.label,
                      selected: _seType == type,
                      onTap: () => setState(() => _seType = type),
                    ),
                ],
              ),
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
