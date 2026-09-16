import 'package:anicel/src/services/persistence/folder_grant.dart'
    show FileArrival;
import 'package:anicel/src/ui/text/app_strings.dart';
import 'package:anicel/src/ui/text/cloud_wait_line.dart';
import 'package:flutter_test/flutter_test.dart';

/// F-141 (유저 2026-09-16): 「그리고 n초동안 클라우드에서 받지 못했습니다?
/// … 진짜로 받은게 없어서인지 아니면 1,2,3초 세는거랑 똑같은데 그냥 오래
/// 걸려서 뜨는건지. 그냥 오래걸리고있는거면 갑자기 표현 다르게두지말것」.
///
/// It was the clock alone: past ten seconds the line changed its words
/// whatever the file was doing. The words follow the ARRIVAL now.
void main() {
  test('🎯a file coming down slowly keeps COUNTING — the words do not '
      'change just because time passed', () {
    final strings = AppText.strings;

    expect(
      cloudWaitLine(const Duration(seconds: 30), FileArrival.partway),
      strings.openWaitingCloudTemplate.replaceAll('{sec}', '30'),
      reason: 'it is arriving, so saying nothing arrived would be a lie',
    );
  });

  test('🚨and 「nothing arrived」 is said only when nothing has', () {
    final strings = AppText.strings;

    expect(
      cloudWaitLine(const Duration(seconds: 30), FileArrival.nothing),
      strings.openWaitingStalledTemplate.replaceAll('{sec}', '30'),
      reason: 'not a byte of it after thirty seconds — that is the news',
    );
    expect(
      cloudWaitLine(const Duration(seconds: 3), FileArrival.nothing),
      strings.openWaitingCloudTemplate.replaceAll('{sec}', '3'),
      reason: 'three seconds of nothing is an ordinary wait, not a stall',
    );
  });

  test('the second it shows is the second that has passed', () {
    expect(
      cloudWaitLine(const Duration(milliseconds: 4200), FileArrival.partway),
      contains('4'),
    );
  });
}
