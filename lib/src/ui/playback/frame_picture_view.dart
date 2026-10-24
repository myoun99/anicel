import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

import '../../models/canvas_viewport.dart';
import '../../models/composite_tree.dart';
import '../../services/playback/frame_demand.dart';
import '../canvas/canvas_layer_stack_view.dart' show CanvasStackRow;
import '../canvas/display_resample.dart';
import '../canvas/viewport_canvas_transform.dart';
import '../effective_device_pixel_ratio.dart';
import 'frame_picture_store.dart';
import 'frame_pictures.dart';
import 'stacked_frame_picture.dart';

/// What a screen showing a RUN takes from the run's maker: the signal that
/// a frame's picture landed, and the pictures the frames are kept in.
typedef StackRun = ({Listenable landings, FramePictures pictures});

/// 🚨★★★A RUN'S FRAME ON SCREEN IS ITS ONE PICTURE (one-picture-per-frame
/// ②-2, D7-2-Q3=a): the frame [nodes] stack for [picture], as the run's
/// maker made it ([FramePictures]) — drawn, never composited here. A frame
/// two screens show the same way is one picture, and this view makes
/// nothing: it takes each as it [StackRun.landings].
///
/// A frame changes WHOLE (유저 2026-10-08: 「재생바는 지나가고있는데 그림이
/// 없어서 비어있다던가」): the last picture shown stands, held by the store
/// for this view ([FramePictureStore.retainPin]), until the one asked for
/// is there. A frame the maker gave up on is drawn from its cels as they
/// stand ([FramePictures.drawingNow]): the run does not wait for it, and
/// what it shows is the frame without what would not come. So is a frame
/// of no row — its page alone, of which the store keeps no picture
/// ([FramePictures.drawsOnlyItsPage]).
///
/// ↩️Each screen stacked a run's frame from its ROWS' images
/// (`CanvasLayerStackView.run`), and composited them again every frame.
class FramePictureView extends StatefulWidget {
  const FramePictureView({
    super.key,
    required this.run,
    required this.picture,
    required this.nodes,
    required this.viewport,
  });

  final StackRun run;

  /// The frame this view shows, and whether its screen paints its paper.
  final DemandedPicture picture;

  /// The tree the screen stacks for [picture] — the key of its picture
  /// ([FramePictures.keyOfStack]).
  final List<CompositeNode<CanvasStackRow>> nodes;

  final CanvasViewport viewport;

  @override
  State<FramePictureView> createState() => _FramePictureViewState();
}

/// What the view draws: a frame's picture — the view's own handle on its
/// image, with what the store lays over it while patches land — or a frame
/// drawn as it stands.
typedef _Shown = ({FramePicture picture, ui.Image image})?;

class _FramePictureViewState extends State<FramePictureView> {
  /// The key of the frame shown — its picture, held for this view by the
  /// store; nothing, where it draws nothing; or the frame as it stands.
  FramePictureKey? _showing;

  _Shown _shown;

  /// A frame the maker gave up on, drawn as its cels stand.
  FrameDrawing? _asItStands;

  FramePictureStore<FramePictureKey> get _store => widget.run.pictures.store;

  @override
  void initState() {
    super.initState();
    widget.run.landings.addListener(_landed);
    _look();
  }

