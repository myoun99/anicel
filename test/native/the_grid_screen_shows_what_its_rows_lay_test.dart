import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show ValueListenable, listEquals;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gpu_engine/gpu_engine.dart';

import 'package:anicel/src/native/app_gpu_engine.dart';
import 'package:anicel/src/native/screen_texture.dart';
import 'package:anicel/src/ui/timeline/timeline_grid_screen.dart';
import 'package:anicel/src/ui/timeline/timeline_grid_tile_ops.dart';
import 'package:anicel/src/ui/timeline/timeline_grid_tile_picture.dart';

import '../helpers/a_shown_surface.dart';

/// 🚨THE GRID'S SCREEN SHOWS WHAT ITS ROWS LAY, IN THE FRAME THEY LAY IT
/// (grid-on-the-engine ④ D1, 관제 2026-11-08 20:54): a row's tile is laid
/// where the row stands, in the view's device pixels; a scroll lays it
/// again where the row went; what a row lays in a paint is on the screen
/// that paint's frame shows; and before the app's engine is open a row
/// lays nothing and draws its cells itself.
void main() {
  late TimelineGridTilePicture tile;
  // The same, for the one case that lets go of it as its store would.
  late TimelineGridTilePicture letGoOf;
  late GpuSurface surface;
  const red = [255, 0, 0, 255];
  const green = [0, 255, 0, 255];
  final opened = debugOpenTimelineGridScreen;

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
    surface = shownSurfaceOf(300, 200);
    debugOpenTimelineGridScreen = (_, _, _) async =>
        ScreenTexture.debugOnSurface(surface);
  });
  tearDownAll(() {
    debugOpenTimelineGridScreen = opened;
    surface.free();
    tile.letGo();
  });

  /// A 300 × 200 view at a ratio of 2, so a logical pixel is two.
  void aSmallView(WidgetTester tester) {
    tester.view
      ..physicalSize = const Size(300, 200)
      ..devicePixelRatio = 2;
    addTearDown(tester.view.reset);
  }

  /// The bytes of a screen [width] × [height]: clear, and [runs] — (left,
  /// right, colour) each — over the rows [top] to [bottom], in device
  /// pixels.
  Uint8List screenOf(
    List<(int, int, List<int>)> runs, {
    int top = 40,
    int bottom = 60,
    int width = 300,
    int height = 200,
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

  /// A grid of [row], 60 × 10 at (10, 20) — of none where it is null —,
  /// inside a scroll of 400 across driven by [scroll]: a viewport 100
  /// across, 20 in from the view's left edge, so the screen stands where
  /// the viewport's clip puts it, not the view's. The row is drawn within
  /// [clip] where there is one, its slot keyed [slot] — under a padding of
  /// none where it is [padded], another parent with the constraints it had.
  Widget aGrid(
    _Row? row, {
    ScrollController? scroll,
    TimelineGridScreenClip? clip,
    Key? slot,
    bool padded = false,
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
          padding: const EdgeInsets.only(left: 20),
          child: SizedBox(
            width: 100,
            height: 100,
            child: SingleChildScrollView(
              controller: scroll,
              scrollDirection: Axis.horizontal,
              child: SizedBox(
                width: 400,
                height: 100,
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
  /// right edge and 20 down — past the right edge of a screen the view
  /// outgrew.
  Widget aGridAtTheRight(_Row row) => Directionality(
    textDirection: TextDirection.ltr,
    child: TimelineGridScreenHost(
      child: Stack(
        children: [
          Positioned(
            right: 20,
            top: 20,
            width: 60,
            height: 10,
            child: TimelineGridScreenSlot(child: CustomPaint(painter: row)),
          ),
        ],
      ),
    ),
  );

  /// Opens each screen on a surface as big as it is asked, the sizes asked
  /// kept in [asked]; freed after the test.
  List<GpuSurface> screensAsAsked(List<(int, int)> asked) {
    final shown = <GpuSurface>[];
    debugOpenTimelineGridScreen = (_, width, height) async {
      asked.add((width, height));
      final surface = shownSurfaceOf(width, height);
      shown.add(surface);
      return ScreenTexture.debugOnSurface(surface);
    };
    addTearDown(() {
      debugOpenTimelineGridScreen = (_, _, _) async =>
          ScreenTexture.debugOnSurface(surface);
      for (final surface in shown) {
        surface.free();
      }
    });
    return shown;
  }

  testWidgets('a row lays its tile where it stands, in device pixels', (
    tester,
  ) async {
    aSmallView(tester);
    final row = _Row(() => tile);
    await tester.pumpWidget(aGrid(row));
    await tester.pump();

    expect(row.laidLast, isTrue);
    expect(
      surface.fingerprint(),
      fingerprintBytes(screenOf([(20, 80, red), (80, 140, green)])),
    );
    final shown = tester.layers.whereType<TextureLayer>().single;
    expect(shown.rect, const Rect.fromLTWH(0, 0, 150, 100));
    // The id the screen presented by: a texture on a surface has 0.
    expect(shown.textureId, 0);
  });

  testWidgets('a scroll lays the tile again where the row went', (
    tester,
  ) async {
    aSmallView(tester);
    final scroll = ScrollController();
    addTearDown(scroll.dispose);
    await tester.pumpWidget(aGrid(_Row(() => tile), scroll: scroll));
    await tester.pump();

    scroll.jumpTo(15);
    await tester.pump();

    // 15 logical pixels are 30 device pixels left: the red half's first
    // ten are past the viewport's left edge, where the screen begins.
    expect(
      surface.fingerprint(),
      fingerprintBytes(screenOf([(0, 50, red), (50, 110, green)])),
    );
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
      fingerprintBytes(screenOf([(20, 140, green)])),
    );
  });

  testWidgets('a row that comes is shown in the frame it comes in', (
    tester,
  ) async {
    aSmallView(tester);
    await tester.pumpWidget(aGrid(null));
    await tester.pump();
    expect(surface.fingerprint(), fingerprintBytes(screenOf([])));

    await tester.pumpWidget(aGrid(_Row(() => tile)));

    expect(
      surface.fingerprint(),
      fingerprintBytes(screenOf([(20, 80, red), (80, 140, green)])),
    );
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
    scroll.jumpTo(15);
    await tester.pump();

    expect(
      surface.fingerprint(),
      fingerprintBytes(screenOf([(0, 50, red), (50, 110, green)])),
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
      fingerprintBytes(screenOf([(20, 50, red), (110, 140, green)])),
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
      fingerprintBytes(screenOf([(20, 80, red)])),
      reason: '⛔premise: the left half alone',
    );

    await tester.pumpWidget(
      aGrid(row, clip: _Rects.of([const Rect.fromLTWH(30, 0, 30, 10)])),
    );
    await tester.pump();

    expect(
      surface.fingerprint(),
      fingerprintBytes(screenOf([(80, 140, green)])),
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
      fingerprintBytes(screenOf([(20, 80, red)])),
      reason: '⛔premise: the left half alone',
    );

    at.value = [const Rect.fromLTWH(30, 0, 30, 10)];
    await tester.pump();

    expect(
      surface.fingerprint(),
      fingerprintBytes(screenOf([(80, 140, green)])),
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
      fingerprintBytes(screenOf([(20, 80, red)])),
      reason: '⛔premise: the left half alone',
    );

    at.value = [const Rect.fromLTWH(30, 0, 30, 10)];
    await tester.pump();

    expect(
      surface.fingerprint(),
      fingerprintBytes(screenOf([(80, 140, green)])),
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
    addTearDown(
      () => debugOpenTimelineGridScreen = (_, _, _) async =>
          ScreenTexture.debugOnSurface(surface),
    );
    await tester.pumpWidget(aGrid(row));
    await tester.pump();

    expect(row.laidLast, isFalse);
    expect(tester.layers.whereType<TextureLayer>(), isEmpty);
  });

  // 타임라인/콘티 리뷰 2026-11-09 A: a window grown stayed laid on the
  // screen it opened at, and what stood past that one's edge was laid
  // nowhere.
  testWidgets('a view that grows is laid on a screen as big as it', (
    tester,
  ) async {
    aSmallView(tester);
    final asked = <(int, int)>[];
    final shown = screensAsAsked(asked);
    await tester.pumpWidget(aGridAtTheRight(_Row(() => tile)));
    await tester.pump();
    expect(asked, [(300, 200)], reason: '⛔premise: the view it opened at');

    tester.view.physicalSize = const Size(600, 200);
    await tester.pump();
    await tester.pump();

    expect(asked, [(300, 200), (600, 200)]);
    // 300 logical across: the row stands at 220 to 280, device 440 to 560.
    expect(
      shown.last.fingerprint(),
      fingerprintBytes(
        screenOf([(440, 500, red), (500, 560, green)], width: 600),
      ),
    );
  });

  // 타임라인/콘티 2026-11-09 01:46: the size a MediaQuery tells of stays.
  testWidgets('a view moved to a screen of twice the ratio at the size it '
      'had is laid on a screen as big as its pixels', (tester) async {
    aSmallView(tester);
    final asked = <(int, int)>[];
    final shown = screensAsAsked(asked);
    await tester.pumpWidget(aGridAtTheRight(_Row(() => tile)));
    await tester.pump();
    expect(asked, [(300, 200)], reason: '⛔premise: the view it opened at');

    tester.view
      ..physicalSize = const Size(600, 400)
      ..devicePixelRatio = 4;
    await tester.pump();
    await tester.pump();

    expect(asked, [(300, 200), (600, 400)]);
    // Still 150 logical across: the row stands at 70 to 130, 20 to 30 —
    // device 280 to 520, 80 to 120.
    expect(
      shown.last.fingerprint(),
      fingerprintBytes(
        screenOf(
          [(280, 400, red), (400, 520, green)],
          top: 80,
          bottom: 120,
          width: 600,
          height: 400,
        ),
      ),
    );
  });

  // 타임라인/콘티 리뷰 2026-11-09 B: they laid on the smaller one held.
  testWidgets('while a screen as big as the view opens, its rows draw '
      'their cells themselves', (tester) async {
    aSmallView(tester);
    final row = _Row(() => tile);
    final shown = screensAsAsked([]);
    await tester.pumpWidget(aGridAtTheRight(row));
    await tester.pump();
    expect(row.laidLast, isTrue, reason: '⛔premise: laid on the one opened');

    final opening = Completer<ScreenTexture>();
    debugOpenTimelineGridScreen = (_, _, _) => opening.future;
    tester.view.physicalSize = const Size(600, 200);
    await tester.pump();

    expect(row.laidLast, isFalse);
    expect(tester.layers.whereType<TextureLayer>(), isEmpty);

    final bigger = shownSurfaceOf(600, 200);
    shown.add(bigger);
    opening.complete(ScreenTexture.debugOnSurface(bigger));
    await tester.pump();
    await tester.pump();

    expect(row.laidLast, isTrue);
    expect(
      bigger.fingerprint(),
      fingerprintBytes(
        screenOf([(440, 500, red), (500, 560, green)], width: 600),
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
    final laid = fingerprintBytes(screenOf([(20, 80, red), (80, 140, green)]));
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

  @override
  void paint(Canvas canvas, Size size) {
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
