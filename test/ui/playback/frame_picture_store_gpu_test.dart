@Tags(['gpu'])
library;

import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:anicel/src/models/canvas_viewport.dart';
import 'package:anicel/src/ui/canvas/display_resample.dart'
    show drawOnTheDisplay;
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
      // Answered the moment every level a screen reads holds it: what a
      // screen shows under that key from then on is the picture alone.
      await store.landingOf('after');
      expect(store.peek('after'), same(patched));
      await store.settled();

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
    'every level of a picture widened, a patch across its old edge, is the '
    'level of the picture laid over all of it (F-533)',
    () async {
      void past(ui.Canvas canvas) {
        frame(canvas);
        canvas.drawRect(
          const ui.Rect.fromLTRB(-256, -128, side + 128, 0),
          ui.Paint()..color = const ui.Color(0xFF20C040),
        );
        canvas.drawRect(
          const ui.Rect.fromLTRB(-256, 0, 0, side + 0.0),
          ui.Paint()..color = const ui.Color(0x80C0C020),
        );
      }

      const across = ui.Rect.fromLTWH(-19, 301, 37, 41);
      void pastWithPatch(ui.Canvas canvas) {
        past(canvas);
        canvas
          ..save()
          ..clipRect(across)
          ..drawPaint(ui.Paint()..color = const ui.Color(0xFFFFEE00))
          ..restore();
      }

      final store = FramePictureStore<String>();
      const extent = ui.Rect.fromLTWH(0, 0, side + 0.0, side + 0.0);
      final widened = await store.lay('before', (
        extent: extent,
        outside: const ui.Color(0xFFFFFFFF),
        draw: frame,
      ));
      // The way a stroke goes: a step in it first, its levels waiting.
      store.patch(from: 'before', to: 'stepped', rect: patch, draw: withPatch);
      await store.landingOf('stepped');
      final room = store.widen(
        key: 'stepped',
        over: const ui.Rect.fromLTRB(-200, -5, side + 0.0, side + 0.0),
        draw: past,
      );
      expect(room, const ui.Rect.fromLTRB(-256, -128, side + 0.0, side + 0.0));
      expect(
        store.patch(
          from: 'stepped',
          to: 'after',
          rect: across,
          draw: pastWithPatch,
        ),
        isTrue,
      );
      expect(await store.landingOf('after'), isTrue);
      expect(store.peek('after'), same(widened));
      widened!.readAt(0.25);
      await store.settled();

      final fresh = await store.lay('fresh', (
        extent: room!,
        outside: const ui.Color(0xFFFFFFFF),
        draw: (canvas) {
          pastWithPatch(canvas);
          canvas
            ..save()
            ..clipRect(patch)
            ..drawPaint(ui.Paint()..color = const ui.Color(0xFFFFEE00))
            ..restore();
        },
      ));
      final want = await _levels(fresh!.image);
      final got = await _levels(widened.image);
      expect(got.length, want.length);
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
      await store.settled();

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

  // 🚨★★★F-512: a step writes no level under what the screen says it reads,
  // so the screen must read no level under what it says: a picture behind
  // the rest is drawn as the picture laid whole.
  test(
    'a screen draws a picture behind the levels it does not read as the '
    'picture laid with the patch in it',
    () async {
      const extent = ui.Rect.fromLTWH(0, 0, side + 0.0, side + 0.0);
      Future<int> apartAt(double scale, {required double toldAt}) async {
        final store = FramePictureStore<String>();
        final behind = await store.lay('before', (
          extent: extent,
          outside: const ui.Color(0xFFFFFFFF),
          draw: frame,
        ));
        behind!.readAt(toldAt);
        store.patch(from: 'before', to: 'after', rect: patch, draw: withPatch);
        await store.landingOf('after');
        final fresh = await store.lay('fresh', (
          extent: extent,
          outside: const ui.Color(0xFFFFFFFF),
          draw: withPatch,
        ));
        final apart = _mostApart(
          await _onScreen(behind.image, scale),
          await _onScreen(fresh!.image, scale),
        );
        store.dispose();
        return apart;
      }

      for (final scale in const [
        1.0,
        0.75,
        0.6,
        0.5,
        0.44,
        0.3,
        0.25,
        0.2,
        0.125,
      ]) {
        expect(
          await apartAt(scale, toldAt: scale),
          lessThanOrEqualTo(1),
          reason: 'at $scale',
        );
      }
      for (final scale in const [0.44, 0.3, 0.2]) {
        expect(
          await apartAt(scale, toldAt: 1),
          greaterThan(1),
          reason: '⛔premise: at $scale the level it reads shows',
        );
      }
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

  // 🚨a-picture-lay-holds-the-raster-thread: a picture over more than a
  // piece is written into a texture made whole, a piece at a time.
  test(
    'a picture laid a piece at a time is, at every level, the picture '
    'rastered at once — its texture made in the format a raster is',
    () async {
      final pictures = FlutterGpuFramePictures();
      final context = gpu.gpuContext;
      // Three pieces across, two down, the last of each a part: the light
      // runs across every edge between them.
      const extent = ui.Rect.fromLTWH(0, 0, 1280, 768);
      void across(ui.Canvas canvas) {
        canvas.drawRect(
          extent,
          ui.Paint()
            ..shader = ui.Gradient.linear(
              ui.Offset.zero,
              const ui.Offset(1280, 768),
              const [ui.Color(0xFFCC2020), ui.Color(0x402040CC)],
            ),
        );
        for (var at = 0; at < 9; at += 1) {
          canvas.drawCircle(
            ui.Offset(256.0 + at * 97, 300.0 + (at % 3) * 150),
            61,
            ui.Paint()..color = const ui.Color(0xC0FFEE00),
          );
        }
      }

      final store = FramePictureStore<String>(onceSide: 512, pieceSide: 512);
      final laid = await store.lay('a', (
        extent: extent,
        outside: const ui.Color(0x00000000),
        draw: across,
      ));
      final recorded = recordedOver(extent, across);
      final whole = await recorded.toImage(1280, 768);
      recorded.dispose();

      expect(
        gpu.Texture.fromImage(context, whole).format,
        context.defaultColorFormat,
        reason: 'the texture a lay is written into is made in it',
      );
      expect(
        pictures.levelsOf(pictures.hold(laid!.image)!),
        pictures.levelsOf(pictures.hold(whole)!),
        reason: 'the chain of a picture rastered at once',
      );
      final want = await _levels(whole);
      final got = await _levels(laid.image);
      expect(got, hasLength(want.length));
      for (var level = 0; level < want.length; level += 1) {
        expect(
          _mostApart(got[level], want[level]),
          lessThanOrEqualTo(1),
          reason: 'level $level',
        );
      }
      whole.dispose();
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
        gpu.BufferView(
          buffer,
          offsetInBytes: 0,
          lengthInBytes: lengthInBytes,
        ),
        gpu.TextureRegion(texture, width: 4, height: 4),
      );

      copy(4 * 4 * 4);
      expect(() => copy(4 * 4 * 4 - 1), throwsException);

      void copyOut(gpu.DeviceBuffer into) =>
          copyTextureIntoBuffer(context.createCommandBuffer(), texture, into);

      copyOut(buffer);
      expect(
        () => copyOut(
          context.createDeviceBuffer(
            gpu.StorageMode.devicePrivate,
            4 * 4 * 4 - 1,
          ),
        ),
        throwsException,
      );
    },
    skip: noFlutterGpu,
  );
}

/// [image] at every level of its chain, as a zoomed-out view draws it:
/// at 1/2^k under `FilterQuality.medium`.
///
/// On a handle of its own, as a screen holds one: a picture's image is let
/// go of when the levels its patches owe are written, 200 ms on, and a
/// machine under load has that between two of these levels.
Future<List<Uint8List>> _levels(ui.Image image) async {
  final held = image.clone();
  final levels = <Uint8List>[];
  for (
    var k = 0;
    (held.width >> k) >= 1 && (held.height >> k) >= 1;
    k += 1
  ) {
    final width = held.width >> k;
    final height = held.height >> k;
    final recorder = ui.PictureRecorder();
    ui.Canvas(recorder).drawImageRect(
      held,
      ui.Rect.fromLTWH(0, 0, held.width.toDouble(), held.height.toDouble()),
      ui.Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
      ui.Paint()..filterQuality = ui.FilterQuality.medium,
    );
    final picture = recorder.endRecording();
    final drawn = await picture.toImage(width, height);
    picture.dispose();
    levels.add((await drawn.toByteData())!.buffer.asUint8List());
    drawn.dispose();
  }
  held.dispose();
  return levels;
}

/// [image] on a screen at display [scale], as a frame's picture is drawn.
Future<Uint8List> _onScreen(ui.Image image, double scale) async {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder)..scale(scale);
  final whole = ui.Rect.fromLTWH(
    0,
    0,
    image.width.toDouble(),
    image.height.toDouble(),
  );
  drawOnTheDisplay(
    canvas,
    image,
    whole,
    whole,
    viewport: CanvasViewport(zoom: scale),
    devicePixelRatio: 1,
  );
  final picture = recorder.endRecording();
  final size = (image.width * scale).ceil();
  final drawn = await picture.toImage(size, size);
  picture.dispose();
  final bytes = (await drawn.toByteData())!.buffer.asUint8List();
  drawn.dispose();
  return bytes;
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
