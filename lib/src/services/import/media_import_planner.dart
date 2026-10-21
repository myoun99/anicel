import 'dart:collection';
import 'dart:math' as math;

import '../editing/default_cut_helpers.dart';
import '../editing/default_layer_helpers.dart'
    show defaultLayerIdForSequence;
import '../editing/run_id_mint.dart' show mintFrameId;
import '../../models/attached_layer_resolve.dart' show attachedMirrorCelId;
import '../../models/attached_mode.dart';
import '../../models/attached_placement.dart';
import '../../models/cut.dart';
import '../../models/cut_id.dart';
import '../../models/frame.dart';
import '../../models/frame_id.dart';
import '../../models/import/cut_folder_edits.dart';
import '../../models/import/cut_folder_parse.dart';
import '../../models/import/import_destination.dart';
import '../../models/layer.dart';
import '../../models/layer_id.dart';
import '../../models/layer_kind.dart';
import '../../models/layer_mark.dart';
import '../../models/media_asset.dart';
import '../../models/media_reference.dart';
import '../../models/timeline_exposure.dart';
import '../../models/import/import_warning.dart';

export '../../models/import/import_destination.dart';

/// PURE construction of the models an import lands: the session mints ids
/// and does IO/decoding around it, the planner decides layer/cut/asset
/// SHAPE. Testable without a byte of pixel data.

/// Id minting seams (the session's counters, injected).
class ImportIdMint {
  const ImportIdMint({
    required this.nextLayerId,
    required this.nextFrameId,
    required this.nextCutId,
  });

  /// The ids of a project being MADE — before any session holds it, so
  /// there is nothing in it to step past: each id is the next of its kind,
  /// in the forms an import mints into a project that exists
  /// (`ImportLanding.idMint`). The drawings' come from the process's one
  /// mint ([mintFrameId]), which the session born for the project goes on
  /// counting from. A .tvpp and a .clip are both such projects.
  factory ImportIdMint.forANewProject() {
    var layers = 0;
    var cuts = 0;
    return ImportIdMint(
      nextLayerId: () => defaultLayerIdForSequence(layers += 1),
      nextFrameId: mintFrameId,
      nextCutId: () => CutId('import-cut-${cuts += 1}'),
    );
  }

  final LayerId Function() nextLayerId;
  final FrameId Function(LayerId layerId) nextFrameId;
  final CutId Function() nextCutId;
}

/// One cel whose PIXELS must be baked after the structural command runs:
/// decode [sourceFile], rasterize it on the cut's canvas, store under
/// (cutId, layerId, frameId).
///
/// ↩️It carried the FIT it stood at. Where a picture stands is one rule for
/// a whole placement — the fit of an import that bakes, or the pose of the
/// reference a row shows (I-68) — and the door that places it says which.
class PlannedCelBake {
  const PlannedCelBake({
    required this.cutId,
    required this.layerId,
    required this.frameId,
    required this.sourceFile,
    this.sourceFrameIndex = 0,
  });

  final CutId cutId;
  final LayerId layerId;
  final FrameId frameId;
  final String sourceFile;

  /// Which SOURCE frame of [sourceFile] this cel bakes (multi-frame
  /// sources): duplicate folding compresses the bake list, so the bake
  /// ordinal is NOT the source index — this field is.
  final int sourceFrameIndex;
}

/// A planned STILL-IMAGE layer (destination = layer or new cut).
class ImageLayerImportPlan {
  const ImageLayerImportPlan({
    required this.layer,
    required this.bakes,
    required this.assets,
  });

  final Layer layer;
  final List<PlannedCelBake> bakes;
  final List<MediaAsset> assets;
}

/// Whether a placement leaves its file in the media pool: NOT when it is
/// BAKED — the pixels are the layer's own then, and nothing draws from the
/// file — unless something placed beside the bake still reads it: a
/// movie's sound on the SE rows, which is no bake ([soundReadsIt]).
///
/// 🗣️F-282-Q6 (유저 2026-10-09, 가): 구우면 풀에 안 남긴다 — the file
/// column of a baked row says 「—」. ↩️「구워도 풀에 남음」 (09-11): baked or
/// not, the file registered, and a carried one's bytes went into the
/// project a second time beside the cels baked from them. That reversed
/// 「pixels absorbed = no entry」 (§3, 07-30), which this returns to.
///
/// ⚠️A reference rasterized LATER keeps its entry
/// (`RasterizeLayerReferenceCommand`): it was registered when it was
/// placed, and the pool is not the command's to empty.
bool placementRegisters({required bool baked, bool soundReadsIt = false}) =>
    !baked || soundReadsIt;

