import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../helpers/dart_sources.dart';

/// 🚨★★ONE ANSWER TO 「DOES THIS DRAWING HAVE A NAME」, AND ONE MARK FOR NO.
///
/// `celNumberOf` (beside `Frame.celNumber`) says whether a drawing has a cel
/// number, and `celNumberOrMark` what it prints when it has none: the
/// in-between mark ○. Until C-save-percent (2026-09-15) seven places on
/// screen spelled the mark themselves after their own `frameName.isEmpty`,
/// so a name of spaces printed as spaces on the timeline and as ○ on the
/// sheet — and a save's notice listing lost drawings was about to be the
/// eighth.
///
/// ⛔SO THIS SCANS SOURCE: seven copies that agree today all pass a
/// behaviour test. A `'○'` literal outside the home, or a
/// `frameName == null || frameName.isEmpty` anywhere, has started the next
/// copy.
void main() {
  const home = 'lib/src/models/frame.dart';
  final markLiteral = RegExp('[\'"]○[\'"]');
  final blankNameCheck = RegExp(
    r'frameName\s*==\s*null\s*\|\|\s*frameName\.isEmpty',
  );

  /// The code on each line of [file] with its comment cut off — a comment
  /// may NAME the mark, and several explain it.
  Iterable<(int, String)> codeLines(File file) sync* {
    final lines = file.readAsLinesSync();
    for (var index = 0; index < lines.length; index += 1) {
      final comment = lines[index].indexOf('//');
      yield (
        index + 1,
        comment == -1 ? lines[index] : lines[index].substring(0, comment),
      );
    }
  }

  test('premise: the mark and the answer have their one home', () {
    final text = File(home).readAsStringSync();
    expect(text, contains('String? celNumberOf('));
    expect(
      text,
      contains('String? get celNumber => celNumberOf(name);'),
      reason:
          'the getter the sheet and the export read asks the same answer — '
          'a body of its own is the copy no behaviour test can see',
    );
    final marks = [
      for (final (_, code) in codeLines(File(home)))
        if (markLiteral.hasMatch(code)) code,
    ];
    expect(
      marks,
      hasLength(1),
      reason: 'the scan below assumes the one mark is spelled here',
    );
  });

  test('nobody else spells the mark or asks whether a frame name is empty',
      () {
    final offenders = <String>[];
    for (final file in dartFilesUnder('lib')) {
      final path = libPath(file);
      for (final (line, code) in codeLines(file)) {
        if (path != home && markLiteral.hasMatch(code)) {
          offenders.add('$path:$line spells the mark');
        }
        if (blankNameCheck.hasMatch(code)) {
          offenders.add('$path:$line asks frameName.isEmpty');
        }
      }
    }
    expect(offenders, isEmpty, reason: 'ask celNumberOf / celNumberOrMark');
  });
}
