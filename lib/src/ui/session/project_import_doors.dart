// The doors a MEDIA FILE comes in through: one still or animated image, a
// Photoshop stack expanded into rows, a PDF's pages as cels — and the file a
// reference row is swapped to (I-47).
//
// Their own object since round 8 (G1, 2026-09-06). All three do the same
// four things in the same order — pass the destination gate, plan the
// layer, land it, then bake its pixels — and the first of those is now
// [ImportLanding] rather than a copy each.

import 'dart:collection';
import 'dart:typed_data';

import '../../models/bitmap_surface.dart';
import '../../models/brush_frame_key.dart';
import '../../models/kept_span.dart';
import '../../models/canvas_size.dart';
import '../../models/dirty_region.dart';
import '../../models/cut.dart';
import '../../models/cut_id.dart';
import '../../models/frame.dart';
import '../../models/frame_id.dart';
import '../../models/layer.dart';
import '../../models/layer_id.dart';
import '../../models/layer_kind.dart';
import '../../models/media_asset.dart';
import '../../models/media_reference.dart';
import '../../models/movie_cel.dart';
import '../../models/movie_clock.dart';
import '../../models/project_frame_rate.dart';
import '../../models/reference_swap.dart';
import '../../models/timeline_coverage.dart';
import '../../models/timeline_exposure.dart';
import '../../models/transform_pose.dart';
import '../../native/qa_video_decoder.dart' show QaVideoInfo;
import '../../services/brush_frame_store.dart' show CelRead;
import '../../services/brush_stroke_blend.dart' show bitmapSurfaceRegionPixels;
import '../../services/commands/rasterize_layer_reference_command.dart';
import '../../services/commands/swap_layer_reference_command.dart';
import '../../services/cut_frame_composite_plan.dart' show referenceMoveAt;
import '../../services/guide_geometry.dart' show GuideTransform;
import '../../services/layer_pose_matrix.dart'
    show LayerPlacement, picturePlacement;
import '../../services/commands/update_layer_timeline_command.dart';
import '../../services/import/import_layer_spot.dart';
import '../../services/import/cel_picture.dart';
import '../../services/import/media_identity_reader.dart';
import '../../services/import/media_import_planner.dart';
import '../../services/import/psd_expand_import.dart';
import '../../services/import/raster_cel_import.dart';
import '../../services/reference_move_carried.dart'
    show ReferenceMoveCarried, ReferenceUse;
import '../../services/media/held_viewer_document.dart';
import '../../services/media/media_byte_source.dart';
import '../../services/media/viewer_document.dart'
    show ViewerDocument, pagePixelSize, pagePixels;
import '../../services/media/movie_bytes.dart';
import '../../services/media/video_decode_worker.dart';
import '../../services/pdf/pdf_render_service.dart';
import '../../services/persistence/media_staging_store.dart';
import '../audio/audio_conform_store.dart';
import '../import/import_file_settings.dart';
import 'import_landing.dart';
import 'media_fingerprint_ledger.dart';
import 'media_pool.dart';
import '../canvas/tiled_surface_compose.dart'
    show composePositionedSurfaceImage, surfaceContentWorldRect;
import 'render_caches.dart';
import 'session_roles.dart';
import '../../models/import/import_warning.dart';

/// WHAT LANDS when a movie is placed, before any of it has landed: where it
/// arrives, the span it covers on the sound's clock, and the row itself.
///
/// One value because three steps read it — the plan makes it, the landing
/// puts it in the project, the bake fills its pixels — and a step deriving
/// its own copy of 「where does this go, how long is it」 is how the bake
/// lands on different frames than the reference showed.
typedef _MoviePlacement = ({
  ImportArrival arrival,
  KeptSpan kept,
  Layer layer,
  List<PlannedCelBake> bakes,
});

/// One picture a bake lays: its pixels, whether the bake lets go of them,
/// and the size the picture IS — what a pose stands on (I-68). A PDF page
/// is rendered at the size it will stand at, so its pixels are not its
/// size.
typedef _BakePicture = ({CelPicture picture, bool owned, CanvasSize size});

/// What making a reference row's pictures from its file again came to
/// ([ProjectImportDoors]): the pictures, or why there are none.
sealed class _Remade {
  const _Remade();
}

/// A reference row's pictures made from its file again, by cel, and the
/// reference that says the size of what it shows.
final class _Drawn extends _Remade {
  const _Drawn(this.pictures, this.reference);

  final Map<FrameId, BitmapSurface> pictures;
  final MediaReference reference;
}

/// No pictures, and [why]: the file did not read, or lacks one a cel shows.
final class _NotDrawn extends _Remade {
  const _NotDrawn(this.why);

  final ReferenceRedraw why;
}

/// A file's pictures, open: how many it holds, each made from its place in
/// the file, and the letting go of what was opened for them.
typedef _OpenPictures = ({
  int count,
  Future<_BakePicture> Function(int index) at,
  Future<void> Function() close,
});

/// The pictures of a file a row asked for, by their place in the file, laid
/// and measured.
typedef _MadePictures = ({
  Map<int, BitmapSurface> surfaces,
  Map<int, CanvasSize> sizes,
});

/// [picture] as the picture it is: its size is its own.
_BakePicture _pictureOf(CelPicture picture, {required bool owned}) =>
    (picture: picture, owned: owned, size: picture.size);

/// Where a placement stands each of its pictures — one rule for the whole
/// placement, given the bake, the picture's own size and the canvas it
/// lands on. A movie rasterized as it is shown stands each frame where its
/// reference fx stood it there ([ProjectImportDoors.rasterizeMovieReference]).
typedef _Standing =
    TransformPose Function(
      PlannedCelBake bake,
      CanvasSize picture,
      CanvasSize canvas,
    );

/// Each picture at its own [fit] — a placement that bakes.
_Standing _atTheFit(MediaFitMode fit) => (_, picture, canvas) =>
    fitPose(picture: picture, canvas: canvas, fit: fit);

/// Every picture where [reference] lays its file ([MediaReference.laid])
/// when the row SHOWS a file (I-68), over each picture's own pixels; each
/// at its own [fit] when it bakes.
_Standing _standingFor(MediaReference? reference, MediaFitMode fit) =>
    reference == null ? _atTheFit(fit) : (_, _, _) => reference.laid;

/// The cels every use of a movie reference is rasterized into
/// ([ProjectImportDoors.rasterizeMovieReference]): the bank the uses share,
/// the bakes that fill it, where each cel's picture stands, and each use's
/// exposure of them, in the uses' order.
typedef _MovieCels = ({
  List<Frame> frames,
  List<PlannedCelBake> bakes,
  Map<FrameId, TransformPose> standing,
  List<SplayTreeMap<int, TimelineExposure>> timelines,
});

/// What one use of a movie reference shows at each position of its block,
/// and the cels that makes ([ProjectImportDoors._plannedMovieUse]).
typedef _PlannedMovieUse = ({
  List<_ShownMovieFrame> shown,
  SequenceLayerImportPlan plan,
});

/// What a movie reference shows at one position: its file, the movie frame
/// the sound's clock reads there, and where that picture stands.
typedef _ShownMovieFrame = ({String file, int movieFrame, TransformPose pose});

/// The image / PSD / PDF / sound import doors.
class ProjectImportDoors {
  ProjectImportDoors({
    required ProjectAccess project,
    required ChangeSink changes,
    required RenderCaches renderCaches,
    required ImportLanding landing,
    required MediaFingerprintLedger fingerprints,
    required MediaPool pool,
    required AudioConformStore conforms,
    required ProjectFrameRate Function() frameRate,
    required HoldMediaBytes holdBytes,
  }) : _project = project,
       _changes = changes,
       _renderCaches = renderCaches,
       _landing = landing,
       _fingerprints = fingerprints,
       _pool = pool,
       _conforms = conforms,
       _frameRate = frameRate,
       _holdBytes = holdBytes;

  final ProjectAccess _project;
  final ChangeSink _changes;
  final RenderCaches _renderCaches;
  final ImportLanding _landing;
  final MediaFingerprintLedger _fingerprints;

