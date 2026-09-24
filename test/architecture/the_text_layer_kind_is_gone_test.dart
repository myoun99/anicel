import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../helpers/dart_sources.dart';
import '../helpers/project_scratch_folder.dart';

/// F-154 (유저 2026-09-16): 「텍스트 레이어 타입 삭제. **잔재 싹 삭제**.
/// 텍스트툴은 도입할 예정이고 일반 레이어에 텍스트 넣게할것임. 그거는 나중에
/// 아이디어로서 상담하고 일단 삭제만 먼저」.
///
/// 🚨A SOURCE SCAN, because a behaviour test cannot say 「잔재가 없다」: a
/// kind no menu offers can still be reachable from a file, a paste, or a
/// branch nobody drives, and every one of those is a remnant. The question
/// this asks is the user's own — is the WORD still in the code.
///
/// ⛔What is NOT deleted: the text SETTING and RENDERING (`TextCelContent`,
/// `TextCelStyle`, `text_cel_render.dart`, the vertical-writing and dialogue
/// fitting). The SE name tag and the dialogue blocks are written with them,
/// and those stay — the user is removing a LAYER KIND, and the text tool
/// they plan will write onto ordinary layers with this same machinery.
///
/// 🚨AND THE SCAN IS TESTED ON A PLANTED REMNANT. An absence test passes
/// just as well when it reads nothing at all: with the kind gone there is
/// no product change left that could turn it red, so the only way to know
/// it still WORKS is to hand it a file that holds the word.
void main() {
  const words = ['LayerKind.text', 'textCelBakes', 'TextCelBakes'];

  /// ⛔THE WALK IS NOT WRITTEN HERE. `dartFilesUnder` is the one walk every
  /// source scan asks (C-save-percent unified seven of them), and it FAILS
  /// on a folder that does not exist rather than quietly measuring nothing.
  List<String> remnantsUnder(String root) {
    final offenders = <String>[];
    for (final file in dartFilesUnder(root)) {
      final text = file.readAsStringSync();
      for (final word in words) {
        if (text.contains(word)) {
          offenders.add('${file.path.replaceAll(r'\', '/')}  ($word)');
        }
      }
    }
    return offenders;
  }

  test('no lib file names the text LAYER KIND — the remnants are gone', () {
    expect(
      remnantsUnder('lib'),
      isEmpty,
      reason:
          'a text-layer remnant is still in lib — the kind went, so every '
          'branch that asked for it goes with it:\n'
          '${remnantsUnder('lib').join('\n')}',
    );
  });

  test('the kind enum itself no longer declares it', () {
    final source = File('lib/src/models/layer_kind.dart').readAsStringSync();
    expect(
      source.contains('  text('),
      isFalse,
      reason: 'LayerKind.text is the thing being removed',
    );
    expect(
      source.contains('hasLayerEffects'),
      isTrue,
      reason: 'fixture: this is the file that declares the kinds',
    );
  });

  test('🚨the scan sees a remnant when there is one', () {
    final planted = Directory.systemTemp.createTempSync('anicel-remnant');
    deleteAfterSessionEnds(planted);
    File('${planted.path}/a_row.dart').writeAsStringSync(
      'void f(LayerKind k) {\n'
      '  if (k == LayerKind.text) {}\n'
      '}\n',
    );
    File('${planted.path}/clean.dart').writeAsStringSync('void g() {}\n');

    final found = remnantsUnder(planted.path);

    expect(
      found,
      hasLength(1),
      reason: 'one file holds the word, one does not',
    );
    expect(found.single, contains('a_row.dart'));
    expect(found.single, contains('LayerKind.text'));
  });
}
