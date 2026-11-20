import 'package:flutter/material.dart' show IconData;

import '../../models/kept_span.dart';
import '../../models/layer_kind.dart';
import '../../models/media_asset.dart';
import '../../models/movie_clock.dart' show ProjectClock;
import '../../models/project_frame_rate.dart';
import '../../services/media/media_facts.dart';
import '../import/import_file_settings.dart' show importFitLabel;
import '../text/app_strings.dart';
import '../text/byte_size_label.dart';
import '../text/pixel_size_label.dart';
import '../text/sample_rate_label.dart';
import '../timeline/layer_label_controls.dart'
    show layerKindDisplayName, layerKindIcon;
import 'media_asset_pool_state.dart';
import 'media_pool_list.dart';

/// What the pool's lines say of each file, column by column — read from what
/// the session already holds, so drawing a line never touches the disk.
///
/// 🗣️asset-placement-presets Q4 (유저 2026-11-17): the file as it is —
/// 품기 · 크기 · 길이 · 비디오 정보 · 오디오 정보 · 날짜, the old second line
/// of a row spread into columns — and the file as its preset places it —
/// 종류 · 맞춤 · 시작 · 끝 · 길이.
final class MediaPoolWords {
  const MediaPoolWords({
    required this.clock,
    this.storedBytes = const {},
    this.conformBytes = const {},
    this.modifiedTimes = const {},
    this.factsOf = _nothingRead,
    this.soundFramesOf = _nothingHeard,
  });

  /// The project's clock — what a length is told in, and what a movie's
  /// frames are counted in the project's by ([placedPicturesOf]).
  final ProjectClock clock;

  /// The project's counting base — what a length is told in.
  int get framesPerSecond => clock.rate.countingBase;

  /// What each carried file ACTUALLY occupies (유저 2026-08-30: 「아무튼
  /// 실제크기」) — see [sizeWord].
  final Map<String, int> storedBytes;

  /// What each sound's conform occupies, for the ones that have one.
  final Map<String, int> conformBytes;

  /// When each linked file was last written, as the session's sweep found.
  final Map<String, DateTime> modifiedTimes;

  /// What the session has read of a file beyond its entry — null while it
  /// has not ([MediaPoolFacts]).
  final MediaPoolFacts? Function(String path) factsOf;

  /// How many project frames a sound lasts, where its conform is held —
  /// null where it is not. ⛔Never asks for one: a list that told every
  /// sound's length would start a decode of each.
  final int? Function(String path) soundFramesOf;

  static MediaPoolFacts? _nothingRead(String path) => null;
  static int? _nothingHeard(String path) => null;

  /// What a cell says where its question means nothing for the file, or its
  /// answer is not read yet — the dash the import table says it with.
  static const String none = '—';

  /// The columns of a file as it is.
  List<MediaPoolColumn> fileColumns() {
    final strings = AppText.strings;
    return [
      MediaPoolColumn(
        id: 'kept',
        label: strings.imFile,
        wordOf: mediaAssetPoolState,
        keepsRoomFor: [
          strings.mediaCarriedState,
          strings.mediaReferencedState,
        ],
      ),
      MediaPoolColumn(
        id: 'size',
        label: strings.imSize,
        wordOf: sizeWord,
        numeric: true,
      ),
      MediaPoolColumn(
        id: 'length',
        label: strings.mediaLength,
        wordOf: lengthWord,
        numeric: true,
        keepsRoomFor: [runningTimeLabel(99 * 60 * 60, 60)],
      ),
      MediaPoolColumn(
        id: 'video',
        label: strings.mediaVideoFacts,
        wordOf: videoWord,
        keepsRoomFor: ['${pixelSizeLabel(99999, 99999)} · 119.88 fps'],
      ),
      MediaPoolColumn(
        id: 'audio',
        label: strings.mediaAudioFacts,
        wordOf: audioWord,
        keepsRoomFor: [
          '${sampleRateLabel(44100)} · ${strings.mediaStereo}',
          '${sampleRateLabel(44100)} · ${strings.mediaChannels(8)}',
        ],
      ),
      MediaPoolColumn(
        id: 'date',
        label: strings.imModified,
        wordOf: dateWord,
        keepsRoomFor: ['00-00 00:00'],
      ),
    ];
  }

