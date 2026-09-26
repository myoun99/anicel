import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 🗣️F-193 (유저 2026-09-27): 「안드로이드, 도구버튼 위에서 펜 호버하다 펜
/// 아예때서 사라지면 버튼 활성화색? 흰색배경된채로 유지되있음」.
///
/// Flutter's Android embedding hands the framework HOVER_MOVE and SCROLL
/// and drops ACTION_HOVER_EXIT, so a pen leaving hover range was never said
/// to have left. The activity hands the exit on as a hover far outside the
/// window, and the framework exits every region the pen was over — the
/// Dart half of that is `app_icon_button_test`'s F-193 case.
///
/// ⚠️A SOURCE PIN, because no machine this suite runs on is an Android
/// device: it can say the activity turns a pen's exit into that hover; what
/// the tablet does with it is the device's to show.
void main() {
  final dispatch = _bodyOf(
    File(
      'android/app/src/main/kotlin/com/myoun/anicel/MainActivity.kt',
    ).readAsStringSync(),
    'override fun dispatchGenericMotionEvent(',
  );

  test('a pen\'s hover exit is handed on as a hover far outside', () {
    expect(dispatch, contains('super.dispatchGenericMotionEvent(ev)'));
    expect(dispatch, contains('MotionEvent.ACTION_HOVER_EXIT'));
    expect(dispatch, contains('MotionEvent.TOOL_TYPE_STYLUS'));
    expect(dispatch, contains('away.action = MotionEvent.ACTION_HOVER_MOVE'));
    expect(dispatch, contains('away.setLocation(-100000f, -100000f)'));
    expect(
      dispatch,
      contains('flutterView.onGenericMotionEvent(away)'),
      reason: 'and hands THAT event to the Flutter view — one built and '
          'then dropped would read the same above',
    );
  });
}

/// The body of the function whose declaration starts with [signature]:
/// from its opening brace to the one that closes it.
String _bodyOf(String source, String signature) {
  final start = source.indexOf(signature);
  expect(start, isNot(-1), reason: 'premise: $signature is in the file');
  final open = source.indexOf('{', start);
  var depth = 0;
  for (var i = open; i < source.length; i += 1) {
    switch (source[i]) {
      case '{':
        depth += 1;
      case '}':
        depth -= 1;
        if (depth == 0) {
          return source.substring(open, i + 1);
        }
    }
  }
  fail('$signature never closes');
}
