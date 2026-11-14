import 'dart:typed_data';
import 'dart:ui' as ui;

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart'
    show
        OffsetLayer,
        RenderRepaintBoundary;
import 'package:flutter_test/flutter_test.dart';
import 'package:gpu_engine/gpu_engine.dart' show GpuTarget;
import 'package:anicel/src/core/floor_math.dart';
import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/bitmap_tile.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/canvas_viewport.dart';
import 'package:anicel/src/models/composite_tree.dart';
import 'package:anicel/src/models/pasteboard_bounds.dart';
import 'package:anicel/src/models/project_background.dart';
import 'package:anicel/src/models/tile_coord.dart';
import 'package:anicel/src/native/engine_chain_holds.dart';
import 'package:anicel/src/native/engine_frame_tools.dart';
import 'package:anicel/src/services/playback/frame_demand.dart';
import 'package:anicel/src/ui/canvas/canvas_layer_stack_view.dart';
import 'package:anicel/src/ui/playback/engine_frame_picture_store.dart';
import 'package:anicel/src/ui/playback/frame_picture_view.dart';
import 'package:anicel/src/ui/playback/frame_pictures.dart';
import 'package:anicel/src/ui/playback/frame_wait_mark.dart';
import 'package:anicel/src/ui/playback/layer_frame_image_cache.dart';
import 'package:anicel/src/ui/playback/stacked_frame_picture.dart';
import 'package:anicel/src/ui/quiet_turns.dart';

import 'a_shown_surface.dart';

/// What a screen shows, row by row.
typedef Shot = ({Uint8List rgba, int width});

/// Opens the engine and what a frame is laid with before the file's first
/// test, off the test's clock: what it waits for comes in real time.
void opensTheEnginesScreens() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => appEngineFrameTools);
}

/// The store of a file's frames' pictures, on the app's engine
/// ([opensTheEnginesScreens]).
EngineFramePictureStore<FramePictureKey> aStoreOfPictures() =>
    EngineFramePictureStore(
      tools: () => appEngineFrameTools,
      openAlready: () => appEngineFrameToolsOpen,
    );

