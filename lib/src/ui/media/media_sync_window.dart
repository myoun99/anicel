import 'package:flutter/material.dart';

import '../../models/media_asset.dart';
import '../../services/media/media_preset_sync.dart';
import '../text/app_strings.dart';
import '../theme/app_theme.dart';
import '../widgets/app_window.dart';
import '../widgets/boolean_dot.dart';
import 'media_pool_words.dart';

/// What the sync window answers: the fields to set, at the places to set
/// them ([MediaPool.syncSoundPlaces]).
typedef MediaSyncAnswer = ({
  Set<SoundSyncField> fields,
  List<SoundPlace> places,
});

/// 🗣️THE SYNC WINDOW (유저 2026-11-17, card 「파일마다 배치 기본값」-Q5:
/// 「동기화 창은 칸과 곳을 둘 다 고른다 · 곳 목록 스크롤 · 「모두 적용」」 —
/// Q6 「시안대로」, its ③): above, the fields to match, each with the
/// preset's value — the start and the length on to begin
/// ([SoundSyncField.asked]); below, every place that uses the file, with
/// how it parts at the fields on, or 「같음」. 「적용」 sets the places picked
/// among those that part; 「모두 적용」 every one that parts. A field off is
/// no difference in the list.
class MediaSyncWindow extends StatefulWidget {
  const MediaSyncWindow({
    super.key,
    required this.asset,
    required this.preset,
    required this.places,
    required this.placeLines,
    required this.words,
  }) : assert(places.length == placeLines.length, 'a line a place');

  final MediaAsset asset;
  final SoundPreset preset;
  final List<SoundPlace> places;

  /// Each of [places] as the uses window names it (`mediaAssetUseLine`).
  final List<String> placeLines;

  /// How a start and a length are said — as the pool's preset face says
  /// them.
  final MediaPoolWords words;

  /// A line of either list (시안 ③'s row).
  static const double lineHeight = 28;

  /// The places list's height: five lines, and it scrolls past them — its
  /// room the same however many places there are.
  static const double placesHeight = 5 * lineHeight;

  @override
  State<MediaSyncWindow> createState() => _MediaSyncWindowState();
}

class _MediaSyncWindowState extends State<MediaSyncWindow> {
  final Set<SoundSyncField> _fields = {...SoundSyncField.asked};

  /// The places picked, by their index — every one to begin.
  late final Set<int> _picked = {
    for (var index = 0; index < widget.places.length; index++) index,
  };

  /// What [index]'s place parts from the preset at, among the fields on.
  Set<SoundSyncField> _partsOf(int index) =>
      widget.places[index].partsFrom(widget.preset, _fields);

  void _answer(List<int> indices) =>
      Navigator.of(context).pop<MediaSyncAnswer>((
        fields: {..._fields},
        places: [for (final index in indices) widget.places[index]],
      ));