  /// The columns of a file as its preset places it.
  List<MediaPoolColumn> presetColumns() {
    final strings = AppText.strings;
    return [
      MediaPoolColumn(
        id: 'kind',
        label: strings.mediaKindOfLayer,
        wordOf: (asset) => layerKindDisplayName(placedKindOf(asset)),
        iconOf: kindIconOf,
        keepsRoomFor: [
          for (final kind in const [
            LayerKind.se,
            LayerKind.image,
            LayerKind.animation,
          ])
            layerKindDisplayName(kind),
        ],
      ),
      MediaPoolColumn(
        id: 'fit',
        label: strings.imFit,
        wordOf: fitWord,
        keepsRoomFor: [
          for (final fit in MediaFitMode.values) importFitLabel(fit),
        ],
      ),
      MediaPoolColumn(
        id: 'start',
        label: strings.mediaStart,
        wordOf: (asset) => _endWord(asset, (span) => span.first),
        numeric: true,
      ),
      MediaPoolColumn(
        id: 'end',
        label: strings.mediaEnd,
        wordOf: (asset) => _endWord(asset, (span) => span.last),
        numeric: true,
      ),
      MediaPoolColumn(
        id: 'span',
        label: strings.mediaLength,
        wordOf: spanWord,
        numeric: true,
        keepsRoomFor: [runningTimeLabel(99 * 60 * 60, 60)],
      ),
    ];
  }

  /// `55 MB + 1.2 GB` — what the file takes, and its conform after a `+`.
  ///
  /// 🚨★★★**THE SIZE SHOWN IS THE SIZE TAKEN** (유저 2026-08-30: 「파일이
  /// 보여주는 크기는 압축된 크기를 보여주는게 맞겟지? … 아무튼 실제크기」).
  /// For a carried file that is what it occupies compressed — in the project
  /// file, or in the staging area before the first save. The import window
  /// still shows the file's own length, and correctly: nothing has been
  /// compressed yet at that point.
  ///
  /// ⛔[MediaAsset.identity] is the FALLBACK, not the answer. It is the
  /// length the file had when it was registered — which for a compressed
  /// asset matches nothing on any disk — and it stays untouched because
  /// relink uses it to tell one `A1.png` from another.
  ///
  /// 🚨The CONFORM, asked for by name (유저 2026-08-30: 「가시화정책에 따라
  /// 미디어풀 패널에서 해당파일의 컨폼파일 크기 표시할것」). It is several
  /// times the sound itself. ⛔`+` and nothing else: it says「and this much
  /// more」, which is exactly what a conform is, and a word here would be
  /// the explanatory caption this app does not put under things.
  String sizeWord(MediaAsset asset) {
    final bytes = storedBytes[asset.path] ?? asset.identity?.lengthBytes;
    final conform = conformBytes[asset.path];
    final hasBytes = bytes != null && bytes > 0;
    final hasConform = conform != null && conform > 0;
    return switch ((hasBytes, hasConform)) {
      (true, true) => '${byteSizeLabel(bytes!)} + ${byteSizeLabel(conform!)}',
      (true, false) => byteSizeLabel(bytes!),
      (false, true) => '+ ${byteSizeLabel(conform!)}',
      (false, false) => none,
    };
  }

  /// How long the file runs — a sound's or a movie's time, a PDF's pages;
  /// a still has no length.
  String lengthWord(MediaAsset asset) {
    final length = _lengthOf(asset);
    if (length == null || _isAStill(asset)) {
      return none;
    }
    return framesWord(asset, length);
  }

