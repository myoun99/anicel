import '../../models/frame_id.dart';
import '../../models/layer.dart';
import '../../models/media_asset.dart';
import '../../models/project.dart';
import '../../models/se_take_placement.dart' show placedSoundBlockOf;
import '../../models/timeline_exposure.dart';
import '../project_lookup.dart' show requireLayerAnywhere;
import 'media_asset_uses.dart';

/// A field of a placed sound its file's preset can set again — a line of
/// the sync window's 「맞출 칸」, in the window's order.
///
/// 🗣️유저 2026-11-17 (card 「파일마다 배치 기본값」-Q5): the sync window
/// picks the fields as well as the places; Q6 「시안대로」 — the 시안's ③
/// draws a sound's four: 시작 · 길이 · 이름 · 대사.
enum SoundSyncField {
  start,
  length,
  nameTag,
  words;

  /// What the window starts with: the start and the length. A block's name
  /// tag and words differ from cut to cut as a rule — 시안 ③: 「이름은
  /// 컷마다 다른 게 정상이라 꺼 둔다」 — so they are asked for, not assumed;
  /// and the pool's badge says only that one of THESE parts from its preset.
  static const Set<SoundSyncField> asked = {start, length};
}

/// What a preset places of a sound: where in the file its block starts and
/// how long the block is — null while the sound's length is not known — and
/// the block's name tag and words.
typedef SoundPreset = ({
  int? start,
  int? length,
  String nameTag,
  String words,
});

/// What [entry]'s preset places of its sound, [soundFrames] long (null:
/// not known yet) — counted as a placement counts it: the start and the
/// length are the first and the count of [MediaPreset.spanOf], what the
/// sound's door lands with (`ProjectImportDoors`, `kept.first` ·
/// `kept.count`); the name tag and the words are what
/// [placedSoundBlockOf] names a new block.
SoundPreset soundPresetOf(MediaAsset entry, {required int? soundFrames}) {
  final block = placedSoundBlockOf(entry, named: entry.name);
  final kept = soundFrames == null || soundFrames < 1
      ? null
      : entry.preset.spanOf(soundFrames);
  return (
    start: kept?.first,
    length: kept?.count,
    nameTag: block.seName,
    words: block.words,
  );
}

/// One place a file's sound plays from — a frame of an SE row carrying it
/// ([FrameMediaUse]) — and what it holds of each [SoundSyncField].
final class SoundPlace {
  const SoundPlace({
    required this.use,
    required this.starts,
    required this.lengths,
    required this.nameTag,
    required this.words,
  });

  final FrameMediaUse use;

  /// Where each of the frame's clips of the file starts in it
  /// ([AudioClip.offsetFrames]) — one, unless the frame links it twice.
  final List<int> starts;

  /// How long each block showing the frame is — one, unless blocks share
  /// it (footsteps reuse).
  final List<int> lengths;

  /// The block's name tag (`Frame.seName`) and its words (`Frame.name`),
  /// empty where it has none.
  final String nameTag;
  final String words;

  /// The fields among [asked] at which this place is not what [preset]
  /// places. A start or a length the preset cannot count yet — its sound's
  /// length unknown — parts from nothing.
  Set<SoundSyncField> partsFrom(
    SoundPreset preset,
    Set<SoundSyncField> asked,
  ) => {
    for (final field in asked)
      if (_partsAt(field, preset)) field,
  };

  bool _partsAt(SoundSyncField field, SoundPreset preset) => switch (field) {
    SoundSyncField.start => _anyBut(starts, preset.start),
    SoundSyncField.length => _anyBut(lengths, preset.length),
    SoundSyncField.nameTag => nameTag != preset.nameTag,
    SoundSyncField.words => words != preset.words,
  };

  static bool _anyBut(List<int> held, int? placed) =>
      placed != null && held.any((value) => value != placed);
}

/// Every place [project] plays the file at [path]'s sound from, in the
/// order [mediaAssetUsesOf] lists them — the uses the pool's in-use mark
/// opens, so the sync window's places are the uses window's.
List<SoundPlace> soundPlacesOf(Project project, String path) {
  final file = normalizedMediaPath(path);
  return [
    for (final use in mediaAssetUsesOf(
      project,
      path,
    ).whereType<FrameMediaUse>())
      _placeOf(requireLayerAnywhere(project, use.layerId), use, file),
  ];
}

SoundPlace _placeOf(Layer row, FrameMediaUse use, String file) {
  final frame = row.frames.firstWhere((frame) => frame.id == use.frameId);
  return SoundPlace(
    use: use,
    starts: [
      for (final clip in row.audioClips)
        if (clip.frameId == use.frameId && clip.filePath == file)
          clip.offsetFrames,
    ],
    lengths: [
      for (final MapEntry(value: block) in blocksShowing(row, use.frameId))
        block.length!,
    ],
    nameTag: frame.seName ?? '',
    words: frame.name ?? '',
  );
}

/// The blocks of [row] that show [frameId], by where each starts — a
/// ghost is derived and no block of its own.
Iterable<MapEntry<int, TimelineExposure>> blocksShowing(
  Layer row,
  FrameId frameId,
) => row.timeline.entries.where(
  (entry) =>
      entry.value.isDrawing &&
      !entry.value.ghost &&
      entry.value.frameId == frameId,
);
