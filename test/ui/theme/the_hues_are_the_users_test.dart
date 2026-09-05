import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/layer_mark.dart';
import 'package:anicel/src/models/layer_process.dart';
import 'package:anicel/src/ui/theme/layer_mark_palette.dart';

/// 🚨THE HUES ARE THE USER'S, MEASURED FROM THEIR OWN SCREENSHOT.
///
/// 유저 2026-08-27: 「색 내가 첨부한거 그대로 살리고 톤만 바꾸라니까? **LO는
/// 흰색이야. 원화는 초록색이었고. BG는 파랑색이었고**」 — a palette invented
/// here once already, while their reference sat unopened.
///
/// A mark's colour is not a small swatch: it is the PAPER of that layer's
/// frame blocks, so it lands across whole rows. This pins the three things
/// the user said out loud, plus the rule that makes the revise column work.
void main() {
  const none = Color(0xFF123456);

  Color colorOf(LayerMark mark) => resolveLayerMarkColor(mark, noneColor: none);

  /// A colour's dominant channel, which is how "흰색 / 초록색 / 파랑색"
  /// reads back out of an ARGB value.
  String hueOf(Color color) {
    final r = (color.toARGB32() >> 16) & 0xFF;
    final g = (color.toARGB32() >> 8) & 0xFF;
    final b = color.toARGB32() & 0xFF;
    if (r > 240 && g > 240 && b > 240) {
      return 'white';
    }
    if (g > r && g > b) {
      return 'green';
    }
    if (b > r && b > g) {
      return 'blue';
    }
    return 'other';
  }

  test('🚨LO는 흰색', () {
    expect(
      hueOf(colorOf(const LayerMark(process: LayerProcess.layout))),
      'white',
    );
  });

  test('🚨원화는 초록색', () {
    expect(hueOf(colorOf(const LayerMark(process: LayerProcess.key))), 'green');
  });

  test('🚨BG(art)는 파랑색', () {
    expect(hueOf(colorOf(const LayerMark(process: LayerProcess.art))), 'blue');
  });

  test('an UNLABELLED row wears the paper the theme passed in — this file '
      'knows labels, not chrome', () {
    expect(colorOf(LayerMark.none), none);
  });

  test('🚨the REVISE colour is the same whatever the stage — 「LO연출이던 '
      '원화연출이던 같은색」, because on paper the revise is what you read', () {
    for (final process in LayerProcess.values) {
      expect(
        colorOf(LayerMark(process: process, revise: LayerRevise.direction)),
        colorOf(
          const LayerMark(
            process: LayerProcess.layout,
            revise: LayerRevise.direction,
          ),
        ),
        reason: '$process',
      );
    }
  });

  test('every stage has a colour of its own — a table with a hole would '
      'throw on the row that used it', () {
    final seen = <Color>{};
    for (final process in LayerProcess.values) {
      final color = colorOf(LayerMark(process: process));
      expect(color, isNot(none));
      seen.add(color);
    }
    expect(
      seen,
      hasLength(LayerProcess.values.length),
      reason: 'two stages sharing a paper would be unreadable on the sheet',
    );
  });

  test('every revise has a colour of its own', () {
    final seen = <Color>{};
    for (final revise in LayerRevise.values) {
      final color = colorOf(
        LayerMark(process: LayerProcess.key, revise: revise),
      );
      expect(color, isNot(none));
      seen.add(color);
    }
    expect(seen, hasLength(LayerRevise.values.length));
  });

  test('the papers are OPAQUE — a translucent one would let the row stripe '
      'through and read as a different colour', () {
    for (final process in LayerProcess.values) {
      expect(
        colorOf(LayerMark(process: process)).toARGB32() >>> 24,
        0xFF,
        reason: '$process',
      );
    }
  });
}