/// How long a still holds in [cut], the cut it joins: the cut's own length
/// — one frame in a cut that has none.
int stillHoldIn(Cut cut) => cut.duration < 1 ? 1 : cut.duration;

/// Builds one IMAGE layer for [sourceFile]: born covering [duration]
/// (the write normalization keeps it at the cut length afterwards).
/// With a [reference] the layer SHOWS the file — it is stamped as
/// [Layer.mediaReference] and the asset REGISTERS; without one the picture
/// is baked, and nothing is stamped or registered ([placementRegisters]).
ImageLayerImportPlan planStillImageLayer({
  required String sourceFile,
  required String displayName,
  required CutId cutId,
  required int duration,
  required MediaFitMode fit,
  required MediaReference? reference,
  required ImportIdMint mint,
  String? sourcePath,
  String? sourceStamp,
  MediaIdentity? identity,
  bool carried = false,
  MediaAssetKind assetKind = MediaAssetKind.image,
  int? pageCount,

  /// Which picture of the file the still is — a PDF's page; what its cel
  /// records when the layer shows the file ([Frame.filePicture]).
  int picture = 0,
}) {
  final layerId = mint.nextLayerId();
  final frameId = mint.nextFrameId(layerId);
  final clampedDuration = duration < 1 ? 1 : duration;
  final layer = Layer(
    id: layerId,
    name: displayName,
    kind: LayerKind.image,
    frames: [
      Frame(
        id: frameId,
        duration: clampedDuration,
        strokes: const [],
        filePicture: reference == null ? null : picture,
      ),
    ],
    timeline: {0: TimelineExposure.drawing(frameId, length: clampedDuration)},
    mediaReference: reference,
  );
  return ImageLayerImportPlan(
    layer: layer,
    bakes: [
      PlannedCelBake(
        cutId: cutId,
        layerId: layerId,
        frameId: frameId,
        sourceFile: sourceFile,
      ),
    ],
    assets: [
      if (placementRegisters(baked: reference == null))
        importedMediaAsset(
          path: sourceFile,
          kind: assetKind,
          fit: fit,
          sourcePath: sourcePath,
          sourceStamp: sourceStamp,
          identity: identity,
          carried: carried,
          pageCount: pageCount,
        ),
    ],
  );
}

/// The pool entry an import registers for [path].
///
/// ⛔ONE spelling of it. The still and the sequence planners each built this
/// record by hand, and the expanded PSD — which registered too until a
/// baked placement stopped registering (F-282-Q6) — would have been the
/// third.
///
/// A [carried] one is a NEW carry ([mintMediaCarry]): an import is the
/// moment a carry is made, even of a path the project carried before.
MediaAsset importedMediaAsset({
  required String path,
  required MediaAssetKind kind,
  required MediaFitMode fit,
  String? sourcePath,
  String? sourceStamp,
  MediaIdentity? identity,
  bool carried = false,
  double? sourceFps,
  int? frameCount,
  int? pageCount,
}) => MediaAsset(
  path: path,
  name: mediaAssetDefaultName(path),
  kind: kind,
  fitMode: fit,
  sourcePath: sourcePath,
  sourceStamp: sourceStamp,
  identity: identity,
  carriedAs: carried ? mintMediaCarry(path) : null,
  sourceFps: sourceFps,
  frameCount: frameCount,
  pageCount: pageCount,
);

/// A planned SEQUENCE layer: N source frames as cels + exposure, with
/// consecutive DUPLICATE frames folded into held exposure (굽기 노출
/// 기본값 = 중복 접기: a 24-file source drawn on twos becomes 12 cels ×
/// 2 commas — the sheet reads right and the project halves).
class SequenceLayerImportPlan {
  const SequenceLayerImportPlan({
    required this.layer,
    required this.bakes,
    required this.assets,
  });

  final Layer layer;
  final List<PlannedCelBake> bakes;
  final List<MediaAsset> assets;
}

