// The doors a MEDIA FILE comes in through: one still or animated image, a
// Photoshop stack expanded into rows, a PDF's pages as cels.
//
// Their own object since round 8 (G1, 2026-09-06). All three do the same
// four things in the same order — pass the destination gate, plan the
// layer, land it, then bake its pixels — and the first of those is now
// [ImportLanding] rather than a copy each.

import 'dart:collection';
import 'dart:typed_data';
import 'dart:ui' as ui show Image, ImageByteFormat;

import '../../models/kept_span.dart';
import '../../models/canvas_size.dart';
import '../../models/cut_id.dart';
import '../../models/layer.dart';
import '../../models/layer_id.dart';
import '../../models/layer_kind.dart';
import '../../models/media_asset.dart';
import '../../models/media_reference.dart';
import '../../models/movie_cel.dart';
import '../../models/movie_clock.dart';
import '../../models/project_frame_rate.dart';
import '../../models/timeline_coverage.dart';
import '../../models/timeline_exposure.dart';
import '../../native/qa_video_decoder.dart' show QaVideoInfo;
import '../../services/commands/update_layer_timeline_command.dart';
import '../../services/import/import_layer_spot.dart';
import '../../services/import/media_identity_reader.dart';
import '../../services/import/media_import_planner.dart';
import '../../services/import/psd_expand_import.dart';
import '../../services/import/raster_cel_import.dart';
import '../../services/media/media_byte_source.dart';
import '../../services/media/video_decode_worker.dart';
import '../../services/pdf/pdf_render_service.dart';
import '../../services/straight_rgba_image.dart';
import '../audio/audio_conform_store.dart';
import '../import/import_file_settings.dart';
import 'import_landing.dart';
import 'media_fingerprint_ledger.dart';
import 'media_pool.dart';
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
      await _bakeLandedCels(
        cutId,
        layer,
        bakes,
        rowId: _rowOf(spot),
        pictureOf: (bake, _) async =>
            (image: decoded[bake.sourceFrameIndex].image, owned: false),
      );
    } finally {
      for (final frame in decoded) {
        frame.image.dispose();
      }
    }
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
  Future<List<ImportWarning>?> importPsdExpanded({
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
      await _bakeLandedCels(
        cutId,
        layer,
        bakes,
        rowId: _rowOf(spot),
        onProgress: onRenderProgress,
        // The bake counts within the SPAN; the document counts from its
        // first page.
        onFailed: (bake) =>
            onPageRenderFailed?.call(firstPage + bake.sourceFrameIndex),
        pictureOf: (bake, canvas) async {
          final pageIndex = firstPage + bake.sourceFrameIndex;
          final pageSize = document.pageSize(pageIndex);
          final placement = placementRectFor(
            sourceWidth: _pagePixels(pageSize.width),
            sourceHeight: _pagePixels(pageSize.height),
            canvas: canvas,
            fit: bake.fit,
          );
          final image = await document.renderPage(
            pageIndex,
            width: _pagePixels(placement.width),
            height: _pagePixels(placement.height),
          );
          return (image: image, owned: true);
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
  /// 굽는다」) — and its SOUND, when [withSound] asks and the movie has
  /// one, lands on the SE rows by the sound's own law, starting where the
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
  }) async {
    // The destination gate runs BEFORE the movie opens — a refused import
    // must not have a document to leak.
    final gate = _landing.arriveAt(settings.into, path: path, spot: spot);
    if (gate == null) {
      return false;
    }
    final opened = await videoDecodeBackend.open(gate.source);
    if (opened == null) {
      return false;
    }
    try {
      final info = opened.info;
      final planned = _planMovieLayer(
        gate,
        info,
        settings,
        rasterize: settings.bake || spot is RowFramesSpot,
      );
      final arrival = planned.arrival;
      final source = arrival.source;
      final asset = _movieAsset(source, info, settings);
      // The conform answers whether there is a sound at all — the one the
      // sound's playback will read.
      final withMovieSound =
          settings.sound &&
          await _conforms.ensurePeaksFor(_pool.importAudioFile(source)) !=
              null;
      if (!_landMovieWithSound(planned, asset, withSound: withMovieSound)) {
        return false;
      }
      await _bakeLandedCels(
        arrival.cutId,
        planned.layer,
        planned.bakes,
        rowId: _rowOf(spot),
        onProgress: onRenderProgress,
        // One frame the reader refuses leaves its cel empty and is
        // reported — never an abort into a half-baked import.
        onFailed: (bake) => onFrameRenderFailed?.call(bake.sourceFrameIndex),
        pictureOf: (bake, _) => _moviePicture(opened.token, info, bake),
      );
      return true;
    } finally {
      await videoDecodeBackend.close(opened.token);
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
          referencePath: source,
          displayName: arrival.displayName,
          span: (first: kept.first, count: kept.count),
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
      fit: settings.fit,
      rasterize: true,
      mint: arrival.mint,
    );
    return (
      arrival: arrival,
      kept: kept,
      layer: plan.layer,
      bakes: plan.bakes,
    );
  }

  /// The pool entry a placed movie registers — baked or not (유저
  /// 2026-09-11: 「구워도 풀에 남음」) — ONE entry, which the sound points
  /// at too.
  MediaAsset _movieAsset(
    String source,
    QaVideoInfo info,
    ImportFileSettings settings,
  ) => importedMediaAsset(
    path: source,
    kind: MediaAssetKind.video,
    fit: settings.fit,
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
    MediaAsset asset, {
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
        assets: [asset],
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
  /// pool entry stays (「구워도 풀에 남음」).
  ///
  /// ⚠️HERE rather than beside [RasterizeLayerReferenceCommand], because
  /// this is where a movie's pixels come in: the reader, the sound's clock,
  /// the duplicate fold and the bake tail are all this file's already, and
  /// a second set of them is what this file exists to prevent. A reference
  /// to anything else stays that command's — a still's one cel IS its
  /// pixels, with nothing to decode.
  Future<bool> rasterizeMovieReference({
    required CutId cutId,
    required LayerId layerId,
    void Function(int rendered, int total)? onRenderProgress,
    void Function(int movieFrame)? onFrameRenderFailed,
  }) async {
    final cut = _project.cutById(cutId);
    if (cut == null) {
      return false;
    }
    final rows = cut.layers.where((candidate) => candidate.id == layerId);
    if (rows.isEmpty) {
      return false;
    }
    final layer = rows.first;
    final reference = layer.mediaReference;
    if (reference == null || !isMovieReference(layer)) {
      return false;
    }
    final blocks = drawingBlocks(layer.timeline);
    if (blocks.length != 1) {
      // A movie reference is ONE block by construction — every reshaping
      // verb stands its row down until this verb has run.
      return false;
    }
    final opened = await videoDecodeBackend.open(reference.assetPath);
    if (opened == null) {
      return false;
    }
    try {
      await _bakeMovieRowIntoCels(
        cutId: cutId,
        layer: layer,
        reference: reference,
        block: blocks.single,
        opened: opened,
        onRenderProgress: onRenderProgress,
        onFrameRenderFailed: onFrameRenderFailed,
      );
      return true;
    } finally {
      await videoDecodeBackend.close(opened.token);
    }
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

  /// The bake [rasterizeMovieReference] runs once it holds the row, its one
  /// block and the open movie: the positions become cels on the sound's
  /// clock, the structure lands as ONE undo step, and the pixels follow it
  /// through the tail every picture door bakes through.
  Future<void> _bakeMovieRowIntoCels({
    required CutId cutId,
    required Layer layer,
    required MediaReference reference,
    required TimelineDrawingBlock block,
    required ({int token, QaVideoInfo info}) opened,
    void Function(int rendered, int total)? onRenderProgress,
    void Function(int movieFrame)? onFrameRenderFailed,
  }) async {
    final info = opened.info;
    final clock = _movieClock(info);
    final movieFrames = [
      for (var position = 0; position < block.length; position += 1)
        clock.movieFrameAt(movieElapsedAt(reference, position)),
    ];
    final plan = planSequenceLayer(
      sourceFiles: List<String>.filled(
        movieFrames.length,
        reference.assetPath,
      ),
      frameFingerprints: movieFrames,
      sourceFrameIndices: movieFrames,
      displayName: layer.name,
      cutId: cutId,
      // The fit the file was PLACED with, so the cels land exactly where
      // the reference's pictures stood (`Project.mediaFitModeFor`).
      fit: _project.repository.requireProject().mediaFitModeFor(
        reference.assetPath,
      ),
      rasterize: true,
      mint: _landing.idMint(),
      assetKind: MediaAssetKind.video,
      sourceFps: info.fps,
    );
    // ⛔`plan.assets` is dropped: the pool entry is already there, and it
    // stays there — baking does not unregister a file.
    final rasterized = layer.copyWith(
      frames: plan.layer.frames,
      timeline: SplayTreeMap<int, TimelineExposure>.of({
        for (final entry in plan.layer.timeline.entries)
          entry.key + block.startIndex: entry.value,
      }),
      mediaReference: null,
    );
    // ONE undo step for the structure — the cels, their exposure and the
    // reference let go of — through the edit funnel every timeline change
    // uses. The pixels follow it, as a landed import's do.
    _project.historyManager.execute(
      UpdateLayerTimelineCommand(
        repository: _project.repository,
        before: layer,
        after: rasterized,
      ),
    );
    await _bakeLandedCels(
      cutId,
      rasterized,
      plan.bakes,
      // The planned layer was only a shape to fold by: the cels are THIS
      // row's, under its own id.
      rowId: layer.id,
      onProgress: onRenderProgress,
      // One frame the reader refuses leaves its cel empty and is reported
      // — never an abort into a half-rasterized row.
      onFailed: (bake) => onFrameRenderFailed?.call(bake.sourceFrameIndex),
      pictureOf: (bake, _) => _moviePicture(opened.token, info, bake),
    );
  }

  /// One movie frame as a picture — the same read for the door that PLACES
  /// a movie baked and the verb that RASTERIZES one placed as a reference.
  Future<({ui.Image image, bool owned})> _moviePicture(
    int token,
    QaVideoInfo info,
    PlannedCelBake bake,
  ) async {
    final rgba = await videoDecodeBackend.frame(token, bake.sourceFrameIndex);
    if (rgba == null) {
      throw StateError('Movie frame ${bake.sourceFrameIndex} did not decode.');
    }
    final image = await decodeStraightRgbaImage(
      rgba: rgba,
      width: info.width,
      height: info.height,
    );
    return (image: image, owned: true);
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
  /// [pictureOf], given the cut's canvas; it is rasterized there with the
  /// bake's fit and donated through the ordinary cel path. [onProgress]
  /// counts every bake, made or not.
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
    required Future<({ui.Image image, bool owned})> Function(
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
          try {
            final surface = await rasterizeImageToSurface(
              image: picture.image,
              canvas: cut.canvasSize,
              fit: bake.fit,
            );
            bakeCelSurface(
              _renderCaches.brushFrameStore,
              _internals.brushFrameKeyForCut(
                cut,
                rowId ?? bake.layerId,
                bake.frameId,
              ),
              surface,
            );
          } finally {
            if (picture.owned) {
              picture.image.dispose();
            }
          }
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
    final landed = _landing.landSound(
      arrival: gate,
      offsetFrames: kept.first,
      lengthFrames: kept.count,
      assets: [
        importedMediaAsset(
          path: source,
          // A movie's sound comes from the MOVIE: one pool entry for the
          // pair, so a relink finds both (「리링크는 풀 항목이 하나라 둘 다
          // 한 번에 따라간다」).
          kind: mediaAssetKindForPath(source) ?? MediaAssetKind.audio,
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
