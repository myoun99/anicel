import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart'
    show FlutterMemoryAllocations, ObjectCreated, ObjectDisposed, ObjectEvent;
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/bitmap_tile.dart';
import 'package:anicel/src/models/camera_pose.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/tile_coord.dart';
import 'package:anicel/src/services/cut_frame_composite_plan.dart';
import 'package:anicel/src/ui/camera/camera_frame_render_service.dart';
import 'package:anicel/src/ui/canvas/tiled_surface_compose.dart';
import 'package:anicel/src/ui/export/held_rows.dart';

/// The row pictures a video run's cut pictures are made of (F-289-Q21,
/// 유저 2026-10-07: 「붙든다 — 재생 줄의 허용치 안에서」): a cel's row is
/// composed once for the frames of the run that show it — held under the
/// cel's address from the frame that composes it to the last frame ahead
/// that shows it, within the room playback's line lends, and where that is
/// short the row shown latest makes room.
void main() {
  /// A 2×2 row picture's bytes.
  const rowBytes = 2 * 2 * 4;

  late int heldBefore;
  late List<int> told;
  late HeldRows rows;
  late int room;

  /// The frames of the run that show each cel, in order.
  late Map<String, List<int>> shows;

  /// The frame of the run being drawn.
  late int at;

  /// The cel each surface was read for.
  final celOf = Expando<String>('cel');

  /// Every picture [compose] made, in the order it made them.
  final composed = <ui.Image>[];

  setUp(() {
    heldBefore = HeldRows.debugHeld;
    told = [];
    room = 1 << 30;
    shows = {};
    at = 0;
    rows = HeldRows(
      room: () => room,
      onHeld: told.add,
      addressOf: (surface) => celOf[surface]!,
      nextShown: (address, from) {
        final ahead = [
          for (final frame in shows[address] ?? const <int>[])
            if (frame >= at + from) frame - at,
        ];
        return ahead.isEmpty ? null : ahead.first;
      },
    );
    composed.clear();
  });

  tearDown(() {
    rows.dispose();
    expect(
      HeldRows.debugHeld,
      heldBefore,
      reason: 'the run is over: nothing left held',
    );
  });

  /// [cel], read — another surface each time, as a cel read again is.
  BitmapSurface read(String cel) {
    final surface = BitmapSurface(
      canvasSize: const CanvasSize(width: 2, height: 2),
      tileSize: 2,
      tiles: {
        TileCoord(x: 0, y: 0): BitmapTile(
          size: 2,
          pixels: Uint8List(16)..fillRange(0, 16, cel.codeUnitAt(0)),
        ),
      },
    );
    celOf[surface] = cel;
    return surface;
  }

  Future<PositionedSurfaceImage> compose() async {
    final recorder = ui.PictureRecorder();
    ui.Canvas(recorder).drawColor(const ui.Color(0xFF204060), ui.BlendMode.src);
    final picture = recorder.endRecording();
    final image = await picture.toImage(2, 2);
    picture.dispose();
    composed.add(image);
    return PositionedSurfaceImage(
      image: image,
      worldRect: const ui.Rect.fromLTWH(0, 0, 2, 2),
    );
  }

  /// A picture made of [cels], in that order — what it was handed for each.
  Future<List<ui.Image>> picture(List<String> cels) => rows.during(
    (asked) async => [
      for (final cel in cels) (await asked.of(read(cel), compose)).image,
    ],
  );

  /// Frame [index] of the run starts, and a picture is made of [cels] — or
  /// of nothing, where the frame is the picture the frame before it was.
  Future<List<ui.Image>> frame(int index, [List<String>? cels]) async {
    at = index;
    rows.nextFrame();
    return cels == null ? const [] : await picture(cels);
  }

  test('🎯a cel shown again is the row composed for it — read again, '
      'another surface, across a frame that does not show it', () async {
    // 🔬The user's film (2026-10-13): 958 of 1,594 row rasters were of cels
    // composed before — a cycle's drawings leave the frame and come back.
    shows = {
      'a': [0, 2],
      'b': [1],
    };
    final [aFirst] = await frame(0, ['a']);
    await frame(1, ['b']);
    final [aAgain] = await frame(2, ['a']);

    expect(identical(aAgain, aFirst), isTrue);
    expect(rows.made, 2, reason: 'a once, and b');
    expect(composed, hasLength(2));
  });

  test('🚨a row is let go when a frame starts from which no frame shows '
      'it — and not before', () async {
    shows = {
      'a': [0, 1],
      'b': [0, 2],
    };
    final [aImage, bImage] = await frame(0, ['a', 'b']);

    await frame(1);
    expect(aImage.debugDisposed, isFalse, reason: 'frame 1 shows a');
    expect(HeldRows.debugHeld - heldBefore, 2);

    await frame(2);
    expect(aImage.debugDisposed, isTrue, reason: 'no frame from 2 on shows a');
    expect(bImage.debugDisposed, isFalse, reason: 'frame 2 shows b');
    expect(HeldRows.debugHeld - heldBefore, 1);
  });

  test('🚨a row no frame after its own shows is composed for its picture '
      'alone, and let go the moment that picture is made', () async {
    shows = {
      'a': [0, 1],
      'b': [0],
    };
    final [aImage, bImage] = await frame(0, ['a', 'b']);

    expect(aImage.debugDisposed, isFalse, reason: 'frame 1 shows a: held');
    expect(bImage.debugDisposed, isTrue, reason: 'no frame after 0 shows b');
    expect(HeldRows.debugHeld - heldBefore, 1);
  });

  test('a cel asked for twice by one picture is composed once — held or '
      'not', () async {
    shows = {
      'a': [0, 1],
      'b': [0],
    };
    final [a1, a2, b1, b2] = await frame(0, ['a', 'a', 'b', 'b']);

    expect(identical(a1, a2), isTrue);
    expect(identical(b1, b2), isTrue);
    expect(rows.made, 2);
  });

  test('🎯where the room is short, the row shown LATEST makes room — not '
      'one shown sooner', () async {
    room = 3 * rowBytes;
    shows = {
      'a': [0, 1],
      'b': [0, 3],
      'c': [1, 2],
      'd': [0, 6],
    };
    final [_, bImage, dImage] = await frame(0, ['a', 'b', 'd']);
    final [_, cImage] = await frame(1, ['a', 'c']);

    expect(dImage.debugDisposed, isTrue, reason: 'shown at 6: latest');
    expect(bImage.debugDisposed, isFalse, reason: 'shown at 3');
    expect(cImage.debugDisposed, isFalse, reason: 'held: frame 2 shows it');
  });

  test('a row shown later than every row it would take the place of is '
      'composed for its picture alone', () async {
    room = 2 * rowBytes;
    shows = {
      'a': [0, 2],
      'b': [0, 3],
      'c': [1, 5],
    };
    final [aImage, bImage] = await frame(0, ['a', 'b']);
    final [cImage] = await frame(1, ['c']);

    expect(cImage.debugDisposed, isTrue, reason: 'shown at 5: after both');
    expect(aImage.debugDisposed, isFalse);
    expect(bImage.debugDisposed, isFalse);
  });

  test('among rows shown next at one frame, the one used least lately makes '
      'room first', () async {
    shows = {
      'a': [0, 1, 3],
      'b': [0, 3],
    };
    final [aImage, bImage] = await frame(0, ['a', 'b']);
    await frame(1, ['a']);

    room = rowBytes;
    await frame(2);
    expect(bImage.debugDisposed, isTrue, reason: 'b was last used at 0');
    expect(aImage.debugDisposed, isFalse, reason: 'a at 1');
  });

  test('🚨the rows a picture is drawn with stay while room is made for '
      'another of its rows — whatever the run says of them', () async {
    room = 2 * rowBytes;
    // The run shows a at 0 and 4 and x at 5 alone — the picture at 1 is
    // made of both all the same.
    shows = {
      'a': [0, 4],
      'x': [5],
      'c': [1, 2],
    };
    final [aImage] = await frame(0, ['a']);
    final [aThen, xImage, cImage] = await frame(1, ['a', 'x', 'c']);

    expect(identical(aThen, aImage), isTrue, reason: 'LIVENESS: a was held');
    expect(
      [aImage.debugDisposed, xImage.debugDisposed],
      [false, false],
      reason: 'a held and x composed — drawn with, both stay',
    );
    expect(cImage.debugDisposed, isTrue, reason: 'no room left for c');
  });

  test('🚨a room lowered while the run goes takes rows back when the next '
      'frame starts — the one shown latest first — and a row asked for '
      'again composes again', () async {
    // The storage session's review (2026-10-08): an OS memory warning
    // halves playback's line while the run goes.
    shows = {
      'a': [0, 1, 2, 3],
      'b': [0, 3],
    };
    final [aImage, bImage] = await frame(0, ['a', 'b']);

    room = rowBytes;
    await frame(1);
    expect(bImage.debugDisposed, isTrue, reason: 'shown at 3, a at 1');
    expect(aImage.debugDisposed, isFalse);
    expect(told.last, rowBytes, reason: 'the lender hears it');

    room = 0;
    await frame(2);
    expect(aImage.debugDisposed, isTrue);
    expect(HeldRows.debugHeld, heldBefore, reason: 'none held');

    room = 1 << 30;
    final made = rows.made;
    final [aAgain, _] = await frame(3, ['a', 'b']);
    expect(rows.made, made + 2, reason: 'both composed again');
    expect(identical(aAgain, aImage), isFalse);
  });

  test('the room is asked when a row would be held, so a line that gives '
      'more holds more', () async {
    shows = {
      'a': [0, 1],
      'b': [1, 2],
    };
    room = 0;
    await frame(0, ['a']);
    expect(HeldRows.debugHeld, heldBefore, reason: 'no room: none held');

    room = rowBytes;
    await frame(1, ['b']);
    expect(HeldRows.debugHeld - heldBefore, 1);
  });

  test('🎯the lender hears what is held each time it changes, and 0 when '
      'the run is over', () async {
    shows = {
      'a': [0, 1, 2],
      'b': [0, 1],
    };
    final [aImage, _] = await frame(0, ['a', 'b']);
    expect(told.last, 2 * rowBytes);

    await frame(1, ['a', 'b']);
    expect(told.last, 2 * rowBytes, reason: 'both were held already');

    await frame(2);
    expect(told.last, rowBytes, reason: 'no frame from 2 on shows b');

    rows.dispose();
    expect(told.last, 0);
    expect(aImage.debugDisposed, isTrue);
    expect(
      [for (var i = 1; i < told.length; i += 1) told[i] != told[i - 1]],
      everyElement(isTrue),
      reason: 'it is told only of a change',
    );
  });

  test('a picture that fails lets go of what was composed for it alone',
      () async {
    shows = {
      'a': [0, 1],
      'b': [0],
    };
    final fresh = <ui.Image>[];
    await expectLater(
      rows.during((asked) async {
        for (final cel in ['a', 'b']) {
          fresh.add((await asked.of(read(cel), compose)).image);
        }
        throw StateError('no raster');
      }),
      throwsStateError,
    );

    final [aImage, bImage] = fresh;
    expect(bImage.debugDisposed, isTrue, reason: 'no frame after 0 shows b');
    expect(aImage.debugDisposed, isFalse, reason: 'frame 1 shows a');
    expect(told.last, rowBytes, reason: 'the lender hears it');
  });

  group('a render that is handed rows', () {
    const canvas = CanvasSize(width: 8, height: 8);

    BitmapSurface ink() {
      final pixels = Uint8List(8 * 8 * 4);
      for (var i = 0; i < pixels.length; i += 4) {
        pixels[i] = 200;
        pixels[i + 3] = 255;
      }
      return BitmapSurface(
        canvasSize: canvas,
        tileSize: 8,
        tiles: {TileCoord(x: 0, y: 0): BitmapTile(size: 8, pixels: pixels)},
      );
    }

    Future<Uint8List> bytesOf(ui.Image image) async =>
        (await image.toByteData(
          format: ui.ImageByteFormat.rawRgba,
        ))!.buffer.asUint8List();

    Future<ui.Image> render(
      CutFrameCompositeLayer layer, {
      required bool displayLevels,
      RowPictures? rows,
    }) => const CameraFrameRenderService().renderThroughCamera(
      layers: [layer],
      pose: CameraPose(center: CanvasPoint(x: 4, y: 4)),
      cameraFrameSize: canvas,
      // A quarter: the level halves twice when asked to.
      outputSize: const CanvasSize(width: 2, height: 2),
      displayLevels: displayLevels,
      rows: rows,
    );

    for (final displayLevels in [false, true]) {
      testWidgets('🚨displayLevels $displayLevels: draws what it is handed, '
          'never lets it go, and draws what it would have composed', (
        tester,
      ) async {
        await tester.runAsync(() async {
          final layer = CutFrameCompositeLayer(surface: ink(), opacity: 1);
          final alone = await render(layer, displayLevels: displayLevels);
          final kept = <PositionedSurfaceImage>[];
          final handed = await render(
            layer,
            displayLevels: displayLevels,
            rows: _Keeping(kept),
          );

          expect(kept, hasLength(1), reason: 'LIVENESS: the row was asked');
          expect(kept.single.image.debugDisposed, isFalse);
          expect(await bytesOf(handed), await bytesOf(alone));
          kept.single.image.dispose();
          alone.dispose();
          handed.dispose();
        });
      });

      testWidgets('🚨displayLevels $displayLevels: with nobody keeping its '
          'rows, a render lets go of every picture it made but the one it '
          'hands back — and with a keeper, of all but the kept', (
        tester,
      ) async {
        await tester.runAsync(() async {
          final layer = CutFrameCompositeLayer(surface: ink(), opacity: 1);
          // Warm: the tiles' own pictures are the tile cache's to keep.
          (await render(layer, displayLevels: displayLevels)).dispose();
          final live = <Object>{};
          void count(ObjectEvent event) {
            if (event.object is! ui.Image) {
              return;
            }
            if (event is ObjectCreated) {
              live.add(event.object);
            } else if (event is ObjectDisposed) {
              live.remove(event.object);
            }
          }

          FlutterMemoryAllocations.instance.addListener(count);
          addTearDown(
            () => FlutterMemoryAllocations.instance.removeListener(count),
          );

          final alone = await render(layer, displayLevels: displayLevels);
          expect(live, {alone}, reason: 'the picture it handed back, alone');
          alone.dispose();

          final kept = <PositionedSurfaceImage>[];
          final handed = await render(
            layer,
            displayLevels: displayLevels,
            rows: _Keeping(kept),
          );
          expect(live, {handed, kept.single.image});
          handed.dispose();
          kept.single.image.dispose();
          expect(live, isEmpty);
        });
      });
    }
  });
}

/// Keeps every row it is asked for: composes it, and holds on to it.
final class _Keeping implements RowPictures {
  _Keeping(this.kept);

  final List<PositionedSurfaceImage> kept;

  @override
  Future<PositionedSurfaceImage> of(
    BitmapSurface surface,
    Future<PositionedSurfaceImage> Function() compose,
  ) async {
    final composed = await compose();
    kept.add(composed);
    return composed;
  }
}
