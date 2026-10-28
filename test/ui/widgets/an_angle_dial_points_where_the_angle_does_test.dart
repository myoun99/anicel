import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderRepaintBoundary;
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/ui/widgets/angle_dial.dart';

/// 🗣️I-132-Q18 b (유저 2026-10-28): the dial's needle points where the
/// angle does — 0° up and clockwise, as After Effects' angle dial reads,
/// and as an angle lane turns the picture (Directional Blur's 0° blurs up
/// and down, I-132-Q8).
void main() {
  const boundary = ValueKey<String>('dial-boundary');

  Future<Uint8List> drawn(WidgetTester tester, double degrees) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          colorScheme: const ColorScheme.light(onSurface: Color(0xFF000000)),
        ),
        home: Scaffold(
          backgroundColor: const Color(0xFFFFFFFF),
          body: Center(
            child: RepaintBoundary(
              key: boundary,
              child: AngleDial(
                degrees: degrees,
                enabled: true,
                onTurned: (_) {},
              ),
            ),
          ),
        ),
      ),
    );
    final box = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(boundary),
    );
    final image = await tester.runAsync(box.toImage);
    addTearDown(image!.dispose);
    final data = await tester.runAsync(
      () => image.toByteData(format: ui.ImageByteFormat.rawRgba),
    );
    return data!.buffer.asUint8List();
  }

  /// How much ink is at ([x], [y]) of the 24-pixel dial.
  int inkAt(Uint8List bytes, int x, int y) =>
      bytes[(y * AngleDial.size.toInt() + x) * 4 + 3];

  // Halfway out from the middle: on the needle's way, off the ring.
  const up = (12, 6);
  const right = (18, 12);
  const down = (12, 18);

  testWidgets('0° points up', (tester) async {
    final bytes = await drawn(tester, 0);
    expect(inkAt(bytes, up.$1, up.$2), greaterThan(0));
    expect(inkAt(bytes, right.$1, right.$2), 0);
    expect(inkAt(bytes, down.$1, down.$2), 0);
  });

  testWidgets('90° points right — clockwise', (tester) async {
    final bytes = await drawn(tester, 90);
    expect(inkAt(bytes, right.$1, right.$2), greaterThan(0));
    expect(inkAt(bytes, up.$1, up.$2), 0);
  });

  testWidgets('a whole turn more points where the angle does', (
    tester,
  ) async {
    final bytes = await drawn(tester, 540);
    expect(inkAt(bytes, down.$1, down.$2), greaterThan(0));
    expect(inkAt(bytes, up.$1, up.$2), 0);
  });
}