SequenceLayerImportPlan planSequenceLayer({
  required List<String> sourceFiles,
  required List<Object?> frameFingerprints,
  required String displayName,
  required CutId cutId,
  required ImportIdMint mint,

  /// The file the layer SHOWS, when it shows one: stamped as
  /// [Layer.mediaReference], and its asset registers — with [fit] as the
  /// pool entry's placement default. Null bakes the pictures, and nothing
  /// is stamped or registered ([placementRegisters]).
  MediaReference? reference,
  MediaFitMode fit = MediaFitMode.contain,
  String? sourcePath,
  String? sourceStamp,
  MediaIdentity? identity,
  bool carried = false,
  double? sourceFps,
  MediaAssetKind assetKind = MediaAssetKind.image,
  int? pageCount,
  List<int>? sourceFrameIndices,

  /// Each position's cel NAME, when the source names its pictures — a
  /// numbered run's numbers (`pictureRunOf`). A folded run of duplicates
  /// takes its first position's name.
  List<String>? frameNames,

  /// The picture of the file the first position is — a span's IN — so the
  /// cels a layer that shows the file keeps each record which picture of
  /// the FILE they are ([Frame.filePicture]).
  int firstPicture = 0,
}) {
  assert(sourceFiles.length == frameFingerprints.length);
  assert(
    sourceFrameIndices == null ||
        sourceFrameIndices.length == sourceFiles.length,
  );
  assert(frameNames == null || frameNames.length == sourceFiles.length);
  final layerId = mint.nextLayerId();
  final frames = <Frame>[];
  final timeline = SplayTreeMap<int, TimelineExposure>();
  final bakes = <PlannedCelBake>[];
  var position = 0;
  FrameId? currentCel;
  Object? currentFingerprint;
  int? blockStart;
  var blockLength = 0;
  var celOrdinal = 0;

  void flush() {
    final cel = currentCel;
    final start = blockStart;
    if (cel == null || start == null) {
      return;
    }
    timeline[start] = TimelineExposure.drawing(cel, length: blockLength);
  }

  for (var i = 0; i < sourceFiles.length; i += 1) {
    final fingerprint = frameFingerprints[i];
    final duplicateOfCurrent =
        currentFingerprint != null && fingerprint == currentFingerprint;
    if (duplicateOfCurrent) {
      blockLength += 1;
      position += 1;
      continue;
    }
    flush();
    final frameId = mint.nextFrameId(layerId);
    celOrdinal += 1;
    final sourceIndex = sourceFrameIndices?[i] ?? i;
    frames.add(
      Frame(
        id: frameId,
        duration: 1,
        strokes: const [],
        name: frameNames?[i],
        filePicture: reference == null ? null : firstPicture + sourceIndex,
      ),
    );
    bakes.add(
      PlannedCelBake(
        cutId: cutId,
        layerId: layerId,
        frameId: frameId,
        sourceFile: sourceFiles[i],
        // A movie shows its frames on the SOUND's clock, so position i is
        // not movie frame i (`MovieClock`); every other source counts one
        // for one.
        sourceFrameIndex: sourceIndex,
      ),
    );
    currentCel = frameId;
    currentFingerprint = fingerprint;
    blockStart = position;
    blockLength = 1;
    position += 1;
  }
  flush();
  assert(celOrdinal == frames.length);

  final layer = Layer(
    id: layerId,
    name: displayName,
    frames: frames,
    timeline: timeline,
    mediaReference: reference,
  );
  return SequenceLayerImportPlan(
    layer: layer,
    bakes: bakes,
    // A layer that draws from the file registers it; a baked one does not
    // ([placementRegisters]).
    assets: reference == null
        ? const []
        : [
            importedMediaAsset(
              path: reference.assetPath,
              kind: assetKind,
              fit: fit,
              sourcePath: sourcePath,
              sourceStamp: sourceStamp,
              identity: identity,
              carried: carried,
              sourceFps: sourceFps,
              // A PDF's page count is its own field; frameCount stays the
              // image-sequence/video detection slot (§6-z10).
              frameCount: assetKind == MediaAssetKind.pdf
                  ? null
                  : sourceFiles.length,
              pageCount: pageCount,
            ),
          ],
  );
}

