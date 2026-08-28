import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 🔄F-46 — **두 뷰어는 같은 아이콘을 쓴다.**
///
/// > 「서브뷰어 패널 아이콘을 일반 뷰어 패널 아이콘을 재사용. 즉 둘이 똑같은
/// > 아이콘 사용. **다 감안하고 말하는것임**」
///
/// ⚠️전에는 **일부러** 달랐고 그 이유가 코드에 적혀 있었다 — 「레일 버튼은
/// 아이콘이 전부라 같은 글리프면 구분이 안 된다」. 유저가 **그것까지 알고**
/// 뒤집었으므로, 다음에 읽는 쪽이 그 주석을 보고 되돌리지 않게 잠근다.
///
/// ⛔소스를 읽는다: 탭 서술자는 State 의 private 스위치라 위젯에서 꺼낼 이음매가
/// 없고, 아이콘 하나를 위해 그 이음매를 새로 뚫는 것은 과하다. 대신 **두 case
/// 블록의 `icon:` 줄을 뽑아 비교**한다 — 구조가 바뀌면 조용히 통과하지 않고
/// 「못 찾았다」로 빨개진다.
void main() {
  String iconOfCase(String source, String caseLabel) {
    final start = source.indexOf('case EditorWorkspace.$caseLabel:');
    expect(start, isNot(-1), reason: '⛔$caseLabel 를 못 찾았다 — 빈 것을 쟀다');
    final next = source.indexOf('      case ', start + 10);
    final block = source.substring(start, next == -1 ? source.length : next);
    final icon = RegExp(r'icon:\s*(Icons\.\w+)').firstMatch(block);
    expect(icon, isNotNull, reason: '⛔$caseLabel 안에 icon: 이 없다');
    return icon!.group(1)!;
  }

  test('뷰어와 서브뷰어의 탭 아이콘이 같다', () {
    final source = File(
      'lib/src/ui/editor_workspace.dart',
    ).readAsStringSync();
    expect(
      iconOfCase(source, 'mediaViewerSubTabId'),
      iconOfCase(source, 'mediaViewerTabId'),
      reason: '유저 2026-08-28 확정(F-46) — 둘이 똑같은 아이콘',
    );
  });
}