  /// 🚨★★★**A PLACEMENT THAT CARRIES HOLDS THE BYTES FIRST.** Every door
  /// here decides an asset carried from the window's Keep, and the landing
  /// is what records it in the pool — so each door asks the pool's one
  /// question for it ([MediaPool.holdCarriedBytes]) BEFORE the landing (유저
  /// 2026-08-30: 「품은 순간 데이터를 가지고있고 불변이었으면좋겠어서」; the
  /// order is [MediaStagingStore.stageCarriedBytes]'s law). 🪦None of the
  /// five doors did from the day staging landed until 2026-09-23: they
  /// decide carrying from a VARIABLE (`carried: copyIntoProject`), and the
  /// scan that keeps the law looked for the literal `carried: true`.
  /// 🪦A one-line forwarder, `_holdCarried`, stood between them and the pool
  /// with this paragraph on it (audit 09-25).
  final MediaPool _pool;
  final AudioConformStore _conforms;
  final ProjectFrameRate Function() _frameRate;

  /// Where a medium's bytes are — the project's own copy first
  /// (`ProjectFile.holdMediaBytes`). 🪦Every door here read the file at the
  /// path it was handed, so placing a carried medium from the pool read its
  /// ORIGINAL: gone, the placement failed; edited, the edit landed (card
  /// `carried-bytes-every-reader`).
  final HoldMediaBytes _holdBytes;

  /// Imports one still or animated image file (PNG/JPEG/GIF…) — the
  /// import window's core verb. Reference mode (default) stamps
  /// [Layer.mediaReference] and REGISTERS the asset; rasterize bakes,
  /// stamps nothing and registers nothing ([placementRegisters]). A NEW cut is
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

    /// Where [path] was cut from — a trimmed file's piece carries its
    /// original here, as provenance only ([TrimmedPieces]).
    String? sourcePath,

