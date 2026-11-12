import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:gpu_engine/gpu_engine.dart';

import '../core/sync_image_upload.dart';
import '../models/canvas_size.dart';
import '../models/canvas_viewport.dart';
import '../models/composite_tree.dart';
import '../native/app_gpu_engine.dart';
import '../native/screen_texture.dart';
import '../services/camera_frame_corners.dart' show CameraView;
import '../services/camera_projection_matrix.dart';
import '../services/cel_looks.dart';
import '../services/playback/frame_demand.dart';
import '../services/viewport_transform_matrix.dart' show viewportOfSimilarity;
import 'canvas/canvas_layer_stack_view.dart'
    show CanvasStackRow, EngineStackScreen, FramePage;
import 'canvas/fx_plugin_stages.dart';
import 'canvas/viewport_canvas_transform.dart' show applyViewportTransform;
import 'editor_session_manager.dart';
import 'playback/camera_shot.dart'
    show canvasCutOnScreen, clipToTheCut, shotClipOnScreen;
import 'playback/frame_pictures.dart';

/// What a shot lays over its picture, in CANVAS space under the view the
/// picture is shown through — handed the scale that view rasters a canvas
/// pixel at, which a `Canvas` will not tell anyone: a pass that rasters a
/// picture of its own (an SE tag with its row's effects) asks it as a
/// folder does.
typedef CameraOverlayPass = void Function(ui.Canvas canvas, double rasterScale);

/// [frame]'s one picture of [nodes] ([FramePictures.pictureOf]) shown
/// through [view] onto a raster of [output] pixels — on [ground], cut at
/// the canvas's edge where [cutsToTheCanvas] says ([canvasCutOnScreen]; a
/// film shows no pasteboard, 「페이스트보드는 포함 안 시킴」), and [over]
/// laid over it through the same view — made on the engine
/// ([frameOnTheEngine]) and read back as a picture.
///
/// 🚨★★★ONE DOOR FOR EVERY PICTURE OF A FRAME THAT GOES TO A FILE OR A
/// PANEL (7′, exports on the engine — 유저 11-08 「지금화면이랑
/// 맞출필요는없어 … 바뀌고 나서만 동일하면되」): a panel's print, a film's
/// frame, a still, a layered file's row, a cel. Each is the picture the
/// engine keeps of the frame, as the canvas shows it ([EngineStackScreen
/// .show]: the view snapped, the display's filter for the scale) — so a
/// still and a panel through one view on one paper are one picture, to the
/// byte. ↩️An export composited its rows again on Flutter, each through the
/// camera (`CameraFrameRenderService.renderThroughCamera`), and a panel's
/// picture came out a few levels apart from the still beside it.
///
/// A frame there is no picture to cut from — its page alone, one a canvas
/// holds as its own over what no cel stores — is drawn as its cels stand
/// ([FramePictures.drawingNow]), through the same view.
///
/// On [frame]'s page, or [page] where the picture is drawn on another
/// ([FramePictures.keyOfStack]): a file's rows on the ground it is made on.
///
/// 🚨★★★ITS CELS ARE LOOKS ([CelLooks]; `gpu-canonical-store-Q10`, 유저
/// 2026-11-10 「추천대로 법 지키도록」): what a shot reads leaves the store as
/// it found it. Held by [looks] where a run holds them across its frames,
/// else for this shot alone.
///
/// ⚠️[nodes] are asked of the frame after its movie cels are hydrated
/// (`MovieCelHydrator.hydrate`): where a movie's picture was laid is part
/// of where its row lies.
Future<ui.Image> frameShot(
  EditorSessionManager session, {
  required FramePictures pictures,
  required List<CompositeNode<CanvasStackRow>> nodes,
  required DemandedPicture frame,
  FramePage? page,
  required CameraView view,
  required CanvasSize output,
  required ui.Color ground,
  bool cutsToTheCanvas = true,
  CameraOverlayPass? over,
  CelLooks? looks,
}) => pictureOfShot(
  frameOnTheEngine(
    session,
    pictures: pictures,
    nodes: nodes,
    frame: frame,
    page: page,
    view: view,
    output: output,
    ground: ground,
    cutsToTheCanvas: cutsToTheCanvas,
    over: over,
    looks: looks,
  ),
);

