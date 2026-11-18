import '../../models/frame_id.dart';
import '../../models/layer.dart';
import '../../models/media_asset.dart';
import '../../models/movie_cel.dart' show isMovieReference;
import '../../models/project.dart';
import '../../models/se_take_placement.dart' show placedSoundBlockOf;
import '../../models/timeline_exposure.dart';
import '../project_lookup.dart' show requireLayer, requireLayerAnywhere;
import 'media_asset_uses.dart';

/// A field of a placement its file's preset can set again — a line of the
/// sync window's 「맞출 칸」, in the window's order.
///
/// 🗣️유저 2026-11-17 (card 「파일마다 배치 기본값」-Q5): the sync window
/// picks the fields as well as the places; Q6 「시안대로」 — the 시안's ③
/// draws a sound's four: 시작 · 길이 · 이름 · 대사. Q7 (kind-too-off) adds a
/// picture's fit and a still's kind, ⚠️which wait on Q8 · Q9.
enum MediaSyncField {
  start,
  length,
  nameTag,
  words;

  /// What the window starts with: the start and the length. A block's name
  /// tag and words differ from cut to cut as a rule — 시안 ③: 「이름은
  /// 컷마다 다른 게 정상이라 꺼 둔다」 — so they are asked for, not assumed;
  /// and the pool's badge says only that one of THESE parts from its preset.
  static const Set<MediaSyncField> asked = {start, length};
}

/// What a preset places of a file at a place: where in the file the place
/// starts and how long its block is — null while the file's length is not
/// known — and a sound block's name tag and words.
typedef MediaSyncPreset = ({
  int? start,
  int? length,
  String nameTag,
  String words,
});

/// What [entry]'s preset places of it, [length] long (null: not known yet)
/// in what the placement counts — the start and the length are the first
/// and the count of [MediaPreset.spanOf], what the file's door lands with
/// (`ProjectImportDoors`, `kept.first` · `kept.count`); the name tag and
/// the words are what [placedSoundBlockOf] names a new sound block.
MediaSyncPreset syncPresetOf(MediaAsset entry, {required int? length}) {
  final block = placedSoundBlockOf(entry, named: entry.name);
  final kept = length == null || length < 1
      ? null
      : entry.preset.spanOf(length);
  return (
    start: kept?.first,
    length: kept?.count,
    nameTag: block.seName,
    words: block.words,
  );
}

/// One place a file is placed at, what it holds of each [MediaSyncField],
/// and what the file's preset places THERE ([placed]) — a sound's frame
/// counted in the sound's frames, a movie's row in the frames its pictures
/// cover, which need not be the same count.
final class MediaSyncPlace {
  const MediaSyncPlace({
    required this.use,
    required this.placed,
    required this.starts,
    required this.lengths,
    this.nameTag,
    this.words,
  });

  /// A frame of an SE row playing the file ([FrameMediaUse]), or a movie's
  /// row ([RowMediaUse]).
  final MediaAssetUse use;

  final MediaSyncPreset placed;

  /// Where the place starts in the file: a sound's clips of it on the frame
  /// (`AudioClip.offsetFrames` — one, unless the frame links it twice), a
  /// movie row's offset into it (`MediaReference.frameOffset`).
  final List<int> starts;

  /// How long each block of the place is — one, unless blocks share it
  /// (footsteps reuse, a movie's row cut in two).
  final List<int> lengths;

  /// A sound block's name tag (`Frame.seName`) and its words (`Frame.name`),
  /// empty where it has none — null where the place is no sound block.
  final String? nameTag;
  final String? words;

  /// The fields this place holds.
  Set<MediaSyncField> get fields => {
    MediaSyncField.start,
    MediaSyncField.length,
    if (nameTag != null) MediaSyncField.nameTag,
    if (words != null) MediaSyncField.words,
  };

  /// The fields among [asked] at which this place is not what [placed]
  /// places. A start or a length the preset cannot count yet — the file's
  /// length unknown — parts from nothing.
  Set<MediaSyncField> partsFrom(Set<MediaSyncField> asked) => {
    for (final field in asked)
      if (_partsAt(field)) field,
  };

