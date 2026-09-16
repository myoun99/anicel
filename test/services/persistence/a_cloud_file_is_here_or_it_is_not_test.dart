import 'dart:io';

import 'package:anicel/src/services/persistence/folder_grant.dart';
import 'package:flutter_test/flutter_test.dart';

/// F-142 · F-141 (유저 2026-09-16).
///
/// > 「드라이브에 있던 파일 열때, 드라이브프로그램에서 아직 다운로드가
/// > 안됬는데(속도가 느림) 그냥 열려버렸거든? … 다 다운 안했는데 그냥
/// > 열어버린 느낌이 있음. 제대로 확인.」
///
/// > 「클라우드에서 내려받는중 표시가 1,2,3초가 아니라 1,3,5초마다? 보임.」
///
/// Both came out of ONE function and ONE habit: a value that answered two
/// questions. The probe asked 「can I read a byte」 and was believed to have
/// answered 「is it all here」; the wait's accumulator answered 「how often
/// do I ask」 and was drawn as 「how long has it been」.
void main() {
  late Directory temp;

  setUp(() {
    temp = Directory.systemTemp.createTempSync('anicel-arrival');
  });

  tearDown(() {
    FolderPicker.debugArrival = null;
    FolderPicker.debugDownloadRequester = null;
    FolderPicker.debugCoordinatedReader = null;
    FolderPicker.debugOperatingSystem = null;
    if (temp.existsSync()) {
      temp.deleteSync(recursive: true);
    }
  });

  String at(String name) => '${temp.path}${Platform.pathSeparator}$name';

  test('🎯the LAST byte is what says it is all here', () async {
    final whole = at('whole.anicel');
    File(whole).writeAsBytesSync(const [1, 2, 3]);
    final empty = at('placeholder.anicel');
    File(empty).writeAsBytesSync(const <int>[]);

    expect(await FolderPicker.arrivalOf(whole), FileArrival.whole);
    expect(
      await FolderPicker.arrivalOf(empty),
      FileArrival.nothing,
      reason: 'it exists and reads as nothing — the placeholder case',
    );
    expect(await FolderPicker.arrivalOf(at('gone.anicel')), FileArrival.nothing);
  });

  /// 🚨★★★THE ONE THE USER HIT. A placeholder fills from the FRONT, so the
  /// first byte lands long before the file does — and Windows has no
  /// coordinator to appeal to, which makes this probe the whole answer
  /// there.
  test('🚨a file only PARTWAY here is NOT opened — the open waits for the '
      'tail', () async {
    FolderPicker.debugOperatingSystem = 'windows';
    final path = at('coming-down.anicel');
    File(path).writeAsBytesSync(const [1, 2, 3]);
    var probes = 0;
    FolderPicker.debugArrival = (_) async =>
        ++probes < 3 ? FileArrival.partway : FileArrival.whole;
    FolderPicker.debugDownloadRequester = (_) async {};

    final source = await FolderPicker.materializeOpenedFile(
      path,
      within: const Duration(seconds: 5),
      step: const Duration(milliseconds: 1),
    );

    expect(
      probes,
      greaterThanOrEqualTo(3),
      reason: 'it kept asking while the tail was still in the cloud',
    );
    expect(source.path, path, reason: 'and then opened the pick itself');
    expect(source.staged, isFalse, reason: 'no copy was made to wait');
  });

  /// 🚨THE BEAT. Measured on this machine before the change, at the
  /// product's own 250ms step: the window was shown seconds
  /// **[0, 0, 1, 3, 5]** (250 · 750 · 1750 · 3750 · 5750 ms) — the probe
  /// spacing's running total, doubling as it went.
  test('🚨the window is shown a CLOCK, not the probe spacing — no second '
      'is skipped', () async {
    final path = at('never.anicel');
    File(path).writeAsBytesSync(const <int>[]);
    FolderPicker.debugDownloadRequester = (_) async {};
    final seen = <Duration>[];

    await expectLater(
      FolderPicker.materializeOpenedFile(
        path,
        within: const Duration(milliseconds: 4200),
        onWaiting: (waited, _) => seen.add(waited),
      ),
      throwsA(isA<FileSystemException>()),
    );

    final seconds = [for (final waited in seen) waited.inSeconds];
    expect(seconds, isNotEmpty);
    for (var i = 1; i < seconds.length; i += 1) {
      expect(
        seconds[i] - seconds[i - 1],
        lessThanOrEqualTo(1),
        reason: 'a second was skipped: $seconds',
      );
    }
    expect(
      seconds.last,
      greaterThanOrEqualTo(3),
      reason: 'and it counted all the way to the deadline: $seconds',
    );
  });

  test('🚨the wait reports WHAT IT SAW, so the sentence can be true', () async {
    final path = at('slowly.anicel');
    File(path).writeAsBytesSync(const [1, 2, 3]);
    FolderPicker.debugArrival = (_) async => FileArrival.partway;
    FolderPicker.debugDownloadRequester = (_) async {};
    final arrivals = <FileArrival>[];

    await expectLater(
      FolderPicker.materializeOpenedFile(
        path,
        within: const Duration(milliseconds: 60),
        step: const Duration(milliseconds: 5),
        onWaiting: (_, arrival) => arrivals.add(arrival),
      ),
      throwsA(isA<FileSystemException>()),
    );

    expect(arrivals, isNotEmpty);
    expect(
      arrivals,
      everyElement(FileArrival.partway),
      reason: 'the line must not claim nothing arrived while it is arriving',
    );
  });

  /// 🚨★★★THE LAW ITSELF, with nothing to imitate.
  ///
  /// Every test above either goes through [FolderPicker.debugArrival] or
  /// uses a whole file, so a probe that quietly stopped asking the LAST
  /// byte would sail through all of them — and that is exactly the bug
  /// F-142 was. Here the ends answer for themselves.
  test('🚨the front alone is PARTWAY — only the last byte says whole', () async {
    final asked = <int>[];
    Future<FileArrival> arrival({
      required int length,
      required Set<int> here,
    }) => FolderPicker.arrivalFrom(
      length: () async => length,
      byteAt: (offset) async {
        asked.add(offset);
        return here.contains(offset);
      },
    );

    expect(await arrival(length: 900, here: const {0}), FileArrival.partway);
    expect(
      asked,
      const [0, 899],
      reason: 'both ends are asked, and the second one is the TAIL',
    );

    asked.clear();
    expect(await arrival(length: 900, here: const {0, 899}), FileArrival.whole);

    asked.clear();
    expect(
      await arrival(length: 900, here: const <int>{}),
      FileArrival.nothing,
    );
    expect(
      asked,
      const [0],
      reason: 'nothing at the front ends the question there',
    );
  });
}
