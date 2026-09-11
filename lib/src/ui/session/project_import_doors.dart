// The doors a MEDIA FILE comes in through: one still or animated image, a
// Photoshop stack expanded into rows, a PDF's pages as cels.
//
// Their own object since round 8 (G1, 2026-09-06). All three do the same
// four things in the same order — pass the destination gate, plan the
// layer, land it, then bake its pixels — and the first of those is now
// [ImportLanding] rather than a copy each.

import 'dart:typed_data';
import 'dart:ui' as ui show ImageByteFormat;

import '../../models/kept_span.dart';
import '../../models/canvas_size.dart';
import '../../models/layer.dart';
import '../../models/layer_kind.dart';
import '../../models/media_asset.dart';
import '../../models/project_frame_rate.dart';
import '../../services/import/import_layer_spot.dart';
import '../../services/import/media_identity_reader.dart';
import '../../services/import/media_import_planner.dart';
import '../../services/import/psd_expand_import.dart';
import '../../services/import/raster_cel_import.dart';
import '../../services/media/media_byte_source.dart';
import '../../services/pdf/pdf_render_service.dart';
import '../audio/audio_conform_store.dart';
import 'import_landing.dart';
import 'media_fingerprint_ledger.dart';
import 'media_pool.dart';
import 'render_caches.dart';
import 'session_roles.dart';

/// The image / PSD / PDF / sound import doors.
class ProjectImportDoors {
  ProjectImportDoors({
    required ProjectAccess project,
    required ChangeSink changes,
    required SessionInternals internals,
    required RenderCaches renderCaches,
    required ImportLanding landing,
    required MediaFingerprintLedger fingerprints,
    required MediaPool pool,
    required AudioConformStore conforms,
    required ProjectFrameRate Function() frameRate,
  }) : _project = project,
       _changes = changes,
       _internals = internals,
       _renderCaches = renderCaches,
       _landing = landing,
       _fingerprints = fingerprints,
       _pool = pool,
       _conforms = conforms,
       _frameRate = frameRate;

  final ProjectAccess _project;
  final ChangeSink _changes;
  final SessionInternals _internals;
  final RenderCaches _renderCaches;
  final ImportLanding _landing;
  final MediaFingerprintLedger _fingerprints;
  final MediaPool _pool;
  final AudioConformStore _conforms;
  final ProjectFrameRate Function() _frameRate;