    /// Hears the carried bytes held, as 0–1 ([MediaPool.holdCarriedBytes])
    /// — a big file's copy is the long wait of a carried placement
    /// (F-494).
    void Function(double fraction)? onCarrying,
  }) async {
    // The destination gate runs BEFORE any decode: a refused import must
    // not have images to leak.
    final gate = _landing.arriveAt(destination, path: path, spot: spot);
    if (gate == null) {
      return false;
    }
    final Uint8List bytes;
    try {
      bytes = await readHeldMediaBytes(_holdBytes, path);
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
        allFrames[index].picture.dispose();
      }
    }
    // A NEW cut is made at the file's own size, which its locked 1:1 fit
    // fills exactly.
    final first = decoded.first.picture;
    final arrival = gate.targetCut == null
        ? gate.withCanvasSize(first.size)
        : gate;
    final source = arrival.source;
    // The file where the user keeps it — what the pool points at, kept
    // inside or not. A carried one's bytes are held as well, before it
    // lands ([MediaPool.holdCarriedBytes]); carrying stopped being the
    // save's business on 2026-08-30.
    final identity = readMediaIdentity(source);

    final cutId = arrival.cutId;
    final stillDuration = arrival.stillDuration(lengthFrames: lengthFrames);
    // Frames on a row are that row's own pixels (「셀에 떨어뜨리면 항상
    // 굽기」) — baked, whatever was asked.
    final reference = rasterize || spot is RowFramesSpot
        ? null
        : placedReference(source, first.size, arrival.canvasSize, fit);

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
        reference: reference,
        mint: arrival.mint,
        identity: identity,
        carried: copyIntoProject,
        sourcePath: sourcePath,
        picture: kept.first,
      );
      layer = plan.layer;
      bakes = plan.bakes;
      assets = plan.assets;
    } else {
      // Animated (GIF): frames become cels with duplicate folding; the
      // fingerprint is a cheap fold over each frame's RGBA bytes.
      final fingerprints = <Object?>[];
      for (final frame in decoded) {
        fingerprints.add(_foldBytes(await frame.picture.straightRgba()));
      }
      final plan = planSequenceLayer(
        sourceFiles: List<String>.filled(decoded.length, source),
        frameFingerprints: fingerprints,
        displayName: arrival.displayName,
        cutId: cutId,
        fit: fit,
        mint: arrival.mint,
        reference: reference,
        identity: identity,
        carried: copyIntoProject,
        sourcePath: sourcePath,
        firstPicture: kept.first,
      );
      layer = plan.layer;
      bakes = plan.bakes;
      assets = plan.assets;
    }

    await _pool.holdCarriedBytes(assets, onProgress: onCarrying);
    final landed = _landing.land(
      [layer],
      arrival: arrival,
      duration: decoded.length > 1 ? _sequenceLength(layer) : stillDuration,
      assets: assets,
    );
    if (!landed) {
      for (final frame in decoded) {
        frame.picture.dispose();
      }
      return false;
    }
    // 🔑 AFTER the registration. The bytes were read to decode them, so the
    // hash costs no I/O. A registered file is one that can go missing and
    // have to be found again — `A1.png` repeats in every cut folder on a
    // real drive — and a baked one is not registered (F-282-Q6).
    if (assets.isNotEmpty) {
      _fingerprints.rememberMediaFingerprint(source, bytes);
    }

    // Bake pixels AFTER the structure exists (keys resolve the owner
    // track through the inserted cut). Duplicate folding compresses the
    // bake list, so every bake names its SOURCE frame index.
    try {
      await _bakeLandedCels(
        cutId,
        layer,
        bakes,
        rowId: _rowOf(spot),
        standing: _standingFor(reference, fit),
        pictureOf: (bake, _) async =>
            _pictureOf(decoded[bake.sourceFrameIndex].picture, owned: false),
      );
    } finally {
      for (final frame in decoded) {
        frame.picture.dispose();
      }
    }
    return true;
  }

  /// A NUMBERED RUN of pictures — `1` · `2` · `3`, `A1` · `A2` … of one
  /// folder (`pictureRunOf`) — as ONE layer's frames, the way an animated
  /// picture comes in ([planSequenceLayer]): a picture the one before it
  /// already showed folds into that one's exposure. [files] are in the
  /// run's order, each with its number, which names its frame; the layer is
  /// [name].
  ///
  /// 🗣️I-76 (유저 2026-10-06 · I-76-Q1 10-08): 「A1-A3 이렇게 한 레이어의 세
  /// 프레임으로 인식하는 느낌」.
  ///
  /// Always baked: a layer's reference names ONE file, and these are many
  /// — the cut folder's law, which always bakes. So nothing registers
  /// ([placementRegisters], F-282-Q6). ↩️Each file registered on its own
  /// (유저 2026-09-11: 「구워도 풀에 남음」).
  ///
  /// One file is decoded at a time — to fold, then again to bake — so a run
  /// of full-page scans never sits in memory whole.
  Future<bool> importPictureRun({
    required List<({String path, String label})> files,
    required String name,
    required ImportFileSettings settings,
    ImportLayerSpot? spot,
    void Function(int done, int total)? onRenderProgress,
    void Function(int position)? onCelFailed,
  }) async {
    if (files.isEmpty) {
      return false;
    }
    final gate = _landing.arriveAt(
      settings.into,
      path: files.first.path,
      spot: spot,
    );
    if (gate == null) {
      return false;
    }
    final sources = [for (final file in files) normalizedMediaPath(file.path)];
    final fold = await _foldRun(sources);
    if (fold == null) {
      return false;
    }
    // A NEW cut is made at the first picture's size, as a still's is.
    final arrival = gate.targetCut == null
        ? gate.withCanvasSize(fold.firstSize)
        : gate;
    final plan = planSequenceLayer(
      sourceFiles: sources,
      frameFingerprints: fold.fingerprints,
      displayName: name,
      cutId: arrival.cutId,
      mint: arrival.mint,
      frameNames: [for (final file in files) file.label],
    );
    if (!_landing.land(
      [plan.layer],
      arrival: arrival,
      duration: _sequenceLength(plan.layer),
      assets: const [],
    )) {
      return false;
    }
    await _bakeLandedCels(
      arrival.cutId,
      plan.layer,
      plan.bakes,
      rowId: _rowOf(spot),
      standing: _atTheFit(settings.fit),
      pictureOf: (bake, _) => _ownedStillOf(bake.sourceFile),
      onProgress: onRenderProgress,
      onFailed: onCelFailed == null
          ? null
          : (bake) => onCelFailed(bake.sourceFrameIndex),
    );
    return true;
  }

  /// What the fold reads of each of [sources]' pictures ([_foldBytes]), and
  /// the first one's size — one file decoded at a time; null when one does
  /// not read.
  ///
  /// ↩️Each one's bytes were fingerprinted on the way, for the pool entry
  /// each file was — the run registers nothing now (F-282-Q6), and a
  /// fingerprint is how a REGISTERED file is found again.
  Future<({List<Object?> fingerprints, CanvasSize firstSize})?> _foldRun(
    List<String> sources,
  ) async {
    final fingerprints = <Object?>[];
    CanvasSize? firstSize;
    for (final source in sources) {
      final still = await _stillOf(source);
      if (still == null) {
        return null;
      }
      firstSize ??= still.size;
      final Uint8List pixels;
      try {
        // A picture held off the engine is read here, not at its decode.
        pixels = await still.straightRgba();
      } on Object {
        return null;
      } finally {
        still.dispose();
      }
      fingerprints.add(_foldBytes(pixels));
    }
    return (fingerprints: fingerprints, firstSize: firstSize!);
  }

  /// A cel's picture to bake, read again: the fold let go of it.
  Future<_BakePicture> _ownedStillOf(String path) async {
    final still = await _stillOf(path);
    if (still == null) {
      throw StateError('$path no longer reads');
    }
    return _pictureOf(still, owned: true);
  }

  /// [path]'s picture — the first frame of what it decodes to, a run's cel
  /// being a still; null when it does not read or decode.
  Future<CelPicture?> _stillOf(String path) async {
    try {
      final bytes = await readHeldMediaBytes(_holdBytes, path);
      final frames = await decodeImageFrames(bytes);
      if (frames.isEmpty) {
        return null;
      }
      for (final extra in frames.skip(1)) {
        extra.picture.dispose();
      }
      return frames.first.picture;
    } on Object {
      return null;
    }
  }

  /// EXPAND: a Photoshop stack becomes ours — its layers with their groups,
  /// names, opacity, blend and eye intact, held in ONE folder named after
  /// the file where they join a cut, and standing bare in a NEW cut, which
  /// is the file's own ([planPsdExpansion], F-422).
  ///
  /// Always baked. "One of them baked means all of them are" is the rule
  /// the user set: a half-linked stack would take original updates on some
  /// rows and not others, and a reorder in Photoshop would break the match
  /// for the rest. So nothing keeps a reference — the merged reading
  /// ([importImageFile]) is the one that stays live. Baked, so the FILE
  /// registers nothing ([placementRegisters], F-282-Q6). ↩️It registered,
  /// carried or linked as the window said (유저 2026-09-11: 「구워도 풀에
  /// 남음」). A NEW cut is made at the document's size.
  ///
  /// Returns the warnings (colour conversions, blends we have no
  /// equivalent for, adjustment layers left behind), or null when the
  /// import did not happen — including a FLATTENED document, which has no
  /// stack to expand and which merge reads perfectly.
  Future<List<ImportWarning>?> importPsdExpanded({
    required String path,
    required ImportDestination destination,
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
      bytes = await readHeldMediaBytes(_holdBytes, path);
    } on Object {
      return null;
    }
    final cutId = gate.cutId;
    final duration = gate.stillDuration(lengthFrames: lengthFrames);
    final newCut = gate.targetCut == null;

    final PsdExpansion? expansion;
    try {
      expansion = await readPsdExpansion(
        bytes: bytes,
        displayName: gate.displayName,
        cutId: cutId,
        duration: duration,
        canvas: gate.canvasSize,
        newCut: newCut,
        fit: fit,
        mint: gate.mint,
      );
    } on Object {
      return null;
    }
    if (expansion == null || expansion.layers.isEmpty) {
      return null;
    }
    final arrival = newCut ? gate.withCanvasSize(expansion.canvas) : gate;

    _landing.land(
      expansion.layers,
      arrival: arrival,
      duration: duration,
      assets: const [],
    );

    // Pixels after the structure, like every other import: the cel keys
    // resolve their owner through the cut that now exists.
    final bakedCut = _project.cutById(cutId);
    if (bakedCut != null) {
      for (final cel in expansion.cels) {
        bakeCelSurface(
          _renderCaches.brushFrameStore,
          _project.brushFrameKeyForCut(bakedCut, cel.layerId, cel.frameId),
          cel.surface,
        );
      }
    }

    // The last row may be a folder — the file's, where it joined a cut, or
    // a group of its own — and a folder takes no brush, so the topmost
    // PICTURE is what the hand should land on.
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

    /// Where [path] was cut from — see [importImageFile]'s.
    String? sourcePath,

    /// See [importImageFile]'s.
    void Function(double fraction)? onCarrying,
  }) async {
    // The destination gate runs BEFORE any native work — a refused
    // import must not have opened a document to leak.
    final gate = _landing.arriveAt(destination, path: path, spot: spot);
    if (gate == null) {
      return false;
    }
    final document = await openHeldViewerDocument(
      _holdBytes,
      path,
      PdfRenderService.open,
    );
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
      final arrival = gate.targetCut == null
          ? gate.withCanvasSize(pagePixelSize(document, firstPage))
          : gate;
      final source = arrival.source;
      final identity = readMediaIdentity(source);
      final cutId = arrival.cutId;
      // Frames on a row are that row's own pixels (「셀에 떨어뜨리면 항상
      // 굽기」) — baked, whatever was asked.
      final reference = rasterize || spot is RowFramesSpot
          ? null
          : placedReference(
              source,
              pagePixelSize(document, firstPage),
              arrival.canvasSize,
              fit,
            );

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
          reference: reference,
          mint: arrival.mint,
          identity: identity,
          carried: copyIntoProject,
          sourcePath: sourcePath,
          assetKind: MediaAssetKind.pdf,
          pageCount: pageCount,
          picture: firstPage,
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
          mint: arrival.mint,
          reference: reference,
          identity: identity,
          carried: copyIntoProject,
          sourcePath: sourcePath,
          assetKind: MediaAssetKind.pdf,
          pageCount: pageCount,
          firstPicture: firstPage,
        );
        layer = plan.layer;
        bakes = plan.bakes;
        assets = plan.assets;
      }

      await _pool.holdCarriedBytes(assets, onProgress: onCarrying);
      final landed = _landing.land(
        [layer],
        arrival: arrival,
        duration: spanCount > 1 ? _sequenceLength(layer) : arrival.projectFps,
        assets: assets,
      );
      if (!landed) {
        return false;
      }
      // ⛔ No fingerprint here. A PDF is opened BY PATH and rendered page by
      // page precisely so a hundred-page conte never lands in memory at
      // once; reading it whole to hash it would undo the one thing this
      // path is written to avoid. A PDF that goes missing stays findable by
      // name and length like it was before.

      // Bake AFTER the structure exists, one page at a time: render the
      // page at exactly the size it will stand at (the vector source
      // rasters once — no second resample), then donate through the
      // ordinary cel path. Each page guards itself (the importCutFolder
      // contract): the command is already committed, so one damaged page
      // must leave its cel empty and be REPORTED — never abort into a
      // half-baked import the dialog would retry as a duplicate.
      final standing = _standingFor(reference, fit);
      await _bakeLandedCels(
        cutId,
        layer,
        bakes,
        rowId: _rowOf(spot),
        standing: standing,
        onProgress: onRenderProgress,
        // The bake counts within the SPAN; the document counts from its
        // first page.
        onFailed: (bake) =>
            onPageRenderFailed?.call(firstPage + bake.sourceFrameIndex),
        pictureOf: (bake, canvas) {
          final pageIndex = firstPage + bake.sourceFrameIndex;
          final page = pagePixelSize(document, pageIndex);
          return _renderedPage(
            document,
            pageIndex,
            page,
            standing(bake, page, canvas),
          );
        },
      );
      return true;
    } finally {
      await document.dispose();
    }
  }

  /// A MOVIE (미디어 배치 라운드 6). The picture lands the way a sequence
  /// does — kept as a REFERENCE when the window's bake is off (one cel over
  /// the span, decoded when it is shown), baked into cels when it is on or
  /// when the drop was a picture row's frames (「프레임 영역은 늘
  /// 굽는다」) — and its SOUND, when the 「소리」 answer
  /// ([ImportFileSettings.movieParts]) brings it and the movie has one,
  /// lands on the SE rows by the sound's own law, starting where the
  /// picture starts (「같은 시작 · 같은 구간」). One undo step for the pair;
  /// after that they are two blocks (「짝 = 따로따로」).
  ///
  /// [settings] are the window row's answers, taken whole — where it goes,
  /// carry or link, bake, 「소리」, the fit, IN/OUT. IN/OUT count PROJECT
  /// frames on the sound's clock ([MovieClock]), the frames a sound's IN/OUT
  /// count, so the pair share one span and the sound's in point is exact.
  Future<bool> importVideoFile({
    required String path,
    required ImportFileSettings settings,
    void Function(int rendered, int total)? onRenderProgress,
    void Function(int movieFrame)? onFrameRenderFailed,
    ImportLayerSpot? spot,

    /// Where [path] was cut from — see [importImageFile]'s.
    String? sourcePath,

    /// See [importImageFile]'s.
    void Function(double fraction)? onCarrying,
  }) async {
    if (settings.movieParts == MovieParts.sound) {
      // A movie that brings its sound ALONE (🗣️유저 2026-09-27: 「소리만
      // 임포트 … 고를수있게」) lands the way a sound does, through the
      // sound's own door: its SE rows, its trim, and the ONE pool entry the
      // pair shares (the door keeps a movie's kind for it). Asked here, so
      // every caller of the movie's door gets the same answer.
      return importSoundFile(
        path: path,
        copyIntoProject: settings.mode == ImportFileMode.keepInside,
        inFrame: settings.inFrame,
        outFrame: settings.outFrame,
        spot: spot,
        sourcePath: sourcePath,
        onCarrying: onCarrying,
      );
    }
    // The destination gate runs BEFORE the movie opens — a refused import
    // must not have a document to leak.
    final gate = _landing.arriveAt(settings.into, path: path, spot: spot);
    if (gate == null) {
      return false;
    }
    final opened = await openHeldMovie(
      videoDecodeBackend,
      _holdBytes,
      gate.source,
    );
    if (opened == null) {
      return false;
    }
    try {
      final info = opened.info;
      final baked = settings.bake || spot is RowFramesSpot;
      final planned = _planMovieLayer(gate, info, settings, rasterize: baked);
      final arrival = planned.arrival;
      final source = arrival.source;
      // The conform answers whether there is a sound at all — the one the
      // sound's playback will read.
      final withMovieSound =
          settings.movieParts == MovieParts.pictureAndSound &&
          await _conforms.ensurePeaksFor(_pool.importAudioFile(source)) !=
              null;
      // A baked picture leaves the file nothing to be for — unless its
      // sound lands beside it, which reads the file ([placementRegisters]).
      final assets = [
        if (placementRegisters(baked: baked, soundReadsIt: withMovieSound))
          _movieAsset(source, info, settings, sourcePath),
      ];
      await _pool.holdCarriedBytes(assets, onProgress: onCarrying);
      if (!_landMovieWithSound(planned, assets, withSound: withMovieSound)) {
        return false;
      }
      await _bakeLandedCels(
        arrival.cutId,
        planned.layer,
        planned.bakes,
        rowId: _rowOf(spot),
        standing: _atTheFit(settings.fit),
        onProgress: onRenderProgress,
        // One frame the reader refuses leaves its cel empty and is
        // reported — never an abort into a half-baked import.
        onFailed: (bake) => onFrameRenderFailed?.call(bake.sourceFrameIndex),
        pictureOf: (bake, _) => _moviePicture(opened.token, info, bake),
      );
      return true;
    } finally {
      await opened.close();
    }
  }

  /// What a placed movie LANDS AS: the span it covers on the sound's clock,
  /// the cut it arrives in — a NEW one is made at the movie's own size,
  /// which its locked 1:1 fit fills exactly — and the row itself.
  ///
  /// [rasterize] asks for cels (the window's 「굽는다」, or a drop onto a
  /// row's frames); without it the row draws from the file and there is
  /// nothing to bake.
  _MoviePlacement _planMovieLayer(
    ImportArrival gate,
    QaVideoInfo info,
    ImportFileSettings settings, {
    required bool rasterize,
  }) {
    final clock = _movieClock(info);
    final kept = KeptSpan(
      length: clock.projectFramesCovering(info.frameCount),
      inFrame: settings.inFrame,
      outFrame: settings.outFrame,
    );
    final arrival = gate.targetCut == null
        ? gate.withCanvasSize(
            CanvasSize(width: info.width, height: info.height),
          )
        : gate;
    final source = arrival.source;
    if (!rasterize) {
      return (
        arrival: arrival,
        kept: kept,
        layer: planMovieReferenceLayer(
          reference: placedReference(
            source,
            CanvasSize(width: info.width, height: info.height),
            arrival.canvasSize,
            settings.fit,
          ).copyWith(frameOffset: kept.first),
          displayName: arrival.displayName,
          length: kept.count,
          mint: arrival.mint,
        ),
        bakes: const [],
      );
    }
    final movieFrames = [
      for (var n = kept.first; n <= kept.last; n += 1) clock.movieFrameAt(n),
    ];
    final plan = planSequenceLayer(
      sourceFiles: List<String>.filled(movieFrames.length, source),
      // A movie frame the clock shows twice is ONE picture held
      // (「중복 접기」): the fingerprint IS the movie frame.
      frameFingerprints: movieFrames,
      sourceFrameIndices: movieFrames,
      displayName: arrival.displayName,
      cutId: arrival.cutId,
      mint: arrival.mint,
    );
    return (
      arrival: arrival,
      kept: kept,
      layer: plan.layer,
      bakes: plan.bakes,
    );
  }

  /// The pool entry a placed movie registers when it does
  /// ([placementRegisters]: unbaked, or with its sound beside it) — ONE
  /// entry, which the sound points at too. ↩️Baked or not (유저 2026-09-11:
  /// 「구워도 풀에 남음」), until F-282-Q6.
  MediaAsset _movieAsset(
    String source,
    QaVideoInfo info,
    ImportFileSettings settings,
    String? sourcePath,
  ) => importedMediaAsset(
    path: source,
    kind: MediaAssetKind.video,
    fit: settings.fit,
    sourcePath: sourcePath,
    identity: readMediaIdentity(source),
    carried: settings.mode == ImportFileMode.keepInside,
    sourceFps: info.fps,
    frameCount: info.frameCount,
  );

  /// The picture and its sound land as ONE undo step; after that they are
  /// two blocks (「짝 = 따로따로」). The sound starts where the picture
  /// starts and runs as long (「같은 시작 · 같은 구간」), and it is landed
  /// only when [withSound] says the movie brought one.
  bool _landMovieWithSound(
    _MoviePlacement planned,
    List<MediaAsset> assets, {
    required bool withSound,
  }) {
    final arrival = planned.arrival;
    final kept = planned.kept;
    var landed = false;
    _project.historyManager.runAsOneStep(arrival.undoDescription, () {
      landed = _landing.land(
        [planned.layer],
        arrival: arrival,
        duration: kept.count,
        assets: assets,
      );
      if (!landed || !withSound) {
        return;
      }
      // A NEW cut is the active one by now, so the sound asks the gate
      // again, there.
      final soundArrival = arrival.targetCut != null
          ? arrival
          : _landing.arriveAt(
              ImportDestination.activeCutLayer,
              path: arrival.source,
            );
      if (soundArrival != null) {
        _landing.landSound(
          arrival: soundArrival,
          offsetFrames: kept.first,
          lengthFrames: kept.count,
        );
      }
    });
    return landed;
  }

  /// RASTERIZE a movie kept as a reference (§6-f; the video spec the user
  /// approved on 2026-09-11): every position of its block becomes a cel —
  /// one per movie frame the sound's clock shows there, consecutive
  /// duplicates folded into held exposure (「중복 접기」, the fold the
  /// placement window's bake uses) — the reference is let go of, and the
  /// pool entry stays: it was made when the reference was placed, and a
  /// later bake does not empty the pool (「구워도 풀에 남음」 — what a
  /// PLACEMENT registers is [placementRegisters]'s, F-282-Q6).
  ///
  /// Where it shows each frame is [referenceLetGo]'s (F-374-Q7): its
  /// reference fx's move carried into the row's own transform and the
  /// frames laid where the file is laid — or, where that transform cannot
  /// carry it, each frame laid where the fx stands it at its position, a cel
  /// apiece wherever the movie or the move changes (「움직이는 참조는
  /// 움직이는 프레임마다 한 장」). A row that waits is left as it is.
  ///
  /// 🗣️F-374-Q10 (유저 2026-10-17, 「같은 셀을 보는 쓰임을 전부 같이」): the
  /// cel the row shows its movie through is its 겸용 link group's, so every
  /// use of it is rasterized with it — each its own way, through ONE bank
  /// of cels ([_movieCelsOf]).
  ///
  /// ⚠️HERE rather than beside [RasterizeLayerReferenceCommand], because
  /// this is where a movie's pixels come in: the reader, the sound's clock,
  /// the duplicate fold and the bake tail are all this file's already, and
  /// a second set of them is what this file exists to prevent. A still's
  /// cels ARE its pixels: what it shows comes from them
  /// ([bakeReferenceAsSeen]).
  Future<bool> rasterizeMovieReference({
    required CutId cutId,
    required LayerId layerId,
    void Function(int rendered, int total)? onRenderProgress,
    void Function(int movieFrame)? onFrameRenderFailed,
  }) async {
    final layer = _project.cutById(cutId)?.layers.byId(layerId);
    if (layer == null || !isMovieReference(layer)) {
      return false;
    }
    final way = _project.cutCommandCoordinator.referenceLetGoOf(
      cutId: cutId,
      layerId: layerId,
    );
    // A movie reference is ONE block by construction — every reshaping verb
    // stands its row down until this verb has run.
    if (way is! ReferenceMoveCarried ||
        way.uses.any(
          (use) =>
              !isMovieReference(use.use.layer) ||
              drawingBlocks(use.use.layer.timeline).length != 1,
        )) {
      return false;
    }
    final opened = <String, HeldMovie>{};
    try {
      // Each file a use shows, opened once.
      for (final use in way.uses) {
        final path = use.use.layer.mediaReference!.assetPath;
        if (opened.containsKey(path)) {
          continue;
        }
        final movie = await openHeldMovie(videoDecodeBackend, _holdBytes, path);
        if (movie == null) {
          return false;
        }
        opened[path] = movie;
      }
      // Or nothing, when a use changed while its file was opened: [way] is
      // the uses' as they were.
      if (_changedSince(way)) {
        return false;
      }
      final cels = _movieCelsOf(way, opened);
      await _bakeLandedCels(
        cutId,
        _letMovieReferencesGo(way, cels, layerId),
        cels.bakes,
        // The cels are THIS row's, under its own id — the bank its link
        // group shares.
        rowId: layerId,
        // Where the reference shows each picture, so the cels land exactly
        // there (I-68). ↩️It read the pool's fit for the file — the fit the
        // row was placed with — and fitted each frame to the canvas again.
        standing: (bake, _, _) => cels.standing[bake.frameId]!,
        onProgress: onRenderProgress,
        // One frame the reader refuses leaves its cel empty and is reported
        // — never an abort into a half-rasterized row.
        onFailed: (bake) => onFrameRenderFailed?.call(bake.sourceFrameIndex),
        pictureOf: (bake, _) {
          final movie = opened[bake.sourceFile]!;
          return _moviePicture(movie.token, movie.info, bake);
        },
      );
      return true;
    } finally {
      for (final movie in opened.values) {
        await movie.close();
      }
    }
  }

  /// Whether a use [way] was asked of has changed since — what a door that
  /// reads before it lets go owes the uses it found ([referenceLetGo]).
  bool _changedSince(ReferenceMoveCarried way) => way.uses.any(
    (use) => _project.layerById(use.use.layer.id) != use.use.layer,
  );

  /// RASTERIZE a STILL reference whose move a transform cannot carry
  /// (F-374-Q7 ②③): every cel takes its picture where the row shows it —
  /// the one place its fx stands the file ([referenceMoveAt]) — IN PLACE,
  /// and the reference goes, as ONE undo step that gives the pictures back
  /// ([SwapLayerReferenceCommand]: a new cel would sweep a 겸용 sibling's
  /// exposures away). The transforms and their switch stay as they are.
  /// False when the row bakes no such way, or a use changed while its cels
  /// were drawn.
  ///
  /// 🗣️F-374-Q10 (유저 2026-10-17, 「같은 셀을 보는 쓰임을 전부 같이」): the
  /// cel is its 겸용 link group's, and every use of it shows the picture
  /// there ([referenceLetGo]), so every use lets go of its reference with
  /// the row.
  ///
  /// 🔧From the CEL, not the file: what the row shows IS its cel moved, so
  /// the bake is that to the pixel — a part of the file the cel's wall cut
  /// off stays off (F-374-Q6 「셀 밖은 버린다」) — and nothing is read.
  Future<bool> bakeReferenceAsSeen({
    required CutId cutId,
    required LayerId layerId,
  }) async {
    final cut = _project.cutById(cutId);
    final layer = cut?.layers.byId(layerId);
    if (cut == null ||
        layer == null ||
        layer.mediaReference == null ||
        isMovieReference(layer)) {
      return false;
    }
    final way = _project.cutCommandCoordinator.referenceLetGoOf(
      cutId: cutId,
      layerId: layerId,
    );
    if (way is! ReferenceMoveCarried || !way.bakes) {
      return false;
    }
    final pictures = await _celsMoved(cut, layer);
    if (_changedSince(way)) {
      return false;
    }
    final history = _project.historyManager;
    history.runAsOneStep('Rasterize layer', () {
      history.execute(
        SwapLayerReferenceCommand(
          repository: _project.repository,
          cutId: cutId,
          layerId: layerId,
          reference: layer.mediaReference!,
          store: _renderCaches.brushFrameStore,
          pictures: pictures,
          cacheInvalidationSink: _renderCaches.cacheInvalidationHub,
          description: 'Rasterize layer',
        ),
      );
      _project.cutCommandCoordinator.letReferencesGo(way);
    });
    _changes.refreshAfterCutCommand();
    _changes.notifyChanged();
    return true;
  }

  /// [layer]'s cels where its reference fx moves them, by key — ONE move,
  /// a still's fx standing the file at one place wherever the row stands
  /// ([ReferenceMoveCarried.bakes]). An empty cel has no picture to move.
  Future<Map<BrushFrameKey, BitmapSurface>> _celsMoved(
    Cut cut,
    Layer layer,
  ) async {
    final move = referenceMoveAt(layer, 0);
    final moved = <BrushFrameKey, BitmapSurface>{};
    if (move == null) {
      return moved;
    }
    for (final frame in layer.frames) {
      final key = _project.brushFrameKeyForCut(cut, layer.id, frame.id);
      final cel = _renderCaches.brushFrameStore.bakedSurfaceOrNull(
        key,
        read: CelRead.look,
      );
      if (cel != null && cel.tiles.isNotEmpty) {
        moved[key] = await _celMoved(cel, move);
      }
    }
    return moved;
  }

  /// [cel]'s picture where [move] carries it, on a cel of the same canvas —
  /// laid as every picture a door bakes is ([layCelPicture]),
  /// whole (F-374-Q8).
  ///
  /// 🚨Composed over where its FILE lies, not over the cel: the clear canvas
  /// round a small picture is no part of it, and a move that grows the
  /// picture grows that too — an 8×8 still fitted ×206 to its canvas asked
  /// ONE raster 590080×538240 for its 8×8 of ink, and the raster failed. No
  /// brush reaches a reference row, so where its file lies is all it holds.
  /// A cel that does not know where its file lies (an older build's, cut at
  /// the wall) is moved as the picture it is, cut at the wall.
  static Future<BitmapSurface> _celMoved(
    BitmapSurface cel,
    LayerPlacement move,
  ) async {
    final held = await _celPicture(cel);
    try {
      return await layCelPicture(
        picture: held.picture,
        canvas: cel.canvasSize,
        placement: move.compose(held.at),
        tileSize: cel.tileSize,
        whole: cel.laidBounds != null,
      );
    } finally {
      held.picture.dispose();
    }
  }

  /// [cel]'s picture over where its file lies ([_celMoved]), and where that
  /// stands on the canvas: composed — or, past the side this device's
  /// engine hands a picture back at, the bytes the cel holds, kept off the
  /// engine as its file was when it was laid ([pictureSideLimit]). A
  /// compose past the side comes back in pieces (`piecesOver`), and a
  /// picture is one image. 🔬Before it did, it came back smaller (20480×1024
  /// asked, 16384×819 made), and the move would have laid it so. A cel that
  /// does not know where its file lies is asked the same over all it holds.
  static Future<({CelPicture picture, LayerPlacement at})> _celPicture(
    BitmapSurface cel,
  ) async {
    final laid = cel.laidBounds;
    final region =
        laid ?? DirtyRegion.wholePixelsOf(surfaceContentWorldRect(cel));
    if (isPastTheSide(region.width, region.height, await pictureSideLimit())) {
      return (
        picture: PixelsPicture(
          bitmapSurfaceRegionPixels(cel, region),
          width: region.width,
          height: region.height,
        ),
        at: GuideTransform(
          1,
          0,
          0,
          1,
          region.left.toDouble(),
          region.top.toDouble(),
        ),
      );
    }
    final composed = await composePositionedSurfaceImage(
      cel,
      over: laid?.rect,
    );
    if (composed == null) {
      throw StateError('The cel did not compose.');
    }
    final at = composed.worldRect.topLeft;
    return (
      picture: EnginePicture(composed.pieces.single.image),
      at: GuideTransform(1, 0, 0, 1, at.dx, at.dy),
    );
  }

  /// I-47: [layerId] — a reference row of the active cut — shows [path]
  /// instead of the file it points at, as ONE undo step
  /// ([SwapLayerReferenceCommand]); how it takes the file is
  /// [referenceSwapFor]'s answer. The new file stands at the row's reference
  /// fx — the same pose over its OWN pixels (I-68: 「같은값만큼 다른용지도 …
  /// 해상도가 달라도 같은크기로 겹치지않게」), so a paper of another
  /// resolution stands at another size where the old one stood.
  /// ↩️A still's new picture was fitted to the canvas as it is NOW, with the
  /// fit the row was placed with — on a canvas grown since, in its middle.
  ///
  /// Each cel takes the same picture of the new file as it showed of the old
  /// ([Frame.filePicture]) — the law every row that shows a file is laid by
  /// (I-68 「가」: one law, one cel or many) — so a file that has no such
  /// picture is not taken, and the answer names the one it lacks
  /// ([ReferenceLacksPicture] — 유저 2026-10-10 「추천대로가자」).
  ///
  /// [ReferenceLeftAlone] for a row that does not take [path], or that
  /// changed while the file was read.
  Future<ReferenceRedraw> swapReference({
    required LayerId layerId,
    required String path,
  }) async {
    final layer = _project.layerById(layerId);
    final reference = layer?.mediaReference;
    if (layer == null ||
        reference == null ||
        referenceSwapFor(layer, path) == null) {
      return const ReferenceLeftAlone();
    }
    return _drawAgain(
      layer,
      reference.copyWith(assetPath: path),
      description: 'Swap layer reference',
    );
  }

  /// [layer] — a reference row of the active cut — pointed at [next] and its
  /// pictures made from that file again ([referenceRedrawFor]), as ONE undo
  /// step. The picture's own size is the file's as it reads now.
  ///
  /// ↩️A moved reference fx laid its OWN file again here too — I-68's one
  /// value, then F-374's keys where they stood the picture still — until
  /// F-374-Q1 (유저 2026-10-17, 「트랜스폼처럼 화면에서 옮긴다」): the
  /// canvas moves the picture, and only another file is drawn again.
  Future<ReferenceRedraw> _drawAgain(
    Layer layer,
    MediaReference next, {
    required String description,
  }) async {
    final cut = _project.activeCutOrNull;
    final redraw = referenceRedrawFor(layer);
    if (cut == null || redraw == null) {
      return const ReferenceLeftAlone();
    }
    final remade = switch (redraw) {
      ReferenceSwap.pictures => await _filePictures(
        layer,
        next,
        cut.canvasSize,
      ),
      // The movie it shows already said its size; another one is asked.
      ReferenceSwap.movie
          when next.assetPath == layer.mediaReference?.assetPath =>
        _Drawn(const <FrameId, BitmapSurface>{}, next),
      ReferenceSwap.movie => await _movieSized(next),
    };
    return switch (remade) {
      _NotDrawn(:final why) => why,
      final _Drawn drawn => _land(cut, layer, drawn, description: description),
    };
  }

  /// [drawn] on [layer] as ONE undo step — or nothing, when the row changed
  /// while its file was read.
  ReferenceRedraw _land(
    Cut cut,
    Layer layer,
    _Drawn drawn, {
    required String description,
  }) {
    if (_project.layerById(layer.id) != layer) {
      return const ReferenceLeftAlone();
    }
    _project.historyManager.execute(
      SwapLayerReferenceCommand(
        repository: _project.repository,
        cutId: cut.id,
        layerId: layer.id,
        reference: drawn.reference,
        store: _renderCaches.brushFrameStore,
        pictures: {
          for (final MapEntry(key: frameId, value: picture)
              in drawn.pictures.entries)
            _project.brushFrameKeyForCut(cut, layer.id, frameId): picture,
        },
        cacheInvalidationSink: _renderCaches.cacheInvalidationHub,
        description: description,
      ),
    );
    // The tidy-up every edit that moves the document owes, as its undo gets
    // it (`_stepHistory`). Where the user stands is the door's to say — a
    // drop stands on the row it landed on before it swaps.
    _changes.refreshAfterCutCommand();
    _changes.notifyChanged();
    return const ReferenceLaid();
  }

  /// [reference]'s file as the pictures [layer]'s cels show — each cel the
  /// picture of the file it says it is ([Frame.filePicture]: a still's one,
  /// a GIF frame's kept), laid where the reference lays them
  /// ([MediaReference.laid]) on a [canvas]-sized cel — and the reference
  /// saying the size of its first cel's picture as the file reads now. Or
  /// why not: the file does not read, or lacks a picture a cel shows — the
  /// first, in the cels' order.
  ///
  /// 🗣️I-68 (유저 2026-10-10 「가」): every row that shows a file is laid
  /// again by one law — the cel's own picture, where its reference lays it.
  /// ↩️Only a still's one cel could be: a GIF's or a PDF's cels said nowhere
  /// which picture of the file each was. ↩️A moved fx laid a GIF's frames
  /// and a PDF's pages again by it too, until F-374-Q1 — and only a still
  /// row takes another file ([referenceSwapFor]).
  Future<_Remade> _filePictures(
    Layer layer,
    MediaReference reference,
    CanvasSize canvas,
  ) async {
    final file = await _openPictures(reference);
    if (file == null) {
      return const _NotDrawn(ReferenceUnreadable());
    }
    final wanted = {for (final frame in layer.frames) frame.filePicture!};
    final _MadePictures made;
    try {
      final lacking = wanted.where((index) => index >= file.count).firstOrNull;
      if (lacking != null) {
        return _NotDrawn(ReferenceLacksPicture(lacking));
      }
      made = await _picturesMade(
        wanted,
        file.at,
        pose: reference.laid,
        canvas: canvas,
      );
    } on Object {
      // A picture the file holds and would not give — a page the renderer
      // gave up on — is one it does not read.
      return const _NotDrawn(ReferenceUnreadable());
    } finally {
      await file.close();
    }
    return _Drawn(
      {
        for (final frame in layer.frames)
          frame.id: made.surfaces[frame.filePicture]!,
      },
      reference.copyWith(
        pictureSize: made.sizes[layer.frames.first.filePicture],
      ),
    );
  }

  /// [reference]'s file open for its pictures — an image's, a still's one
  /// and a GIF's frames, read through the project's copy first
  /// ([readHeldMediaBytes]) as every door here reads. Null when it does not
  /// open.
  ///
  /// ↩️A PDF's pages opened here too, each rendered once at the size its
  /// pose stood it at, for a moved fx to lay them again — until F-374-Q1:
  /// no PDF row takes another file ([referenceSwapFor]).
  Future<_OpenPictures?> _openPictures(MediaReference reference) async {
    final List<DecodedImageFrame> frames;
    try {
      frames = await decodeImageFrames(
        await readHeldMediaBytes(_holdBytes, reference.assetPath),
      );
    } on Object {
      return null;
    }
    return (
      count: frames.length,
      at: (index) async => _pictureOf(frames[index].picture, owned: false),
      close: () async {
        for (final frame in frames) {
          frame.picture.dispose();
        }
      },
    );
  }

  /// The [wanted] pictures of a file, each made by [pictureAt] from its
  /// place in the file and laid on a [canvas]-sized cel where [pose] stands
  /// it ([_celLaid]), with its own size.
  ///
  /// ⛔ONE LOOP for a GIF's frames and a PDF's pages: each wrote it out —
  /// and a PDF's are laid again no more (F-374-Q1, [_openPictures]).
  static Future<_MadePictures> _picturesMade(
    Set<int> wanted,
    Future<_BakePicture> Function(int index) pictureAt, {
    required TransformPose pose,
    required CanvasSize canvas,
  }) async {
    final made = (surfaces: <int, BitmapSurface>{}, sizes: <int, CanvasSize>{});
    for (final index in wanted) {
      final picture = await pictureAt(index);
      made.sizes[index] = picture.size;
      made.surfaces[index] = await _celLaid(picture, pose, canvas);
    }
    return made;
  }

  /// [reference] with its movie's frame size as the decoder reads the file
  /// now — a movie's cel holds no pictures, so there is nothing to make —
  /// or, when the movie does not open, why not.
  Future<_Remade> _movieSized(MediaReference reference) async {
    final info = await readHeldMovieInfo(
      videoDecodeBackend,
      _holdBytes,
      reference.assetPath,
    );
    return info == null
        ? const _NotDrawn(ReferenceUnreadable())
        : _Drawn(
            const <FrameId, BitmapSurface>{},
            reference.copyWith(
              pictureSize: CanvasSize(width: info.width, height: info.height),
            ),
          );
  }

  /// The sound's clock for a movie the decoder has answered about: the
  /// project's rate, the audio speed's accumulated pull and the file's own
  /// rate — ONE answer for the door that places a movie and the verb that
  /// rasterizes one, which have to agree or a bake would land on different
  /// frames than the reference showed.
  MovieClock _movieClock(QaVideoInfo info) => movieClockFor(
    projectRate: _frameRate(),
    audioSpeed: _project.repository.requireProject().audioSpeed,
    movie: info,
  );

  /// The cels [rasterizeMovieReference] makes of [way]'s uses, each planned
  /// from the movie [opened] holds for its file ([_plannedMovieUse]) — and
  /// a picture a use before it made a cel of is that cel, the bank being
  /// one, as the one cel they shared was. A use alone is planned as it
  /// always was.
  _MovieCels _movieCelsOf(
    ReferenceMoveCarried way,
    Map<String, HeldMovie> opened,
  ) {
    final frames = <Frame>[];
    final bakes = <PlannedCelBake>[];
    final standing = <FrameId, TransformPose>{};
    final timelines = <SplayTreeMap<int, TimelineExposure>>[];
    final made = <_ShownMovieFrame, FrameId>{};
    for (final (:use, track: _, :asShown) in way.uses) {
      final block = drawingBlocks(use.layer.timeline).single;
      final (:shown, :plan) = _plannedMovieUse(
        use,
        block,
        info: opened[use.layer.mediaReference!.assetPath]!.info,
        asShown: asShown,
      );
      final celOf = <FrameId, FrameId>{};
      final mine = <_ShownMovieFrame, FrameId>{};
      for (final MapEntry(key: position, value: exposure)
          in plan.layer.timeline.entries) {
        if (exposure.frameId case final cel?) {
          final earlier = made[shown[position]];
          celOf[cel] = earlier ?? cel;
          if (earlier == null) {
            mine.putIfAbsent(shown[position], () => cel);
            standing[cel] = shown[position].pose;
          }
        }
      }
      made.addAll(mine);
      frames.addAll(
        plan.layer.frames.where((frame) => celOf[frame.id] == frame.id),
      );
      bakes.addAll(
        plan.bakes.where((bake) => celOf[bake.frameId] == bake.frameId),
      );
      timelines.add(
        SplayTreeMap.of({
          for (final MapEntry(key: position, value: exposure)
              in plan.layer.timeline.entries)
            position + block.startIndex: exposure.copyWith(
              frameId: celOf[exposure.frameId],
            ),
        }),
      );
    }
    return (
      frames: frames,
      bakes: bakes,
      standing: standing,
      timelines: timelines,
    );
  }

  /// What [use] shows at each position of its one [block] — the movie frame
  /// the sound's clock of [info] reads there, standing where its reference
  /// fx stands it at that position where its cels take the picture as it
  /// shows it ([asShown]), else where its file is laid, the move its own
  /// transform's now — and the cels that makes: one wherever the movie or
  /// the move changes (「중복 접기」, the fold the placement window's bake
  /// uses).
  _PlannedMovieUse _plannedMovieUse(
    ReferenceUse use,
    TimelineDrawingBlock block, {
    required QaVideoInfo info,
    required bool asShown,
  }) {
    final reference = use.layer.mediaReference!;
    final clock = _movieClock(info);
    final shown = [
      for (var position = 0; position < block.length; position += 1)
        (
          file: reference.assetPath,
          movieFrame: clock.movieFrameAt(movieElapsedAt(reference, position)),
          pose: asShown
              ? reference.poseAt(block.startIndex + position)
              : reference.laid,
        ),
    ];
    return (
      shown: shown,
      plan: planSequenceLayer(
        sourceFiles: List<String>.filled(shown.length, reference.assetPath),
        // A position is a cel of its own where the movie or the move
        // changes.
        frameFingerprints: shown,
        sourceFrameIndices: [
          for (final position in shown) position.movieFrame,
        ],
        displayName: use.layer.name,
        cutId: use.cut.id,
        mint: _landing.idMint(),
        assetKind: MediaAssetKind.video,
        sourceFps: info.fps,
      ),
    );
  }

  /// The structure a movie's rasterize lands as ONE undo step — every use's
  /// reference fx's move carried into its own transform where that carries
  /// it, as a still's is (F-374-Q3 · Q7 · Q10), the bank [cels] holds, each
  /// use's exposure of it and every reference let go of — through the edit
  /// funnels every transform and timeline change uses. The pixels follow
  /// it, as a landed import's do. Answers [layerId]'s row as it lands.
  Layer _letMovieReferencesGo(
    ReferenceMoveCarried way,
    _MovieCels cels,
    LayerId layerId,
  ) {
    final landed = <LayerId, Layer>{};
    _project.historyManager.runAsOneStep('Rasterize layer', () {
      _project.cutCommandCoordinator.carryReferenceMoves(way);
      for (final (index, letGo) in way.uses.indexed) {
        final use = letGo.use;
        final carried = _project
            .cutById(use.cut.id)!
            .layers
            .byId(use.layer.id)!;
        // ⛔`plan.assets` is dropped: the pool entry is already there, and
        // it stays there — baking does not unregister a file. The first
        // use's bank is every use's: the timeline funnel mirrors it, and
        // sweeps the one cel it replaces from the others' exposures.
        final rasterized = carried.copyWith(
          frames: cels.frames,
          timeline: cels.timelines[index],
          mediaReference: null,
        );
        _project.historyManager.execute(
          UpdateLayerTimelineCommand(
            repository: _project.repository,
            before: carried,
            after: rasterized,
          ),
        );
        landed[use.layer.id] = rasterized;
      }
    });
    return landed[layerId]!;
  }

  /// One movie frame as a picture — the same read for the door that PLACES
  /// a movie baked and the verb that RASTERIZES one placed as a reference.
  Future<_BakePicture> _moviePicture(
    int token,
    QaVideoInfo info,
    PlannedCelBake bake,
  ) async {
    final rgba = await videoDecodeBackend.frame(token, bake.sourceFrameIndex);
    if (rgba == null) {
      throw StateError('Movie frame ${bake.sourceFrameIndex} did not decode.');
    }
    final picture = await pictureOfPixels(
      rgba,
      width: info.width,
      height: info.height,
    );
    return _pictureOf(picture, owned: true);
  }

  /// The row a [spot] names, when it names one — frames let go of on a
  /// row are that row's cels.
  LayerId? _rowOf(ImportLayerSpot? spot) =>
      spot is RowFramesSpot ? spot.layerId : null;

  /// Bakes a landed import's cels and hands the session the row to stand
  /// on — the TAIL every picture door shares (a still or a GIF, a PDF's
  /// pages, a movie's frames). Cels that belong to a row ALREADY on the
  /// sheet ([rowId] — frames dropped on it, or a movie rasterized where it
  /// stands) are keyed under that row rather than under the [layer] that
  /// was only planned. A picture for each bake comes from
  /// [pictureOf], given the cut's canvas; it is rasterized there and
  /// donated through the ordinary cel path. [onProgress] counts every bake,
  /// made or not.
  ///
  /// Where each picture stands is [standing]'s — the placement's one rule,
  /// asked with the picture's own size ([_standingFor]).
  ///
  /// With [onFailed], a bake that throws leaves its cel empty and is
  /// reported, and the rest go on: the structure is already committed, and
  /// a half-baked import is one the window would retry as a duplicate.
  /// Without it the throw is the caller's.
  ///
  /// ⛔ONE TAIL, FOUR DOORS. The still/GIF door and the PDF door each wrote
  /// it out — the cut, the loop, the row to stand on — the movie door was
  /// the third, and rasterizing a movie in place is the fourth.
  Future<void> _bakeLandedCels(
    CutId cutId,
    Layer layer,
    List<PlannedCelBake> bakes, {
    required LayerId? rowId,
    required _Standing standing,
    required Future<_BakePicture> Function(
      PlannedCelBake bake,
      CanvasSize canvas,
    )
    pictureOf,
    void Function(int done, int total)? onProgress,
    void Function(PlannedCelBake bake)? onFailed,
  }) async {
    // Pixels bake AFTER the structure exists: the keys resolve the owner
    // track through the inserted cut.
    final cut = _project.cutById(cutId);
    if (cut != null) {
      var done = 0;
      for (final bake in bakes) {
        try {
          final picture = await pictureOf(bake, cut.canvasSize);
          final surface = await _celLaid(
            picture,
            standing(bake, picture.size, cut.canvasSize),
            cut.canvasSize,
          );
          bakeCelSurface(
            _renderCaches.brushFrameStore,
            _project.brushFrameKeyForCut(
              cut,
              rowId ?? bake.layerId,
              bake.frameId,
            ),
            surface,
          );
        } on Object {
          if (onFailed == null) {
            rethrow;
          }
          onFailed(bake);
        }
        done += 1;
        onProgress?.call(done, bakes.length);
      }
    }
    _changes.refreshAfterCutCommand(preferredActiveLayerId: rowId ?? layer.id);
    _changes.notifyChanged();
  }

  /// [picture] laid on a [canvas]-sized cel where it stands at [pose]
  /// ([_laid]) — and let go of once laid when it was made for the laying
  /// ([_BakePicture.owned]). How an import bakes each picture, and how a
  /// reference row's pictures are laid again ([_picturesMade]).
  ///
  /// Whole, past the wall (F-374-Q8: 「참조 그림은 벽 밖까지 통째로」) — and
  /// a file baked as it lands is laid so too: placed and then rasterized it
  /// would be the very same picture.
  static Future<BitmapSurface> _celLaid(
    _BakePicture picture,
    TransformPose pose,
    CanvasSize canvas,
  ) async {
    try {
      return await layCelPicture(
        picture: picture.picture,
        canvas: canvas,
        placement: _laid(picture, pose),
        whole: true,
      );
    } finally {
      if (picture.owned) {
        picture.picture.dispose();
      }
    }
  }

  /// Where [picture]'s pixels lay when the picture stands at [pose]: the
  /// pose stands on the picture's own size, and its pixels may be drawn at
  /// another — a PDF page is rendered at the size it will stand at.
  static LayerPlacement _laid(_BakePicture picture, TransformPose pose) {
    final image = picture.picture;
    final size = picture.size;
    final onTheCanvas = picturePlacement(pose, size);
    if (image.width == size.width && image.height == size.height) {
      return onTheCanvas;
    }
    return onTheCanvas.compose(
      GuideTransform(
        size.width / image.width,
        0,
        0,
        size.height / image.height,
        0,
        0,
      ),
    );
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

    /// Where [path] was cut from — see [importImageFile]'s.
    String? sourcePath,

    /// See [importImageFile]'s.
    void Function(double fraction)? onCarrying,
  }) async {
    final gate = _landing.arriveOnSeRows(path: path, spot: spot);
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
    final assets = [
      importedMediaAsset(
        path: source,
        // A movie's sound comes from the MOVIE: one pool entry for the
        // pair, so a relink finds both (「리링크는 풀 항목이 하나라 둘 다
        // 한 번에 따라간다」).
        kind: mediaAssetKindForPath(source) ?? MediaAssetKind.audio,
        fit: MediaFitMode.contain,
        sourcePath: sourcePath,
        identity: readMediaIdentity(source),
        carried: copyIntoProject,
      ),
    ];
    await _pool.holdCarriedBytes(assets, onProgress: onCarrying);
    final landed = _landing.landSound(
      arrival: gate,
      offsetFrames: kept.first,
      lengthFrames: kept.count,
      assets: assets,
    );
    if (landed) {
      _changes.notifyChanged();
    }
    return landed;
  }

  /// [pageIndex] — a [page]-sized picture — rendered at the size [pose]
  /// stands it at: the vector source rasters ONCE, at the size it will live
  /// at, and no second resample makes it soft.
  static Future<_BakePicture> _renderedPage(
    ViewerDocument document,
    int pageIndex,
    CanvasSize page,
    TransformPose pose,
  ) async => (
    picture: EnginePicture(
      await document.renderPage(
        pageIndex,
        width: pagePixels(page.width * pose.scaleX.abs()),
        height: pagePixels(page.height * pose.scaleY.abs()),
      ),
    ),
    owned: true,
    size: page,
  );

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

  Object _foldBytes(Uint8List pixels) {
    // Every 4th PIXEL, all four channels — a fold that read one channel
    // would merge frames whose change hides in the others.
    final data = ByteData.sublistView(pixels);
    var hash = 0x811c9dc5;
    for (var i = 0; i + 3 < data.lengthInBytes; i += 16) {
      hash = (hash ^ data.getUint32(i)) * 0x01000193 & 0xFFFFFFFF;
    }
    return Object.hash(hash, data.lengthInBytes);
  }
}
