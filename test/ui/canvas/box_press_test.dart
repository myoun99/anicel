import 'dart:ui' show ImageByteFormat, PictureRecorder;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/ui/canvas/box_chrome.dart';
import 'package:anicel/src/ui/canvas/box_press.dart';

/// 🚨★★★**A HANDLE AND THE CROSS ARE GRABBED WHERE THEY ARE DRAWN** (F-262).
///
/// 🗣️유저 2026-10-02: 「변형도구의 사각형 공통ui, 꼭짓점이나 십자가 등
/// 작동박스가 보이는것보다 큰거같음. 박스 외 부분 조작하는데도 크기가
/// 줄어든다거나 십자가가 움직인다거나. **보이는 만큼 존재하도록.** 십자가는
/// 물론 복잡한 모양이니 **십자가크기의 박스**」.
///
/// ↩️Both were taken anywhere within 16px of their centre — a disc 32px
/// across round a square drawn 9px wide — so a press well clear of
/// everything drawn still scaled the box or carried the cross away.
///
/// This is the press every box on the canvas asks ([boxPressAt]): the
/// transform tool's, a layer's fx box, the camera's frame.
void main() {
  // A 100×100 box with its top-left corner at (100, 100), a handle on each
  // corner and the cross in the middle.
  const box = Rect.fromLTWH(100, 100, 100, 100);
  final handles = [
    box.topLeft,
    box.topRight,
    box.bottomRight,
    box.bottomLeft,
  ];

  BoxPressHit? pressAt(Offset press, {bool turns = true}) => boxPressAt(
    press,
    anchor: box.center,
    handles: handles,
    inside: box.contains,
    onStage: (_) => true,
    turns: turns,
  );

  test('a handle is taken on the square that is drawn for it', () {
    expect(pressAt(box.topLeft), (press: BoxPress.handle, handle: 0));
    // The square is 9 wide and wears a 1.5 outline on its edge: 5.25 out.
    for (final within in const [
      Offset(4, 4),
      Offset(-4, -4),
      Offset(5, 0),
      Offset(0, -5),
    ]) {
      expect(
        pressAt(box.bottomRight + within),
        (press: BoxPress.handle, handle: 2),
        reason: '$within from the corner is on the square',
      );
    }
  });

  test('🚨beside a handle the press is the box\'s own — the move inside it, '
      'the turn outside', () {
    // 8px is well inside the 16px disc the press used to take.
    expect(
      pressAt(box.topLeft + const Offset(8, 8)),
      (press: BoxPress.inside, handle: -1),
      reason: '유저: 「박스 외 부분 조작하는데도 크기가 줄어든다거나」',
    );
    expect(
      pressAt(box.topLeft - const Offset(8, 8)),
      (press: BoxPress.turn, handle: -1),
    );
    expect(
      pressAt(box.topLeft + const Offset(6, 0)),
      (press: BoxPress.inside, handle: -1),
      reason: 'one pixel past the outline is past the handle',
    );
  });

  test('the cross is taken on the box its arms span', () {
    expect(pressAt(box.center), (press: BoxPress.anchor, handle: -1));
    // The arms reach 7 from the centre; the corner of that box has no ink
    // in it and is still the cross — 유저: 「십자가크기의 박스」.
    expect(
      pressAt(box.center + const Offset(6, 6)),
      (press: BoxPress.anchor, handle: -1),
    );
  });

  test('🚨beside the cross the press moves the box, not the cross', () {
    for (final beside in const [
      Offset(8, 0),
      Offset(0, 8),
      Offset(-10, 3),
      Offset(11, 11),
    ]) {
      expect(
        pressAt(box.center + beside),
        (press: BoxPress.inside, handle: -1),
        reason: '$beside — 유저: 「십자가가 움직인다거나」',
      );
    }
  });

  test('the cross is on top: dragged onto a handle, it is what is taken', () {
    expect(
      boxPressAt(
        box.topLeft,
        anchor: box.topLeft,
        handles: handles,
        inside: box.contains,
        onStage: (_) => true,
      ),
      (press: BoxPress.anchor, handle: -1),
    );
  });

  /// ⛔The other half, read off the PAINT: the pixels the chrome puts down
  /// for a handle and for the cross, against the box a press is taken in.
  /// A footprint that grew again — or a square that was drawn bigger and
  /// not taken bigger — parts the two, and this is where it shows.
  testWidgets('⛔what is drawn is what is taken — the painted pixels of a '
      'handle and of the cross fill the box a press takes them in', (
    tester,
  ) async {
    const at = Offset(40, 40);

    /// The box of every pixel [chrome] paints, on an 80×80 sheet.
    Future<Rect> painted(SelectionTransformChrome chrome) async {
      final recorder = PictureRecorder();
      paintBoxChrome(
        Canvas(recorder),
        chrome,
        color: const Color(0xFFFF0000),
      );
      final picture = recorder.endRecording();
      late Rect box;
      await tester.runAsync(() async {
        final image = await picture.toImage(80, 80);
        final data = await image.toByteData(format: ImageByteFormat.rawRgba);
        final bytes = data!.buffer.asUint8List();
        var left = 80;
        var top = 80;
        var right = -1;
        var bottom = -1;
        for (var y = 0; y < 80; y += 1) {
          for (var x = 0; x < 80; x += 1) {
            if (bytes[(y * 80 + x) * 4 + 3] == 0) {
              continue;
            }
            if (x < left) left = x;
            if (x > right) right = x;
            if (y < top) top = y;
            if (y > bottom) bottom = y;
          }
        }
        image.dispose();
        box = Rect.fromLTRB(
          left.toDouble(),
          top.toDouble(),
          right + 1.0,
          bottom + 1.0,
        );
      });
      picture.dispose();
      return box;
    }

    void sameBox(Rect drawn, Rect taken, String what) {
      // Within the pixel an anti-aliased edge spills into.
      for (final (a, b, edge) in [
        (drawn.left, taken.left, 'left'),
        (drawn.top, taken.top, 'top'),
        (drawn.right, taken.right, 'right'),
        (drawn.bottom, taken.bottom, 'bottom'),
      ]) {
        expect(a, closeTo(b, 1), reason: '$what: $edge — $drawn vs $taken');
      }
    }

    sameBox(
      await painted((box: const [], handles: const [at], anchor: null)),
      boxHandleFootprint(at),
      'a handle',
    );
    sameBox(
      await painted((box: const [], handles: const [], anchor: at)),
      boxCrossFootprint(at),
      'the cross',
    );
  });

  test('a box that does not turn takes nothing outside it', () {
    expect(pressAt(box.topLeft - const Offset(8, 8), turns: false), isNull);
  });
}