  /// Imports one still or animated image file (PNG/JPEG/GIF…) — the
  /// import window's core verb. Reference mode (default) stamps
  /// [Layer.mediaReference]; rasterize bakes and stamps nothing. Both
  /// REGISTER the asset (유저 2026-09-11: 「구워도 풀에 남음」). A NEW cut is
  /// made at the file's own size. One undo step; the baked cels display
  /// through the ordinary store paths. Returns false when nothing imported
  /// — including when the row a drop aimed at ([spot]) takes no frames.
  Future<bool> importImageFile({
    required String path,
    required ImportDestination destination,
    required bool copyIntoProject,
    bool rasterize = false,
    MediaFitMode fit = MediaFitMode.contain,
    int? lengthFrames,
    int inFrame = 0,
    int? outFrame,
    ImportLayerSpot? spot,
  }) async {
    // The destination gate runs BEFORE any decode: a refused import must
    // not have images to leak.
    final gate = _landing.arriveAt(destination, path: path, spot: spot);
    if (gate == null) {
      return false;
    }
    final Uint8List bytes;
    try {
      bytes = await MediaFileBytes(path).read();
    } on Object {
      return false;
    }
    final List<DecodedImageFrame> allFrames;
    try {
      allFrames = await decodeImageFrames(bytes);
    } on Object {
      return false;
    }
    if (allFrames.isEmpty) {
      return false;
    }
    // IN/OUT on a multi-frame source: only the chosen span becomes cels.
    // The frames outside it are disposed HERE rather than left to the
    // finally block, which only knows about the ones that were kept.
    final kept = KeptSpan(
      length: allFrames.length,
      inFrame: inFrame,
      outFrame: outFrame,
    );
    final decoded = allFrames.sublist(kept.first, kept.last + 1);
    for (var index = 0; index < allFrames.length; index += 1) {
      if (index < kept.first || index > kept.last) {
        allFrames[index].image.dispose();
      }
    }
    // A NEW cut is made at the file's own size, which its locked 1:1 fit
    // fills exactly.
    final first = decoded.first.image;
    final arrival = gate.targetCut == null
        ? gate.withCanvasSize(
            CanvasSize(width: first.width, height: first.height),
          )
        : gate;
    final source = arrival.source;
    // The file where the user keeps it, either way: carrying is a fact
    // about the SAVE now, not about a copy made at import time.
    final identity = readMediaIdentity(source);

    final cutId = arrival.cutId;
    final stillDuration = arrival.stillDuration(lengthFrames: lengthFrames);

    final Layer layer;
    final List<PlannedCelBake> bakes;
    final List<MediaAsset> assets;
    // A drop on a row's frames takes every picture as frames: a still is
    // ONE cell there (「한 장이면 한 칸」), not a hold over the cut.
    if (decoded.length == 1 && spot is! RowFramesSpot) {
      final plan = planStillImageLayer(
        sourceFile: source,
        displayName: arrival.displayName,
        cutId: cutId,
        duration: stillDuration,
        fit: fit,
        rasterize: rasterize,
        mint: arrival.mint,
        identity: identity,
        carried: copyIntoProject,
      );
      layer = plan.layer;
      bakes = plan.bakes;
      assets = plan.assets;
    } else {
      // Animated (GIF): frames become cels with duplicate folding; the
      // fingerprint is a cheap fold over each frame's RGBA bytes.
      final fingerprints = <Object?>[];
      for (final frame in decoded) {
        final data = await frame.image.toByteData(
          format: ui.ImageByteFormat.rawStraightRgba,
        );
        fingerprints.add(data == null ? null : _foldBytes(data));
      }
      final plan = planSequenceLayer(
        sourceFiles: List<String>.filled(decoded.length, source),
        frameFingerprints: fingerprints,
        displayName: arrival.displayName,
        cutId: cutId,
        fit: fit,
        rasterize: rasterize,
        mint: arrival.mint,
        referencePath: source,
        identity: identity,
        carried: copyIntoProject,
      );
      layer = plan.layer;
      bakes = plan.bakes;
      assets = plan.assets;
    }

    final landed = _landing.land(
      [layer],
      arrival: arrival,
      duration: decoded.length > 1 ? _sequenceLength(layer) : stillDuration,
      assets: assets,
    );
    if (!landed) {
      for (final frame in decoded) {
        frame.image.dispose();
      }
      return false;
    }
    // Frames dropped on a row are that row's cels, so their pixels are
    // keyed under it rather than under the layer that was only planned.
    final rowId = spot is RowFramesSpot ? spot.layerId : null;
    // 🔑 AFTER the registration. The bytes were read to decode them, so the
    // hash costs no I/O. A RASTERIZING import used to skip it because it
    // registered nothing; it registers now (유저 2026-09-11: 「구워도 풀에
    // 남음」), and a registered file is one that can go missing and have to
    // be found again — `A1.png` repeats in every cut folder on a real drive.
    if (assets.isNotEmpty) {
      _fingerprints.rememberMediaFingerprint(source, bytes);
    }

    // Bake pixels AFTER the structure exists (keys resolve the owner
    // track through the inserted cut). Duplicate folding compresses the
    // bake list, so every bake names its SOURCE frame index.
    try {
      final bakedCut = _project.cutById(cutId);
      if (bakedCut != null) {
        for (final bake in bakes) {
          final surface = await rasterizeImageToSurface(
            image: decoded[bake.sourceFrameIndex].image,
            canvas: bakedCut.canvasSize,
            fit: bake.fit,
          );
          bakeCelSurface(
            _renderCaches.brushFrameStore,
            _internals.brushFrameKeyForCut(
              bakedCut,
              rowId ?? bake.layerId,
              bake.frameId,
            ),
            surface,
          );
        }
      }
    } finally {
      for (final frame in decoded) {
        frame.image.dispose();
      }
    }

    _changes.refreshAfterCutCommand(
      preferredActiveLayerId: rowId ?? layer.id,
    );
    _changes.notifyChanged();
    return true;
  }

