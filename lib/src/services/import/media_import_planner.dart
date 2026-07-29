import 'dart:collection';

import '../../controllers/default_cut_helpers.dart';
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

  final LayerId Function() nextLayerId;
  final FrameId Function(LayerId layerId) nextFrameId;
  final CutId Function() nextCutId;
}

/// One cel whose PIXELS must be baked after the structural command runs:
/// decode [sourceFile], rasterize at the cut's canvas with [fit], store
/// under (cutId, layerId, frameId).
class PlannedCelBake {
  const PlannedCelBake({
    required this.cutId,
    required this.layerId,
    required this.frameId,
    required this.sourceFile,
    required this.fit,
    this.sourceFrameIndex = 0,
  });

  final CutId cutId;
  final LayerId layerId;
  final FrameId frameId;
  final String sourceFile;
  final MediaFitMode fit;

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

/// Builds one IMAGE layer for [sourceFile]: born covering [duration]
/// (the write normalization keeps it at the cut length afterwards).
/// Reference mode registers the asset and stamps [Layer.mediaReference];
/// rasterize mode registers nothing (§3: pixels absorbed = no entry).
ImageLayerImportPlan planStillImageLayer({
  required String sourceFile,
  required String displayName,
  required CutId cutId,
  required int duration,
  required MediaFitMode fit,
  required bool rasterize,
  required ImportIdMint mint,
  String? sourcePath,
  String? sourceStamp,
  MediaAssetKind assetKind = MediaAssetKind.image,
  int? pageCount,
}) {
  final layerId = mint.nextLayerId();
  final frameId = mint.nextFrameId(layerId);
  final clampedDuration = duration < 1 ? 1 : duration;
  final layer = Layer(
    id: layerId,
    name: displayName,
    kind: LayerKind.image,
    frames: [Frame(id: frameId, duration: clampedDuration, strokes: const [])],
    timeline: {0: TimelineExposure.drawing(frameId, length: clampedDuration)},
    mediaReference: rasterize ? null : MediaReference(assetPath: sourceFile),
  );
  return ImageLayerImportPlan(
    layer: layer,
    bakes: [
      PlannedCelBake(
        cutId: cutId,
        layerId: layerId,
        frameId: frameId,
        sourceFile: sourceFile,
        fit: fit,
      ),
    ],
    assets: rasterize
        ? const []
        : [
            MediaAsset(
              path: sourceFile,
              name: mediaAssetDefaultName(sourceFile),
              kind: assetKind,
              fitMode: fit,
              sourcePath: sourcePath,
              sourceStamp: sourceStamp,
              pageCount: pageCount,
            ),
          ],
  );
}

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
  required MediaFitMode fit,
  required bool rasterize,
  required ImportIdMint mint,
  String? referencePath,
  String? sourcePath,
  String? sourceStamp,
  double? sourceFps,
  MediaAssetKind assetKind = MediaAssetKind.image,
  int? pageCount,
}) {
  assert(sourceFiles.length == frameFingerprints.length);
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
    frames.add(Frame(id: frameId, duration: 1, strokes: const []));
    bakes.add(
      PlannedCelBake(
        cutId: cutId,
        layerId: layerId,
        frameId: frameId,
        sourceFile: sourceFiles[i],
        fit: fit,
        sourceFrameIndex: i,
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
    mediaReference: rasterize || referencePath == null
        ? null
        : MediaReference(assetPath: referencePath),
  );
  return SequenceLayerImportPlan(
    layer: layer,
    bakes: bakes,
    assets: rasterize || referencePath == null
        ? const []
        : [
            MediaAsset(
              path: referencePath,
              name: mediaAssetDefaultName(referencePath),
              kind: assetKind,
              fitMode: fit,
              sourcePath: sourcePath,
              sourceStamp: sourceStamp,
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
  final List<String> warnings;
}

CutFolderImportPlan planCutFolderImport({
  required CutFolderParseResult parsed,
  required String Function(String relativePath) resolveFile,
  required CanvasSize canvasSize,
  required MediaFitMode fit,
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
        fit: fit,
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
            fit: fit,
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
          fit: fit,
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
    warnings.add('The folder held no importable cels or pictures.');
  }

  // Nothing exits silently (§6-z21): an archived-process symbol with no
  // matching top-level layer has no base to attach to — say so.
  final baseSymbols = {for (final layer in parsed.layers) layer.symbol};
  for (final group in parsed.processGroups) {
    for (final layer in group.layers) {
      if (!baseSymbols.contains(layer.symbol)) {
        warnings.add(
          '${group.process}/${layer.symbol}: no matching top-level layer '
          '— ${layer.cells.length} cel(s) skipped.',
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
  // Keep the fixtures (instruction + camera), replace the default
  // drawing layer with the parsed structure.
  final fixtureLayers = [
    for (final layer in defaultCut.layers)
      if (layer.kind != LayerKind.animation) layer,
  ];
  final cut = defaultCut.copyWith(
    duration: duration,
    layers: layers.isEmpty ? defaultCut.layers : [...layers, ...fixtureLayers],
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
