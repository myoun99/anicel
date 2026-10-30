@Tags(['gpu'])
library;

import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:anicel/src/ui/playback/flutter_gpu_copies.dart';
import 'package:anicel/src/ui/playback/frame_picture_gpu.dart';
import 'package:anicel/src/ui/playback/frame_picture_store.dart';
import 'package:flutter_gpu/gpu.dart' as gpu;
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/a_canvas_standing_on_a_frame.dart' show noFlutterGpu;

/// 🚨★★★A PATCHED PICTURE IS THE PICTURE LAID WITH THE PATCH IN IT — at
/// every level of its mip chain, which is what a zoomed-out view draws.
///
/// The writes are `flutter_gpu`'s, which needs Impeller:
/// `flutter test --enable-impeller --enable-flutter-gpu <this file>`. On a
/// runner without it the test is skipped, and says so — not deleted, not
/// left out (관제 10-24, gpu-pins-run-in-a-batch-of-their-own).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const side = 1024;
  // Off the store's grid (4 at 1024) on every side and across the red and
  // blue's edge: the store widens it, and the frame's own drawing fills
  // what it widens over.
  const patch = ui.Rect.fromLTWH(501, 503, 37, 41);

  void frame(ui.Canvas canvas) {
    canvas
      ..drawRect(
        const ui.Rect.fromLTWH(0, 0, side / 2, side + 0.0),
        ui.Paint()..color = const ui.Color(0xFFCC2020),
      )
      ..drawRect(
        const ui.Rect.fromLTWH(side / 2, 0, side / 2, side + 0.0),
        ui.Paint()..color = const ui.Color(0xFF2040CC),
      );
  }

  void withPatch(ui.Canvas canvas) {
    frame(canvas);
    canvas
      ..save()
      ..clipRect(patch)
      ..drawPaint(ui.Paint()..color = const ui.Color(0xFFFFEE00))
      ..restore();
  }

  test(
    'every level of a patched picture is the level of the picture laid '
    'with the patch in it',
    () async {
      final store = FramePictureStore<String>();
      const extent = ui.Rect.fromLTWH(0, 0, side + 0.0, side + 0.0);
      final patched = await store.lay('before', (
        extent: extent,
        outside: const ui.Color(0xFFFFFFFF),
        draw: frame,
      ));
      final untouched = await _levels(patched!.image);
      expect(
        store.patch(from: 'before', to: 'after', rect: patch, draw: withPatch),
        isTrue,
      );
      // Answered the moment every level holds it: what a screen shows
      // under that key from then on is the picture alone.
      await store.landingOf('after');
      expect(store.peek('after'), same(patched));

      final fresh = await store.lay('fresh', (
        extent: extent,
        outside: const ui.Color(0xFFFFFFFF),
        draw: withPatch,
      ));
      final want = await _levels(fresh!.image);
      final got = await _levels(patched.image);
      for (var level = 0; level < want.length; level += 1) {
        expect(
          _mostApart(got[level], want[level]),
          lessThanOrEqualTo(1),
          reason: 'level $level',
        );
        if (level <= 6) {
          expect(
            _mostApart(got[level], untouched[level]),
            greaterThan(0),
            reason: 'level $level shows the patch',
          );
        }
      }
      store.dispose();
    },
    skip: noFlutterGpu,
  );

  test(
    'patches asked back to back land as the picture laid with them all, '
    'a later one over an earlier at every level',
    () async {
      final store = FramePictureStore<String>();
      const extent = ui.Rect.fromLTWH(0, 0, side + 0.0, side + 0.0);
      // Each overlaps the one before it; the frame each patch draws is the
      // frame with every stroke so far.
      const strokes = [
        (ui.Rect.fromLTWH(480, 490, 61, 50), ui.Color(0xFFFFEE00)),
        (ui.Rect.fromLTWH(509, 503, 45, 70), ui.Color(0xFF20C040)),
        (ui.Rect.fromLTWH(530, 470, 33, 64), ui.Color(0xFF8020C0)),
      ];
      void Function(ui.Canvas) upTo(int count) => (canvas) {
        frame(canvas);
        for (final (rect, colour) in strokes.take(count)) {
          canvas.drawRect(rect, ui.Paint()..color = colour);
        }
      };
      final patched = await store.lay('0', (
        extent: extent,
        outside: const ui.Color(0xFFFFFFFF),
        draw: frame,
      ));
      for (final (index, (rect, _)) in strokes.indexed) {
        expect(
          store.patch(
            from: '$index',
            to: '${index + 1}',
            rect: rect,
            draw: upTo(index + 1),
          ),
          isTrue,
        );
      }
      await store.landingOf('${strokes.length}');
      expect(store.peek('${strokes.length}'), same(patched));

      final fresh = await store.lay('fresh', (
        extent: extent,
        outside: const ui.Color(0xFFFFFFFF),
        draw: upTo(strokes.length),
      ));
      final want = await _levels(fresh!.image);
      final got = await _levels(patched!.image);
      for (var level = 0; level < want.length; level += 1) {
        expect(
          _mostApart(got[level], want[level]),
          lessThanOrEqualTo(1),
          reason: 'level $level',
        );
      }
      store.dispose();
    },
    skip: noFlutterGpu,
  );

  // 🚨★★★F-509 (iPhone and iPad, 1079–1083): the screen is drawn again only
  // where its drawing changed, an image told apart by its identity — a
  // write into the image a screen drew showed nowhere. Every runner draws
  // the whole screen, so the pixels cannot pin it: the identity does.
  test(
    'a picture written into is a new image over the same texels, and says '
    'so to whoever draws it',
    () async {
      final store = FramePictureStore<String>();
      const extent = ui.Rect.fromLTWH(0, 0, side + 0.0, side + 0.0);
      final picture = await store.lay('before', (
        extent: extent,
        outside: const ui.Color(0xFFFFFFFF),
        draw: frame,
      ));
      // What a screen drew: a handle of its own on the image it was.
      final drawn = picture!.image.clone();
      var told = 0;
      picture.addListener(() => told += 1);
      expect(
        store.patch(from: 'before', to: 'after', rect: patch, draw: withPatch),
        isTrue,
      );
      await store.landingOf('after');

      expect(store.peek('after'), same(picture));
      expect(
        picture.image.isCloneOf(drawn),
        isFalse,
        reason: 'the image drawn before the write is not the one after it',
      );
      expect(told, 1, reason: 'whoever draws it is told, once a write');
      final before = await _levels(drawn);
      final after = await _levels(picture.image);
      expect(
        _mostApart(before.first, after.first),
        0,
        reason: 'one texture, written once — no texel copied',
      );
      drawn.dispose();
      store.dispose();
    },
    skip: noFlutterGpu,
  );

  test(
    'a move that carries no texels leaves its picture the image it was',
    () async {
      final store = FramePictureStore<String>();
      const extent = ui.Rect.fromLTWH(0, 0, side + 0.0, side + 0.0);
      final picture = await store.lay('before', (
        extent: extent,
        outside: const ui.Color(0xFFFFFFFF),
        draw: frame,
      ));
      final drawn = picture!.image;
      var told = 0;
      picture.addListener(() => told += 1);
      expect(store.move(from: 'before', to: 'after'), isTrue);
      await store.landingOf('after');

      expect(store.peek('after'), same(picture));
      // ⚠️Told by identity, not `same`: a mismatch would print the image a
      // write let go of.
      expect(
        identical(picture.image, drawn),
        isTrue,
        reason: 'a move writes no texel: the image a screen drew stands',
      );
      expect(told, 0, reason: 'no screen is told of a move');
      store.dispose();
    },
    skip: noFlutterGpu,
  );

  test('a texel flutter_gpu has no name for is BGRA10_XR, eight bytes — a '
      'write into it is not sized at nothing (F-509-Q9)', () {
    expect(FlutterGpuFramePictures.bytesPerTexel(gpu.PixelFormat.unknown), 8);
    for (final format in [
      gpu.PixelFormat.r8g8b8a8UNormInt,
      gpu.PixelFormat.b8g8r8a8UNormInt,
    ]) {
      expect(FlutterGpuFramePictures.bytesPerTexel(format), 4);
    }
  });

  test(
    'past the Dart check the engine still refuses a length that is not the '
    "region's (F-509-Q10)",
    () {
      final context = gpu.gpuContext;
      final texture = context.createTexture(
        gpu.StorageMode.devicePrivate,
        4,
        4,
        format: gpu.PixelFormat.r8g8b8a8UNormInt,
      );
      final buffer = context.createDeviceBuffer(
        gpu.StorageMode.devicePrivate,
        4 * 4 * 4,
      );
      void copy(int lengthInBytes) => copyBufferIntoTexture(
        context.createCommandBuffer(),
        buffer,
        offsetInBytes: 0,
        lengthInBytes: lengthInBytes,
        destination: texture,
        x: 0,
        y: 0,
        width: 4,
        height: 4,
        mipLevel: 0,
      );

      copy(4 * 4 * 4);
      expect(() => copy(4 * 4 * 4 - 1), throwsException);
    },
    skip: noFlutterGpu,
  );
}

/// [image] at every level of its chain, as a zoomed-out view draws it:
/// at 1/2^k under `FilterQuality.medium`.
Future<List<Uint8List>> _levels(ui.Image image) async {
  final levels = <Uint8List>[];
  for (var k = 0; (image.width >> k) >= 1; k += 1) {
    final size = image.width >> k;
    final recorder = ui.PictureRecorder();
    ui.Canvas(recorder).drawImageRect(
      image,
      ui.Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
      ui.Rect.fromLTWH(0, 0, size.toDouble(), size.toDouble()),
      ui.Paint()..filterQuality = ui.FilterQuality.medium,
    );
    final picture = recorder.endRecording();
    final drawn = await picture.toImage(size, size);
    picture.dispose();
    levels.add((await drawn.toByteData())!.buffer.asUint8List());
    drawn.dispose();
  }
  return levels;
}

int _mostApart(Uint8List a, Uint8List b) {
  var most = 0;
  for (var i = 0; i < a.length; i += 1) {
    final apart = (a[i] - b[i]).abs();
    if (apart > most) {
      most = apart;
    }
  }
  return most;
}
