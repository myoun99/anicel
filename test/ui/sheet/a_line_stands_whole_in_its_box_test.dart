import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/ui/sheet/sheet_line.dart';

import '../../helpers/app_faces.dart';

/// 🗣️I-127-Q4 (유저 2026-11-01): 「글자를 줄여 칸에 맞춘다」 — a line wider
/// than its box stands whole in it, smaller. ↩️It was cut with a `…`.
void main() {
  const slot = Rect.fromLTWH(10, 20, 100, 16);

  group('a line that fits', () {
    const line = Size(40, 16);

    test('stands as it runs: left, centred or right', () {
      expect(
        SheetLinePlace.of(line, slot, SheetTextForm.leftLine).rect,
        const Rect.fromLTWH(10, 20, 40, 16),
      );
      expect(
        SheetLinePlace.of(line, slot, SheetTextForm.centredLine).rect,
        const Rect.fromLTWH(40, 20, 40, 16),
      );
      expect(
        SheetLinePlace.of(line, slot, SheetTextForm.rightLine).rect,
        const Rect.fromLTWH(70, 20, 40, 16),
      );
    });

    test('is not scaled', () {
      expect(
        SheetLinePlace.of(line, slot, SheetTextForm.centredLine).scale,
        1,
      );
    });
  });

  group('a line wider than its box', () {
    const line = Size(400, 16);

    for (final form in [
      SheetTextForm.leftLine,
      SheetTextForm.centredLine,
      SheetTextForm.rightLine,
    ]) {
      test('$form: fills the box across, about its own middle', () {
        final place = SheetLinePlace.of(line, slot, form);
        expect(place.scale, 0.25);
        expect(place.rect, const Rect.fromLTWH(10, 26, 100, 4));
      });
    }
  });

  test('a box with no room shows nothing, and asks nothing impossible', () {
    final place = SheetLinePlace.of(
      const Size(40, 16),
      const Rect.fromLTWH(10, 20, -6, 16),
      SheetTextForm.centredLine,
    );
    expect(place.scale, 0);
    expect(place.rect.isFinite, isTrue);
  });

  testWidgets('printing lays the whole line in the box, and only there', (
    tester,
  ) async {
    await loadTheAppFaces();
    final line = sheetLine(
      'tanaka yoshiyuki tanaka yoshiyuki',
      const TextStyle(fontSize: 20, color: Color(0xFF000000)),
    );
    addTearDown(line.dispose);
    expect(line.didExceedMaxLines, isFalse);

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    SheetLinePlace.of(
      line.size,
      const Rect.fromLTWH(10, 20, 100, 22),
      SheetTextForm.leftLine,
    ).paint(canvas, line);
    final picture = recorder.endRecording();
    addTearDown(picture.dispose);

    final inked = await tester.runAsync(() async {
      final image = await picture.toImage(200, 60);
      final data = await image.toByteData();
      image.dispose();
      return [
        for (var y = 0; y < 60; y++)
          for (var x = 0; x < 200; x++)
            if (data!.getUint8((y * 200 + x) * 4 + 3) > 0)
              Offset(x + 0.5, y + 0.5),
      ];
    });

    expect(inked, isNotEmpty);
    final ink = inked!.reduce(
      (a, b) => Offset(a.dx < b.dx ? a.dx : b.dx, a.dy < b.dy ? a.dy : b.dy),
    );
    final end = inked.reduce(
      (a, b) => Offset(a.dx > b.dx ? a.dx : b.dx, a.dy > b.dy ? a.dy : b.dy),
    );
    expect(ink.dx, greaterThanOrEqualTo(10));
    expect(end.dx, lessThanOrEqualTo(110));
    expect(end.dx, greaterThan(100));
  });
}