/// A MOVIE kept as a reference (미디어 배치 라운드 6: 「배치 창의 굽기 열이
/// 끔이면 참조」): ONE cel exposed for [length] frames, pointing at the file
/// from the span's first frame — [reference]'s
/// [MediaReference.frameOffset].
///
/// ⚠️The cel has no pixels, and that is the design, not a gap: a movie is
/// decoded when it is shown (08-31 「굽지 않고 재생할 때 디코드」), so the
/// one block the timeline draws IS the model — moving it moves the
/// exposure, trimming its head moves [MediaReference.frameOffset] (the SE
/// block's sound shift, 「앞을 자르면 파일 안의 시작점이 움직인다」), and
/// timing a frame at a time waits for the rasterize that makes it cels.
/// The span counts PROJECT frames on the sound's clock, like a sound's.
Layer planMovieReferenceLayer({
  required MediaReference reference,
  required String displayName,
  required int length,
  required ImportIdMint mint,
}) {
  final layerId = mint.nextLayerId();
  final frameId = mint.nextFrameId(layerId);
  return Layer(
    id: layerId,
    name: displayName,
    frames: [Frame(id: frameId, duration: 1, strokes: const [])],
    timeline: SplayTreeMap<int, TimelineExposure>()
      ..[0] = TimelineExposure.drawing(frameId, length: length),
    mediaReference: reference,
  );
}

/// The whole-folder plan, as the import window answered it: the cuts it
/// lands as — the folder's ONE cut, or under 「커스텀」 one for each row sent
/// to a cut of its own (default fixtures kept, drawing layer replaced by
/// the rows) — what it lays into the cut the project has open, the cel
/// bakes, and the fit each layer's cels are laid with.
class CutFolderImportPlan {
  const CutFolderImportPlan({
    required this.cuts,
    required this.openCutLayers,
    required this.bakes,
    required this.fits,
    required this.warnings,
  });

  /// The new cuts, in the order the track takes them.
  final List<Cut> cuts;

  /// The rows 「커스텀」 sent into the cut the project has open, bottom
  /// first.
  final List<Layer> openCutLayers;
  final List<PlannedCelBake> bakes;

  /// How each layer's cels are laid on its cut's canvas — the fit its row
  /// was answered ([CutFolderEdits.fitOf]).
  final Map<LayerId, MediaFitMode> fits;
  final List<ImportWarning> warnings;
}

/// [parsed] as [edits] answered it: its rows stacked as the timeline stacks
/// them — pictures at the bottom, each symbol's own layer with its
/// corrections right above it — each the kind, colour label and fit it was
/// given, in the cut its 넣을 곳 names: the folder's ONE cut, or under
/// 「커스텀」 [openCut] or a cut of the row's own ([CutFolderEdits.intoOf]).
///
/// A new cut is [openCut]'s size — the project's, not the scans' — and
/// runs as long as the longest layer in it; a picture is held over its
/// cut, [openCut]'s own length for one that joins it.
///
/// ↩️The folder's references (timesheet scans, the reference movie) were
/// registered here too, under the window's one carry answer; they are the
/// window's own rows now, asked what every file is asked (F-429-Q4).
CutFolderImportPlan planCutFolderImport({
  required CutFolderParseResult parsed,
  CutFolderEdits edits = const CutFolderEdits(),
  required String Function(String relativePath) resolveFile,
  required Cut? openCut,
  required ImportIdMint mint,
}) => _FolderPlan(parsed, edits, resolveFile, openCut, mint).plan();

/// A cut the folder's rows land in while they are planned, and the rows
/// that go there, bottom first.
class _FolderLanding {
  _FolderLanding(this.name);

  /// What a new cut is named — the folder's, or the row's it is made for.
  final String name;
  final pictures = <ParsedPicture>[];
  final layers = <ParsedCelLayer>[];

  /// How long a new cut runs: its longest layer, one comma a cel (min 1).
  int get length => layers.fold(
    1,
    (longest, layer) => math.max(longest, layer.cells.length),
  );
}

/// [planCutFolderImport]'s working: the rows gathered by the cut each goes
/// to, then laid cut by cut.
class _FolderPlan {
  _FolderPlan(
    this.parsed,
    this.edits,
    this.resolveFile,
    this.openCut,
    this.mint,
  );

  final CutFolderParseResult parsed;
  final CutFolderEdits edits;
  final String Function(String relativePath) resolveFile;
  final Cut? openCut;
  final ImportIdMint mint;

  final _cuts = <Cut>[];
  final _openCutLayers = <Layer>[];
  final _bakes = <PlannedCelBake>[];
  final _fits = <LayerId, MediaFitMode>{};

  /// Where the folder's ONE cut and the open cut gather their rows — a
  /// row's own cut is keyed by the row ([_landingOf]).
  static const _theFolder = 'folder';
  static const _theOpenCut = 'open';

