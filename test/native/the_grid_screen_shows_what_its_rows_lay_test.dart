import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show ValueListenable, listEquals;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gpu_engine/gpu_engine.dart';

import 'package:anicel/src/native/app_gpu_engine.dart';
import 'package:anicel/src/native/screen_texture.dart';
import 'package:anicel/src/ui/timeline/axis_turn.dart';
import 'package:anicel/src/ui/timeline/timeline_grid_screen.dart';
import 'package:anicel/src/ui/timeline/timeline_grid_tile_ops.dart';
import 'package:anicel/src/ui/timeline/timeline_grid_tile_picture.dart';
import 'package:anicel/src/ui/timeline/timeline_grid_tile_store.dart';

import '../helpers/a_shown_surface.dart';
import '../helpers/census_where_textures_are_ram.dart';

/// 🚨THE GRID'S SCREEN SHOWS WHAT ITS ROWS LAY, IN THE FRAME THEY LAY IT
/// (grid-on-the-engine ④ D1, 관제 2026-11-08 20:54): a row's tile is laid
/// where the row stands, in the view's device pixels; a scroll moves it with
/// the row and lays nothing till what the view shows has left the screen;
/// what a row lays in a paint is on the screen that paint's frame shows; the
/// screen is as big as what of its box the view shows, rounded up; and before
/// the app's engine is open a row lays nothing and draws its cells itself.
void main() {
  late TimelineGridTilePicture tile;
  // The same, for the one case that lets go of it as its store would.
  late TimelineGridTilePicture letGoOf;
  // The screen opened last, every one opened, and the sizes they were asked.
  late GpuSurface surface;
  final surfaces = <GpuSurface>[];
  final asked = <(int, int)>[];
  const red = [255, 0, 0, 255];
  const green = [0, 255, 0, 255];
  final opener = debugOpenTimelineGridScreen;

  setUpAll(() async {
    final engine = await openAppGpuEngine();
    // 120 × 20: red over its left half, green over its right.
    final grid = GpuGrid(engine);
    final ops = TimelineGridTileOpWriter()
      ..fillRect(0, 0, 60, 20, timelineGridPackRgba(const Color(0xFFFF0000)))
      ..fillRect(60, 0, 60, 20, timelineGridPackRgba(const Color(0xFF00FF00)));
    TimelineGridTilePicture drawn() {
      final picture = GpuGridPicture(engine, 120, 20);
      grid.draw(picture, ops.build());
      return TimelineGridTilePicture(picture);
    }

    tile = drawn();
    letGoOf = drawn();
    grid.free();
  });
  tearDownAll(() {
    debugOpenTimelineGridScreen = opener;
    tile.letGo();
  });
  setUp(() {
    debugOpenTimelineGridScreen = (_, width, height) async {
      asked.add((width, height));
      surface = shownSurfaceOf(width, height);
      surfaces.add(surface);
      return ScreenTexture.debugOnSurface(surface);
    };
  });
  tearDown(() {
    for (final surface in surfaces) {
      surface.free();
    }
    surfaces.clear();
    asked.clear();
  });

  /// A 300 × 200 view at a ratio of 2, so a logical pixel is two.
  void aSmallView(WidgetTester tester) {
    tester.view
      ..physicalSize = const Size(300, 200)
      ..devicePixelRatio = 2;
    addTearDown(tester.view.reset);
  }

  /// The bytes of a screen [width] × [height]: clear, and [runs] — (left,
  /// right, colour) each — over the rows [top] to [bottom], in its pixels.
  Uint8List screenOf(
    List<(int, int, List<int>)> runs, {
    int top = 196,
    int bottom = 216,
    int width = 512,
    int height = 512,
  }) {
    final bytes = Uint8List(width * height * 4);
    for (final (left, right, [r, g, b, a]) in runs) {
      for (var y = top; y < bottom; y++) {
        for (var x = left; x < right; x++) {
          bytes.setAll(
            (y * width + x) * 4,
            surface.bgra ? [b, g, r, a] : [r, g, b, a],
          );
        }
      }
    }
    return bytes;
  }

  // What [aGrid] lays, unscrolled: the view shows 200 × 200 of its box from
  // (40, 0), so a screen of 512 × 512 — spare split either side — starts at
  // (-116, -156), and the row's device (60, 40) is its (176, 196).
  const laidWhole = <(int, int, List<int>)>[
    (176, 236, red),
    (236, 296, green),
  ];

  /// A grid of [row], 60 × 10 at (10, 20) — of none where it is null —,
  /// [content] across inside a scroll driven by [scroll]: a viewport
  /// [viewport] across, 20 in from the view's left edge, so what is shown
  /// stands where the viewport's clip puts it, not the view's. The row is
  /// drawn within [clip] where there is one, its slot keyed [slot] — under a
  /// padding of none where it is [padded], another parent with the
  /// constraints it had.
  Widget aGrid(
    _Row? row, {
    ScrollController? scroll,
    TimelineGridScreenClip? clip,
    Key? slot,
    bool padded = false,
    double viewport = 100,
    double content = 400,
    double left = 20,
    Axis axis = Axis.horizontal,
  }) {
    final slotted = TimelineGridScreenSlot(
      key: slot,
      clip: clip,
      child: CustomPaint(painter: row),
    );
    return Directionality(
      textDirection: TextDirection.ltr,
      child: Align(
        alignment: Alignment.topLeft,
        child: Padding(
          padding: EdgeInsets.only(left: left),
          child: sizedAlong(
            axis,
            along: viewport,
            across: 100,
            child: SingleChildScrollView(
              controller: scroll,
              scrollDirection: axis,
              child: sizedAlong(
                axis,
                along: content,
                across: 100,
                child: TimelineGridScreenHost(
                  child: Stack(
                    children: [
                      if (row != null)
                        Positioned(
                          left: 10,
                          top: 20,
                          width: 60,
                          height: 10,
                          child: padded
                              ? Padding(
                                  padding: EdgeInsets.zero,
                                  child: slotted,
                                )
                              : slotted,
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// A grid as big as the view, of [row] 60 × 10, 20 in from the view's
  /// right edge and 20 down — or 20 up from its bottom, where [low]
  /// — past the edge of a screen the view outgrew.
  Widget aGridAtTheRight(_Row row, {bool low = false}) => Directionality(
    textDirection: TextDirection.ltr,
    child: TimelineGridScreenHost(
      child: Stack(
        children: [
          Positioned(
            right: 20,
            top: low ? null : 20,
            bottom: low ? 20 : null,
            width: 60,
            height: 10,
            child: TimelineGridScreenSlot(child: CustomPaint(painter: row)),
          ),
        ],
      ),
    ),
  );

  testWidgets('a row lays its tile where it stands, in device pixels', (
    tester,
  ) async {
    aSmallView(tester);
    final row = _Row(() => tile);
    await tester.pumpWidget(aGrid(row));
    await tester.pump();

    expect(row.laidLast, isTrue);
    expect(surface.fingerprint(), fingerprintBytes(screenOf(laidWhole)));
    final shown = tester.layers.whereType<TextureLayer>().single;
    // In the box's own pixels: it starts at the view's device 40.
    expect(shown.rect, const Rect.fromLTWH(-78, -78, 256, 256));
    // The id the screen presented by: a texture on a surface has 0.
    expect(shown.textureId, 0);
  });

  testWidgets('a scroll moves the screen with its rows and lays nothing', (
    tester,
  ) async {
    aSmallView(tester);
    final scroll = ScrollController();
    addTearDown(scroll.dispose);
    await tester.pumpWidget(aGrid(_Row(() => tile), scroll: scroll));
    await tester.pump();
    final at = tester.layers.whereType<TextureLayer>().single.rect;

    scroll.jumpTo(15);
    await tester.pump();

    // Laid again, the screen would start where the view shows, and the row
    // stand 30 further left on it.
    expect(surface.fingerprint(), fingerprintBytes(screenOf(laidWhole)));
    expect(tester.layers.whereType<TextureLayer>().single.rect, at);
  });

  testWidgets('a scroll past what the screen holds lays it again where the '
      'row went', (tester) async {
    aSmallView(tester);
    final scroll = ScrollController();
    addTearDown(scroll.dispose);
    await tester.pumpWidget(aGrid(_Row(() => tile), scroll: scroll));
    await tester.pump();

    scroll.jumpTo(85);
    await tester.pump();

    // 170 device pixels left: the box starts at -130, what the view shows
    // past where the screen ended (226), and the row at -110 is its 6.
    expect(
      surface.fingerprint(),
      fingerprintBytes(screenOf([(6, 66, red), (66, 126, green)])),
    );

    // Back: what the view shows starts before where that screen now does.
    scroll.jumpTo(0);
    await tester.pump();

    expect(surface.fingerprint(), fingerprintBytes(screenOf(laidWhole)));
  });

  testWidgets('a scroll down past what the screen holds lays it again, and '
      'back up', (tester) async {
    aSmallView(tester);
    final scroll = ScrollController();
    addTearDown(scroll.dispose);
    await tester.pumpWidget(
      aGrid(_Row(() => tile), scroll: scroll, axis: Axis.vertical),
    );
    await tester.pump();
    expect(asked, [(512, 512)], reason: '⛔premise');

    scroll.jumpTo(85);
    await tester.pump();

    // 170 device pixels up: the row at -130 is the screen's 26.
    expect(
      surface.fingerprint(),
      fingerprintBytes(screenOf(laidWhole, top: 26, bottom: 46)),
    );

    scroll.jumpTo(0);
    await tester.pump();

    expect(surface.fingerprint(), fingerprintBytes(screenOf(laidWhole)));
  });

  testWidgets('a box out of the view lays nothing', (tester) async {
    aSmallView(tester);
    final row = _Row(() => tile);
    await tester.pumpWidget(aGrid(row));
    await tester.pump();

    final lay = GpuGridLay(appGpuEngineOpen.value!);
    addTearDown(lay.free);
    lay.lay(surface, (0, 0, 512, 512), const []);
    final wiped = surface.fingerprint();

    await tester.pumpWidget(aGrid(row, left: 200));
    await tester.pump();

    expect(surface.fingerprint(), wiped);
  });

  testWidgets('a box never in the view opens no screen', (tester) async {
    aSmallView(tester);
    await tester.pumpWidget(aGrid(_Row(() => tile), left: 200));
    await tester.pump();
    await tester.pump();

    expect(asked, isEmpty);
  });

  // 512 × (1 / 1.9) × 1.9 is 511.99999999999994: a screen standing exactly
  // on what it shows would, off by that last bit, be laid again every frame.
  testWidgets('a frame that moved nothing lays nothing, whatever the last '
      'bit of the ratio', (tester) async {
    tester.view
      ..physicalSize = const Size(512, 512)
      ..devicePixelRatio = 1.9;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(aGridAtTheRight(_Row(() => tile)));
    await tester.pump();
    expect(asked, [(512, 512)], reason: 'no step more for the last bit');
    final laid = surface.fingerprint();

    final lay = GpuGridLay(appGpuEngineOpen.value!);
    addTearDown(lay.free);
    lay.lay(surface, (0, 0, 512, 512), const []);
    final wiped = surface.fingerprint();
    expect(wiped, isNot(laid), reason: '⛔premise: wiped by hand');

    tester.binding.scheduleForcedFrame();
    await tester.pump();

    expect(surface.fingerprint(), wiped);
  });

  testWidgets('what a row lays in a paint is shown in that frame', (
    tester,
  ) async {
    aSmallView(tester);
    final row = _Row(() => tile);
    await tester.pumpWidget(aGrid(row));
    await tester.pump();

    // The green half alone, over the whole row.
    row.layFrom(const Rect.fromLTWH(60, 0, 60, 20));
    await tester.pump();

    expect(
      surface.fingerprint(),
      fingerprintBytes(screenOf([(176, 296, green)])),
    );
  });

  testWidgets('a row that comes is shown in the frame it comes in', (
    tester,
  ) async {
    aSmallView(tester);
    await tester.pumpWidget(aGrid(_Row(() => tile)));
    await tester.pump();
    await tester.pumpWidget(aGrid(null));
    await tester.pump();
    expect(surface.fingerprint(), fingerprintBytes(screenOf([])));

    await tester.pumpWidget(aGrid(_Row(() => tile)));

    expect(surface.fingerprint(), fingerprintBytes(screenOf(laidWhole)));
  });

  testWidgets('a tile its store lets go of lives while a row lays it', (
    tester,
  ) async {
    aSmallView(tester);
    final scroll = ScrollController();
    addTearDown(scroll.dispose);
    final row = _Row(() => letGoOf);
    await tester.pumpWidget(aGrid(row, scroll: scroll));
    await tester.pump();
    expect(letGoOf.debugHolds, 2, reason: 'the store and the row');

    letGoOf.letGo();
    scroll.jumpTo(85);
    await tester.pump();

    expect(
      surface.fingerprint(),
      fingerprintBytes(screenOf([(6, 66, red), (66, 126, green)])),
    );
    row.layFrom(null);
    await tester.pump();
    expect(letGoOf.debugHolds, 0, reason: 'freed once no row lays it');
  });

  testWidgets('a row that lays nothing leaves nothing shown', (tester) async {
    aSmallView(tester);
    final row = _Row(() => tile);
    await tester.pumpWidget(aGrid(row));
    await tester.pump();
    expect(surface.fingerprint(), isNot(fingerprintBytes(screenOf([]))));

    row.layFrom(null);
    await tester.pump();

    expect(surface.fingerprint(), fingerprintBytes(screenOf([])));
  });

  testWidgets('a row drawn within a clip lays its tile within the clip, '
      'each part of the tile where it stood', (tester) async {
    aSmallView(tester);
    // A quarter of the row at each end: red's first half, green's last.
    final clip = _Rects.of([
      const Rect.fromLTWH(0, 0, 15, 10),
      const Rect.fromLTWH(45, 0, 15, 10),
    ]);
    await tester.pumpWidget(aGrid(_Row(() => tile), clip: clip));
    await tester.pump();

    expect(
      surface.fingerprint(),
      fingerprintBytes(screenOf([(176, 206, red), (266, 296, green)])),
    );
  });

  testWidgets('a row built again within another clip lays within that one', (
    tester,
  ) async {
    aSmallView(tester);
    final row = _Row(() => tile);
    await tester.pumpWidget(
      aGrid(row, clip: _Rects.of([const Rect.fromLTWH(0, 0, 30, 10)])),
    );
    await tester.pump();
    expect(
      surface.fingerprint(),
      fingerprintBytes(screenOf([(176, 236, red)])),
      reason: '⛔premise: the left half alone',
    );

    await tester.pumpWidget(
      aGrid(row, clip: _Rects.of([const Rect.fromLTWH(30, 0, 30, 10)])),
    );
    await tester.pump();

    expect(
      surface.fingerprint(),
      fingerprintBytes(screenOf([(236, 296, green)])),
    );
  });

  testWidgets('a clip that moves by itself lays the row again within it', (
    tester,
  ) async {
    aSmallView(tester);
    final at = ValueNotifier([const Rect.fromLTWH(0, 0, 30, 10)]);
    addTearDown(at.dispose);
    await tester.pumpWidget(aGrid(_Row(() => tile), clip: _Rects(at)));
    await tester.pump();
    expect(
      surface.fingerprint(),
      fingerprintBytes(screenOf([(176, 236, red)])),
      reason: '⛔premise: the left half alone',
    );

    at.value = [const Rect.fromLTWH(30, 0, 30, 10)];
    await tester.pump();

    expect(
      surface.fingerprint(),
      fingerprintBytes(screenOf([(236, 296, green)])),
    );
  });

  testWidgets('the screen stands under its rows', (tester) async {
    aSmallView(tester);
    await tester.pumpWidget(aGrid(_Row(() => tile)));
    await tester.pump();

    final layers = tester.layers;
    final shown = layers.whereType<TextureLayer>().single;
    final row = tester
        .renderObject(find.byType(TimelineGridScreenSlot))
        .debugLayer!;
    expect(
      layers.indexOf(shown),
      lessThan(layers.indexOf(row)),
      reason: 'a frame shows what comes after over what comes before',
    );
  });

  testWidgets('a row built again within a clip that moves by itself lays '
      'again as that clip moves', (tester) async {
    aSmallView(tester);
    final row = _Row(() => tile);
    await tester.pumpWidget(
      aGrid(row, clip: _Rects.of([const Rect.fromLTWH(0, 0, 60, 10)])),
    );
    await tester.pump();
    final at = ValueNotifier([const Rect.fromLTWH(0, 0, 30, 10)]);
    addTearDown(at.dispose);
    await tester.pumpWidget(aGrid(row, clip: _Rects(at)));
    await tester.pump();
    expect(
      surface.fingerprint(),
      fingerprintBytes(screenOf([(176, 236, red)])),
      reason: '⛔premise: the left half alone',
    );

    at.value = [const Rect.fromLTWH(30, 0, 30, 10)];
    await tester.pump();

    expect(
      surface.fingerprint(),
      fingerprintBytes(screenOf([(236, 296, green)])),
    );
  });
  testWidgets('a part of the row its clip leaves none of is not laid', (
    tester,
  ) async {
    aSmallView(tester);
    final before = tile.debugHolds;
    // The second rect lies past the row's end.
    await tester.pumpWidget(
      aGrid(
        _Row(() => tile),
        clip: _Rects.of([
          const Rect.fromLTWH(0, 0, 30, 10),
          const Rect.fromLTWH(70, 0, 10, 10),
        ]),
      ),
    );
    await tester.pump();

    expect(tile.debugHolds - before, 1, reason: 'the one part laid');
  });

  testWidgets('before the engine is open a row lays nothing', (tester) async {
    aSmallView(tester);
    final row = _Row(() => tile);
    debugOpenTimelineGridScreen = (_, _, _) => Completer<ScreenTexture>().future;
    await tester.pumpWidget(aGrid(row));
    await tester.pump();

    expect(row.laidLast, isFalse);
    expect(tester.layers.whereType<TextureLayer>(), isEmpty);
  });

  // 관제 2026-11-09 08:07 E③: it opened a texture as big as the view for
  // the grids no row of which lays on it.
  testWidgets('a grid no row lays on opens no screen, till one comes', (
    tester,
  ) async {
    aSmallView(tester);
    await tester.pumpWidget(aGrid(null));
    await tester.pump();
    await tester.pump();
    expect(asked, isEmpty);
    expect(tester.layers.whereType<TextureLayer>(), isEmpty);

    final row = _Row(() => tile);
    await tester.pumpWidget(aGrid(row));
    await tester.pump();
    await tester.pump();

    expect(asked, [(512, 512)]);
    expect(row.laidLast, isTrue);
    expect(surface.fingerprint(), fingerprintBytes(screenOf(laidWhole)));
  });

  // 관제 2026-11-09 08:07 E②: as big as the view, it held a panel's strip
  // at the price of the whole window.
  testWidgets('a screen is as big as what of its box the view shows', (
    tester,
  ) async {
    tester.view
      ..physicalSize = const Size(3000, 2000)
      ..devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(aGrid(_Row(() => tile)));
    await tester.pump();

    expect(asked, [(512, 512)]);
  });

  testWidgets('a side that fills a step keeps room to scroll where its box '
      'goes on', (tester) async {
    tester.view
      ..physicalSize = const Size(600, 200)
      ..devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    // 512 of its 800 shown: 512 and the room is the step past 512.
    await tester.pumpWidget(aGrid(_Row(() => tile), viewport: 256));
    await tester.pump();

    expect(asked, [(1024, 512)]);
  });

  testWidgets('a side scrolled to its box\'s end keeps room to scroll back', (
    tester,
  ) async {
    tester.view
      ..physicalSize = const Size(600, 200)
      ..devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    final scroll = ScrollController(initialScrollOffset: 144);
    addTearDown(scroll.dispose);
    await tester.pumpWidget(
      aGrid(_Row(() => tile), scroll: scroll, viewport: 256),
    );
    await tester.pump();

    expect(asked, [(1024, 512)]);
  });

  // 2.9999999999999996 to 515 at 1.35; 1136.0000000000002 to
  // 1648.0000000000002 at 1.1: each 512 wide, and a pixel more by a bare
  // floor or ceiling.
  for (final (ratio, device) in const [(1.35, 3), (1.1, 1136)]) {
    testWidgets('a box of a whole step at a ratio of $ratio needs no step '
        'more for the last bit', (tester) async {
      tester.view
        ..physicalSize = const Size(2000, 200)
        ..devicePixelRatio = ratio;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Stack(
            children: [
              Positioned(
                left: device / ratio,
                top: 0,
                width: 512 / ratio,
                height: 50,
                child: TimelineGridScreenHost(
                  child: TimelineGridScreenSlot(
                    child: CustomPaint(painter: _Row(() => tile)),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
      await tester.pump();

      expect(asked, [(512, 512)]);
    });
  }

  testWidgets('a panel that grows within its screen paints no row again', (
    tester,
  ) async {
    aSmallView(tester);
    final row = _Row(() => tile);
    await tester.pumpWidget(aGrid(row));
    await tester.pump();
    await tester.pump();
    final painted = row.paints;

    await tester.pumpWidget(aGrid(row, viewport: 110));
    await tester.pump();

    expect(asked, [(512, 512)], reason: '⛔premise: 220 and the room fit');
    expect(row.paints, painted);
  });

  testWidgets('a side its box shows whole keeps no room', (tester) async {
    tester.view
      ..physicalSize = const Size(600, 200)
      ..devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      aGrid(_Row(() => tile), viewport: 256, content: 256),
    );
    await tester.pump();

    expect(asked, [(512, 512)]);
  });

  // Nothing tells the box of this one: its own size stays, no row paints,
  // no scroll moves.
  testWidgets('a panel grown around a box that stays is laid on a screen as '
      'big as what it now shows', (tester) async {
    tester.view
      ..physicalSize = const Size(600, 200)
      ..devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    final row = _Row(() => tile);
    await tester.pumpWidget(aGrid(row));
    await tester.pump();
    expect(asked, [(512, 512)], reason: '⛔premise: 200 and the room');

    await tester.pumpWidget(aGrid(row, viewport: 280));
    await tester.pump();
    await tester.pump();

    // 560 shown and the room. The row at device 60 to 180, 40 to 60: 464
    // spare split either side from the viewport's 40.
    expect(asked, [(512, 512), (1024, 512)]);
    expect(
      surface.fingerprint(),
      fingerprintBytes(
        screenOf([(252, 312, red), (312, 372, green)], width: 1024),
      ),
    );
  });

  // 타임라인/콘티 리뷰 2026-11-09 A: a window grown stayed laid on the
  // screen it opened at, and what stood past that one's edge was laid
  // nowhere.
  testWidgets('a view that grows is laid on a screen as big as it, and the '
      'one it outgrew is let go of', (tester) async {
    aSmallView(tester);
    final holding = ScreenTexture.liveBytes;
    await tester.pumpWidget(aGridAtTheRight(_Row(() => tile)));
    await tester.pump();
    expect(asked, [(512, 512)], reason: '⛔premise: the view it opened at');

    tester.view.physicalSize = const Size(600, 200);
    await tester.pump();
    await tester.pump();

    expect(asked, [(512, 512), (1024, 512)]);
    // 300 logical across: the row stands at 220 to 280, device 440 to 560,
    // on a screen with 424 spare across and 312 down.
    expect(
      surface.fingerprint(),
      fingerprintBytes(
        screenOf([(652, 712, red), (712, 772, green)], width: 1024),
      ),
    );
    expect(ScreenTexture.liveBytes - holding, 1024 * 512 * 4);
  });

  testWidgets('a view that only grows taller is laid on a screen as tall', (
    tester,
  ) async {
    aSmallView(tester);
    await tester.pumpWidget(aGridAtTheRight(_Row(() => tile), low: true));
    await tester.pump();
    expect(asked, [(512, 512)], reason: '⛔premise: the view it opened at');

    tester.view.physicalSize = const Size(300, 600);
    await tester.pump();
    await tester.pump();

    expect(asked, [(512, 512), (512, 1024)]);
    // 300 logical down: the row stands at 270 to 280, device 540 to 560, on
    // a screen with 212 spare across and 424 down.
    expect(
      surface.fingerprint(),
      fingerprintBytes(
        screenOf(
          [(246, 306, red), (306, 366, green)],
          top: 752,
          bottom: 772,
          height: 1024,
        ),
      ),
    );
  });

  // 타임라인/콘티 2026-11-09 01:46: the size a MediaQuery tells of stays.
  testWidgets('a view moved to a screen of twice the ratio at the size it '
      'had is laid on a screen as big as its pixels', (tester) async {
    aSmallView(tester);
    await tester.pumpWidget(aGridAtTheRight(_Row(() => tile)));
    await tester.pump();
    expect(asked, [(512, 512)], reason: '⛔premise: the view it opened at');

    tester.view
      ..physicalSize = const Size(600, 400)
      ..devicePixelRatio = 4;
    await tester.pump();
    await tester.pump();

    expect(asked, [(512, 512), (1024, 512)]);
    // Still 150 logical across: the row stands at 70 to 130, 20 to 30 —
    // device 280 to 520, 80 to 120 — on a screen with 424 spare across and
    // 112 down.
    expect(
      surface.fingerprint(),
      fingerprintBytes(
        screenOf(
          [(492, 612, red), (612, 732, green)],
          top: 136,
          bottom: 176,
          width: 1024,
        ),
      ),
    );
  });

  // 타임라인/콘티 리뷰 2026-11-09 B: they laid on the smaller one held.
  testWidgets('while a screen as big as the view opens, its rows draw '
      'their cells themselves', (tester) async {
    aSmallView(tester);
    final row = _Row(() => tile);
    await tester.pumpWidget(aGridAtTheRight(row));
    await tester.pump();
    expect(row.laidLast, isTrue, reason: '⛔premise: laid on the one opened');

    final opening = Completer<ScreenTexture>();
    debugOpenTimelineGridScreen = (_, _, _) => opening.future;
    tester.view.physicalSize = const Size(600, 200);
    await tester.pump();
    // The frame it outgrew the screen in: its rows have laid on it, and it
    // shows what it holds from the start of what the view shows.
    expect(
      tester.layers.whereType<TextureLayer>().single.rect,
      const Rect.fromLTWH(0, -78, 256, 256),
    );

    await tester.pump();

    expect(row.laidLast, isFalse);
    expect(tester.layers.whereType<TextureLayer>(), isEmpty);

    final bigger = shownSurfaceOf(1024, 512);
    surfaces.add(bigger);
    surface = bigger;
    opening.complete(ScreenTexture.debugOnSurface(bigger));
    await tester.pump();
    await tester.pump();

    expect(row.laidLast, isTrue);
    expect(
      bigger.fingerprint(),
      fingerprintBytes(
        screenOf([(652, 712, red), (712, 772, green)], width: 1024),
      ),
    );
  });

  // 타임라인/콘티 리뷰 2026-11-09 H: it let go of what it laid as it went,
  // and was not laid out again to paint it anew.
  testWidgets('a row moved to another parent lays its tile again', (
    tester,
  ) async {
    aSmallView(tester);
    final slot = GlobalKey();
    final row = _Row(() => tile);
    await tester.pumpWidget(aGrid(row, slot: slot));
    await tester.pump();
    final laid = fingerprintBytes(screenOf(laidWhole));
    expect(surface.fingerprint(), laid, reason: '⛔premise');

    await tester.pumpWidget(aGrid(row, slot: slot, padded: true));

    expect(surface.fingerprint(), laid);
  });

  // 타임라인/콘티 리뷰 2026-11-09 I.
  testWidgets('a clip is asked for its rects once a paint, however many '
      'tiles its row lays', (tester) async {
    aSmallView(tester);
    final at = ValueNotifier([const Rect.fromLTWH(0, 0, 30, 10)]);
    addTearDown(at.dispose);
    final clip = _Rects(at);
    final row = _Row(() => tile, times: 3);
    await tester.pumpWidget(aGrid(row, clip: clip));
    await tester.pump();
    expect(row.laidLast, isTrue, reason: '⛔premise');
    final before = clip.asked;

    at.value = [const Rect.fromLTWH(30, 0, 30, 10)];
    await tester.pump();

    expect(clip.asked - before, 1);
  });

  // 관제 2026-11-09 08:07 E①.
  testWidgets('what a screen holds is on the census till it is freed', (
    tester,
  ) async {
    aSmallView(tester);
    final holding = ScreenTexture.liveBytes;
    await tester.pumpWidget(aGrid(_Row(() => tile)));
    await tester.pump();

    expect(ScreenTexture.liveBytes - holding, 512 * 512 * 4);
    expect(
      collectMemoryCensusWhereTexturesAreRam(
        const [],
      ).items.singleWhere((item) => item.id == 'timelineTiles').bytes,
      TimelineGridTileStore.instance.tileImageBytes + ScreenTexture.liveBytes,
    );

    await tester.pumpWidget(const SizedBox());

    expect(ScreenTexture.liveBytes, holding);
  });
}

/// A row that lays a part of its tile over all of itself where its grid's
/// screen takes it ([TimelineGridScreenSlot.laying]) — the whole, till
/// [layFrom] names another, or none, and paints it again — [times] over.
class _Row extends CustomPainter {
  _Row(this._tile, {this.times = 1}) : super(repaint: _changed);

  final TimelineGridTilePicture Function() _tile;
  final int times;
  static final ValueNotifier<int> _changed = ValueNotifier(0);

  Rect? _from = const Rect.fromLTWH(0, 0, 120, 20);
  void layFrom(Rect? value) {
    _from = value;
    _changed.value += 1;
  }

  /// Whether its last paint could lay its tile.
  bool laidLast = false;

  /// How many times it was painted.
  int paints = 0;

  @override
  void paint(Canvas canvas, Size size) {
    paints += 1;
    final laying = TimelineGridScreenSlot.laying;
    laidLast = laying != null;
    if (_from case final from?) {
      for (var laid = 0; laid < times; laid += 1) {
        laying?.lay((picture: _tile(), from: from, onto: Offset.zero & size));
      }
    }
  }

  @override
  bool shouldRepaint(_Row oldDelegate) => false;
}

/// A clip of the rects [at] holds, which clips again as they move.
class _Rects extends TimelineGridScreenClip {
  _Rects(this.at) : super(reclip: at);

  _Rects.of(List<Rect> rects) : this(ValueNotifier(rects));

  final ValueListenable<List<Rect>> at;

  /// How many times it was asked for its rects.
  int asked = 0;

  @override
  List<Rect> rectsIn(Size size) {
    asked += 1;
    return at.value;
  }

  @override
  bool shouldReclip(_Rects oldClipper) =>
      !listEquals(oldClipper.at.value, at.value);
}