  /// `1920×1080 · 23.976 fps` — the picture's size, and a movie's rate.
  String videoWord(MediaAsset asset) {
    final size = factsOf(asset.path)?.picture?.size;
    if (size == null) {
      return none;
    }
    final pixels = pixelSizeLabel(size.width, size.height);
    final fps = asset.sourceFps;
    return asset.kind == MediaAssetKind.video && fps != null && fps > 0
        ? '$pixels · ${framesPerSecondLabel(fps)}'
        : pixels;
  }

  /// `48kHz · 스테레오` — a sound's, or a movie's soundtrack's.
  String audioWord(MediaAsset asset) {
    final sound = factsOf(asset.path)?.sound;
    if (sound == null) {
      return none;
    }
    final strings = AppText.strings;
    final channels = switch (sound.channels) {
      1 => strings.mediaMono,
      2 => strings.mediaStereo,
      final count => strings.mediaChannels(count),
    };
    return '${sampleRateLabel(sound.sampleRate)} · $channels';
  }

  /// `MM-DD hh:mm` — the dash where none is known.
  ///
  /// 🗣️F-589-Q1 (유저 2026-11-14: 「품을 때의 날짜를 적어 두고 그것을
  /// 띄운다」): a carried file's date is the one its carry recorded — the
  /// bytes the project holds do not change when the original does.
  /// ↩️It read the original's date now, edited or gone.
  String dateWord(MediaAsset asset) {
    final modified = switch (asset.carriedAs) {
      final carried? => carried.modified,
      null => modifiedTimes[asset.path],
    };
    if (modified == null) {
      return none;
    }
    String two(int value) => value.toString().padLeft(2, '0');
    return '${two(modified.month)}-${two(modified.day)} '
        '${two(modified.hour)}:${two(modified.minute)}';
  }

  IconData kindIconOf(MediaAsset asset) => layerKindIcon(placedKindOf(asset));

  /// How the preset fits a picture to the cut — nothing for a sound.
  String fitWord(MediaAsset asset) => asset.kind == MediaAssetKind.audio
      ? none
      : importFitLabel(asset.preset.fit);

  /// How long what the preset places runs ([MediaPreset.spanOf]).
  String spanWord(MediaAsset asset) {
    final span = _spanOf(asset);
    return span == null ? none : framesWord(asset, span.count);
  }

  /// A frame of a span — counted from 1, as a transport counts.
  String frameWord(int frame) => '${frame + 1}';

  /// The preset's first or last frame ([frameWord]) — or page.
  String _endWord(MediaAsset asset, int Function(KeptSpan span) end) {
    final span = _spanOf(asset);
    return span == null ? none : frameWord(end(span));
  }

  /// What [asset]'s preset keeps of it — null for a still, which is held
  /// over the cut and has no span, and while its length is not known.
  KeptSpan? _spanOf(MediaAsset asset) {
    final length = _lengthOf(asset);
    return length == null || _isAStill(asset)
        ? null
        : asset.preset.spanOf(length);
  }

  /// [asset]'s whole length in what a placement counts — a sound's project
  /// frames, a picture file's ([placedPicturesOf]).
  int? _lengthOf(MediaAsset asset) => asset.kind == MediaAssetKind.audio
      ? soundFramesOf(asset.path)
      : placedPicturesOf(asset, factsOf(asset.path)?.picture, clock);

  /// One picture in a picture file: a still, which has no length.
  bool _isAStill(MediaAsset asset) =>
      asset.kind == MediaAssetKind.image && asset.pictures == 1;

  /// [count] of [asset]'s frames as a length — pages for a PDF, a running
  /// time for the rest.
  String framesWord(MediaAsset asset, int count) =>
      asset.kind == MediaAssetKind.pdf
      ? AppText.strings.mediaPages(count)
      : runningTimeLabel(count, framesPerSecond);
}
