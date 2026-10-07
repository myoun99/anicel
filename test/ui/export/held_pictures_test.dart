import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/ui/export/held_pictures.dart';

/// The pictures a run of frames is made of, each held for one frame after
/// the last frame that asked for it (F-289): what makes a frame that is the
/// frame before it cost nothing, and what lets go of a picture nobody asks
/// for any more.
void main() {
  late HeldPictures pictures;
  late int heldBefore;

  /// Every picture made here, in the order it was made.
  final made = <ui.Image>[];

  setUp(() {
    pictures = HeldPictures();
    heldBefore = HeldPictures.debugHeld;
    made.clear();
  });

  tearDown(() {
    pictures.dispose();
    expect(HeldPictures.debugHeld, heldBefore, reason: 'nothing left held');
  });

  Future<ui.Image> render() async {
    final recorder = ui.PictureRecorder();
    ui.Canvas(recorder).drawColor(const ui.Color(0xFF204060), ui.BlendMode.src);
    final image = await recorder.endRecording().toImage(2, 2);
    made.add(image);
    return image;
  }

  test('a picture asked for twice in one frame is made once, and is one '
      'picture', () async {
    final first = await pictures.of('a', render);
    final again = await pictures.of('a', render);

    expect(identical(again, first), isTrue);
    expect(pictures.made, 1);
    expect(HeldPictures.debugHeld - heldBefore, 1);
  });

  test('🚨the next frame asking for it gets the picture it was — nothing is '
      'made, however long the run of frames', () async {
    final first = await pictures.of('a', render);
    for (var frame = 0; frame < 5; frame += 1) {
      pictures.nextFrame();
      expect(identical(await pictures.of('a', render), first), isTrue);
    }
    expect(pictures.made, 1);
    expect(first.debugDisposed, isFalse);
  });

  test('another key is another picture, and both are held', () async {
    final a = await pictures.of('a', render);
    final b = await pictures.of(('a', 1), render);

    expect(identical(a, b), isFalse);
    expect(pictures.made, 2);
    expect(HeldPictures.debugHeld - heldBefore, 2);
  });

  test('🚨a picture stays for ONE frame that does not ask for it, and is let '
      'go when the frame after that starts', () async {
    final a = await pictures.of('a', render);

    pictures.nextFrame();
    await pictures.of('b', render);
    expect(a.debugDisposed, isFalse, reason: 'the frame before\'s, still');

    pictures.nextFrame();
    expect(a.debugDisposed, isTrue, reason: 'two frames on');
    expect(made[1].debugDisposed, isFalse, reason: 'b was the last frame\'s');
    expect(HeldPictures.debugHeld - heldBefore, 1);
  });

  test('asked for again after the frame it sat out, it is the picture it '
      'was', () async {
    final a = await pictures.of('a', render);
    pictures.nextFrame();
    // This frame does not ask.
    pictures.nextFrame();
    expect(a.debugDisposed, isTrue);

    final again = await pictures.of('a', render);
    expect(identical(again, a), isFalse, reason: 'made anew: the old is gone');
    expect(pictures.made, 2);
  });

  test('a render that fails holds nothing, and the next ask renders', () async {
    await expectLater(
      pictures.of('a', () async => throw StateError('no raster')),
      throwsStateError,
    );
    expect(HeldPictures.debugHeld, heldBefore);

    final a = await pictures.of('a', render);
    expect(a.debugDisposed, isFalse);
    expect(made, hasLength(1));
  });

  test('🎯each picture let go is said by its key, as it goes — what was held '
      'WITH it goes with it (the rows a cut\'s picture is made of)', () async {
    final heard = <Object>[];
    final own = HeldPictures(onLetGo: heard.add);
    await own.of('a', render);
    own.nextFrame();
    await own.of('b', render);
    expect(heard, isEmpty, reason: 'a is the frame before\'s, still held');

    own.nextFrame();
    expect(heard, ['a']);
    expect(made.first.debugDisposed, isTrue);

    own.dispose();
    expect(heard, ['a', 'b']);
  });

  test('dispose lets go of this frame\'s and the frame before\'s', () async {
    final a = await pictures.of('a', render);
    pictures.nextFrame();
    final b = await pictures.of('b', render);

    pictures.dispose();
    expect(a.debugDisposed, isTrue);
    expect(b.debugDisposed, isTrue);
    expect(HeldPictures.debugHeld, heldBefore);
  });
}