  @override
  void didUpdateWidget(FramePictureView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.run.landings, widget.run.landings)) {
      oldWidget.run.landings.removeListener(_landed);
      widget.run.landings.addListener(_landed);
    }
    if (!identical(oldWidget.run.pictures, widget.run.pictures)) {
      _letGo(oldWidget.run.pictures.store);
    }
    _look();
  }

  @override
  void dispose() {
    widget.run.landings.removeListener(_landed);
    _letGo(_store);
    super.dispose();
  }

  void _landed() => setState(_look);

  /// Takes the frame asked for where it is there; leaves what stands where
  /// it is not yet.
  void _look() {
    final pictures = widget.run.pictures;
    final key = pictures.keyOfStack(widget.nodes, widget.picture);
    if (key == _showing) {
      return;
    }
    final there = _store.peek(key);
    if (there != null) {
      _letGo(_store);
      _store.retainPin(key);
      _shown = (picture: there, image: there.image.clone());
    } else if (pictures.drawsOnlyItsPage(key) || pictures.gaveUpAt(key)) {
      // Nothing of it to wait for: its page alone, or a frame whose making
      // threw — drawn as it stands.
      _letGo(_store);
      final now = pictures.drawingNow(widget.nodes, widget.picture);
      _asItStands = now.drawing;
      if (now.thrown case (final error, final stack)) {
        FlutterError.reportError(
          FlutterErrorDetails(
            exception: error,
            stack: stack,
            library: 'frame picture view',
            context: ErrorDescription('drawing a frame as its cels stand'),
          ),
        );
      }
    } else {
      return;
    }
    _showing = key;
  }

  /// Lets go of what is shown, and of [store]'s hold on its picture.
  void _letGo(FramePictureStore<FramePictureKey> store) {
    if (_shown case (:final image, picture: _)) {
      image.dispose();
      store.releasePin(_showing!);
    }
    _shown = null;
    _asItStands = null;
    _showing = null;
  }

  @override
  Widget build(BuildContext context) => CustomPaint(
    painter: _FramePicturePainter(
      shown: _shown,
      asItStands: _asItStands,
      viewport: widget.viewport,
      devicePixelRatio: EffectiveDevicePixelRatio.of(context),
    ),
    child: const SizedBox.expand(),
  );
}

class _FramePicturePainter extends CustomPainter {
  _FramePicturePainter({
    required this.shown,
    required this.asItStands,
    required this.viewport,
    required this.devicePixelRatio,
  });

  final _Shown shown;
  final FrameDrawing? asItStands;
  final CanvasViewport viewport;
  final double devicePixelRatio;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    applyViewportTransform(
      canvas,
      viewport,
      devicePixelRatio: devicePixelRatio,
    );
    if (shown case (:final picture, :final image)) {
      _paintPicture(canvas, picture, image);
    } else if (asItStands case final drawing?) {
      _paintOutside(canvas, drawing.extent, drawing.outside);
      canvas.clipRect(drawing.extent);
      drawing.draw(canvas);
    }
    canvas.restore();
  }

  /// The picture as its store says it is drawn ([FramePicture]): its image
  /// where its extent lies, the world outside it its colour, and every
  /// patch still landing over it with `BlendMode.src` — the image and its
  /// patches in a layer of their own, so a patch's clear texels cut
  /// through the picture alone.
  void _paintPicture(Canvas canvas, FramePicture picture, ui.Image image) {
    _paintOutside(canvas, picture.extent, picture.outside);
    final landing = picture.landing;
    if (landing.isNotEmpty) {
      canvas.saveLayer(picture.extent, Paint());
    }
    _lay(canvas, image, picture.extent);
    for (final patch in landing) {
      _lay(canvas, patch.image, patch.rect, blendMode: BlendMode.src);
    }
    if (landing.isNotEmpty) {
      canvas.restore();
    }
  }

  void _lay(
    Canvas canvas,
    ui.Image image,
    Rect at, {
    BlendMode blendMode = BlendMode.srcOver,
  }) => drawOnTheDisplay(
    canvas,
    image,
    Offset.zero & Size(image.width.toDouble(), image.height.toDouble()),
    at,
    viewport: viewport,
    devicePixelRatio: devicePixelRatio,
    blendMode: blendMode,
  );

  void _paintOutside(Canvas canvas, Rect extent, Color outside) {
    if (outside.a == 0) {
      return;
    }
    canvas.save();
    canvas.clipRect(extent, clipOp: ui.ClipOp.difference);
    canvas.drawPaint(Paint()..color = outside);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_FramePicturePainter oldDelegate) =>
      !identical(oldDelegate.shown?.image, shown?.image) ||
      !identical(oldDelegate.asItStands, asItStands) ||
      oldDelegate.viewport != viewport ||
      oldDelegate.devicePixelRatio != devicePixelRatio;
}