/// The frame [shot] makes on the engine ([frameOnTheEngine]) read back
/// once as a picture of the caller's own to dispose ([pictureOfLaid]), and
/// the frame let go.
Future<ui.Image> pictureOfShot(Future<GpuShown> shot) async {
  final laid = await shot;
  try {
    return pictureOfLaid(appGpuExport, laid);
  } finally {
    laid.free();
  }
}

/// [picture] on a frame [export] makes ([GpuExport.blank]) — its
/// premultiplied rows uploaded and laid over it — for the caller to free:
/// what a writer is handed of a picture the app draws for itself, a
/// sheet's page or a conte's, read back the way a frame made on the engine
/// is ([pictureOfLaid]). [picture] stays the caller's.
Future<GpuShown> frameOfPicture(GpuExport export, ui.Image picture) async {
  final (width, height) = (picture.width, picture.height);
  final rows = await picture.toByteData();
  final uploaded = export.upload(rows!.buffer.asUint8List(), width, height);
  try {
    final frame = export.blank(width, height);
    try {
      export.lay(frame, uploaded);
    } on Object {
      frame.free();
      rethrow;
    }
    return frame;
  } finally {
    uploaded.free();
  }
}

/// [laid] — a frame [export] made ([GpuExport.blank]) — read back once as
/// a picture: what a panel or a preview is handed of a frame made on the
/// engine.
ui.Image pictureOfLaid(GpuExport export, GpuShown laid) => pictureOf(
  PremultipliedRows(export.read(laid).take(), laid.width, laid.height),
);

/// [frameShot]'s frame as the engine keeps it, for the caller to free: a
/// frame the export made ([GpuExport.blank]) on [ground], the frame's
/// picture laid over it cut at the canvas's edge, and [over] rastered and
/// laid over that — its last picture made on the engine, so what a writer
/// takes of it is read back once (gpu-export-path ①⑵).
///
/// ⚠️A cut on whole pixels is laid within them, and only an anti-aliased
/// one — a camera turned — through the cover the app rasters of it: the
/// one cut either way ([canvasCutOnScreen]).
Future<GpuShown> frameOnTheEngine(
  EditorSessionManager session, {
  required FramePictures pictures,
  required List<CompositeNode<CanvasStackRow>> nodes,
  required DemandedPicture frame,
  FramePage? page,
  required CameraView view,
  required CanvasSize output,
  required ui.Color ground,
  bool cutsToTheCanvas = true,
  CameraOverlayPass? over,
  CelLooks? looks,
}) async {
  final looking = looks ?? CelLooks(session.renderCaches.brushFrameStore);
  final picture = await pictures.pictureOf(
    nodes,
    frame,
    shouldAbort: _stays,
    page: page,
    looks: looking,
  );
  GpuSurface? target;
  GpuShown? shown;
  GpuShown? laid;
  try {
    final asItStands = picture == null
        ? await pictures
              .readInStack(nodes, frame, page: page, looks: looking)
              .then(
                (_) => pictures.drawingNow(
                  nodes,
                  frame,
                  page: page,
                  looks: looking,
                ),
              )
        : null;
    final onTheRaster = panelViewOnRaster(view, output);
    final tools = await session.renderCaches.framePictureStore.tools;
    final raster = target = ScreenTexture.surfaceOf(
      appGpuEngine,
      output.width,
      output.height,
    );
    final size = (output.width, output.height);
    Future<void> showOn(GpuTarget onto) async {
      if (picture != null) {
        picture.show(onto, size, viewport: onTheRaster, devicePixelRatio: 1);
        return;
      }
      final screen = EngineStackScreen(tools.composite, tools.letters);
      try {
        // Its plug-ins' steps run first, as a picture's are when it is
        // laid (🗣️I-132-Q34 a).
        await FxPluginStages.recordedThrough<void>(
          () => screen.compose(asItStands!.frame),
          discard: (_) {},
        );
        screen.show(onto, size, viewport: onTheRaster, devicePixelRatio: 1);
      } finally {
        screen.free();
      }
    }

    await showOn(raster);
    final export = await appGpuExportKernels.ready;
    final made = laid = export.blank(
      output.width,
      output.height,
      ground: gpuColourOf(ground.toARGB32()),
    );
    shown = export.shown(raster, output.width, output.height);
    await _layCut(
      export,
      made,
      shown,
      cut: cutsToTheCanvas
          ? canvasCutOnScreen(frame.cut.canvasSize, onTheRaster, 1)
          : null,
    );
    if (over != null) {
      await layDrawnOver(export, made, (canvas) {
        applyViewportTransform(canvas, onTheRaster);
        over(canvas, onTheRaster.zoom.abs());
      });
    }
    if (asItStands?.thrown case (final error, final stack)) {
      Error.throwWithStackTrace(error, stack);
    }
    laid = null;
    return made;
  } finally {
    laid?.free();
    shown?.free();
    target?.free();
    // 🚨Shot, the picture is left as the shot found it: one a step of the
    // run wants or a screen holds stays, and one made for the shot alone
    // goes ([PlaybackCacheBudget.letGoUnwanted]) — the shot's hold on it
    // released ([FramePictures.pictureOf]), whatever became of the shot.
    if (picture != null) {
      session.playbackRig.playbackCache.letGoUnwanted(
        pictures.keyOfStack(nodes, frame, page: page),
      );
      picture.release();
    }
  }
}