  @override
  Widget build(BuildContext context) {
    final strings = AppText.strings;
    final parting = [
      for (var index = 0; index < widget.places.length; index++)
        if (_partsOf(index).isNotEmpty) index,
    ];
    final picked = [
      for (final index in parting)
        if (_picked.contains(index)) index,
    ];
    return AppWindow(
      windowKey: const ValueKey<String>('media-sync-window'),
      title: strings.mediaSyncTitle(widget.asset.name),
      titleIcon: Icons.sync,
      onClose: () => Navigator.of(context).pop(),
      body: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppWindowField(
            label: strings.mediaSyncFields,
            child: Column(
              children: [
                for (final field in SoundSyncField.values) _fieldLine(field),
              ],
            ),
          ),
          const SizedBox(height: 12),
          AppWindowField(
            label: strings.mediaSyncPlaces(
              total: widget.places.length,
              parting: parting.length,
            ),
            child: SizedBox(
              height: MediaSyncWindow.placesHeight,
              child: ListView.builder(
                key: const ValueKey<String>('media-sync-places'),
                itemExtent: MediaSyncWindow.lineHeight,
                itemCount: widget.places.length,
                itemBuilder: (context, index) => _placeLine(index),
              ),
            ),
          ),
        ],
      ),
      actions: [
        AppWindowAction(
          actionKey: const ValueKey<String>('media-sync-cancel'),
          label: strings.commonCancel,
          onPressed: () => Navigator.of(context).pop(),
        ),
        AppWindowAction(
          actionKey: const ValueKey<String>('media-sync-apply-all'),
          label: strings.mediaSyncApplyAllOf(parting.length),
          onPressed: parting.isEmpty ? null : () => _answer(parting),
        ),
        AppWindowAction(
          actionKey: const ValueKey<String>('media-sync-apply'),
          label: strings.mediaSyncApply(picked.length),
          emphasis: AppWindowActionEmphasis.primary,
          onPressed: picked.isEmpty ? null : () => _answer(picked),
        ),
      ],
    );
  }

  /// A field: its ring, its name, and what the preset places there.
  Widget _fieldLine(SoundSyncField field) => SizedBox(
    height: MediaSyncWindow.lineHeight,
    child: Row(
      children: [
        BooleanDotButton(
          keyValue: 'media-sync-field-${field.name}',
          value: _fields.contains(field),
          tooltip: _labelOf(field),
          onChanged: (on) => setState(
            () => on ? _fields.add(field) : _fields.remove(field),
          ),
        ),
        const SizedBox(width: 4),
        SizedBox(width: 56, child: Text(_labelOf(field))),
        Expanded(
          child: Text(
            _presetWordOf(field),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: AppColors.textDim),
          ),
        ),
      ],
    ),
  );

  /// A place: its ring — dead where it parts at nothing — where it is, and
  /// how it parts.
  Widget _placeLine(int index) {
    final parts = _partsOf(index);
    final canPick = parts.isNotEmpty;
    return Row(
      children: [
        BooleanDotButton(
          keyValue: 'media-sync-place-$index',
          value: canPick && _picked.contains(index),
          tooltip: widget.placeLines[index],
          onChanged: canPick
              ? (on) => setState(
                  () => on ? _picked.add(index) : _picked.remove(index),
                )
              : null,
        ),
        const SizedBox(width: 4),
        Expanded(
          child: Text(
            widget.placeLines[index],
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            canPick ? _partsWord(index, parts) : AppText.strings.mediaSyncSame,
            key: ValueKey<String>('media-sync-parts-$index'),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: AppColors.textDim),
          ),
        ),
      ],
    );
  }

  /// `시작 1 → 3 · 길이 0:00+4 → 0:00+6` — each field [index]'s place parts
  /// at, what it holds and what the preset places.
  String _partsWord(int index, Set<SoundSyncField> parts) => [
    for (final field in SoundSyncField.values)
      if (parts.contains(field))
        '${_labelOf(field)} ${_heldWordOf(widget.places[index], field)} → '
            '${_presetWordOf(field)}',
  ].join(' · ');

  String _labelOf(SoundSyncField field) => switch (field) {
    SoundSyncField.start => AppText.strings.mediaStart,
    SoundSyncField.length => AppText.strings.mediaLength,
    SoundSyncField.nameTag => AppText.strings.seNameLabel,
    SoundSyncField.words => AppText.strings.seDialogueLabel,
  };

  String _presetWordOf(SoundSyncField field) => switch (field) {
    SoundSyncField.start => _startWord(widget.preset.start),
    SoundSyncField.length => _lengthWord(widget.preset.length),
    SoundSyncField.nameTag => _textWord(widget.preset.nameTag),
    SoundSyncField.words => _textWord(widget.preset.words),
  };

  /// What [place] holds at [field] — each value once, where blocks or
  /// clips of one place hold more than one.
  String _heldWordOf(SoundPlace place, SoundSyncField field) =>
      switch (field) {
        SoundSyncField.start => place.starts.toSet().map(_startWord),
        SoundSyncField.length => place.lengths.toSet().map(_lengthWord),
        SoundSyncField.nameTag => [_textWord(place.nameTag)],
        SoundSyncField.words => [_textWord(place.words)],
      }.join(', ');

  String _startWord(int? first) =>
      first == null ? MediaPoolWords.none : widget.words.frameWord(first);

  String _lengthWord(int? count) => count == null
      ? MediaPoolWords.none
      : widget.words.framesWord(widget.asset, count);

  static String _textWord(String text) =>
      text.isEmpty ? MediaPoolWords.none : text;
}
