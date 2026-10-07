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

/// The row pictures a video run's held cut pictures are made of (F-289-Q21,
/// 유저 2026-10-07: 「붙든다 — 재생 줄의 허용치 안에서」): a row a held
/// picture is made of composes once for every picture after it that shows
/// it, and goes when the last of them does — within the room playback's
/// line lends.
void main() {
  /// A 2×2 row picture's bytes.
  const rowBytes = 2 * 2 * 4;

  late int heldBefore;
  late List<int> told;
  late HeldRows rows;
  late int room;

  /// Every picture [compose] made, in the order it made them.
  final composed = <ui.Image>[];

  /// Every picture key a test made a picture under.
  final keys = <Object>{};

  setUp(() {
    heldBefore = HeldRows.debugHeld;
    told = [];
    room = 1 << 30;
    rows = HeldRows(room: () => room, onHeld: told.add);
    composed.clear();
    keys.clear();
  });

  tearDown(() {
    keys.forEach(rows.letGoOf);
    expect(
      HeldRows.debugHeld,
      heldBefore,
      reason: 'every picture let go: nothing left held',
    );
  });

  BitmapSurface surface(int seed) => BitmapSurface(
    canvasSize: const CanvasSize(width: 2, height: 2),
    tileSize: 2,
    tiles: {
      TileCoord(x: 0, y: 0): BitmapTile(
        size: 2,
        pixels: Uint8List(16)..fillRange(0, 16, seed),
      ),
    },
  );

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

  /// One picture under [key], made of [surfaces] in that order — what it
  /// was handed for each.
  Future<List<ui.Image>> picture(Object key, List<BitmapSurface> surfaces) {
    keys.add(key);
    return rows.during(key, (asked) async {
      return [
        for (final surface in surfaces)
          (await asked.of(surface, compose)).image,
      ];
    });
  }

  test('🎯a row a held picture is made of composes ONCE for the picture '
      'after it — the same picture, handed again', () async {
    final a = surface(1);
    final [aFirst, _] = await picture('p1', [a, surface(2)]);
    final [aAgain, _] = await picture('p2', [a, surface(3)]);

    expect(identical(aAgain, aFirst), isTrue);
    expect(rows.made, 3, reason: 'a once, then b and c');
    expect(composed, hasLength(3));
  });

  test('🚨a row goes when the LAST held picture made of it does, and not '
      'before', () async {
    final a = surface(1);
    final [aImage, bImage] = await picture('p1', [a, surface(2)]);
    final [_, cImage] = await picture('p2', [a, surface(3)]);

    rows.letGoOf('p1');
    expect(bImage.debugDisposed, isTrue, reason: 'only p1 was made of b');
    expect(aImage.debugDisposed, isFalse, reason: 'p2 is made of a too');
    expect(HeldRows.debugHeld - heldBefore, 2);

    rows.letGoOf('p2');
    expect(aImage.debugDisposed, isTrue);
    expect(cImage.debugDisposed, isTrue);
    expect(HeldRows.debugHeld, heldBefore);
  });

  test('a surface read again is another object, and composes again — a row '
      'is held under the surface itself', () async {
    await picture('p1', [surface(1)]);
    await picture('p2', [surface(1)]);

    expect(rows.made, 2, reason: 'equal surfaces, two objects');
  });

  test('a row asked for twice by one picture is held once, and goes with '
      'it', () async {
    final a = surface(1);
    final [first, second] = await picture('p1', [a, a]);

    expect(identical(first, second), isTrue);
    expect(rows.made, 1);
    rows.letGoOf('p1');
    expect(first.debugDisposed, isTrue, reason: 'one picture, one hold');
  });

  test('🚨a row that does not fit in the room is composed for its picture '
      'alone, and let go the moment that picture is made', () async {
    room = rowBytes;
    final a = surface(1);
    final b = surface(2);
    final [aImage, bImage] = await picture('p1', [a, b]);

    expect(aImage.debugDisposed, isFalse, reason: 'a fit: held');
    expect(bImage.debugDisposed, isTrue, reason: 'b did not: let go');
    expect(HeldRows.debugHeld - heldBefore, 1);

    await picture('p2', [a, b]);
    expect(rows.made, 3, reason: 'a held; b composed again');
  });

  test('the room is asked when a row would be held, so a line that gives '
      'more holds more', () async {
    room = 0;
    await picture('p1', [surface(1)]);
    expect(HeldRows.debugHeld, heldBefore, reason: 'no room: none held');

    room = rowBytes;
    await picture('p2', [surface(2)]);
    expect(HeldRows.debugHeld - heldBefore, 1);
  });

  test('🎯the lender hears what is held each time it changes, and 0 when '
      'the last row goes', () async {
    final a = surface(1);
    await picture('p1', [a, surface(2)]);
    expect(told.last, 2 * rowBytes);

    await picture('p2', [a]);
    expect(told.last, 2 * rowBytes, reason: 'a was held already');

    rows.letGoOf('p1');
    expect(told.last, rowBytes, reason: 'b went; a stays with p2');

    rows.letGoOf('p2');
    expect(told.last, 0);
    expect(
      [for (var i = 1; i < told.length; i += 1) told[i] != told[i - 1]],
      everyElement(isTrue),
      reason: 'it is told only of a change',
    );
  });

  test('a picture that fails holds nothing new — and the rows it shared '
      'with a held one stay held', () async {
    final a = surface(1);
    final [aImage] = await picture('p1', [a]);

    final fresh = <ui.Image>[];
    await expectLater(
      rows.during('p2', (asked) async {
        await asked.of(a, compose);
        fresh.add((await asked.of(surface(2), compose)).image);
        throw StateError('no raster');
      }),
      throwsStateError,
    );

    expect(fresh.single.debugDisposed, isTrue, reason: 'p2 holds nothing');
    expect(aImage.debugDisposed, isFalse, reason: 'p1 still holds a');
    rows.letGoOf('p1');
    expect(aImage.debugDisposed, isTrue, reason: 'p2 left no hold on it');
    expect(HeldRows.debugHeld, heldBefore);
  });

  test('a picture made again under its key lets go of what the one before '
      'held, after taking what they share', () async {
    final a = surface(1);
    final [aImage, bImage] = await picture('p', [a, surface(2)]);
    await picture('p', [a]);

    expect(aImage.debugDisposed, isFalse);
    expect(bImage.debugDisposed, isTrue);
    expect(HeldRows.debugHeld - heldBefore, 1);
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
