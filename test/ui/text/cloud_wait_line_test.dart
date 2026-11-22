import 'package:anicel/src/ui/text/app_strings.dart';
import 'package:anicel/src/ui/text/cloud_wait_line.dart';
import 'package:flutter_test/flutter_test.dart';

/// F-141 (유저 2026-09-16): 「그냥 오래걸리고있는거면 갑자기 표현
/// 다르게두지말것」 — and F-608 (유저 2026-11-23, a Galaxy Tab on build
/// 1098): 「그냥 도착안했다고 안뜨게하는게 젤 확실할거같은데」. A wait counts
/// to its end in the words it began with: no 「nothing has arrived」, however
/// long it goes on.
void main() {
  String fromTheCloud(Duration waited) =>
      cloudWaitLine(waited, fromTheCloud: true);
  String reading(Duration waited) => cloudWaitLine(waited, fromTheCloud: false);

  test('🎯a wait keeps COUNTING past ten seconds, a minute, ten minutes — '
      'the words never turn to 「nothing has arrived」', () {
    final strings = AppText.strings;
    for (final seconds in [9, 10, 11, 25, 60, 600]) {
      final waited = Duration(seconds: seconds);
      expect(
        fromTheCloud(waited),
        strings.openWaitingCloudTemplate.replaceAll('{sec}', '$seconds'),
      );
      expect(
        reading(waited),
        strings.openWaitingReadingTemplate.replaceAll('{sec}', '$seconds'),
      );
    }
  });

  test('the second it shows is the second that has passed', () {
    expect(
      fromTheCloud(const Duration(milliseconds: 4200)),
      AppText.strings.openWaitingCloudTemplate.replaceAll('{sec}', '4'),
    );
  });

  /// F-621-Q2 (유저 2026-11-19: 「투명하게만 하면되. 1번대로하자」): a
  /// file on the disk read for two seconds under 「クラウドから受信中」.
  test('🎯the cloud is named only while the device says the file is coming '
      'from it — a file it calls here is being READ', () {
    final strings = AppText.strings;
    expect(
      reading(const Duration(seconds: 2)),
      strings.openWaitingReadingTemplate.replaceAll('{sec}', '2'),
    );
    expect(
      fromTheCloud(const Duration(seconds: 2)),
      strings.openWaitingCloudTemplate.replaceAll('{sec}', '2'),
    );
  });
}
