import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../helpers/dart_sources.dart';

/// 🚨A LIST NAMES A FRAME THE WAY THE RULER DOES — EVERY LIST (F-284).
///
/// 유저 2026-10-04: 「링크된 오디오 링크버튼눌러서 쓰는곳 확인할때, 인덱스도
/// 표시 … 이런 표기는 초+코마 표기로 바꾼거에 대응하도록 법 통일. 프레임
/// 링크된거 보여줄때도 동일하게 해서 링크된거 보여주는 창 다 법 통일해서
/// 적용」.
///
/// The lines take the notation as an argument (`framePlace:`), and the
/// session has ONE (`framePlaceLabel`, which follows the seconds display).
/// ⛔A behaviour test can only prove the lists it knows of write the frame
/// the ruler's way; this scan proves no list hands the lines a notation of
/// its own — and that nothing but the session builds one.
void main() {
  const argument = 'framePlace:';
  const passedOn = 'framePlace: framePlace';
  const theSessions = 'framePlaceLabel';

  /// The lines of [file] that hand a notation on, comments aside.
  List<String> handsOf(File file) => [
    for (final line in file.readAsLinesSync())
      if (!line.trimLeft().startsWith('//') && line.contains(argument))
        line.trim(),
  ];

  final hands = <String, List<String>>{
    for (final file in dartFilesUnder('lib'))
      if (handsOf(file) case final found when found.isNotEmpty)
        libPath(file): found,
  };

  test('premise: the scan sees the lists that name a frame', () {
    expect(
      hands.keys,
      containsAll(<String>[
        // What a save could not carry.
        'lib/src/ui/menu/editor_top_strip.dart',
        // What a link takes: a linked paste, a name given by hand or by
        // the numbering, a 겸용 conversion.
        'lib/src/ui/paste_linked_asking_first.dart',
        'lib/src/ui/timeline/instance_editor_commands.dart',
        'lib/src/ui/session/block_naming.dart',
        'lib/src/ui/session/cut_verbs.dart',
        // Where a media pool file is used.
        'lib/src/ui/workspace/workspace_tabs.dart',
      ]),
      reason: 'an empty scan must not pass for nothing',
    );
  });

  test('every list hands the lines the session\'s notation', () {
    final strays = <String>[
      for (final MapEntry(key: path, value: lines) in hands.entries)
        for (final line in lines)
          if (!line.contains(passedOn) && !line.contains(theSessions))
            '$path: $line',
    ];
    expect(
      strays,
      isEmpty,
      reason: 'a frame is written by the session (framePlaceLabel) — a '
          'list with its own notation does not follow the seconds display',
    );
  });

  test('nothing but the session builds a frame\'s place', () {
    const build = 'timelineFramePlaceLabel(';
    final callers = [
      for (final file in dartFilesUnder('lib'))
        if (file.readAsLinesSync().any(
          (line) =>
              !line.trimLeft().startsWith('//') && line.contains(build),
        ))
          libPath(file),
    ];
    expect(callers, unorderedEquals(<String>[
      // Its home, beside the ruler's two lines it is made of.
      'lib/src/ui/timeline/timeline_frame_ruler_painter.dart',
      // The one caller.
      'lib/src/ui/editor_session_manager.dart',
    ]));
  });
}
