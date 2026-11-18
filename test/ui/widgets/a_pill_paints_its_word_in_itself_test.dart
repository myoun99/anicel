import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/ui/theme/app_theme.dart';
import 'package:anicel/src/ui/widgets/pill_strip.dart';

/// 🗣️tool-settings-segments-overlap-at-the-narrowest (검증/서피스 11-17, on
/// F-530's fourth pass): at the tool settings' least width the brush's edge
/// strip had no width at all, and its words — 「1」 · 「2」 · 「3」 — stood on
/// one another and past the strip. A word of one letter cannot be cut, so
/// no line ran over and nothing clipped it. A pill's word is painted in its
/// pill alone, however narrow the strip is given.
void main() {
  const ground = Color(0xFF102030);

  testWidgets('a strip narrower than its words paints no ink past its own '
      'edge', (tester) async {
    const strip = 12.0;
    final shot = GlobalKey();
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: Align(
          alignment: Alignment.topLeft,
          child: RepaintBoundary(
            key: shot,
            // The words in a panel's style, on a ground of the test's own.
            child: Material(
              color: ground,
              child: SizedBox(
                width: 60,
                height: 40,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: SizedBox(
                    width: strip,
                    child: PillStrip.even(
                      items: [
                        for (final word in ['1', '2', '3', '4'])
                          PillItem(
                            keyValue: word,
                            label: word,
                            selected: word == '3',
                            onTap: () {},
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    final boundary =
        shot.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final pixels = (await tester.runAsync(() async {
      final image = await boundary.toImage();
      return image.toByteData(format: ui.ImageByteFormat.rawStraightRgba);
    }))!;
    final ground8 = [
      for (final channel in [ground.r, ground.g, ground.b])
        (channel * 255).round(),
    ];
    final inked = <String>[];
    for (var y = 0; y < 40; y += 1) {
      // A pixel's width past the strip's edge, for its hairline's blend.
      for (var x = strip.toInt() + 1; x < 60; x += 1) {
        final at = (y * 60 + x) * 4;
        final colour = [
          for (var channel = 0; channel < 3; channel += 1)
            pixels.getUint8(at + channel),
        ];
        if (colour.join() != ground8.join()) {
          inked.add('($x, $y)');
        }
      }
    }
    expect(inked, isEmpty);
  });
}