/// [shown] laid over [laid], cut where [cut] says — whole where there is
/// none: within the whole pixels a hard cut falls on, else through the
/// cover the app rasters of it.
Future<void> _layCut(
  GpuExport export,
  GpuShown laid,
  GpuShown shown, {
  required ({List<ui.Offset> corners, ui.Clip behavior})? cut,
}) async {
  if (cut == null) {
    export.lay(laid, shown);
    return;
  }
  if (cut.behavior != ui.Clip.antiAlias) {
    export.lay(laid, shown, within: _wholePixelsOf(cut.corners));
    return;
  }
  final covered = await _rasterOf(laid.width, laid.height, (canvas) {
    clipToTheCut(canvas, cut);
    canvas.drawPaint(ui.Paint()..color = const ui.Color(0xFFFFFFFF));
  });
  final cover = export.cover(
    Uint8List.fromList([
      for (var at = 3; at < covered.length; at += 4) covered[at],
    ]),
    laid.width,
    laid.height,
  );
  try {
    export.lay(laid, shown, cover: cover);
  } finally {
    cover.free();
  }
}

/// The pixels a hard cut's [corners] bound — [left, top, right, bottom),
/// whole pixels already ([shotClipOnScreen]).
(int, int, int, int) _wholePixelsOf(List<ui.Offset> corners) {
  var bounds = ui.Rect.fromPoints(corners.first, corners.first);
  for (final corner in corners.skip(1)) {
    bounds = bounds.expandToInclude(ui.Rect.fromPoints(corner, corner));
  }
  return (
    bounds.left.round(),
    bounds.top.round(),
    bounds.right.round(),
    bounds.bottom.round(),
  );
}

/// What [draw] draws on a raster of [onto]'s size, laid over [onto]
/// ([drawnOnTheEngine]).
Future<void> layDrawnOver(
  GpuExport export,
  GpuShown onto,
  void Function(ui.Canvas canvas) draw,
) async {
  final over = await drawnOnTheEngine(export, onto.width, onto.height, draw);
  try {
    export.lay(onto, over);
  } finally {
    over.free();
  }
}

/// What [draw] draws on a raster of [width] × [height], on the engine to
/// be laid over a frame there, for the caller to free: what the app draws
/// over a frame made on the engine — a shot's overlay, a stage's apron, a
/// cut's names and its veils — drawn by Flutter and laid by the engine
/// (gpu-export-path ①⑵: the letters are Flutter's, Q30).
///
/// Where [inks] says where [draw] inks — in the raster's pixels, as its
/// painter answers it — only the whole pixels round it are rastered, read
/// back and put on the GPU, and laid where they stand on a blank of the
/// raster's size there: the same frame, its other pixels clear. 🔬A 4K
/// frame's names inked 1–20% of it, and reading the whole of it back and
/// putting it up took 165–370 ms (card
/// an-exports-overlay-raster-reads-back-the-whole-frame).
Future<GpuShown> drawnOnTheEngine(
  GpuExport export,
  int width,
  int height,
  void Function(ui.Canvas canvas) draw, {
  ui.Rect? inks,
}) async {
  if (inks == null) {
    return export.upload(await _rasterOf(width, height, draw), width, height);
  }
  final (left, top, right, bottom) = _pixelsRound(inks, width, height);
  final whole = export.blank(width, height);
  if (right <= left || bottom <= top) {
    return whole;
  }
  try {
    final part = export.upload(
      await _rasterOf(width, height, draw, part: (left, top, right, bottom)),
      right - left,
      bottom - top,
    );
    try {
      export.lay(whole, part, x: left, y: top);
    } finally {
      part.free();
    }
    return whole;
  } on Object {
    whole.free();
    rethrow;
  }
}

