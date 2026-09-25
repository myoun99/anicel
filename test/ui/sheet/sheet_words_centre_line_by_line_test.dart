import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/sheet_marks.dart';
import 'package:anicel/src/models/sheet_paint_layer.dart';
import 'package:anicel/src/ui/sheet_painting.dart';

/// Words set centred centre EACH LINE — the way the PDF sets them, line by
/// line, from the same breaks. A block laid out left-aligned and then
/// centred as a whole leaves a wrapped title's short line hanging left on
/// screen while the PDF centres it.
void main() {
  testWidgets('a wrapped centred title centres its short line too', (
    tester,
  ) async {
    // The test font sets every glyph a 1em square: 'aaaa bb' at 10 in a
    // slot 50 wide wraps to 'aaaa' (40 wide) over 'bb' (20 wide).
    const words = SheetWords(
      SheetPaintLayer.content,
      text: 'aaaa bb',
      slot: Rect.fromLTWH(0, 0, 50, 40),
      size: 10,
      argb: 0xFF000000,
      h: SheetAlign.center,
    );
    final recorder = ui.PictureRecorder();
    paintSheetMarks(
      ui.Canvas(recorder),
      const Size(50, 40),
      (viewport: null, devicePixelRatio: 1, paper: const Size(50, 40)),
      const [words],
      style: (size, {required bold, required color}) =>
          TextStyle(fontSize: size, color: color),
    );
    final picture = recorder.endRecording();
    final pixels = (await tester.runAsync(() async {
      final image = await picture.toImage(50, 40);
      final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      image.dispose();
      return data!;
    }))!;
    picture.dispose();
    bool inked(int x, int y) => pixels.getUint8((y * 50 + x) * 4 + 3) > 128;

    // The second line's row.
    expect(inked(30, 15), isTrue, reason: 'centred, bb spans 15..35');
    expect(inked(5, 15), isFalse, reason: 'left-hung, bb would span 0..20');
  });

  testWidgets('a one-line number never breaks: it runs on past its slot and '
      'the slot clips it', (tester) async {
    // 'aaaaa' at 10 is 50 wide; the slot is 30. Wrapped it would stack
    // three lines; set on one line it fills the first row, right-aligned,
    // and nothing lands on the second.
    const words = SheetWords(
      SheetPaintLayer.content,
      text: 'aaaaa',
      slot: Rect.fromLTWH(10, 0, 30, 40),
      size: 10,
      argb: 0xFF000000,
      h: SheetAlign.end,
      fit: SheetWordsFit.oneLine,
    );
    final recorder = ui.PictureRecorder();
    paintSheetMarks(
      ui.Canvas(recorder),
      const Size(50, 40),
      (viewport: null, devicePixelRatio: 1, paper: const Size(50, 40)),
      const [words],
      style: (size, {required bold, required color}) =>
          TextStyle(fontSize: size, color: color),
    );
    final picture = recorder.endRecording();
    final pixels = (await tester.runAsync(() async {
      final image = await picture.toImage(50, 40);
      final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      image.dispose();
      return data!;
    }))!;
    picture.dispose();
    bool inked(int x, int y) => pixels.getUint8((y * 50 + x) * 4 + 3) > 128;

    expect(inked(35, 5), isTrue, reason: 'the first row carries the number');
    expect(inked(35, 15), isFalse, reason: 'nothing broke onto a second row');
    expect(inked(5, 5), isFalse, reason: 'the slot clips what outruns it');
  });

  testWidgets('a rounded fill and a picture cut to a rounded slot leave their '
      'corners bare; a square fill does not', (tester) async {
    // The app's corner on a printed window (유저 2026-09-25: 「모서리
    // 둥글게 … 우리 앱 통일 모서리 따라서」).
    final picture = (await tester.runAsync(() async {
      final recorder = ui.PictureRecorder();
      ui.Canvas(recorder).drawPaint(Paint()..color = const Color(0xFF00FF00));
      final drawn = recorder.endRecording();
      final image = await drawn.toImage(8, 8);
      drawn.dispose();
      return image;
    }))!;
    addTearDown(picture.dispose);
    final recorder = ui.PictureRecorder();
    paintSheetMarks(
      ui.Canvas(recorder),
      const Size(100, 40),
      (viewport: null, devicePixelRatio: 1, paper: const Size(100, 40)),
      [
        const SheetFill(
          SheetPaintLayer.form,
          rect: Rect.fromLTWH(0, 0, 30, 30),
          argb: 0xFF000000,
          cornerRadius: 6,
        ),
        const SheetFill(
          SheetPaintLayer.form,
          rect: Rect.fromLTWH(35, 0, 30, 30),
          argb: 0xFF000000,
        ),
        const SheetPicture(
          SheetPaintLayer.content,
          cutId: 'c',
          pictureFrame: 0,
          slot: Rect.fromLTWH(70, 0, 30, 30),
          cornerRadius: 6,
        ),
      ],
      style: (size, {required bold, required color}) =>
          TextStyle(fontSize: size, color: color),
      images: SheetMarkImages(pictureFor: (cutId, frame) => picture),
    );
    final drawn = recorder.endRecording();
    final pixels = (await tester.runAsync(() async {
      final image = await drawn.toImage(100, 40);
      final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      image.dispose();
      return data!;
    }))!;
    drawn.dispose();
    int alpha(int x, int y) => pixels.getUint8((y * 100 + x) * 4 + 3);

    expect(alpha(0, 0), 0, reason: 'the rounded fill\'s corner is bare');
    expect(alpha(15, 15), 255);
    expect(alpha(35, 0), 255, reason: 'a square fill fills its corner');
    expect(alpha(70, 0), 0, reason: 'the picture is cut to the round');
    expect(alpha(85, 15), 255);
  });

  test('a title too long for its line is set SMALLER, as large as fits — a '
      'short one keeps its size', () {
    // 유저 2026-09-25: 「길어져서 다 안들어가면 크기 작게하는방향」. The
    // test font sets every glyph one em wide: twelve glyphs at 60 are 720
    // wide, and the slot is 535.
    TextStyle style(double size, {required bool bold, required Color color}) =>
        TextStyle(fontSize: size, color: color);
    SheetWords title(String text) => SheetWords(
      SheetPaintLayer.content,
      text: text,
      slot: const Rect.fromLTWH(0, 0, 535, 75),
      size: 60,
      argb: 0xFF000000,
      fit: SheetWordsFit.shrink,
    );

    expect(sheetWordsSize(title('aaaaaaaaaaaa'), style), 44.5);
    expect(sheetWordsSize(title('aaaaaa'), style), 60);
  });
}
