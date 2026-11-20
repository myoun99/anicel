import 'package:flutter/material.dart';

import '../../models/media_asset.dart';
import '../../services/media/media_preset_sync.dart';
import '../import/import_file_settings.dart' show importFitLabel;
import '../text/app_strings.dart';
import '../timeline/layer_label_controls.dart' show layerKindDisplayName;
import '../timeline/scale_lane_form.dart' show TwoScales;
import '../widgets/app_window.dart';
import '../widgets/ellipsis_text.dart';
import '../widgets/settings_rows.dart';
import 'media_pool_words.dart';

/// What the sync window answers: the fields to set, at the places to set
/// them ([MediaPool.syncPlaces]).
typedef MediaSyncAnswer = ({
  Set<MediaSyncField> fields,
  List<MediaSyncPlace> places,
});

/// 🗣️THE SYNC WINDOW (유저 2026-11-17, card 「파일마다 배치 기본값」-Q5:
/// 「동기화 창은 칸과 곳을 둘 다 고른다 · 곳 목록 스크롤 · 「모두 적용」」 —
/// Q6 「시안대로」, its ③): above, the fields its places hold, each with what
/// the preset places there — the start and the length on to begin
/// ([MediaSyncField.asked]); below, every place that uses the file, with
/// how it parts at the fields on, or 「같음」. 「적용」 sets the places picked
/// among those that part; 「모두 적용」 every one that parts. A field off is
/// no difference in the list. A place a sync cannot set — an image's kind
/// for a row of more cels — says how it parts, its ring dead (Q8).
class MediaSyncWindow extends StatefulWidget {
  const MediaSyncWindow({
    super.key,
    required this.asset,
    required this.places,
    required this.placeLines,
    required this.words,
  }) : assert(places.length == placeLines.length, 'a line a place');

  final MediaAsset asset;
  final List<MediaSyncPlace> places;

  /// Each of [places] as the uses window names it (`mediaAssetUseLine`).
  final List<String> placeLines;

  /// How a start and a length are said — as the pool's preset face says
  /// them.
  final MediaPoolWords words;

  /// The column a field's name stands in.
  static const double fieldNameWidth = 64;

  /// The column a place stands in — the uses window's line.
  static const double placeNameWidth = 160;

  /// The places list's height: five settings rows, and it scrolls past
  /// them — its room the same however many places there are.
  static const double placesHeight = 5 * 40;

  @override
  State<MediaSyncWindow> createState() => _MediaSyncWindowState();
}

class _MediaSyncWindowState extends State<MediaSyncWindow> {
  final Set<MediaSyncField> _fields = {...MediaSyncField.asked};

  /// The places picked, by their index — every one to begin.
  late final Set<int> _picked = {
    for (var index = 0; index < widget.places.length; index++) index,
  };

  /// The fields any of the places holds, in the window's order — a movie's
  /// row has no name tag.
  late final List<MediaSyncField> _shown = [
    for (final field in MediaSyncField.values)
      if (widget.places.any((place) => place.fields.contains(field))) field,
  ];

  /// What [index]'s place parts from its preset at, among the fields on.
  Set<MediaSyncField> _partsOf(int index) =>
      widget.places[index].partsFrom(_fields);

