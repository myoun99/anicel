import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/services/persistence/folder_grant.dart';

/// **F-14 — a starting point is a hint, and a hint may not refuse.**
///
/// 유저 2026-08-24: 「윈도우에서 저장 시 **드라이브에 저장하려고하면 폴더선택을
/// 열 수 없었다고 뜨고 저장안됨**」.
///
/// `initialDirectory` is documented in `FolderPicker.pick` as a hint —
/// 「every platform is free to ignore it」 — and the pickers wrapped the call
/// in a catch-all that turned a hint the platform would not start in into
/// "the picker could not be opened". The hint is dropped and the same
/// question asked again.
void main() {
  test('a hint that throws is dropped, and the answer is the hintless one', () async {
    final asked = <String?>[];
    final answer = await FolderPicker.askingAgainWithoutHint((hint) async {
      asked.add(hint);
      if (hint != null) {
        throw StateError('D-drive is not a place this picker will start in');
      }
      return 'picked';
    }, 'D-drive');

    expect(answer, 'picked');
    expect(
      asked,
      ['D-drive', null],
      reason: 'the hint first, because it is what the user meant; then the '
          'same question without the half that refused',
    );
  });

  test('a hint that works is the only attempt', () async {
    var calls = 0;
    final answer = await FolderPicker.askingAgainWithoutHint((hint) async {
      calls += 1;
      return hint;
    }, '/somewhere');

    expect(answer, '/somewhere');
    expect(calls, 1, reason: 'nothing refused, so nothing is asked twice');
  });

  test('⛔a refusal with NO hint to drop is a real refusal', () async {
    var calls = 0;
    await expectLater(
      FolderPicker.askingAgainWithoutHint((hint) async {
        calls += 1;
        throw StateError('no picker here at all');
      }, null),
      throwsStateError,
    );
    expect(
      calls,
      1,
      reason: 'the second attempt exists to remove the hint — with none to '
          'remove there is nothing else to try',
    );
  });

  test('and a refusal that survives the drop still throws', () async {
    var calls = 0;
    await expectLater(
      FolderPicker.askingAgainWithoutHint((hint) async {
        calls += 1;
        throw StateError('no picker here at all');
      }, '/somewhere'),
      throwsStateError,
    );
    expect(calls, 2);
  });
}