  /// EXPAND: a Photoshop stack becomes ours — ONE folder named after the
  /// file, holding its layers with their groups, names, opacity, blend and
  /// eye intact.
  ///
  /// Always baked. "One of them baked means all of them are" is the rule
  /// the user set: a half-linked stack would take original updates on some
  /// rows and not others, and a reorder in Photoshop would break the match
  /// for the rest. So nothing keeps a reference — the merged reading
  /// ([importImageFile]) is the one that stays live. The FILE still
  /// registers, carried or linked as the window said: a baked file is the
  /// pool's to offer again (유저 2026-09-11: 「구워도 풀에 남음」). A NEW cut
  /// is made at the document's size.
  ///
  /// Returns the warnings (colour conversions, blends we have no
  /// equivalent for, adjustment layers left behind), or null when the
  /// import did not happen — including a FLATTENED document, which has no
  /// stack to expand and which merge reads perfectly.
  Future<List<String>?> importPsdExpanded({
    required String path,
    required ImportDestination destination,
    required bool copyIntoProject,
    MediaFitMode fit = MediaFitMode.contain,
    int? lengthFrames,
    ImportLayerSpot? spot,
  }) async {
    // Same order as the image path: the destination gate runs before any
    // read, so a refused import never has pixels to leak.
    final gate = _landing.arriveAt(destination, path: path, spot: spot);
    if (gate == null) {
      return null;
    }
    final Uint8List bytes;
    try {
      bytes = await MediaFileBytes(path).read();
    } on Object {
      return null;
    }
    final cutId = gate.cutId;
    final duration = gate.stillDuration(lengthFrames: lengthFrames);

    final PsdExpansion? expansion;
    try {
      expansion = await readPsdExpansion(
        bytes: bytes,
        displayName: gate.displayName,
        cutId: cutId,
        duration: duration,
        canvas: gate.canvasSize,
        canvasFromDocument: gate.targetCut == null,
        fit: fit,
        mint: gate.mint,
      );
    } on Object {
      return null;
    }
    if (expansion == null || expansion.layers.isEmpty) {
      return null;
    }
    final arrival = gate.targetCut == null
        ? gate.withCanvasSize(expansion.canvas)
        : gate;

    _landing.land(
      expansion.layers,
      arrival: arrival,
      duration: duration,
      assets: [
        importedMediaAsset(
          path: arrival.source,
          kind: MediaAssetKind.image,
          fit: fit,
          identity: readMediaIdentity(arrival.source),
          carried: copyIntoProject,
        ),
      ],
    );
    _fingerprints.rememberMediaFingerprint(arrival.source, bytes);

    // Pixels after the structure, like every other import: the cel keys
    // resolve their owner through the cut that now exists.
    final bakedCut = _project.cutById(cutId);
    if (bakedCut != null) {
      for (final cel in expansion.cels) {
        bakeCelSurface(
          _renderCaches.brushFrameStore,
          _internals.brushFrameKeyForCut(bakedCut, cel.layerId, cel.frameId),
          cel.surface,
        );
      }
    }

    // The folder row is the last layer, and a folder takes no brush — so
    // the topmost PICTURE is what the hand should land on.
    final picture = expansion.layers.lastWhere(
      (layer) => layer.kind != LayerKind.folder,
      orElse: () => expansion!.layers.last,
    );
    _changes.refreshAfterCutCommand(preferredActiveLayerId: picture.id);
    _changes.notifyChanged();
    return expansion.warnings;
  }

