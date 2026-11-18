import '../../models/canvas_point.dart';
import '../../models/canvas_size.dart';
import '../../models/frame_id.dart';
import '../../models/import/cut_folder_edits.dart' show CutFolderEdits;
import '../../models/layer.dart';
import '../../models/layer_kind.dart';
import '../../models/media_asset.dart';
import '../../models/media_reference.dart';
import '../../models/movie_cel.dart' show isMovieReference;
import '../../models/project.dart';
import '../../models/property_track.dart';
import '../../models/se_take_placement.dart' show placedSoundBlockOf;
import '../../models/timeline_exposure.dart';
import '../import/raster_cel_import.dart' show fitPose;
import '../project_lookup.dart'
    show requireCut, requireLayer, requireLayerAnywhere;
import 'media_asset_uses.dart';
import 'media_facts.dart' show keptPicturesOf, placedKindOf;

/// A field of a placement its file's preset can set again — a line of the
/// sync window's 「맞출 칸」, in the window's order.
///
/// 🗣️유저 2026-11-17 (card 「파일마다 배치 기본값」-Q5): the sync window
/// picks the fields as well as the places; Q6 「시안대로」 — the 시안's ③
/// draws a sound's four: 시작 · 길이 · 이름 · 대사. Q7 (kind-too-off): a
/// picture's fit and, where its preset keeps one picture, its kind.
enum MediaSyncField {
  start,
  length,
  fit,
  kind,
  nameTag,
  words;

  /// What the window starts with: the start and the length. A block's name
  /// tag and words differ from cut to cut as a rule — 시안 ③: 「이름은
  /// 컷마다 다른 게 정상이라 꺼 둔다」 — and a fit and a kind are asked for
  /// too (Q7 kind-too-off).
  static const Set<MediaSyncField> asked = {start, length};
}

/// What a preset places of a file at a place: where in the file the place
/// starts and how long its block is — null while the file's length is not
/// known — how it fits a picture to the cut and the kind of row it makes,
/// and a sound block's name tag and words.
typedef MediaSyncPreset = ({
  int? start,
  int? length,
  MediaFitMode fit,
  LayerKind kind,
  String nameTag,
  String words,
});

/// What [entry]'s preset places of it, [length] long (null: not known yet)
/// in what the placement counts — the start and the length are the first
/// and the count of [MediaPreset.spanOf], what the file's door lands with
/// (`ProjectImportDoors`, `kept.first` · `kept.count`); the kind is the
/// pool's ([placedKindOf]); the name tag and the words are what
/// [placedSoundBlockOf] names a new sound block.
MediaSyncPreset syncPresetOf(MediaAsset entry, {required int? length}) {
  final block = placedSoundBlockOf(entry, named: entry.name);
  final kept = length == null || length < 1
      ? null
      : entry.preset.spanOf(length);
  return (
    start: kept?.first,
    length: kept?.count,
    fit: entry.preset.fit,
    kind: placedKindOf(entry),
    nameTag: block.seName,
    words: block.words,
  );
}

/// A placed picture's size — the scale it was placed at
/// (`MediaReference.pose`, which no edit moves: an edit keys the fx) — and
/// the one its file's fit places it at on its cut's canvas ([fitPose]).
/// [heldFit] is the fit [held] is, where it is one.
typedef MediaSyncSize = ({
  CanvasPoint held,
  CanvasPoint placed,
  MediaFitMode? heldFit,
});

/// One place a file is placed at, what it holds of each [MediaSyncField],
/// and what the file's preset places THERE ([placed]) — a sound's frame
/// counted in the sound's frames, a movie's row in the frames its pictures
/// cover, which need not be the same count.
final class MediaSyncPlace {
  const MediaSyncPlace({
    required this.use,
    required this.placed,
    this.starts,
    this.lengths,
    this.size,
    this.kind,
    this.cels = 1,
    this.nameTag,
    this.words,
  });

  /// A frame of an SE row playing the file ([FrameMediaUse]), or a row
  /// showing it ([RowMediaUse]).
  final MediaAssetUse use;

  final MediaSyncPreset placed;

  /// Where the place starts in the file: a sound's clips of it on the frame
  /// (`AudioClip.offsetFrames` — one, unless the frame links it twice), a
  /// movie row's offset into it (`MediaReference.frameOffset`). Null where
  /// the place holds no start: a row of a still, a GIF or a PDF, whose
  /// pictures are its cels.
  final List<int>? starts;

  /// How long each block of the place is — one, unless blocks share it
  /// (footsteps reuse, a movie's row cut in two). Null where [starts] is.
  final List<int>? lengths;

  /// A row's picture size ([MediaSyncSize]) — null where the place shows no
  /// picture.
  final MediaSyncSize? size;

  /// A row's kind, where a sync sets it: an image's or an animation's row
  /// of a file its preset keeps one picture of. Null elsewhere.
  final LayerKind? kind;

  /// How many cels the row holds — an image's row holds one
  /// ([CutFolderEdits.holds]).
  final int cels;

  /// A sound block's name tag (`Frame.seName`) and its words (`Frame.name`),
  /// empty where it has none — null where the place is no sound block.
  final String? nameTag;
  final String? words;