/// The pictures of the frames [stackOf] stacks, of [images]' cels, kept by
/// [store] — on a page of [canvasSize] with no wall — their background work
/// taking its turns in [quietTurns] where a test names them, the nodes it
/// holds on [line] where one is named.
StackRun runOver(
  LayerFrameImageCache images,
  EngineFramePictureStore<FramePictureKey> store, {
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
/// top left over [under] — what [screen] shows ([shotOf]) — in a place
/// that marks its frames' waits as the canvas's panel does
/// ([FrameWaitPlace], where a test stands the mark): the mark at the
/// window's middle, past what [screen] shows.
Widget onAScreen(
  GlobalKey screen, {
  required Size size,
  required Color under,
  required Widget view,
}) => MaterialApp(
  home: FrameWaitPlace(
    child: Stack(
      children: [
        Align(
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
        const Positioned.fill(child: FrameWaitMark()),
      ],
    ),
  ),
);

/// What [screen] shows, at the window's ratio.
Future<Shot> shotOf(WidgetTester tester, GlobalKey screen) async {
  final render = screen.currentContext!.findRenderObject()!
      as RenderRepaintBoundary;
  final ratio = tester.view.devicePixelRatio;
  final shot = await tester.runAsync(() async {
    final image = await render.toImage(pixelRatio: ratio);
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

/// The paint after a step went into its picture, which is the paint that
/// showed it: a step is composed in at the paint that shows it, and there
/// is nothing to wait for. A frame is asked for all the same, or the screen
/// would not be read as it now is.
Future<void> inThePicture(WidgetTester tester) => tester.pump();

/// A store that says which keys were laid, which a step was written into
/// and which a landing moved a picture to — on the app's tools, or on
/// [tools] where a test opens its own.
class StoreTellingItsWrites extends EngineFramePictureStore<FramePictureKey> {
  StoreTellingItsWrites({Future<EngineFrameTools> Function()? tools})
    : super(tools: tools ?? () => appEngineFrameTools);

  final List<FramePictureKey> laid = [];
  final List<FramePictureKey> patched = [];
  final List<FramePictureKey> moved = [];

  /// The widest a step written in was said to reach, in world pixels.
  double widestPatch = 0;

  /// Whether a step was written into the picture under [key], or a picture
  /// moved there.
  bool landedAt(FramePictureKey key) =>
      patched.contains(key) || moved.contains(key);

  @override
  Future<EngineFramePicture?> lay(
    FramePictureKey key,
    StackedFrame frame, {
    bool shownNow = false,
    bool Function() gone = _stays,
    ({FramePictureKey film, ui.Rect fresh})? over,
    EngineChainHolds? holds,
  }) {
    laid.add(key);
    return super.lay(
      key,
      frame,
      shownNow: shownNow,
      gone: gone,
      over: over,
      holds: holds,
    );
  }

  @override
  bool patch({
    required FramePictureKey from,
    required FramePictureKey to,
    required ui.Rect rect,
    required StackedFrame frame,
    EngineChainHolds? holds,
  }) {
    patched.add(to);
    widestPatch = math.max(widestPatch, rect.width);
    return super.patch(
      from: from,
      to: to,
      rect: rect,
      frame: frame,
      holds: holds,
    );
  }

  @override
  bool move({required FramePictureKey from, required FramePictureKey to}) {
    moved.add(to);
    return super.move(from: from, to: to);
  }

  static bool _stays() => false;
}

/// A store whose lays stay on their way: a frame's picture never comes —
/// on the app's tools, or on [tools] where a test opens its own.
class StoreLayingNothing extends EngineFramePictureStore<FramePictureKey> {
  StoreLayingNothing({Future<EngineFrameTools> Function()? tools})
    : super(tools: tools ?? () => appEngineFrameTools);

  @override
  Future<EngineFramePicture?> lay(
    FramePictureKey key,
    StackedFrame frame, {
    bool shownNow = false,
    bool Function() gone = _stays,
    ({FramePictureKey film, ui.Rect fresh})? over,
    EngineChainHolds? holds,
  }) => Completer<EngineFramePicture?>().future;

  static bool _stays() => false;
}

/// A store no picture comes of: every lay asked of it throws [why], and
/// [laid] says each that was asked.
class StoreWhoseLaysThrow extends EngineFramePictureStore<FramePictureKey> {
  StoreWhoseLaysThrow(this.why) : super(tools: () => appEngineFrameTools);

  final Object why;
  final List<FramePictureKey> laid = [];

  @override
  Future<EngineFramePicture?> lay(
    FramePictureKey key,
    StackedFrame frame, {
    bool shownNow = false,
    bool Function() gone = _stays,
    ({FramePictureKey film, ui.Rect fresh})? over,
    EngineChainHolds? holds,
  }) {
    laid.add(key);
    return Future.error(why);
  }

  static bool _stays() => false;
}

/// What [box] — a repaint boundary — shows at the window's ratio, as
/// [shotOf] reads a screen.
Future<Shot> shotOfBox(WidgetTester tester, RenderBox box) async {
  final ratio = tester.view.devicePixelRatio;
  final shot = await tester.runAsync(() async {
    final layer = box.debugLayer! as OffsetLayer;
    final image = await layer.toImage(Offset.zero & box.size, pixelRatio: ratio);
    final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    final width = image.width;
    image.dispose();
    return (rgba: data!.buffer.asUint8List(), width: width);
  });
  return shot!;
}

/// The box a frame's screen paints in, inside [view].
Finder theFrameScreenIn(Finder view) => find.descendant(
  of: view,
  matching: find.byWidgetPredicate(
    (widget) => widget is LeafRenderObjectWidget,
  ),
);

/// Lets [store]'s tools open before a paint needs them, where no picture
/// laid will come to paint again.
Future<void> itsToolsOpen(
  WidgetTester tester,
  EngineFramePictureStore<FramePictureKey> store,
) => tester.runAsync(() => store.tools);

/// [picture]'s pixels over [world] at 100%, read back from the GPU:
/// premultiplied RGBA, row after row.
Uint8List pixelsOfPicture(EngineFramePicture picture, ui.Rect world) =>
    _shownOver(
      world,
      (target, size, viewport) => picture.show(
        target,
        size,
        viewport: viewport,
        devicePixelRatio: 1,
      ),
    );

/// [surface]'s pixels laid out again on the tiles the engine stores: a
/// fixture's tile size is how it counts its pixels, and a frame is laid from
/// these.
BitmapSurface onTheEnginesTiles(BitmapSurface surface) {
  const side = defaultCelTileSize;
  final laid = <TileCoord, Uint8List>{};
  for (final MapEntry(key: at, value: tile) in surface.tiles.entries) {
    final pixels = tile.pixels;
    for (var y = 0; y < tile.size; y += 1) {
      for (var x = 0; x < tile.size; x += 1) {
        final worldX = at.x * surface.tileSize + x;
        final worldY = at.y * surface.tileSize + y;
        final from = (y * tile.size + x) * 4;
        final to = ((worldY % side) * side + worldX % side) * 4;
        laid.putIfAbsent(
            TileCoord(x: floorDiv(worldX, side), y: floorDiv(worldY, side)),
            () => Uint8List(side * side * 4),
          )
          .setRange(to, to + 4, pixels, from);
      }
    }
  }
  return BitmapSurface(
    canvasSize: surface.canvasSize,
    pasteboardReach: surface.pasteboardReach,
    tiles: {
      for (final MapEntry(:key, :value) in laid.entries)
        key: BitmapTile(size: side, pixels: value),
    },
    texts: surface.texts,
    photos: surface.photos,
    laidBounds: surface.laidBounds,
  );
}

/// What a float showing [rgba] over the whole pixels of [where] holds where
/// it lands, on the tiles the engine stores.
Map<TileCoord, BitmapTile> tilesOfColorOver(
  ui.Rect where,
  List<int> rgba,
) {
  const side = defaultCelTileSize;
  final laid = <TileCoord, Uint8List>{};
  for (var y = where.top.floor(); y < where.bottom.ceil(); y += 1) {
    for (var x = where.left.floor(); x < where.right.ceil(); x += 1) {
      final to = ((y % side) * side + x % side) * 4;
      laid
          .putIfAbsent(
            TileCoord(x: floorDiv(x, side), y: floorDiv(y, side)),
            () => Uint8List(side * side * 4),
          )
          .setRange(to, to + 4, rgba);
    }
  }
  return {
    for (final MapEntry(:key, :value) in laid.entries)
      key: BitmapTile(size: side, pixels: value),
  };
}

/// The premultiplied RGBA [frame] lays over [world], a canvas pixel [zoom]
/// to a side, on the engine ([opensTheEnginesScreens]).
Uint8List pixelsOfFrame(StackedFrame frame, ui.Rect world, {double zoom = 1}) {
  final (:composite, :letters) = appEngineFrameToolsOpen!;
  final screen = EngineStackScreen(composite, letters);
  try {
    screen.compose(frame);
    return _shownOver(
      world,
      (target, size, viewport) => screen.show(
        target,
        size,
        viewport: viewport,
        devicePixelRatio: 1,
      ),
      zoom: zoom,
    );
  } finally {
    screen.free();
  }
}

Uint8List _shownOver(
  ui.Rect world,
  void Function(GpuTarget target, (int, int) size, CanvasViewport viewport)
  show, {
  double zoom = 1,
}) {
  final width = (world.width * zoom).round();
  final height = (world.height * zoom).round();
  final target = shownSurfaceOf(width, height);
  try {
    show(
      target,
      (width, height),
      CanvasViewport(
        zoom: zoom,
        panX: -world.left * zoom,
        panY: -world.top * zoom,
      ),
    );
    return target.read();
  } finally {
    target.free();
  }
}