  /// Imports a PDF: pages become cels at canvas resolution — §6-m's full
  /// pre-conversion, with the CEL STORE as the persistent home (it saves
  /// inside the .anicel, so placement rides every display/export path
  /// untouched; no separate disk cache). 1 page = 1 frame (§6-k).
  /// Returns false when the renderer is absent
  /// ([PdfRenderService.availability] says which), the destination
  /// refuses, or the document has no pages; a corrupt/locked file throws
  /// at open. A single page failing to RENDER leaves its cel empty and
  /// reports through [onPageRenderFailed] — the import still completes.
  Future<bool> importPdfFile({
    required String path,
    required ImportDestination destination,
    required bool copyIntoProject,
    bool rasterize = false,
    MediaFitMode fit = MediaFitMode.contain,
    int inFrame = 0,
    int? outFrame,
    void Function(int done, int total)? onRenderProgress,
    void Function(int pageIndex)? onPageRenderFailed,
    ImportLayerSpot? spot,
  }) async {
    // The destination gate runs BEFORE any native work — a refused
    // import must not have opened a document to leak.
    final gate = _landing.arriveAt(destination, path: path, spot: spot);
    if (gate == null) {
      return false;
    }
    final document = await PdfRenderService.open(path);
    if (document == null) {
      return false; // Renderer absent — the honest-absence state.
    }
    try {
      final pageCount = document.pageCount;
      if (pageCount <= 0) {
        return false;
      }
      // IN/OUT over PAGES: a hundred-page conte is imported for the cuts
      // someone is drawing this week, not for all of it. The span decides
      // how many cels there are; [pageCount] keeps describing the FILE,
      // because that is what the asset records about it.
      final kept = KeptSpan(
        length: pageCount,
        inFrame: inFrame,
        outFrame: outFrame,
      );
      final firstPage = kept.first;
      final spanCount = kept.count;
      // A NEW cut is made at the span's first page, at the size the
      // renderer calls 1:1 — the size the window's locked 1:1 fit draws.
      final firstSize = document.pageSize(firstPage);
      final arrival = gate.targetCut == null
          ? gate.withCanvasSize(
              CanvasSize(
                width: _pagePixels(firstSize.width),
                height: _pagePixels(firstSize.height),
              ),
            )
          : gate;
      final source = arrival.source;
      final identity = readMediaIdentity(source);
      final cutId = arrival.cutId;

      final Layer layer;
      final List<PlannedCelBake> bakes;
      final List<MediaAsset> assets;
      // A row's frames take one cell per page, a single page too.
      if (spanCount == 1 && spot is! RowFramesSpot) {
        // A one-page span is a still: an image-kind layer holding over the
        // cut, exactly like a placed PNG.
        final plan = planStillImageLayer(
          sourceFile: source,
          displayName: arrival.displayName,
          cutId: cutId,
          duration: arrival.stillDuration(),
          fit: fit,
          rasterize: rasterize,
          mint: arrival.mint,
          identity: identity,
          carried: copyIntoProject,
          assetKind: MediaAssetKind.pdf,
          pageCount: pageCount,
        );
        layer = plan.layer;
        bakes = plan.bakes;
        assets = plan.assets;
      } else {
        // Pages never fold (the fingerprint is the page index): a conte's
        // pages can repeat a layout, but page 12 is still page 12.
        final plan = planSequenceLayer(
          sourceFiles: List<String>.filled(spanCount, source),
          frameFingerprints: [
            for (var i = 0; i < spanCount; i += 1) firstPage + i,
          ],
          displayName: arrival.displayName,
          cutId: cutId,
          fit: fit,
          rasterize: rasterize,
          mint: arrival.mint,
          referencePath: source,
          identity: identity,
          carried: copyIntoProject,
          assetKind: MediaAssetKind.pdf,
          pageCount: pageCount,
        );
        layer = plan.layer;
        bakes = plan.bakes;
        assets = plan.assets;
      }

      final landed = _landing.land(
        [layer],
        arrival: arrival,
        duration: spanCount > 1 ? _sequenceLength(layer) : arrival.projectFps,
        assets: assets,
      );
      if (!landed) {
        return false;
      }
      final rowId = spot is RowFramesSpot ? spot.layerId : null;
      // ⛔ No fingerprint here. A PDF is opened BY PATH and rendered page by
      // page precisely so a hundred-page conte never lands in memory at
      // once; reading it whole to hash it would undo the one thing this
      // path is written to avoid. A PDF that goes missing stays findable by
      // name and length like it was before.

      // Bake AFTER the structure exists, one page at a time: render the
      // page at exactly its placement size (the vector source rasters
      // once, at the size it will live at — no second resample), then
      // donate through the ordinary cel path. Each page guards itself
      // (the importCutFolder contract): the command is already committed,
      // so one damaged page must leave its cel empty and be REPORTED —
      // never abort into a half-baked import the dialog would retry as a
      // duplicate.
      final bakedCut = _project.cutById(cutId);
      if (bakedCut != null) {
        var done = 0;
        for (final bake in bakes) {
          // The bake counts within the SPAN; the document counts from its
          // first page.
          final pageIndex = firstPage + bake.sourceFrameIndex;
          try {
            final pageSize = document.pageSize(pageIndex);
            final placement = placementRectFor(
              sourceWidth: _pagePixels(pageSize.width),
              sourceHeight: _pagePixels(pageSize.height),
              canvas: bakedCut.canvasSize,
              fit: bake.fit,
            );
            final image = await document.renderPage(
              pageIndex,
              width: _pagePixels(placement.width),
              height: _pagePixels(placement.height),
            );
            try {
              final surface = await rasterizeImageToSurface(
                image: image,
                canvas: bakedCut.canvasSize,
                fit: bake.fit,
              );
              bakeCelSurface(
                _renderCaches.brushFrameStore,
                _internals.brushFrameKeyForCut(
                  bakedCut,
                  rowId ?? bake.layerId,
                  bake.frameId,
                ),
                surface,
              );
            } finally {
              image.dispose();
            }
          } on Object {
            onPageRenderFailed?.call(pageIndex);
          }
          done += 1;
          onRenderProgress?.call(done, bakes.length);
        }
      }

      _changes.refreshAfterCutCommand(
        preferredActiveLayerId: rowId ?? layer.id,
      );
      _changes.notifyChanged();
      return true;
    } finally {
      await document.dispose();
    }
  }

