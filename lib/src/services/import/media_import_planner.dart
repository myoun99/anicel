import 'dart:collection';

import '../editing/default_cut_helpers.dart';
import '../editing/default_layer_helpers.dart'
    show defaultLayerIdForSequence;
import '../editing/run_id_mint.dart' show mintFrameId;
import '../../models/attached_mode.dart';
import '../../models/attached_placement.dart';
import '../../models/canvas_size.dart';
import '../../models/cut.dart';
import '../../models/cut_id.dart';
import '../../models/frame.dart';
import '../../models/frame_id.dart';
import '../../models/import/cut_folder_parse.dart';
import '../../models/layer.dart';
import '../../models/layer_folder.dart';
import '../../models/layer_id.dart';
import '../../models/layer_kind.dart';
import '../../models/media_asset.dart';
import '../../models/media_reference.dart';
import '../../models/timeline_exposure.dart';
import '../../models/import/import_warning.dart';

/// PURE construction of the models an import lands (§6-z21's
/// interpretation table IS this plan rendered): the session mints ids and
/// does IO/decoding around it, the planner decides layer/cut/asset SHAPE.
/// Testable without a byte of pixel data.

/// Where an import lands (§2's three destinations; PROJECT — a new
/// project sized to the media — is a later round, documented).
enum ImportDestination {
  /// A layer in the ACTIVE cut.
  activeCutLayer,

  /// A new cut appended to the selected track.
  newCut,
}

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
  /// numbered run's cel labels, as the cut folder names its cels
  /// ([planCutFolderImport]). A folded run of duplicates takes its first
  /// position's name.
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

/// The whole-folder plan: ONE fully-formed cut (default fixtures kept,
/// drawing layer replaced by the parsed structure), the cel bakes, and
/// the reference registrations. Multi-cut folders (rule H) report the
/// EXTRA cut numbers — the session follows up with linked-cut creation.
class CutFolderImportPlan {
  const CutFolderImportPlan({
    required this.cut,
    required this.bakes,
    required this.assets,
    required this.extraCutNumbers,
    required this.warnings,
  });

  final Cut cut;
  final List<PlannedCelBake> bakes;
  final List<MediaAsset> assets;
  final List<String> extraCutNumbers;
  final List<ImportWarning> warnings;
}