  /// The fields this place holds.
  Set<MediaSyncField> get fields => {
    if (starts != null) MediaSyncField.start,
    if (lengths != null) MediaSyncField.length,
    if (size != null) MediaSyncField.fit,
    if (kind != null) MediaSyncField.kind,
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

  /// Whether a sync can set this place at every field among [asked] it
  /// parts at: not where it would make an image's row of one holding more
  /// than one cel (🗣️Q8 same-switch: 「셀이 여럿인 곳은 그 차이를 보여 주되
  /// 고를 수 없다」).
  bool canSetAt(Set<MediaSyncField> asked) =>
      !partsFrom(asked).contains(MediaSyncField.kind) ||
      CutFolderEdits.holds(placed.kind, cels);

  bool _partsAt(MediaSyncField field) => switch (field) {
    MediaSyncField.start => _anyBut(starts, placed.start),
    MediaSyncField.length => _anyBut(lengths, placed.length),
    MediaSyncField.fit => size != null && size!.held != size!.placed,
    MediaSyncField.kind => kind != null && kind != placed.kind,
    MediaSyncField.nameTag => nameTag != null && nameTag != placed.nameTag,
    MediaSyncField.words => words != null && words != placed.words,
  };

  static bool _anyBut(List<int>? held, int? placed) =>
      held != null && placed != null && held.any((value) => value != placed);
}

/// The lengths of a file a sync counts its preset from, each in what its
/// placement counts: its sound's project frames, where its conform is held,
/// and what a placement of its pictures covers (`placedPicturesOf`) — each
/// null while it is not known.
typedef MediaSyncLengths = ({int? sound, int? pictures});

/// Every place [project] places [entry] at that a sync can set, in the
/// order [mediaAssetUsesOf] lists them — the uses the pool's in-use mark
/// opens, so the sync window's places are the uses window's: a frame of an
/// SE row playing it, and a row showing it.
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
        RowMediaUse() => _rowPlaceOf(project, entry, use, pictures),
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

/// A row showing [entry]: its picture's size and, where a sync sets it, its
/// kind; a movie's row its start in the file and its blocks' length too.
MediaSyncPlace? _rowPlaceOf(
  Project project,
  MediaAsset entry,
  RowMediaUse use,
  MediaSyncPreset placed,
) {
  final row = requireLayer(project, cutId: use.cutId, layerId: use.layerId);
  final reference = row.mediaReference;
  if (reference == null) {
    return null;
  }
  final movie = isMovieReference(row);
  return MediaSyncPlace(
    use: use,
    placed: placed,
    starts: movie ? [reference.frameOffset] : null,
    lengths: movie
        ? [
            for (final MapEntry(value: block) in heldBlocksOf(row))
              block.length!,
          ]
        : null,
    size: _sizeOf(
      reference,
      requireCut(project, use.cutId).canvasSize,
      placed.fit,
    ),
    kind: _kindSetIn(row, entry) ? row.kind : null,
    cels: row.frames.length,
  );
}

MediaSyncSize _sizeOf(
  MediaReference reference,
  CanvasSize canvas,
  MediaFitMode fit,
) {
  CanvasPoint at(MediaFitMode mode) =>
      fitPose(picture: reference.pictureSize, canvas: canvas, fit: mode).scale;
  final held = reference.pose.scale;
  return (
    held: held,
    placed: at(fit),
    heldFit: MediaFitMode.values.where((mode) => at(mode) == held).firstOrNull,
  );
}

/// Whether a sync sets [row]'s kind: a row of an image or an animation,
/// not riding a base whose kind it takes (`updateLayerKind`), of a file
/// its preset keeps one picture of — 「종류(그림 한 장일 때)」 (Q7) — as
/// far as the pool knows: a count not read yet holds no kind.
bool _kindSetIn(Layer row, MediaAsset entry) =>
    (row.kind == LayerKind.image || row.kind == LayerKind.animation) &&
    !isAttachedLayer(row) &&
    entry.pictures != null &&
    keptPicturesOf(entry) == 1;

/// [reference] placed at [size]: its placed scale made [size], and every
/// key of its size lane carried by the same ratio, axis by axis — the keys,
/// their frames and the way they move kept; where it stands and turns, its
/// other lanes' keys and where its pixels are laid as they were.
///
/// 🗣️유저 2026-11-18 (card 「파일마다 배치 기본값」-Q9 「맞춤같은 비율조절시
/// 키는 유지함. 거기서 크기만 새롭게」 · Q10 「크기 키를 새 맞춤 비율만큼 함께
/// 바꾼다」).
MediaReference resizedTo(MediaReference reference, CanvasPoint size) {
  final held = reference.pose.scale;
  final across = size.x / held.x;
  final down = size.y / held.y;
  return reference.copyWith(
    pose: reference.pose.copyWith(scaleX: size.x, scaleY: size.y),
    fx: reference.fx.copyWith(
      scale: PropertyTrack(
        keys: {
          for (final MapEntry(key: frame, value: key)
              in reference.fx.scale.keys.entries)
            frame: key.copyWith(
              value: CanvasPoint(
                x: key.value.x * across,
                y: key.value.y * down,
              ),
            ),
        },
      ),
    ),
    // Held as it is: a reference whose pixels are laid at its placed pose
    // keeps no `laid` of its own, and would move them along with it.
    laid: reference.laid,
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
