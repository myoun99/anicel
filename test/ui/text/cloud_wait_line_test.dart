import 'package:anicel/src/ui/text/app_strings.dart';
import 'package:anicel/src/ui/text/cloud_wait_line.dart';
import 'package:flutter_test/flutter_test.dart';

/// F-141 (유저 2026-09-16): 「그리고 n초동안 클라우드에서 받지 못했습니다?
/// … 진짜로 받은게 없어서인지 아니면 1,2,3초 세는거랑 똑같은데 그냥 오래
/// 걸려서 뜨는건지. 그냥 오래걸리고있는거면 갑자기 표현 다르게두지말것」.
///
/// It was the clock alone: past ten seconds the line changed its words
/// whatever the file was doing. The words follow the ARRIVAL now — and
/// since F-608 ① (2026-11-17), the LAST arrival: a download that stopped
/// halfway is stuck too.
void main() {
  /// A cloud wait's line: the device says the file is still on its way.
  String fromTheCloud(Duration waited, Duration quiet) =>
      cloudWaitLine(waited, quiet, fromTheCloud: true);

  test('🎯a file coming down slowly keeps COUNTING — the words do not '
      'change just because time passed', () {
    final strings = AppText.strings;

    expect(
      fromTheCloud(
        const Duration(seconds: 30),
        const Duration(milliseconds: 900),
      ),
      strings.openWaitingCloudTemplate.replaceAll('{sec}', '30'),
      reason: 'it is arriving, so saying nothing arrived would be a lie',
    );
  });

  test('🚨「nothing arrived」 is said only when nothing has, for the '
      'seconds nothing has', () {
    final strings = AppText.strings;

    expect(
      fromTheCloud(const Duration(seconds: 30), const Duration(seconds: 30)),
      strings.openWaitingStalledTemplate.replaceAll('{sec}', '30'),
      reason: 'not a byte of it after thirty seconds — that is the news',
    );
    expect(
      fromTheCloud(const Duration(seconds: 3), const Duration(seconds: 3)),
      strings.openWaitingCloudTemplate.replaceAll('{sec}', '3'),
      reason: 'three seconds of nothing is an ordinary wait, not a stall',
    );
  });

  /// F-608 ① (2026-11-17): the user's file came down from Drive with the
  /// window saying only 「여는 중」 — and once the wait could see bytes, a
  /// download that STOPPED halfway still counted on as if moving.
  test('🚨a download that stops partway is stuck from its LAST byte — and '
      'the seconds it says are the quiet ones, not the whole wait', () {
    final strings = AppText.strings;

    expect(
      fromTheCloud(const Duration(seconds: 50), const Duration(seconds: 12)),
      strings.openWaitingStalledTemplate.replaceAll('{sec}', '12'),
      reason: 'twelve seconds of nothing since the last piece — not fifty',
    );
    expect(
      fromTheCloud(
        const Duration(seconds: 50),
        cloudWaitSaysNothingAfter - const Duration(milliseconds: 1),
      ),
      strings.openWaitingCloudTemplate.replaceAll('{sec}', '50'),
      reason: 'a hair under the floor is still a wait counting on',
    );
    expect(
      fromTheCloud(const Duration(seconds: 50), cloudWaitSaysNothingAfter),
      strings.openWaitingStalledTemplate.replaceAll('{sec}', '10'),
      reason: 'and the floor itself is where the words change',
    );
  });

  test('the second it shows is the second that has passed', () {
    expect(
      fromTheCloud(const Duration(milliseconds: 4200), Duration.zero),
      contains('4'),
    );
  });

  /// F-621-Q2 (유저 2026-11-19: 「투명하게만 하면되. 1번대로하자」): a
  /// file on the disk read for two seconds under 「クラウドから受信中」.
  test('🎯the cloud is named only while the device says the file is coming '
      'from it — a file it calls here is being READ, and a stall is a '
      'stall either way', () {
    final strings = AppText.strings;
    String reading(Duration waited, Duration quiet) =>
        cloudWaitLine(waited, quiet, fromTheCloud: false);

    expect(
      reading(const Duration(seconds: 2), Duration.zero),
      strings.openWaitingReadingTemplate.replaceAll('{sec}', '2'),
    );
    expect(
      fromTheCloud(const Duration(seconds: 2), Duration.zero),
      strings.openWaitingCloudTemplate.replaceAll('{sec}', '2'),
    );
    expect(
      reading(const Duration(seconds: 30), const Duration(seconds: 12)),
      strings.openWaitingStalledTemplate.replaceAll('{sec}', '12'),
      reason: 'nothing more of the file for twelve seconds is the news, '
          'whoever holds it',
    );
  });
}