CutFolderImportPlan planCutFolderImport({
  required CutFolderParseResult parsed,
  required String Function(String relativePath) resolveFile,
  required CanvasSize canvasSize,
  required ImportIdMint mint,
}) {
  final warnings = [...parsed.warnings];
  final cutId = mint.nextCutId();

  // Duration: every symbol layer lays its cels one comma each — the cut
  // runs as long as the longest layer (min 1).
  var duration = 1;
  for (final layer in parsed.layers) {
    if (layer.cells.length > duration) {
      duration = layer.cells.length;
    }
  }

  final layers = <Layer>[];
  final bakes = <PlannedCelBake>[];

  // Pictures first = bottom of the stack (BG under the cels).
  for (final picture in parsed.pictures) {
    final layerId = mint.nextLayerId();
    final frameId = mint.nextFrameId(layerId);
    layers.add(
      Layer(
        id: layerId,
        name: picture.name,
        kind: LayerKind.image,
        frames: [Frame(id: frameId, duration: duration, strokes: const [])],
        timeline: {0: TimelineExposure.drawing(frameId, length: duration)},
      ),
    );
    bakes.add(
      PlannedCelBake(
        cutId: cutId,
        layerId: layerId,
        frameId: frameId,
        sourceFile: resolveFile(picture.file),
      ),
    );
  }

  // Symbol layers in symbol order, each with its archived-process attach
  // structure (rule G/M → the R2 attach-folder shape: FREE attach rows
  // BELOW the base, one organizer folder per process).
  for (final parsedLayer in parsed.layers) {
    final baseId = mint.nextLayerId();

    for (final group in parsed.processGroups) {
      final processLayer = group.layers.where(
        (layer) => layer.symbol == parsedLayer.symbol,
      );
      if (processLayer.isEmpty) {
        continue;
      }
      final organizerId = mint.nextLayerId();
      final attachId = mint.nextLayerId();
      final attachCels = processLayer.first.cells;
      final attachFrames = <Frame>[];
      final attachTimeline = SplayTreeMap<int, TimelineExposure>();
      for (var i = 0; i < attachCels.length; i += 1) {
        final frameId = mint.nextFrameId(attachId);
        attachFrames.add(Frame(id: frameId, duration: 1, strokes: const []));
        attachTimeline[i] = TimelineExposure.drawing(frameId, length: 1);
        bakes.add(
          PlannedCelBake(
            cutId: cutId,
            layerId: attachId,
            frameId: frameId,
            sourceFile: resolveFile(attachCels[i].file),
          ),
        );
      }
      // Members precede their folder row; the whole run sits BELOW the
      // base (the archived process shows through under the newest one).
      layers.add(
        Layer(
          id: attachId,
          name: '${parsedLayer.symbol} ${group.process}',
          frames: attachFrames,
          timeline: attachTimeline,
          onTimesheet: false,
          attachedToLayerId: baseId,
          attachedPlacement: AttachedPlacement.below,
          attachedMode: AttachedMode.free,
          folderId: organizerId,
        ),
      );
      layers.add(
        createFolderLayer(id: organizerId, name: group.process),
      );
    }

    final baseFrames = <Frame>[];
    final baseTimeline = SplayTreeMap<int, TimelineExposure>();
    for (var i = 0; i < parsedLayer.cells.length; i += 1) {
      final cell = parsedLayer.cells[i];
      final frameId = mint.nextFrameId(baseId);
      baseFrames.add(
        Frame(
          id: frameId,
          duration: 1,
          strokes: const [],
          name: cell.label,
        ),
      );
      baseTimeline[i] = TimelineExposure.drawing(frameId, length: 1);
      bakes.add(
        PlannedCelBake(
          cutId: cutId,
          layerId: baseId,
          frameId: frameId,
          sourceFile: resolveFile(cell.file),
        ),
      );
    }
    layers.add(
      Layer(
        id: baseId,
        name: parsedLayer.symbol,
        frames: baseFrames,
        timeline: baseTimeline,
      ),
    );
  }

  if (layers.isEmpty) {
    warnings.add(
      const ImportWarning(
        'folderNothing',
        'The folder held no importable cels or pictures.',
      ),
    );
  }

  // Nothing exits silently (§6-z21): an archived-process symbol with no
  // matching top-level layer has no base to attach to — say so.
  final baseSymbols = {for (final layer in parsed.layers) layer.symbol};
  for (final group in parsed.processGroups) {
    for (final layer in group.layers) {
      if (!baseSymbols.contains(layer.symbol)) {
        warnings.add(
          ImportWarning(
            'folderNoBase',
            '{process}/{symbol}: no matching top-level layer — {n} cel(s) '
            'skipped.',
            {
              'process': group.process,
              'symbol': layer.symbol,
              'n': '${layer.cells.length}',
            },
          ),
        );
      }
    }
  }

  // References register (never baked — §6-z22); timing sheets are noted
  // for the later XDTS-read round.
  final assets = <MediaAsset>[];
  for (final reference in parsed.references) {
    final kind = switch (reference.kind) {
      ParsedReferenceKind.timesheetScan => MediaAssetKind.image,
      ParsedReferenceKind.movie => MediaAssetKind.video,
      ParsedReferenceKind.timingSheet => null,
      ParsedReferenceKind.workFile => null,
    };
    if (kind == null) {
      continue;
    }
    final path = resolveFile(reference.file);
    assets.add(
      MediaAsset(path: path, name: mediaAssetDefaultName(path), kind: kind),
    );
  }

  final cutName = parsed.cutNumbers.isEmpty
      ? parsed.folderName
      : parsed.cutNumbers.first;
  final defaultCut = createDefaultCut(
    cutId: cutId,
    name: cutName,
    layerId: mint.nextLayerId(),
    canvasSize: canvasSize,
  );
  final cut = importedCut(
    defaultCut: defaultCut,
    layers: layers,
    duration: duration,
  );

  return CutFolderImportPlan(
    cut: cut,
    bakes: bakes,
    assets: assets,
    extraCutNumbers: parsed.cutNumbers.length > 1
        ? parsed.cutNumbers.sublist(1)
        : const [],
    warnings: warnings,
  );
}
