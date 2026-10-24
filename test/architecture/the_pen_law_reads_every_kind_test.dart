import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../helpers/dart_sources.dart';

/// 🗣️THE PEN LAW (tool-settings-panel-tidy, 유저 2026-10-10): 「필압이 있다도
/// 하나의 판단기준일거같은데 … 윈탭골라도 필압은 먹히니까 감지가능하단거아냐」
/// → 「우선 1번 제일 확실한방법 좋아. 앞으로의 펜 작동 기준으로 삼으면
/// 좋을거같고」. A pen the OS hands over as a MOUSE is the pen while its
/// driver says it is down (`PenSidecars.kindOf`). Every answer the app gives
/// by the kind of a pointer asks it through that one door, or a pen handed
/// over as a mouse gets a mouse's answer there — a one-pixel slop for a
/// hand that always wobbles.
///
/// 🗣️I-124 (유저 2026-10-22): 「터치인지 펜인지 확인하는 로직같은거
/// 통일안되있으면 겸사겸사 통일하고 입구 단순화」. Four recognisers each
/// wrote the slop over the law's kind, and three places spelled the pen's two
/// ends out; both live in `PenSidecars` now — `hitSlopOf`, `isPenKind` — and
/// nothing else may spell them. ↩️Until then this read each
/// `computeHitSlop(` call's argument for the law's door.
///
/// ⚠️SOURCE, because a widget test drives only the screens it builds: the
/// next place to measure a press by its kind passes every test it has none
/// of.
///
/// ⚠️A `switch` that lays every kind out arm by arm — the census's hands,
/// the echo's kinds, the inspector's colours — names the pen's two ends as
/// one arm of many. It answers which of all the kinds this is, not whether
/// it is the pen, and is not scanned.
void main() {
  test('⛔premise: the law has its one home, and the scan reaches the slops '
      'the app measures', () {
    final home = File(_theOnePlace).readAsStringSync();
    expect(home, contains('static PointerDeviceKind kindOf('));
    expect(home, contains('computeHitSlop(kindOf(kind), settings)'));
    expect(home, contains('static bool isPenKind('));
    expect(
      [
        for (final file in dartFilesUnder('lib/src/ui'))
          ...'PenSidecars.hitSlopOf('.allMatches(file.readAsStringSync()),
      ],
      hasLength(greaterThanOrEqualTo(4)),
    );
  });

  test('🚨nothing in lib measures a slop or spells the pen\'s two ends out '
      'but the law\'s home', () {
    final hits = [
      for (final file in dartFilesUnder('lib'))
        if (libPath(file) != _theOnePlace)
          for (final line in _asks(file.readAsStringSync()))
            '${libPath(file)}: $line',
    ];
    expect(
      hits,
      isEmpty,
      reason: 'ask `PenSidecars.hitSlopOf` or `PenSidecars.isPenKind`: a pen '
          'the OS calls a mouse wobbles as a pen does',
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

  test('🚨and every other pen-or-mouse question asks it the same way — the '
      'glide a pen stops, the aim a finger\'s mouse may not take', () {
    for (final (path, asked) in const [
      ('lib/src/ui/timeline/stylus_glide_stop.dart', 'PenSidecars.kindOf('),
      ('lib/src/ui/brush/brush_canvas_panel.dart', 'kind: PenSidecars.kindOf('),
    ]) {
      expect(File(path).readAsStringSync(), contains(asked), reason: path);
    }
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
