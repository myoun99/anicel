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
/// ⚠️SOURCE, because a widget test drives only the screens it builds: the
/// next place to measure a press by its kind passes every test it has none
/// of.
void main() {
  test('⛔premise: the law has its one home, and the scan reaches the slops '
      'the app measures', () {
    expect(
      File('lib/src/services/input/pen_sidecars.dart').readAsStringSync(),
      contains('static PointerDeviceKind kindOf('),
    );
    expect(_slopCalls(), hasLength(greaterThanOrEqualTo(4)));
  });

  test('🚨every slop the app measures by a pointer\'s kind reads the kind '
      'through the pen law', () {
    final offenders = [
      for (final (where, argument) in _slopCalls())
        if (!argument.startsWith('PenSidecars.kindOf(')) where,
    ];
    expect(
      offenders,
      isEmpty,
      reason: 'computeHitSlop(PenSidecars.kindOf(kind), …): a pen the OS '
          'calls a mouse wobbles as a pen does',
    );
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

/// Each `computeHitSlop(` call under `lib/src/ui`, where it stands and its
/// first argument as written.
List<(String, String)> _slopCalls() {
  const call = 'computeHitSlop(';
  return [
    for (final file in dartFilesUnder('lib/src/ui'))
      for (final (index, line) in file.readAsLinesSync().indexed)
        if (!line.trimLeft().startsWith('//') && line.contains(call))
          (
            '${file.path}:${index + 1}',
            file
                .readAsLinesSync()
                .skip(index)
                .take(3)
                .join(' ')
                .split(call)[1]
                .trimLeft(),
          ),
  ];
}
