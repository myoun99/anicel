import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/text_cel_style.dart';
import 'package:anicel/src/ui/text/text_cel_render.dart';
import 'package:flutter_test/flutter_test.dart';

/// THE SE NAME TAG IS SET AS IT ALWAYS WAS — its letters' recipe moved out
/// of `layoutTextCel` on 2026-10-06 so that a text on a cel is set with the
/// same one (`canvasLetterTextStyle`, R9-rest), and a tag is drawn on the
/// canvas and into every export. These hold what that move must not have
/// changed: the line's pitch, the shrink to a budget, the outline at the
/// shrunk size, where the lines stand, the colour.
///
/// ⚠️In the TEST FONT, which sets every glyph as a box one letter-size wide
/// and tall. Nothing here loads the app's faces — the numbers are the box's.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const canvas = CanvasSize(width: 400, height: 300);

  TextCelLayout tag(
    String words, {
    required TextCelStyle style,
    ui.Offset position = const ui.Offset(10, 10),
    double? maxWidth,
  }) {
    final layout = layoutTextCel(
      content: TextCelContent(text: words, style: style, position: position),
      canvas: canvas,
      maxWidth: maxWidth,
    );
    addTearDown(layout.dispose);
    return layout;
  }

  /// [layout] drawn on the canvas, as premultiplied RGBA.
  Future<Uint8List> drawn(TextCelLayout layout) async {
    final recorder = ui.PictureRecorder();
    layout.paint(ui.Canvas(recorder));
    final picture = recorder.endRecording();
    final image = await picture.toImage(canvas.width, canvas.height);
    picture.dispose();
    final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    image.dispose();
    return data!.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
  }

  List<int> pixel(Uint8List bytes, int x, int y) =>
      bytes.sublist((y * canvas.width + x) * 4, (y * canvas.width + x) * 4 + 4);

  test('a line is a quarter taller than its letters', () {
    final layout = tag('ab', style: const TextCelStyle(fontSize: 20));

    expect(layout.textSize, const ui.Size(40, 25));
  });

  test('a line wider than its budget is set smaller, to fit it — once', () {
    // Ten letters at 20 are 200 wide; at four fifths of that they are set
    // at 16, and a line of those is 20 tall.
    final layout = tag(
      'abcdefghij',
      style: const TextCelStyle(fontSize: 20),
      maxWidth: 160,
    );

    expect(layout.textSize.width, closeTo(160, 0.01));
    expect(layout.textSize.height, closeTo(20, 0.01));
  });

  test('a line inside its budget keeps its size', () {
    final layout = tag(
      'abcd',
      style: const TextCelStyle(fontSize: 20),
      maxWidth: 100,
    );

    expect(layout.textSize, const ui.Size(80, 25));
  });

  test('🚨the outline is stroked at the size the letters were SET at, not '
      'the size the style asked for', () async {
    final bytes = await drawn(
      tag(
        'abcdefghij',
        style: const TextCelStyle(
          fontSize: 20,
          align: TextCelAlign.left,
          color: 0xFF000000,
          outlineColor: 0xFFFF0000,
          outlineWidth: 2,
        ),
        maxWidth: 100,
      ),
    );

    // The letters end at 110. At the asked size they would have run on to
    // 210, and their outlines with them.
    expect(pixel(bytes, 60, 16), [0, 0, 0, 255], reason: 'a letter');
    expect(pixel(bytes, 110, 16), [255, 0, 0, 255], reason: 'its outline');
    expect(pixel(bytes, 130, 16), [0, 0, 0, 0]);
    expect(pixel(bytes, 170, 26), [0, 0, 0, 0]);
  });

  test('the lines stand about the position as the alignment says, and a '
      'shorter line inside the block the same way', () async {
    // 「abcd」 over 「ab」 at size 10: the second line's letters are drawn
    // from 24.4 down, and x is where the alignment puts them.
    Future<Uint8List> lines(TextCelAlign align) => drawn(
      tag(
        'abcd\nab',
        style: TextCelStyle(fontSize: 10, align: align),
        position: const ui.Offset(100, 10),
      ),
    );
    const ink = [32, 32, 32, 255];
    const clear = [0, 0, 0, 0];

    final left = await lines(TextCelAlign.left);
    expect(pixel(left, 105, 30), ink, reason: 'left: 100 to 120');
    expect(pixel(left, 125, 30), clear);
    expect(pixel(left, 135, 16), ink, reason: 'the long line: to 140');

    final centre = await lines(TextCelAlign.center);
    expect(pixel(centre, 95, 30), ink, reason: 'centre: 90 to 110');
    expect(pixel(centre, 85, 30), clear);
    expect(pixel(centre, 115, 30), clear);
    expect(pixel(centre, 85, 16), ink, reason: 'the long line: 80 to 120');

    final right = await lines(TextCelAlign.right);
    expect(pixel(right, 85, 30), ink, reason: 'right: 80 to 100');
    expect(pixel(right, 75, 30), clear);
    expect(pixel(right, 65, 16), ink, reason: 'the long line: from 60');
  });
}
