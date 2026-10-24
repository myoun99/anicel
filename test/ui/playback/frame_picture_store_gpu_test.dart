@Tags(['gpu'])
library;

import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:anicel/src/ui/playback/frame_picture_store.dart';
import 'package:flutter_gpu/gpu.dart' as gpu;
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/poll_until.dart';

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
      await store.settled();
      expect(store.peek('after'), same(patched));
      expect(patched.landing, isEmpty);

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
    skip: _noFlutterGpu,
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
      await store.settled();
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
    skip: _noFlutterGpu,
  );

  test(
    'patches laid as one at the cap show what they were drawn over the '
    'picture, and land as the picture laid with them all',
    () async {
      final store = FramePictureStore<String>(
        levelsQuiet: const Duration(days: 1),
        levelsWaitAtMost: 2,
      );
      const extent = ui.Rect.fromLTWH(0, 0, side + 0.0, side + 0.0);
      const strokes = [
        (ui.Rect.fromLTWH(480, 490, 61, 50), ui.Color(0xFFFFEE00)),
        (ui.Rect.fromLTWH(601, 703, 45, 70), ui.Color(0xFF20C040)),
        (ui.Rect.fromLTWH(530, 470, 33, 64), ui.Color(0xFF8020C0)),
      ];
      void Function(ui.Canvas) upTo(int count) => (canvas) {
        frame(canvas);
        for (final (rect, colour) in strokes.take(count)) {
          canvas.drawRect(rect, ui.Paint()..color = colour);
        }
      };
      Future<FramePicture> fresh(int count) async => (await store.lay(
        'fresh $count',
        (
          extent: extent,
          outside: const ui.Color(0xFFFFFFFF),
          draw: upTo(count),
        ),
      ))!;
      final patched = (await store.lay('0', (
        extent: extent,
        outside: const ui.Color(0xFFFFFFFF),
        draw: frame,
      )))!;
      for (var index = 0; index < 2; index += 1) {
        store.patch(
          from: '$index',
          to: '${index + 1}',
          rect: strokes[index].$1,
          draw: upTo(index + 1),
        );
      }
      final spanning = strokes[0].$1.expandToInclude(strokes[1].$1);
      expect(
        await pollUntil(
          () =>
              patched.landing.length == 1 &&
              patched.landing.single.rect.contains(spanning.topLeft) &&
              patched.landing.single.rect.contains(
                spanning.bottomRight - const ui.Offset(1, 1),
              ),
        ),
        isTrue,
        reason: 'the two laid as one',
      );
      expect(
        _mostApart(
          await _shown(patched),
          (await _levels((await fresh(2)).image)).first,
        ),
        lessThanOrEqualTo(1),
        reason: 'the picture with the one over it is the frame with both',
      );

      store.patch(from: '2', to: '3', rect: strokes[2].$1, draw: upTo(3));
      await store.settled();
      expect(patched.landing, isEmpty);
      final want = await _levels((await fresh(3)).image);
      final got = await _levels(patched.image);
      for (var level = 0; level < want.length; level += 1) {
        expect(
          _mostApart(got[level], want[level]),
          lessThanOrEqualTo(1),
          reason: 'level $level',
        );
      }
      store.dispose();
    },
    skip: _noFlutterGpu,
  );
}

/// [picture] as a 100% view draws it: its image, each of its landing
/// patches over its place with `BlendMode.src`.
Future<Uint8List> _shown(FramePicture picture) async {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder)
    ..drawImage(picture.image, ui.Offset.zero, ui.Paint());
  for (final patch in picture.landing) {
    canvas.drawImageRect(
      patch.image,
      ui.Rect.fromLTWH(
        0,
        0,
        patch.image.width.toDouble(),
        patch.image.height.toDouble(),
      ),
      patch.rect.shift(-picture.extent.topLeft),
      ui.Paint()..blendMode = ui.BlendMode.src,
    );
  }
  final drawn = recorder.endRecording();
  final image = await drawn.toImage(picture.image.width, picture.image.height);
  drawn.dispose();
  final bytes = (await image.toByteData())!.buffer.asUint8List();
  image.dispose();
  return bytes;
}

/// Why this runner cannot write into a picture, or null when it can.
final String? _noFlutterGpu = () {
  try {
    gpu.gpuContext;
    return null;
  } on Exception catch (error) {
    return 'needs Impeller with Flutter GPU — run with '
        '`flutter test --enable-impeller --enable-flutter-gpu`: $error';
  }
}();

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
