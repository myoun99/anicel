import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderRepaintBoundary;
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/canvas_viewport.dart';
import 'package:anicel/src/models/composite_tree.dart';
import 'package:anicel/src/models/pasteboard_bounds.dart';
import 'package:anicel/src/models/project_background.dart';
import 'package:anicel/src/services/playback/frame_demand.dart';
import 'package:anicel/src/ui/canvas/canvas_layer_stack_view.dart';
import 'package:anicel/src/ui/playback/frame_picture_gpu.dart';
import 'package:anicel/src/ui/playback/frame_picture_store.dart';
import 'package:anicel/src/ui/playback/frame_picture_view.dart';
import 'package:anicel/src/ui/playback/frame_pictures.dart';
import 'package:anicel/src/ui/playback/layer_frame_image_cache.dart';
import 'package:anicel/src/ui/playback/stacked_frame_picture.dart';

/// What a screen shows, row by row.
typedef Shot = ({Uint8List rgba, int width});

/// The pictures of the frames [stackOf] stacks, of [images]' cels, kept by
/// [store] — on a page of [canvasSize] with no wall.
StackRun runOver(
  LayerFrameImageCache images,
  FramePictureStore<FramePictureKey> store, {
  required CanvasSize canvasSize,
  required List<CompositeNode<CanvasStackRow>> Function(DemandedPicture)
  stackOf,
  ProjectBackground paper = ProjectBackground.defaultBackground,
}) {
  final landings = ValueNotifier<int>(0);
  addTearDown(landings.dispose);
  return (
    landings: landings,
    pictures: FramePictures(
      store: store,
      layerImages: images,
      stackOf: stackOf,
      pageOf: (picture) => (
        canvasSize: canvasSize,
        pasteboardReach: PasteboardReach.whole,
        paintPaper: picture.paintPaper,
        paperBackground: paper,
      ),
    ),
  );
}

/// The frame [nodes] stack for [picture] as a canvas that stands on it
/// shows it — the editing canvas's view standing: the frame's one picture,
/// made where the view misses it, and the rows [live] holds drawn live.
FramePictureView standingOn(
  StackRun run, {
  Key? key,
  required DemandedPicture picture,
  required List<CompositeNode<CanvasStackRow>> nodes,
  required CanvasViewport viewport,
  required LiveRows live,
}) => FramePictureView(
  key: key,
  run: run,
  picture: picture,
  nodes: nodes,
  viewport: viewport,
  live: live,
  laysWhatItMisses: true,
  wholeFrames: false,
);

/// The frame's own picture where a canvas stands on it or plays it — under
/// [within] where a test names where.
///
/// ⚠️Not a bare `find.byType(FramePictureView)`: the onion ghosts lie over
/// the frame's picture in a picture view of their own, there while the
/// canvas stands with no ghost too (`_ghostsOver`). Laid under them, the
/// frame's is the first.
Finder theFramesPicture({Finder? within}) {
  final views = find.byType(FramePictureView);
  return (within == null
          ? views
          : find.descendant(of: within, matching: views))
      .first;
}

/// [view] on a screen of its own, [size] logical pixels at the window's
/// top left over [under] — what [screen] shows ([shotOf]).
Widget onAScreen(
  GlobalKey screen, {
  required Size size,
  required Color under,
  required Widget view,
}) => MaterialApp(
  home: Align(
    alignment: Alignment.topLeft,
    child: RepaintBoundary(
      key: screen,
      child: ClipRect(
        child: Container(
          width: size.width,
          height: size.height,
          color: under,
          child: view,
        ),
      ),
    ),
  ),
);

/// What [screen] shows, at the window's ratio.
Future<Shot> shotOf(WidgetTester tester, GlobalKey screen) async {
  final render = screen.currentContext!.findRenderObject()!
      as RenderRepaintBoundary;
  final shot = await tester.runAsync(() async {
    final image = await render.toImage(
      pixelRatio: tester.view.devicePixelRatio,
    );
    final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    final width = image.width;
    image.dispose();
    return (rgba: data!.buffer.asUint8List(), width: width);
  });
  return shot!;
}

/// Each pixel [a] and [b] show differently, where and how.
List<String> differences(Shot a, Shot b) => [
  for (var at = 0; at < a.rgba.length; at += 4)
    if (!listEquals(a.rgba.sublist(at, at + 4), b.rgba.sublist(at, at + 4)))
      '(${at ~/ 4 % a.width}, ${at ~/ 4 ~/ a.width}): '
          '${a.rgba.sublist(at, at + 4)} → ${b.rgba.sublist(at, at + 4)}',
];

/// A GPU whose writes never come back: every patch stays drawn over its
/// picture ([FramePicture.landing]), so what shows once it lands is the
/// patch's own texels.
class WritesNeverLand implements FramePictureGpu {
  /// Whether every render waits its turn ([letOneThrough]): a step stays on
  /// its way into the picture, none of its texels there. ⛔Not left to the
  /// test's raster: it renders a patch before the next paint, and the
  /// screen while a step lands was never drawn.
  bool holdsRenders = false;

  final List<Completer<void>> _waiting = [];

  /// How many renders wait their turn.
  int get rendersWaiting => _waiting.length;

  /// Lets the render that has waited longest through.
  void letOneThrough() => _waiting.removeAt(0).complete();

  /// Holds no render from here on, and lets every waiting one through.
  void letAllThrough() {
    holdsRenders = false;
    for (final turn in _waiting) {
      turn.complete();
    }
    _waiting.clear();
  }

  @override
  Future<ui.Image> render(ui.Picture picture, int width, int height) async {
    if (holdsRenders) {
      final turn = Completer<void>();
      _waiting.add(turn);
      await turn.future;
    }
    return picture.toImage(width, height);
  }

  @override
  Object? hold(ui.Image image) => image;

  @override
  int levelsOf(Object held) {
    final image = held as ui.Image;
    return math.max(image.width, image.height).bitLength;
  }

  @override
  Future<bool> writeBase(Object held, List<BaseWrite> writes) =>
      Completer<bool>().future;

  @override
  Future<bool> writeLevels(Object held, ui.Image run, List<RunSpan> spans) =>
      Completer<bool>().future;
}
