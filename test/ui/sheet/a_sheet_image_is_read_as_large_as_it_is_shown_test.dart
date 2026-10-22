import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cel_photo.dart';
import 'package:anicel/src/models/media_reference.dart';
import 'package:anicel/src/models/transform_pose.dart';
import 'package:anicel/src/ui/media/viewer_raster_budget.dart';
import 'package:anicel/src/ui/sheet/sheet_image_cache.dart';
import 'package:anicel/src/ui/sheet/sheet_photos.dart';

import '../../helpers/cel_photo_fixture.dart';
import '../../helpers/solid_png_fixture.dart';
import '../../helpers/temp_dir.dart';
import '../../helpers/the_file_itself.dart';

/// I-97 B2 — the sheets' media images (the logo, a cover's picture, the
/// photos on their ink) are read THROUGH THE PROJECT, AS LARGE AS SHOWN:
/// one read at a time, within one viewer's share of the device, the
/// carried copy first.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('sheet-images'));
  tearDown(() {
    ViewerRasterBudget.debugPageBytesOverride = null;
    deleteTempQuietly(dir);
  });

  Future<ui.Image> picture(int width, int height) {
    final recorder = ui.PictureRecorder();
    ui.Canvas(
      recorder,
    ).drawColor(const ui.Color(0xFF00FFFF), ui.BlendMode.src);
    return recorder.endRecording().toImage(width, height);
  }

  group('a sheet\'s image is read through the project (readSheetImage)', () {
    test('as wide as asked, its shape kept — and never wider than the '
        'file', () async {
      final path = await writeSolidPng(dir, 'logo.png', width: 8, height: 4);
      Future<(int, int)?> read(int? width) async {
        final image = await readSheetImage(theFileItself, path, width);
        if (image == null) {
          return null;
        }
        image.dispose();
        return (image.width, image.height);
      }

      expect(await read(4), (4, 2));
      expect(await read(null), (8, 4), reason: 'null is its own size');
      expect(await read(16), (8, 4), reason: 'a file has no more pixels');
    });

    test('🚨the carried copy wins: what the project answers for the path, '
        'not the file the path names', () async {
      final named = await writeSolidPng(dir, 'named.png', width: 8, height: 8);
      final carried = await writeSolidPng(
        dir,
        'carried.png',
        width: 6,
        height: 3,
      );
      final asked = <String>[];
      final image = await readSheetImage(
        (path) {
          asked.add(path);
          return theFileItself(carried);
        },
        named,
        null,
      );
      addTearDown(() => image?.dispose());

      expect(asked, [named], reason: 'the project is asked for the path');
      expect((image?.width, image?.height), (6, 3));
    });

    test('a file that cannot be read is null — a sheet prints the empty '
        'box', () async {
      final text = File('${dir.path}/not-a-picture.png')
        ..writeAsStringSync('not a picture');
      expect(await readSheetImage(theFileItself, text.path, null), isNull);
      expect(
        await readSheetImage(theFileItself, '${dir.path}/gone.png', 4),
        isNull,
      );
    });
  });

  group('the sheets\' image cache (SheetImageCache)', () {
    late _Reads reads;
    late List<int> told;
    late int landed;
    late SheetImageCache cache;

    void makeCache() {
      reads = _Reads();
      told = [];
      landed = 0;
      cache = SheetImageCache(read: reads.call, onHeldBytesChanged: told.add)
        ..addListener(() => landed += 1);
    }

    /// [path] at [width] asked for and landed with a [side]-pixel square.
    Future<ui.Image> hold(String path, int width, {int side = 4}) async {
      cache.imageFor(path, width: width);
      await pumpEventQueue();
      final image = await picture(side, side);
      await reads.land(image);
      return image;
    }

    test('🚨one read at a time — and what the sheets stopped asking for is '
        'never read', () async {
      makeCache();
      addTearDown(cache.dispose);

      // Two in one paint, then one more while the first is read.
      expect(cache.imageFor('a', width: 4), isNull);
      expect(cache.imageFor('b', width: 4), isNull);
      await pumpEventQueue();
      expect(cache.imageFor('c', width: 4), isNull);
      await pumpEventQueue();
      expect(reads.asked, [(path: 'a', width: 4)], reason: 'one at a time');

      await reads.land(await picture(4, 4));
      expect(landed, 1, reason: 'the sheets are told once');
      expect(
        reads.asked,
        hasLength(1),
        reason: 'the landing empties the list: the sheets ask again for '
            'what they show NOW',
      );

      cache.imageFor('d', width: 4);
      await pumpEventQueue();
      expect(
        reads.asked.last,
        (path: 'd', width: 4),
        reason: 'b and c, asked before the landing and not since, are not '
            'read',
      );
    });

    test('a width not in yet shows the sharpest held of the same picture, '
        'and is asked for', () async {
      makeCache();
      addTearDown(cache.dispose);
      await hold('a', 4, side: 4);
      final sharper = await hold('a', 8, side: 8);
      await hold('b', 16, side: 16);

      expect(identical(cache.imageFor('a', width: 16), sharper), isTrue);
      await pumpEventQueue();
      expect(reads.asked.last, (path: 'a', width: 16));
    });

    test('⛔a picture that cannot be read is not asked for again, at any '
        'width — what was read of it still shows', () async {
      makeCache();
      addTearDown(cache.dispose);
      final shown = await hold('a', 4);
      cache.imageFor('a', width: 8);
      await pumpEventQueue();
      await reads.land(null);
      final before = reads.asked.length;

      expect(identical(cache.imageFor('a', width: 8), shown), isTrue);
      expect(identical(cache.imageFor('a', width: 2), shown), isTrue);
      await pumpEventQueue();
      expect(reads.asked, hasLength(before));
    });

    test('what is held stays within one viewer\'s share — the least '
        'recently asked for let go first, never the one just read', () async {
      // A 4×4 picture is a page: the share is four of them.
      ViewerRasterBudget.debugPageBytesOverride = 4 * 4 * 4;
      makeCache();
      addTearDown(cache.dispose);
      final first = await hold('p0', 4);
      final second = await hold('p1', 4);
      await hold('p2', 4);
      await hold('p3', 4);
      expect(told.last, 4 * 64, reason: 'the census hears all four');
      // Asked for again: to the young end.
      expect(identical(cache.imageFor('p0', width: 4), first), isTrue);

      await hold('p4', 4);

      expect(identical(cache.imageFor('p0', width: 4), first), isTrue);
      expect(second.debugDisposed, isTrue, reason: 'p1 was the oldest ask');
      expect(cache.imageFor('p1', width: 4), isNull);
      expect(told.last, 4 * 64);
      expect(cache.decodedBytes, 4 * 64);
    });

    test('a picture larger than the whole share is still held — the one '
        'just read is never let go', () async {
      ViewerRasterBudget.debugPageBytesOverride = 4 * 4 * 4;
      makeCache();
      addTearDown(cache.dispose);
      final small = await hold('p0', 4);
      final big = await hold('big', 16, side: 16);

      expect(identical(cache.imageFor('big', width: 16), big), isTrue);
      expect(small.debugDisposed, isTrue, reason: 'all else goes');
      expect(cache.decodedBytes, 16 * 16 * 4);
      expect(told.last, 16 * 16 * 4);
    });

    test('the memory warning halves what is held', () async {
      ViewerRasterBudget.debugPageBytesOverride = 4 * 4 * 4;
      makeCache();
      addTearDown(cache.dispose);
      final held = [
        for (final path in ['p0', 'p1', 'p2', 'p3']) await hold(path, 4),
      ];
      final before = landed;

      cache.respondToMemoryPressure();

      expect(
        [for (final image in held) image.debugDisposed],
        [true, true, false, false],
      );
      expect(told.last, 2 * 64);
      expect(landed, before + 1, reason: 'the sheets showing them repaint');
    });

    test('a cache let go of tells the census zero, and lets go of a read '
        'that lands after it', () async {
      makeCache();
      final held = await hold('a', 4);
      cache.imageFor('b', width: 4);
      await pumpEventQueue();

      cache.dispose();
      final tooLate = await picture(4, 4);
      await reads.land(tooLate);

      expect(told.last, 0);
      expect(held.debugDisposed, isTrue);
      expect(tooLate.debugDisposed, isTrue);
      expect(cache.imageFor('c', width: 4), isNull);
      await pumpEventQueue();
      expect(reads.asked.last.path, 'b', reason: 'nothing is read after');
    });

    test('a cache let go of before its read starts reads nothing', () async {
      makeCache();
      cache.imageFor('a', width: 4);
      cache.dispose();
      await pumpEventQueue();

      expect(reads.asked, isEmpty);
    });
  });

  group('an export reads what its sheet asks for (SheetImageRun)', () {
    test('a sheet paints once to say what it asks for, and again with it in '
        'hand — each picture read once', () async {
      final asked = <({String path, int? width})>[];
      final file = await picture(4, 4);
      addTearDown(file.dispose);
      final run = SheetImageRun((path, width) async {
        asked.add((path: path, width: width));
        return file.clone();
      });
      addTearDown(run.dispose);
      final got = <ui.Image?>[];

      await paintWithSheetImages(
        ui.Canvas(ui.PictureRecorder()),
        run,
        (canvas) {
          got.add(run.imageFor('a', width: 3));
          run.imageFor('a', width: 3);
        },
      );

      expect(got, hasLength(2));
      expect(got.first, isNull);
      expect(got.last, isNotNull);
      expect(asked, [(path: 'a', width: 3)]);
    });

    test('a paint that asks for nothing is painted once — and drawn', () async {
      final run = SheetImageRun((path, width) async => null);
      var painted = 0;
      final recorder = ui.PictureRecorder();

      await paintWithSheetImages(ui.Canvas(recorder), run, (canvas) {
        painted += 1;
        canvas.drawRect(
          const ui.Rect.fromLTWH(0, 0, 2, 2),
          ui.Paint()..color = const ui.Color(0xFFFF0000),
        );
      });
      final image = await recorder.endRecording().toImage(2, 2);
      addTearDown(image.dispose);
      final bytes = await image.toByteData();

      expect(painted, 1);
      expect(bytes!.getUint8(0), 255, reason: 'the first pass, drawn');
    });

    test('with no images to be had, it is painted once with none', () async {
      var painted = 0;
      await paintWithSheetImages(
        ui.Canvas(ui.PictureRecorder()),
        null,
        (canvas) => painted += 1,
      );
      expect(painted, 1);
    });
  });

  group('a photo asks for the pixels it is drawn at (paintSheetPhotos)', () {
    int? widthAsked(CelPhoto photo, double displayScale) {
      int? asked;
      paintSheetPhotos(
        ui.Canvas(ui.PictureRecorder()),
        [photo],
        imageFor: (path, {width}) {
          asked = width;
          return null;
        },
        displayScale: displayScale,
      );
      return asked;
    }

    final photo = photoOf(1, size: const CanvasSize(width: 64, height: 32));

    test('the viewer\'s ladder over its own pixels — rounded up, and never '
        'past them', () {
      expect(widthAsked(photo, 0.25), 16);
      expect(widthAsked(photo, 0.3), 32, reason: 'at least what is drawn');
      expect(widthAsked(photo, 1), 64);
      expect(widthAsked(photo, 3), 64, reason: 'the file has no more');
    });

    test('on its more magnified axis', () {
      final stretched = CelPhoto(
        id: 1,
        reference: MediaReference(
          assetPath: 'C:/pool/photo.png',
          pose: TransformPose(
            center: CanvasPoint(x: 10, y: 6),
            scaleX: 2,
            scaleY: -0.5,
          ),
          pictureSize: const CanvasSize(width: 64, height: 32),
        ),
      );
      expect(widthAsked(stretched, 0.25), 32);
    });
  });
}

/// Reads a test lands by hand, oldest first ([land]) — and every one that
/// was asked for, in order ([asked]).
class _Reads {
  final asked = <({String path, int? width})>[];
  final _out = <Completer<ui.Image?>>[];

  Future<ui.Image?> call(String path, int? width) {
    asked.add((path: path, width: width));
    final read = Completer<ui.Image?>();
    _out.add(read);
    return read.future;
  }

  /// Lands the oldest read still out with [image], and lets the cache hear.
  Future<void> land(ui.Image? image) async {
    _out.removeAt(0).complete(image);
    await pumpEventQueue();
  }
}
