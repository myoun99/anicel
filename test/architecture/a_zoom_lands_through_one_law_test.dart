import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 🚨★★★A ZOOM LANDS THROUGH ONE LAW (F-122 · I-27).
///
/// 유저 2026-09-13 (I-27): 「확대 축소 로직이 터치랑 추가될 키보드 숏컷이랑
/// 여러곳에 나뉘어져있을 가능성 높으니 **법 하나로 통일**」 · 2026-09-17
/// (F-122): 「캔버스 베이스 패널 많을테니 **다 법 통일해서** 적용되면되」 ·
/// 「**근본/구조적으로** 해결해줘. 증상만 해결말고」.
///
/// It was two. The pill's verbs stopped at the advertised 10%–1600% and the
/// gesture layer's pinch, wheel and trackpad only at the model's sanity
/// rail — and none of them landed on a zoom the pill could write, so `55%`
/// stood for every zoom from 54.5 to 55.5. `CanvasZoomScale.landed` is the
/// one law now (range + the readout grid), and `CanvasZoomScale.zoomedTo`
/// is the one road to it.
///
/// ⛔A behaviour test cannot hold this. It passes for every road that
/// exists today and says nothing about the sixth one: a new verb that calls
/// the model's raw `zoomedAround` works, zooms, and quietly keeps a zoom the
/// pill cannot say. So the rule is read off the source.
void main() {
  const law = 'lib/src/ui/canvas/canvas_zoom_scale.dart';
  const model = 'lib/src/models/canvas_viewport.dart';

  Iterable<({String path, String source})> libSources() => Directory('lib')
      .listSync(recursive: true)
      .whereType<File>()
      .where((file) => file.path.endsWith('.dart'))
      .map(
        (file) => (
          path: file.path.replaceAll('\\', '/'),
          source: file.readAsStringSync(),
        ),
      );

  test('nothing under lib/ zooms a view around an anchor but the law', () {
    final strays = <String>[
      for (final file in libSources())
        if (file.path != law &&
            file.path != model &&
            file.source.contains('.zoomedAround('))
          file.path,
    ];
    expect(
      strays,
      isEmpty,
      reason:
          'these zoom with the model\'s raw verb, so their zoom stops at the '
          'sanity rail instead of the advertised range and lands nowhere the '
          'pill can write — take `CanvasZoomScale.zoomedTo`',
    );
    expect(
      '.zoomedAround('.allMatches(File(law).readAsStringSync()).length,
      1,
      reason: '$law takes the raw verb once, inside `zoomedTo`',
    );
  });

  test('every fit under lib/ says where its zoom lands', () {
    // The argument list of each call, by paren depth — a fit's arguments
    // are plain expressions, so the first `)` at depth zero closes it.
    String argumentsFrom(String source, int open) {
      var depth = 0;
      for (var i = open; i < source.length; i += 1) {
        if (source[i] == '(') depth += 1;
        if (source[i] == ')') depth -= 1;
        if (depth == 0) return source.substring(open, i);
      }
      return source.substring(open);
    }

    final fits = <String>[];
    final unlanded = <String>[];
    for (final file in libSources()) {
      if (file.path == model) continue;
      for (final call in RegExp(
        r'CanvasViewport\.fitTo(?:CanvasRect|View)\(',
      ).allMatches(file.source)) {
        fits.add(file.path);
        if (!argumentsFrom(file.source, call.end - 1).contains('zoomLanding:')) {
          unlanded.add(file.path);
        }
      }
    }
    expect(fits, isNotEmpty, reason: 'the scan found no fit at all — it is '
        'reading the wrong tree, and an empty list would pass anything');
    expect(
      unlanded,
      isEmpty,
      reason:
          'a fit with no `zoomLanding:` keeps whatever ratio fell out of the '
          'division — `CanvasZoomScale.landedToFit` puts it on the grid the '
          'pill writes, BEFORE the rect is centred',
    );
  });
}