  /// A SOUND onto the track's SE rows ([ImportLanding.landSound]). The
  /// conform answers how long it is, and [inFrame]/[outFrame] trim it: the
  /// in point is how far into the file the block's sound starts, the span
  /// is the block's length. Returns false when the sound cannot be read or
  /// there is no cut to measure from.
  Future<bool> importSoundFile({
    required String path,
    required bool copyIntoProject,
    int inFrame = 0,
    int? outFrame,
    ImportLayerSpot? spot,
  }) async {
    final gate = _landing.arriveAt(
      ImportDestination.activeCutLayer,
      path: path,
      spot: spot,
    );
    if (gate == null) {
      return false;
    }
    final source = _pool.importAudioFile(path);
    final peaks = await _conforms.ensurePeaksFor(source);
    if (peaks == null) {
      return false;
    }
    final kept = KeptSpan(
      length: peaks.durationFrames(_frameRate()),
      inFrame: inFrame,
      outFrame: outFrame,
    );
    final landed = _landing.landSound(
      arrival: gate,
      offsetFrames: kept.first,
      lengthFrames: kept.count,
      assets: [
        importedMediaAsset(
          path: source,
          kind: MediaAssetKind.audio,
          fit: MediaFitMode.contain,
          identity: readMediaIdentity(source),
          carried: copyIntoProject,
        ),
      ],
    );
    if (landed) {
      _changes.notifyChanged();
    }
    return landed;
  }

  /// A page extent as whole pixels the renderer accepts.
  int _pagePixels(double extent) => extent.round().clamp(1, 1 << 13).toInt();

  int _sequenceLength(Layer layer) {
    var end = 1;
    for (final entry in layer.timeline.entries) {
      final length = entry.value.length ?? 1;
      if (entry.key + length > end) {
        end = entry.key + length;
      }
    }
    return end;
  }

  Object _foldBytes(ByteData data) {
    // Every 4th PIXEL, all four channels — a fold that read one channel
    // would merge frames whose change hides in the others.
    var hash = 0x811c9dc5;
    for (var i = 0; i + 3 < data.lengthInBytes; i += 16) {
      hash = (hash ^ data.getUint32(i)) * 0x01000193 & 0xFFFFFFFF;
    }
    return Object.hash(hash, data.lengthInBytes);
  }
}
