import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderRepaintBoundary;
import 'package:flutter_gpu/gpu.dart' as gpu;
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
import 'package:anicel/src/ui/quiet_turns.dart';

import 'settle_async.dart';

/// What a screen shows, row by row.
typedef Shot = ({Uint8List rgba, int width});

/// The pictures of the frames [stackOf] stacks, of [images]' cels, kept by
/// [store] — on a page of [canvasSize] with no wall — their background work
/// taking its turns in [quietTurns] where a test names them, the nodes it
/// holds on [line] where one is named.
StackRun runOver(
  LayerFrameImageCache images,
  FramePictureStore<FramePictureKey> store, {
  required CanvasSize canvasSize,
  required List<CompositeNode<CanvasStackRow>> Function(DemandedPicture)
  stackOf,
  ProjectBackground paper = ProjectBackground.defaultBackground,
  QuietTurns? quietTurns,
  HeldNodesLine? line,
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
      quietTurns: quietTurns,
      line: line,
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

/// The key [frame]'s picture is kept under by the canvas standing on it
/// while it holds what only the canvas's live rows show — a step on its
/// way, a ghost ([FramePictureKey.standingOn]) — the frame's own picture
/// under [view] where a test names one.
FramePictureKey keptByTheCanvas(
  WidgetTester tester,
  FramePictureKey frame, {
  Finder? view,
}) => frame.standingOn(tester.state(view ?? theFramesPicture()));

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

/// Each pixel [a] and [b] show differently — more than [by] apart in a
/// channel — where and how.
List<String> differences(Shot a, Shot b, {int by = 0}) => [
  for (var at = 0; at < a.rgba.length; at += 4)
    if ([
      for (var channel = at; channel < at + 4; channel += 1)
        (a.rgba[channel] - b.rgba[channel]).abs(),
    ].any((apart) => apart > by))
      '(${at ~/ 4 % a.width}, ${at ~/ 4 ~/ a.width}): '
          '${a.rgba.sublist(at, at + 4)} → ${b.rgba.sublist(at, at + 4)}',
];

/// A GPU whose renders wait their turn where asked ([holdsRenders]) — what
/// it does with a write is its kind's: [WritesNeverLand], [WritesLand].
abstract class RendersHeld implements FramePictureGpu {
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
}

/// A GPU whose writes never come back: every patch stays on its way into
/// its picture, and the picture shows what it was.
class WritesNeverLand extends RendersHeld {
  @override
  Object? hold(ui.Image image) => image;

  @override
  int levelsOf(Object held) {
    final image = held as ui.Image;
    return math.max(image.width, image.height).bitLength;
  }

  @override
  ui.Image imageOf(Object held) =>
      throw StateError('a write that never lands gives no image');

  @override
  Future<bool> write(Object held, List<BaseWrite> base, LevelWrites? levels) =>
      Completer<bool>().future;
}

/// A GPU whose every write throws as it is asked — as `flutter_gpu`'s did
/// into an iPhone's or iPad's picture (F-509): no patch goes in.
class WritesThrow extends WritesNeverLand {
  @override
  Future<bool> write(Object held, List<BaseWrite> base, LevelWrites? levels) =>
      throw StateError('a texel of no size');
}

/// The app's own writes into a frame's picture ([FlutterGpuFramePictures]):
/// a step seen on its way into the picture, then in it.
///
/// Flutter GPU's, so Impeller's alone: a pin on it carries the `gpu` tag
/// and skips where there is none to write with ([noFlutterGpu]).
class WritesLand extends RendersHeld {
  final FlutterGpuFramePictures _gpu = FlutterGpuFramePictures();

  @override
  Object? hold(ui.Image image) => _gpu.hold(image);

  @override
  int levelsOf(Object held) => _gpu.levelsOf(held);

  @override
  ui.Image imageOf(Object held) => _gpu.imageOf(held);

  /// Runs once, as the next write is in and before the store hears of it:
  /// what comes to the screen meanwhile.
  void Function()? beforeTheNextLands;

  @override
  Future<bool> write(
    Object held,
    List<BaseWrite> base,
    LevelWrites? levels,
  ) async {
    final written = await _gpu.write(held, base, levels);
    final meanwhile = beforeTheNextLands;
    beforeTheNextLands = null;
    meanwhile?.call();
    return written;
  }
}

/// Why this runner cannot write into a frame's picture, or null when it can.
final String? noFlutterGpu = () {
  try {
    gpu.gpuContext;
    return null;
  } on Exception catch (error) {
    return 'needs Impeller with Flutter GPU — run with '
        '`flutter test --enable-impeller --enable-flutter-gpu`: $error';
  }
}();

/// Waits for [landing] — a patch or a move a store answers for
/// (`FramePictureStore.landingOf`) — to be in its picture, and pumps the
/// paint after it.
///
/// ⚠️Both clocks ([settleAsync]), not `runAsync` alone: the store's chain
/// runs in the test's pumped zone, and a write in it comes back from the
/// GPU in real time — awaited inside `runAsync`, the chain never moved on.
///
/// 🚨Asks that the view wanted a frame the moment it landed: the texels go
/// into the picture's texture in place, so a capture here shows them
/// whether or not the view painted again — only the frame says the screen
/// will (🔬its repaint taken out, every pixel pin still passed).
///
/// 🚨★★★And that every frame view draws its picture's image AS IT IS NOW
/// ([FramePicture.image]) — a frame is not enough on an iPhone or iPad,
/// whose screen is drawn again only where its drawing changed, an image
/// told apart by its identity: a view drawing the image it drew before the
/// write showed the write nowhere there (F-509), and every capture here
/// would still show it.
Future<void> inThePicture(WidgetTester tester, Future<void>? landing) async {
  expect(landing, isNotNull, reason: '⛔premise: on its way into a picture');
  var landed = false;
  var framed = false;
  unawaited(
    landing!.then((_) {
      landed = true;
      framed = tester.binding.hasScheduledFrame;
    }),
  );
  expect(
    await settleAsync(tester, () => landed),
    isTrue,
    reason: 'LIVENESS: it is in the picture',
  );
  expect(framed, isTrue, reason: 'the view asks for the frame that shows it');
  await tester.pump();
  final views = find.descendant(
    of: find.byType(FramePictureView),
    matching: find.byType(CustomPaint),
  );
  for (final paint in tester.widgetList<CustomPaint>(views)) {
    final shown =
        (paint.painter as dynamic).shown
            as ({FramePicture picture, ui.Image image})?;
    if (shown case (:final picture, :final image)) {
      expect(
        image.isCloneOf(picture.image),
        isTrue,
        reason: 'a view draws its picture as it is now, not as it was drawn',
      );
    }
  }
}