  bool _partsAt(MediaSyncField field) => switch (field) {
    MediaSyncField.start => _anyBut(starts, placed.start),
    MediaSyncField.length => _anyBut(lengths, placed.length),
    MediaSyncField.nameTag => nameTag != null && nameTag != placed.nameTag,
    MediaSyncField.words => words != null && words != placed.words,
  };

  static bool _anyBut(List<int> held, int? placed) =>
      placed != null && held.any((value) => value != placed);
}

/// The lengths of a file a sync counts its preset from, each in what its
/// placement counts: its sound's project frames, where its conform is held,
/// and what a placement of its pictures covers (`placedPicturesOf`) — each
/// null while it is not known.
typedef MediaSyncLengths = ({int? sound, int? pictures});

/// Whether a place of [entry] in [project] parts from its preset at the
/// fields the sync window starts with ([MediaSyncField.asked]) — what turns
/// the pool's in-use mark into its sync (시안 ③: 「프리셋과 다른 곳이 있는
/// 행의 「쓰는 곳」 버튼이 같은 자리에서 동기화 모양」).
bool partsFromItsPreset(
  Project project,
  MediaAsset entry, {
  required MediaSyncLengths lengths,
}) => syncPlacesOf(project, entry, lengths: lengths).any(
  (place) => place.partsFrom(MediaSyncField.asked).isNotEmpty,
);

/// Every place [project] places [entry] at that a sync can set, in the
/// order [mediaAssetUsesOf] lists them — the uses the pool's in-use mark
/// opens, so the sync window's places are the uses window's: a frame of an
/// SE row playing it, and a movie's row.
///
/// ⚠️A row of a still, a GIF or a PDF holds no start a sync sets — its
/// pictures are its cels — and its fit and a still's kind wait on card
/// 「파일마다 배치 기본값」-Q8 · Q9: such a row is no place here yet.
List<MediaSyncPlace> syncPlacesOf(
  Project project,
  MediaAsset entry, {
  required MediaSyncLengths lengths,
}) {
  final file = normalizedMediaPath(entry.path);
  final sound = syncPresetOf(entry, length: lengths.sound);
  final pictures = syncPresetOf(entry, length: lengths.pictures);
  return [
    for (final use in mediaAssetUsesOf(project, file))
      ?switch (use) {
        FrameMediaUse() => _soundPlaceOf(
          requireLayerAnywhere(project, use.layerId),
          use,
          file,
          sound,
        ),
        RowMediaUse() => _moviePlaceOf(
          requireLayer(project, cutId: use.cutId, layerId: use.layerId),
          use,
          pictures,
        ),
        _ => null,
      },
  ];
}

MediaSyncPlace _soundPlaceOf(
  Layer row,
  FrameMediaUse use,
  String file,
  MediaSyncPreset placed,
) {
  final frame = row.frames.firstWhere((frame) => frame.id == use.frameId);
  return MediaSyncPlace(
    use: use,
    placed: placed,
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

MediaSyncPlace? _moviePlaceOf(
  Layer row,
  RowMediaUse use,
  MediaSyncPreset placed,
) {
  final reference = row.mediaReference;
  if (reference == null || !isMovieReference(row)) {
    return null;
  }
  return MediaSyncPlace(
    use: use,
    placed: placed,
    starts: [reference.frameOffset],
    lengths: [
      for (final MapEntry(value: block) in heldBlocksOf(row)) block.length!,
    ],
  );
}

/// The blocks of [row], by where each starts — a ghost is derived and no
/// block of its own.
Iterable<MapEntry<int, TimelineExposure>> heldBlocksOf(Layer row) =>
    row.timeline.entries.where(
      (entry) => entry.value.isDrawing && !entry.value.ghost,
    );

/// The blocks of [row] that show [frameId] ([heldBlocksOf]).
Iterable<MapEntry<int, TimelineExposure>> blocksShowing(
  Layer row,
  FrameId frameId,
) => heldBlocksOf(row).where((entry) => entry.value.frameId == frameId);