/// The whole pixels of a [width] × [height] raster round [inks] —
/// [left, top, right, bottom) — with [_inkReach] more on every side.
(int, int, int, int) _pixelsRound(ui.Rect inks, int width, int height) {
  if (inks.isEmpty) {
    return (0, 0, 0, 0);
  }
  return (
    (inks.left.floor() - _inkReach).clamp(0, width),
    (inks.top.floor() - _inkReach).clamp(0, height),
    (inks.right.ceil() + _inkReach).clamp(0, width),
    (inks.bottom.ceil() + _inkReach).clamp(0, height),
  );
}

/// How far past the box its painter answers a raster's ink may fall, in
/// its pixels: an edge's anti-aliasing, and the filter a picture laid at a
/// scale samples its neighbours by.
const int _inkReach = 2;

/// What [draw] draws on a raster of [width] × [height], premultiplied
/// RGBA — only its [part] — [left, top, right, bottom) — where one is
/// named.
///
/// ⚠️[draw] is recorded on the whole raster and its picture rastered off
/// the part's corner, not drawn on a canvas moved there or cut to the part:
/// a painter that reads where it stands on the canvas (`getTransform()` —
/// a pan's phase, a checker's) or how far it reaches
/// (`getLocalClipBounds()` — the buffer an effect is drawn through) reads
/// what it would on the whole raster. It is moved there by a scene's
/// offset, not drawn on a second canvas: the picture is the overlay's own
/// lines and letters, and a picture drawn on a canvas is what
/// `every_overlay_is_laid_on_the_engine_test` takes for a frame composed by
/// Flutter.
Future<Uint8List> _rasterOf(
  int width,
  int height,
  void Function(ui.Canvas canvas) draw, {
  (int, int, int, int)? part,
}) async {
  final recorder = ui.PictureRecorder();
  draw(
    ui.Canvas(
      recorder,
      ui.Offset.zero & ui.Size(width.toDouble(), height.toDouble()),
    ),
  );
  final drawn = recorder.endRecording();
  try {
    final image = switch (part) {
      (final left, final top, final right, final bottom) => await _partOf(
        drawn,
        left: left,
        top: top,
        width: right - left,
        height: bottom - top,
      ),
      null => await drawn.toImage(width, height),
    };
    try {
      final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      return data!.buffer.asUint8List();
    } finally {
      image.dispose();
    }
  } finally {
    drawn.dispose();
  }
}

/// [picture] rastered on [width] × [height] from its pixel ([left], [top]).
Future<ui.Image> _partOf(
  ui.Picture picture, {
  required int left,
  required int top,
  required int width,
  required int height,
}) async {
  final scene = (ui.SceneBuilder()
        ..addPicture(ui.Offset(-left.toDouble(), -top.toDouble()), picture))
      .build();
  try {
    return await scene.toImage(width, height);
  } finally {
    scene.dispose();
  }
}

bool _stays() => false;

/// Where [view] lays the canvas on a raster of [output] pixels — its
/// camera's projection onto it, a device pixel the raster's: what every
/// [frameShot] is drawn through, and a conte picture's live one
/// (`ContePictureLive`).
///
/// 🚨ONE SPELLING OF IT (conte-picture-print-and-live-part-at-edges, 유저
/// 11-07 「0 으로 맞춘다」). ↩️The live one reached the same map by another
/// road — through the paper, the slot's scale and then the box's — and
/// stood its camera at the middle of the frame's height scaled to the
/// box, where the print's stands at the middle of its raster's rounded
/// height: apart wherever the raster's height is rounded (a camera frame
/// or a moving camera's region off the raster's aspect).
CanvasViewport panelViewOnRaster(CameraView view, CanvasSize output) =>
    viewportOfSimilarity(
      cameraProjectionMatrix(view.pose, view.frameSize, outputSize: output),
    )!;
