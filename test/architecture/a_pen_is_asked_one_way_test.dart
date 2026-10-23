import 'package:flutter_test/flutter_test.dart';

import '../helpers/dart_sources.dart';

/// 🚨WHETHER A KIND IS THE PEN, AND HOW FAR A PRESS OF IT MAY WOBBLE, ARE
/// ASKED OF `PenSidecars` (`lib/src/services/input/pen_sidecars.dart`).
///
/// 🗣️I-124 (유저 2026-10-22): 「터치인지 펜인지 확인하는 로직같은거
/// 통일안되있으면 겸사겸사 통일하고 입구 단순화」. Three places spelled the
/// pen's two ends out as a comparison — the brush's pressure, the pen's
/// lean, the glide stop — and four recognisers wrote Flutter's slop over the
/// pen law's kind. Each asks `PenSidecars.isPenKind` or `hitSlopOf` now.
///
/// ⚠️A `switch` that lays every kind out arm by arm — the census's hands,
/// the echo's kinds, the inspector's colours — names the pen's two ends as
/// one arm of many. It answers which of all the kinds this is, not whether
/// it is the pen, and is not scanned.
void main() {
  test('nothing in lib spells the pen\'s two ends or the slop out but '
      'PenSidecars', () {
    final hits = [
      for (final file in dartFilesUnder('lib'))
        if (libPath(file) != _theOnePlace)
          for (final line in _asks(file.readAsStringSync()))
            '${libPath(file)}: $line',
    ];
    expect(
      hits,
      isEmpty,
      reason: 'ask `PenSidecars.isPenKind` or `PenSidecars.hitSlopOf`',
    );
  });

  test('the scan sees a planted ask, and not a switch arm or a comment', () {
    const planted = '''
    (kind == PointerDeviceKind.stylus ||
        kind == PointerDeviceKind.invertedStylus) &&
    event.kind != PointerDeviceKind.invertedStylus) {
final slop = computeHitSlop(kind, settings);
  PointerDeviceKind.stylus || PointerDeviceKind.invertedStylus => true,
/// How far a press may wobble (`computeHitSlop`).
// ↩️It was kind == PointerDeviceKind.invertedStylus.
''';
    expect(_asks(planted), [
      'kind == PointerDeviceKind.invertedStylus) &&',
      'event.kind != PointerDeviceKind.invertedStylus) {',
      'final slop = computeHitSlop(kind, settings);',
    ]);
  });
}

const _theOnePlace = 'lib/src/services/input/pen_sidecars.dart';

/// Each line of [source] that asks either question itself — trimmed,
/// comments skipped. The pen's other end is the one a pen test cannot leave
/// out, so the comparison with it is the ask.
List<String> _asks(String source) => [
  for (final line in source.split('\n'))
    if (!line.trimLeft().startsWith('//') && _ask.hasMatch(line)) line.trim(),
];

final _ask = RegExp(
  r'[!=]=\s*PointerDeviceKind\.invertedStylus\b|\bcomputeHitSlop\(',
);
