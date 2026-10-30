import 'package:flutter/material.dart';

import '../../models/app_frame_count_settings.dart';
import '../../models/cut.dart';
import '../../models/cut_id.dart';
import '../../models/project_frame_rate.dart';
import '../../models/se_dialogue_spacing.dart';
import '../../models/se_line_type.dart';
import '../../services/audio/audio_peaks_extractor.dart';
import '../text/app_strings.dart';
import '../widgets/app_window.dart';
import '../widgets/field_slider.dart';
import '../widgets/frame_count_field.dart';
import '../widgets/panel_flyout.dart';
import '../widgets/pill_strip.dart';
import 'instance_edit_dialog.dart';
import 'instance_edit_preview.dart';
import 'se_offset_strip.dart';
import '../input/control_press_claim.dart';

/// A sound the edited SE instance carries: what to show, and the opaque
/// token the host uses to find it again (R5 #19) — and, for its start
/// offset (09-27), where in the file it starts, the block it plays in, and
/// its waveform ([SeOffsetStrip]) — and its own gain (I-140).
typedef SeInstanceAudioLink = ({
  String label,
  int token,
  int offsetFrames,
  double gain,
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
    this.seTypes = SeLineTypes.allOn,
    this.spacing = SeDialogueSpacing.standard,
    this.unlinkedAudioTokens = const {},
    this.audioOffsets = const {},
    this.audioGains = const {},
  });

  final String seName;
  final String dialogue;

  /// The line's delivery in each cut it plays in (I-20, F-386) — ON / OFF /
  /// MONO, as the window showed them ([SeLineTypes.shownIn]).
  final SeLineTypes seTypes;

  /// Where the line's glyphs stand on the block (F-496 ③).
  final SeDialogueSpacing spacing;

  /// The [SeInstanceAudioLink.token]s of the sounds unlinked in this
  /// sitting. Empty on every dialog that never showed one — unlinking is a
  /// decision made HERE and applied on OK, so Cancel keeps the sound.
  final Set<int> unlinkedAudioTokens;

  /// The start offsets moved in this sitting, by token — only the sounds
  /// that stay linked. Applied on OK like everything else here.
  final Map<int, int> audioOffsets;

  /// The gains moved in this sitting, by token — only the sounds that stay
  /// linked, applied on OK as the offsets are.
  final Map<int, double> audioGains;
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
    this.initialSeTypes = SeLineTypes.allOn,
    this.cuts = const [],
    this.initialCutId,
    this.creating = false,
    this.previewAxis = Axis.horizontal,
    this.linkedAudio = const [],
    this.initialSpacing = SeDialogueSpacing.standard,
    this.blockFrames,
    this.frameRate = ProjectFrameRate.fps24,
    this.onCountEntryChanged,
  });

  final String initialSeName;
  final String initialDialogue;

  /// The deliveries the block has (I-20, F-386) — ON for one that never
  /// chose.
  final SeLineTypes initialSeTypes;

  /// The cuts the block plays in, in the track's order — the ones its
  /// delivery is set for, picked one at a time (F-386: 「컷을 팝오버로
  /// 골라서 컷마다 타입 다르게」). Empty for a block between cuts, whose one
  /// delivery is its own.
  final List<Cut> cuts;

  /// The cut the window opens on — where it was opened from. One the block
  /// does not play in opens on its first.
  final CutId? initialCutId;

  /// The sounds this instance carries (R5 #19). Shown even when empty —
  /// "none" is the answer to "what is this block linked to?", and a field
  /// that appears only sometimes cannot be asked.
  final List<SeInstanceAudioLink> linkedAudio;

  /// Whether a new entry is being created (title wording only).
  final bool creating;

  /// Follows the timeline orientation so the preview matches what the
  /// user is looking at.
  final Axis previewAxis;

  /// Where the line's glyphs stand on the block (F-496 ③) — the standard
  /// for one that never set them.
  final SeDialogueSpacing initialSpacing;

  /// How many frames the edited block runs — what the preview lays its
  /// glyphs over. Null previews a block filling the strip.
  final int? blockFrames;

  /// The project's rate — what the spacing's counts are typed against as
  /// seconds+frames ([FrameCountField]).
  final ProjectFrameRate frameRate;

  /// The way a count was just switched to be typed — what every count
  /// window opens on next (I-24-open-entry-Q1).
  final ValueChanged<FrameCountEntry>? onCountEntryChanged;

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

  /// The dialogue as typed, which the preview shows and OK keeps: every
  /// space is a glyph's place on the block, the ends' too. 🗣️F-484 (유저
  /// 2026-10-27): 「띄어쓰기 할때마다도 라이브로 보여지도록」. ↩️Both
  /// trimmed it (since 07-09, nobody's order), so a space typed at the end
  /// showed only once a letter followed it, and OK dropped it.
  String get _dialogue => _dialogueController.text;

  @override
  void dispose() {
    _seNameController.dispose();
    _dialogueController.dispose();
    super.dispose();
  }

  /// The deliveries picked in this sitting, applied on OK.
  late SeLineTypes _seTypes = widget.initialSeTypes;

  /// The glyphs' spacing given in this sitting, applied on OK — what its
  /// counts show, so a koma per glyph moved under one shows the one the
  /// spacing keeps ([SeDialogueSpacing]).
  late SeDialogueSpacing _spacing = widget.initialSpacing;

  /// The cut the type pills set — null only for a block in no cut.
  late CutId? _cutId =
      widget.cuts.any((cut) => cut.id == widget.initialCutId)
      ? widget.initialCutId
      : widget.cuts.firstOrNull?.id;

  /// Tokens struck through in this sitting, applied on OK.
  final Set<int> _unlinked = <int>{};

  /// Start offsets moved in this sitting, by token, applied on OK.
  final Map<int, int> _offsets = <int, int>{};

  /// Gains moved in this sitting, by token, applied on OK.
  final Map<int, double> _gains = <int, double>{};

  void _submit() {
    Navigator.of(context).pop(
      SeInstanceDialogResult(
        seName: _seNameController.text.trim(),
        dialogue: _dialogue,
        seTypes: _seTypes.shownIn([for (final cut in widget.cuts) cut.id]),
        spacing: _spacing,
        unlinkedAudioTokens: Set.unmodifiable(_unlinked),
        audioOffsets: Map.unmodifiable({
          for (final MapEntry(key: token, value: offset) in _offsets.entries)
            if (!_unlinked.contains(token)) token: offset,
        }),
        audioGains: Map.unmodifiable({
          for (final MapEntry(key: token, value: gain) in _gains.entries)
            if (!_unlinked.contains(token)) token: gain,
        }),
      ),
    );
  }

  // 🗣️I-20 (유저 2026-09-30): 「se 블록의 타입으로서 on off mono 타입
  // 추가」 — one of three, always; a grouped choice wears the pills. F-386
  // (유저 2026-10-17): 「타입 정하는곳에서 컷을 팝오버로 골라서 컷마다 타입
  // 다르게」 — the pills set the cut picked before them, in the list the
  // export's cut picker opens.
  Widget _typeField(AppStrings strings) {
    final picked = widget.cuts.where((cut) => cut.id == _cutId).firstOrNull;
    return AppWindowField(
      label: strings.seTypeLabel,
      child: Row(
        children: [
          PanelFlyoutButton(
            key: const ValueKey<String>('se-type-cut-picker'),
            label: picked?.name ?? '—',
            enabled: widget.cuts.isNotEmpty,
            entriesBuilder: () => widget.cuts.asFlyoutValueChoices(
              current: picked,
              choiceOf: (cut) => PanelFlyoutChoice(
                key: 'se-type-cut-${cut.id.value}',
                label: '${cut.name} · ${_seTypes.inCut(cut.id).label}',
              ),
              onPicked: (cut) => setState(() => _cutId = cut.id),
            ),
          ),
          const SizedBox(width: 8),
          PillStrip(
            items: [
              for (final type in SeLineType.values)
                PillItem(
                  keyValue: 'se-type-${type.name}',
                  label: type.label,
                  selected: _seTypes.inCut(_cutId) == type,
                  onTap: () => setState(
                    () => _seTypes = _seTypes.withCut(_cutId, type),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  // 🗣️F-496 ③ (유저 2026-10-28): 「대사 오프셋/글자별 코마 기능 … 글자별
  // 코마는 기본값 3코마, 오프셋은 기본값 0(1코마째부터 시작)」 — each a count
  // of frames, typed in the app's one count field (I-24: 「여러곳에서 쓰일테니
  // 공용화」).
  Widget _spacingField(AppStrings strings) {
    Widget count(
      String keyPrefix,
      String label,
      int shown,
      SeDialogueSpacing Function(int count) given,
    ) => Expanded(
      child: FrameCountField(
        keyPrefix: keyPrefix,
        label: label,
        framesPerSecond: widget.frameRate.countingBase,
        initialEntry: AppFrameCountSettings.settings.value.lastEntry,
        count: shown,
        onEntryChanged: widget.onCountEntryChanged,
        onChanged: (count) => setState(() => _spacing = given(count)),
      ),
    );
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        count(
          'se-dialogue-offset',
          strings.seDialogueOffsetLabel,
          _spacing.offset,
          (offset) => _spacing.copyWith(offset: offset),
        ),
        const SizedBox(width: 12),
        count(
          'se-koma-per-glyph',
          strings.seKomaPerGlyphLabel,
          _spacing.komaPerGlyph,
          (koma) => _spacing.copyWith(komaPerGlyph: koma),
        ),
      ],
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
                  // Its own gain — the level it was brought in at, a pro
                  // tool's clip gain; the row's volume over time is its
                  // 「오디오」 group's (유저 I-140: 「블록마다의 게인(한 값)은
                  // 남겨 블록 편집창에」).
                  FieldSlider(
                    key: ValueKey<String>('se-gain-${link.token}'),
                    min: 0,
                    max: 2,
                    value: _gains[link.token] ?? link.gain,
                    label: strings.audioGainLabel,
                    // A gain of 1 is 100%, as the row's volume reads — in
                    // whole per cents, which is what it holds (F-488).
                    unit: '%',
                    displayScale: 100,
                    divisions: 200,
                    onChanged: (gain) =>
                        setState(() => _gains[link.token] = gain),
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
          _typeField(strings),
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
          _spacingField(strings),
          const SizedBox(height: 12),
          _linkedAudioField(strings),
        ],
      ),
      preview: InstanceEditPreview.se(
        axis: widget.previewAxis,
        dialogue: _dialogue,
        seName: _seNameController.text.trim(),
        delivery: _seTypes.inCut(_cutId),
        spacing: _spacing,
        blockFrames: widget.blockFrames,
      ),
      onSubmit: _submit,
    );
  }
}