  CutFolderImportPlan plan() {
    final landings = <String, _FolderLanding>{};
    _FolderLanding at(String rowKey, String name) =>
        landings.putIfAbsent(_landingOf(rowKey), () => _FolderLanding(name));
    for (final picture in parsed.pictures) {
      at(picture.rowKey, picture.name).pictures.add(picture);
    }
    for (final layer in parsed.layers) {
      // A correction riding its symbol goes where the symbol goes.
      final row = edits.ridesItsBase(parsed, layer)
          ? parsed.baseOf(layer)!
          : layer;
      at(row.rowKey, row.symbol).layers.add(layer);
    }
    for (final MapEntry(:key, value: landing) in landings.entries) {
      _land(key, landing);
    }
    return CutFolderImportPlan(
      cuts: _cuts,
      openCutLayers: _openCutLayers,
      bakes: _bakes,
      fits: _fits,
      warnings: [
        ...parsed.warnings,
        if (landings.isEmpty)
          const ImportWarning(
            'folderNothing',
            'The folder held no importable cels or pictures.',
          ),
      ],
    );
  }

  /// Where the row keyed [rowKey] goes when it goes on its own: the
  /// folder's one cut, or under 「커스텀」 the open cut or a cut of its own.
  String _landingOf(String rowKey) => !edits.custom
      ? _theFolder
      : switch (edits.intoOf(rowKey, hasOpenCut: openCut != null)) {
          ImportDestination.activeCutLayer => _theOpenCut,
          ImportDestination.newCut => 'own $rowKey',
        };

  /// [landing]'s rows laid, bottom first, and its cut made — or, for the
  /// open cut's, the rows handed to it.
  void _land(String key, _FolderLanding landing) {
    final open = key == _theOpenCut ? openCut : null;
    final cutId = open?.id ?? mint.nextCutId();
    final rows = _FolderCut(
      open == null ? landing.length : stillHoldIn(open),
      mint,
    );
    final layers = <Layer>[];
    void lay(_FolderRow row, String rowKey, List<String> files) {
      layers.add(row.layer);
      _fits[row.layer.id] = edits.fitOf(rowKey);
      for (final (index, file) in files.indexed) {
        _bakes.add(
          PlannedCelBake(
            cutId: cutId,
            layerId: row.layer.id,
            frameId: row.celIds[index],
            sourceFile: resolveFile(file),
          ),
        );
      }
    }

    // Pictures first = bottom of the stack (BG under the cels).
    for (final picture in landing.pictures) {
      lay(
        rows.layer(
          name: picture.name,
          kind: edits.kindOfPicture(picture),
          mark: edits.markOfPicture(picture),
          cels: const [null],
        ),
        picture.rowKey,
        [picture.file],
      );
    }
    // Each symbol's own layer, and the corrections riding it right above
    // it — the parse already stands them in that order.
    final bases = <ParsedCelLayer, _FolderBase>{};
    for (final layer in landing.layers) {
      final row = _rowOf(rows, layer, bases[parsed.baseOf(layer)]);
      bases[layer] = (
        layer: row.layer,
        cels: {
          for (final (index, cel) in layer.cells.indexed)
            cel.label: row.celIds[index],
        },
      );
      lay(row, layer.rowKey, [for (final cel in layer.cells) cel.file]);
    }

    if (open != null) {
      _openCutLayers.addAll(layers);
      return;
    }
    _cuts.add(
      importedCut(
        defaultCut: createDefaultCut(
          cutId: cutId,
          name: key == _theFolder ? edits.nameOf(parsed) : landing.name,
          layerId: mint.nextLayerId(),
          canvasSize: openCut?.canvasSize ?? defaultCutCanvasSize,
        ),
        layers: layers,
        duration: rows.duration,
      ),
    );
  }

  /// [layer] as a row of [rows]' cut: its symbol's attach row while it
  /// rides [base] — SYNCED when it corrects only cels [base] has, FREE
  /// otherwise ([CutFolderParseResult.correctsOnlyItsBaseCels]) — else a
  /// layer of its own.
  _FolderRow _rowOf(_FolderCut rows, ParsedCelLayer layer, _FolderBase? base) {
    final kind = edits.kindOfLayer(parsed, layer);
    final mark = edits.markOfLayer(parsed, layer);
    if (base == null || !edits.ridesItsBase(parsed, layer)) {
      return rows.layer(
        name: layer.symbol,
        kind: kind,
        mark: mark,
        cels: [for (final cel in layer.cells) cel.label],
      );
    }
    return parsed.correctsOnlyItsBaseCels(layer)
        ? rows.syncedCorrectionOf(base, layer, kind, mark)
        : rows.freeCorrectionOf(base, layer, kind, mark);
  }
}