  /// Whether [index]'s place parts at the fields on and a sync can set it
  /// there ([MediaSyncPlace.canSetAt]).
  bool _canPick(int index) =>
      _partsOf(index).isNotEmpty && widget.places[index].canSetAt(_fields);

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
    final settable = [
      for (final index in parting)
        if (_canPick(index)) index,
    ];
    final picked = [
      for (final index in settable)
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
              children: [for (final field in _shown) _fieldLine(field)],
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
          label: strings.mediaSyncApplyAllOf(settable.length),
          emphasis: AppWindowActionEmphasis.second,
          onPressed: settable.isEmpty ? null : () => _answer(settable),
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

  /// A field: its name, what the preset places there, and its ring — the
  /// app's labelled boolean (`SettingsSwitchRow`: 유저 2026-09-24 「설정 줄
  /// 하나로」, 10-23 F-439-Q1 「링만 컨트롤, 라벨은 글자」), led by what the
  /// row is as the export window's layers are.
  Widget _fieldLine(MediaSyncField field) => SettingsSwitchRow(
    tileKey: ValueKey<String>('media-sync-field-${field.name}'),
    leading: _nameColumn(_labelOf(field), MediaSyncWindow.fieldNameWidth),
    label: _placedWordOf(field),
    value: _fields.contains(field),
    onChanged: (on) =>
        setState(() => on ? _fields.add(field) : _fields.remove(field)),
  );

  /// A place: where it is, how it parts — or 「같음」 — and its ring, the
  /// same row as a field's, dead where it is nothing to set
  /// ([_canPick]).
  Widget _placeLine(int index) {
    final parts = _partsOf(index);
    final canPick = _canPick(index);
    return SettingsSwitchRow(
      tileKey: ValueKey<String>('media-sync-place-$index'),
      leading: _nameColumn(
        widget.placeLines[index],
        MediaSyncWindow.placeNameWidth,
      ),
      label: parts.isNotEmpty
          ? _partsWord(index, parts)
          : AppText.strings.mediaSyncSame,
      value: canPick && _picked.contains(index),
      onChanged: canPick
          ? (on) => setState(
              () => on ? _picked.add(index) : _picked.remove(index),
            )
          : null,
    );
  }

  /// What a row is, in a column of its own width — cut, and saying the
  /// rest of itself, where it is longer.
  static Widget _nameColumn(String name, double width) =>
      SizedBox(width: width, child: EllipsisText(name, maxLines: 1));

  /// `시작 1 → 3 · 길이 0:00+4 → 0:00+6` — each field [index]'s place parts
  /// at, what it holds and what its preset places.
  String _partsWord(int index, Set<MediaSyncField> parts) {
    final place = widget.places[index];
    return [
      for (final field in MediaSyncField.values)
        if (parts.contains(field))
          '${_labelOf(field)} ${_heldWordOf(place, field)} → '
              '${_valueWord(place.placed, field)}',
    ].join(' · ');
  }

  /// A field's name — a start, a length, a fit and a kind as the pool's
  /// columns name them.
  String _labelOf(MediaSyncField field) => switch (field) {
    MediaSyncField.start => AppText.strings.mediaStart,
    MediaSyncField.length => AppText.strings.mediaLength,
    MediaSyncField.fit => AppText.strings.imFit,
    MediaSyncField.kind => AppText.strings.mediaKindOfLayer,
    MediaSyncField.nameTag => AppText.strings.seNameLabel,
    MediaSyncField.words => AppText.strings.seDialogueLabel,
  };

  /// What the preset places at [field] — each value once, where a movie's
  /// sound and its pictures count their lengths apart.
  String _placedWordOf(MediaSyncField field) => {
    for (final place in widget.places)
      if (place.fields.contains(field)) _valueWord(place.placed, field),
  }.join(', ');

  String _valueWord(MediaSyncPreset placed, MediaSyncField field) =>
      switch (field) {
        MediaSyncField.start => _startWord(placed.start),
        MediaSyncField.length => _lengthWord(placed.length),
        MediaSyncField.fit => importFitLabel(placed.fit),
        MediaSyncField.kind => layerKindDisplayName(placed.kind),
        MediaSyncField.nameTag => _textWord(placed.nameTag),
        MediaSyncField.words => _textWord(placed.words),
      };

  /// What [place] holds at [field] — each value once, where blocks or
  /// clips of one place hold more than one.
  String _heldWordOf(MediaSyncPlace place, MediaSyncField field) =>
      switch (field) {
        MediaSyncField.start => {...?place.starts}.map(_startWord),
        MediaSyncField.length => {...?place.lengths}.map(_lengthWord),
        MediaSyncField.fit => [_sizeWord(place.size)],
        MediaSyncField.kind => [
          if (place.kind case final kind?) layerKindDisplayName(kind),
        ],
        MediaSyncField.nameTag => [_textWord(place.nameTag ?? '')],
        MediaSyncField.words => [_textWord(place.words ?? '')],
      }.join(', ');

  /// A placed picture's size: the fit it is, or its scale as its size lane
  /// prints one (`150, 80%`).
  static String _sizeWord(MediaSyncSize? size) => switch (size) {
    null => MediaPoolWords.none,
    (heldFit: final fit?, held: _, placed: _) => importFitLabel(fit),
    (:final held, heldFit: null, placed: _) => const TwoScales().label(held),
  };

  String _startWord(int? first) =>
      first == null ? MediaPoolWords.none : widget.words.frameWord(first);

  String _lengthWord(int? count) => count == null
      ? MediaPoolWords.none
      : widget.words.framesWord(widget.asset, count);

  static String _textWord(String text) =>
      text.isEmpty ? MediaPoolWords.none : text;
}