/// A row the folder lands, and the cel each of its parsed cels bakes into —
/// in the parse's order, which a synced row's bank does not keep.
typedef _FolderRow = ({Layer layer, List<FrameId> celIds});

/// A symbol's own layer as its corrections ride it: the layer, and its cel
/// for each label the folder named — by the label, as an image layer's
/// one cel goes nameless.
typedef _FolderBase = ({Layer layer, Map<String, FrameId> cels});

/// The rows of ONE cut a folder lands in: each laid over the cut's
/// [duration], its ids from [mint].
///
/// 🗣️07-29 (유저), what a correction becomes: 「연출수정 = 그 위에 싱크
/// 어태치로 해당 프레임 위치에 넣기. 작감수정도 동일. LO에 없는 번호를
/// 수정에서 새로 만들면 = 프리 어태치로」 — SYNCED when every cel corrects
/// one its base has ([syncedCorrectionOf]); FREE when one is new, laid as
/// the folder's every layer is ([freeCorrectionOf]). Named by the symbol
/// alone — the colour label tells the two apart (F-429-Q2).
class _FolderCut {
  const _FolderCut(this.duration, this.mint);

  final int duration;
  final ImportIdMint mint;

  /// A row of the folder as a layer of its own, its cels named [cels] (a
  /// picture's are not): an image layer's one cel held over the cut's
  /// [duration], an animation layer's cels one comma each — the kind
  /// decides the shape, whatever file the row came from (🗣️F-429: 「레이어
  /// 타입(이미지,애니메이션)으로서 지정가능하고 그게 인식기준」).
  _FolderRow layer({
    required String name,
    required LayerKind kind,
    required LayerMark mark,
    required List<String?> cels,
  }) {
    final layerId = mint.nextLayerId();
    final held = kind.holdsSingleCel;
    final length = held ? duration : 1;
    final frames = [
      for (final cel in cels)
        Frame(
          id: mint.nextFrameId(layerId),
          duration: length,
          strokes: const [],
          name: held ? null : cel,
        ),
    ];
    return (
      layer: Layer(
        id: layerId,
        name: name,
        kind: kind,
        mark: mark,
        frames: frames,
        timeline: {
          for (final (index, frame) in frames.indexed)
            index: TimelineExposure.drawing(frame.id, length: length),
        },
      ),
      celIds: [for (final frame in frames) frame.id],
    );
  }

  /// [correction]'s cels as [base]'s FREE attach row, right above it, laid
  /// as a layer of its own is.
  _FolderRow freeCorrectionOf(
    _FolderBase base,
    ParsedCelLayer correction,
    LayerKind kind,
    LayerMark mark,
  ) {
    final (:layer, :celIds) = this.layer(
      name: correction.symbol,
      kind: kind,
      mark: mark,
      cels: [for (final cel in correction.cells) cel.label],
    );
    return (
      layer: layer.copyWith(
        // An attach row is born off the sheet (`addAttachedLayer`).
        onTimesheet: false,
        attachedToLayerId: base.layer.id,
        attachedPlacement: AttachedPlacement.above,
        attachedMode: AttachedMode.free,
      ),
      celIds: celIds,
    );
  }

  /// [correction]'s cels as [base]'s SYNCED attach row, right above it:
  /// one mirror cel per base cel — the always-mirror shape
  /// (`cutWithReconciledAttachedMirrors`) made here, as the .clip import's
  /// attach rows are; the corrected ones are the cels that get pixels.
  _FolderRow syncedCorrectionOf(
    _FolderBase base,
    ParsedCelLayer correction,
    LayerKind kind,
    LayerMark mark,
  ) {
    final layerId = mint.nextLayerId();
    FrameId mirrorOf(FrameId baseCel) =>
        attachedMirrorCelId(layerId, baseCel);
    return (
      layer: Layer(
        id: layerId,
        name: correction.symbol,
        kind: kind,
        mark: mark,
        frames: [
          for (final frame in base.layer.frames)
            Frame(id: mirrorOf(frame.id), duration: 1, strokes: const []),
        ],
        timeline: const {},
        onTimesheet: false,
        attachedToLayerId: base.layer.id,
        attachedPlacement: AttachedPlacement.above,
        attachedMode: AttachedMode.synced,
        baseFrameLinks: {
          for (final frame in base.layer.frames)
            frame.id: mirrorOf(frame.id),
        },
      ),
      celIds: [
        for (final cel in correction.cells) mirrorOf(base.cels[cel.label]!),
      ],
    );
  }
}
