import 'dart:async';
import 'dart:io';

import 'package:anicel/src/services/persistence/folder_grant.dart';
import 'package:flutter_test/flutter_test.dart';

/// The wait a cloud pick needs, and the copy it must NOT make.
///
/// Fetching a File Provider placeholder takes time and the provider
/// reports that by failing the read it has just started (실측 08-27,
/// iPhone + Google Drive: the first open said 「잠시 후 다시 시도해
/// 주세요」, the second opened the same file). So the materialiser asks
/// the platform to fetch and waits for THE PICK to read.
///
/// ⛔It used to stage a local copy instead (유저 2026-08-27: 「사본은
/// 왠만하면 만들고싶지않아」): the cloud client already keeps one, so
/// ours was the same bytes twice, and the `.anicel` door left it in the
/// system temp with every cel ref pointing inside it. The staged road
/// survives only as an alarmed last resort — `staged: true` is the
/// caller's cue to say so on screen.
void main() {
  late Directory temp;

  setUp(() {
    temp = Directory.systemTemp.createTempSync('anicel-materialise');
  });

  tearDown(() {
    FolderPicker.debugCoordinatedReader = null;
    FolderPicker.debugDownloadRequester = null;
    FolderPicker.debugCoordinatedInPlaceReader = null;
    FolderPicker.debugOperatingSystem = null;
    if (temp.existsSync()) {
      temp.deleteSync(recursive: true);
    }
  });

  /// 🚨★★★THE PROVIDER IS ASKED BEFORE A READABLE FILE IS BELIEVED. A
  /// materialised File Provider item reads at once — and on 2026-09-13
  /// what read at once was the copy Drive had cached from the iPad's own
  /// first save: one cut of twelve, the desktop's revision sitting in the
  /// cloud. `requestFileDownload` is iCloud's API and Drive ignores it;
  /// a coordinated read is what a provider answers with its current item.
  /// It copies nothing — the pick is still the file that opens.
  test('🎯with a coordinator the provider is ASKED before a readable file '
      'is believed — the copy it cached may be old', () async {
    FolderPicker.debugOperatingSystem = 'ios';
    final path = '${temp.path}${Platform.pathSeparator}drive.anicel';
    File(path).writeAsBytesSync(const [9, 9]);
    final asked = <String>[];
    FolderPicker.debugCoordinatedInPlaceReader = (requested) async {
      asked.add(requested);
      return true;
    };
    var downloads = 0;
    FolderPicker.debugDownloadRequester = (_) async => downloads += 1;

    final source = await FolderPicker.materializeOpenedFile(path);

    expect(asked, [path], reason: 'one coordinated read, copying nothing');
    expect(
      downloads,
      0,
      reason: 'it read at once — the fetch-and-wait is for a placeholder',
    );
    expect(source.staged, isFalse);
    expect(source.path, path, reason: 'the pick is the file that opens');
  });

  /// 🚨★★★F-135 (유저 2026-09-15: 「우선 프로젝트 열 때 여는중 이라고만
  /// 뜨는데」) — on an iPad the provider's fetch IS the long wait, and it
  /// used to be awaited before the wait's clock and its Cancel existed.
  test('🚨 while the PROVIDER holds the file, the wait reports itself',
      () async {
    FolderPicker.debugOperatingSystem = 'ios';
    final path = '${temp.path}${Platform.pathSeparator}fetching.anicel';
    File(path).writeAsBytesSync(const [9, 9]);
    final provider = Completer<bool>();
    FolderPicker.debugCoordinatedInPlaceReader = (_) => provider.future;
    final seen = <Duration>[];

    final opening = FolderPicker.materializeOpenedFile(
      path,
      within: null,
      step: const Duration(milliseconds: 5),
      onWaiting: seen.add,
      isCancelled: () => false,
    );
    await Future<void>.delayed(const Duration(milliseconds: 80));
    expect(seen, isNotEmpty, reason: 'the fetch is the wait a window draws');
    provider.complete(true);

    final source = await opening;
    expect(source.path, path, reason: 'when the provider lets go, it opens');
  });

  test('🚨 a Cancel while the PROVIDER holds the file stops the open there',
      () async {
    FolderPicker.debugOperatingSystem = 'ios';
    final path = '${temp.path}${Platform.pathSeparator}stopped.anicel';
    File(path).writeAsBytesSync(const [9, 9]);
    // The provider answers late, and fine — so an open that ignored the
    // Cancel would come back with the pick instead of stopping.
    FolderPicker.debugCoordinatedInPlaceReader = (_) =>
        Future<bool>.delayed(const Duration(milliseconds: 400), () => true);
    var stop = false;

    final opening = FolderPicker.materializeOpenedFile(
      path,
      within: null,
      step: const Duration(milliseconds: 5),
      isCancelled: () => stop,
    );
    await Future<void>.delayed(const Duration(milliseconds: 30));
    stop = true;

    await expectLater(opening, throwsA(isA<MaterializeCancelled>()));
  });

  test('an instant answer from the provider is not a wait — nothing is '
      'reported, and no tick is waited out', () async {
    FolderPicker.debugOperatingSystem = 'ios';
    final path = '${temp.path}${Platform.pathSeparator}instant.anicel';
    File(path).writeAsBytesSync(const [9, 9]);
    FolderPicker.debugCoordinatedInPlaceReader = (_) async => true;
    final seen = <Duration>[];
    final clock = Stopwatch()..start();

    // ⚠️A LONG tick, and the time measured. Nothing reported is not enough:
    // a wait that sat out its tick before noticing the answer reports
    // nothing either — it only opens every local file a tick late.
    await FolderPicker.materializeOpenedFile(
      path,
      within: null,
      step: const Duration(seconds: 3),
      onWaiting: seen.add,
      isCancelled: () => false,
    );

    expect(seen, isEmpty);
    expect(
      clock.elapsed,
      lessThan(const Duration(seconds: 1)),
      reason: 'the answer ends the tick, not the tick the answer',
    );
  });

  test('without a coordinator nothing is asked — there is nobody to ask',
      () async {
    FolderPicker.debugOperatingSystem = 'windows';
    final path = '${temp.path}${Platform.pathSeparator}local.anicel';
    File(path).writeAsBytesSync(const [9, 9]);
    var asked = 0;
    FolderPicker.debugCoordinatedInPlaceReader = (_) async {
      asked += 1;
      return true;
    };

    await FolderPicker.materializeOpenedFile(path);

    expect(asked, 0);
  });

  /// A placeholder to every probe this code makes: an entry that is
  /// there and reads as nothing.
  String placeholder(String name) {
    final path = '${temp.path}${Platform.pathSeparator}$name';
    File(path).writeAsBytesSync(const <int>[]);
    return path;
  }

  test('the fetch is REQUESTED and the pick itself is what gets opened — '
      'no copy is made', () async {
    final path = placeholder('arrives.tvpp');
    var asked = 0;
    var staged = 0;
    // 🚨★★★THE ARRIVAL IS CAUSED BY THE ASK, not scheduled beside it.
    //
    // This used to land the bytes on an 8 ms timer. Under the full suite
    // that timer could fire BEFORE `materializeOpenedFile` ran its first
    // probe — and a file that is already readable returns immediately
    // WITHOUT asking, which is correct product behaviour and exactly what
    // the next test pins. So the assertion below read `asked == 0` and the
    // gate went red for a reason that had nothing to do with the code
    // (실측 2026-08-28: green alone, intermittently red in a bulk run).
    //
    // ⛔The fix is the test's, not the product's. Writing from inside the
    // requester is also the truer story: the platform lands the bytes
    // BECAUSE it was asked to fetch them.
    FolderPicker.debugDownloadRequester = (requested) async {
      asked += 1;
      expect(requested, path);
      // The provider lands the bytes in the PICK, which is what
      // materialisation actually means.
      File(path).writeAsBytesSync(const [1, 2, 3]);
    };
    FolderPicker.debugCoordinatedReader =
        ({required String sourcePath, required String destinationPath}) async {
          staged += 1;
          return false;
        };

    final source = await FolderPicker.materializeOpenedFile(
      path,
      within: const Duration(seconds: 2),
      step: const Duration(milliseconds: 1),
    );

    expect(asked, 1, reason: 'asked the platform to fetch it');
    expect(staged, 0, reason: 'and copied nothing while waiting');
    expect(source.staged, isFalse);
    expect(source.path, path, reason: 'the pick is the file that opens');
  });

  test('a file already readable is opened untouched — nothing is asked, '
      'nothing is copied', () async {
    final path = '${temp.path}${Platform.pathSeparator}local.anicel';
    File(path).writeAsBytesSync(const [9, 9]);
    var asked = 0;
    FolderPicker.debugDownloadRequester = (_) async => asked += 1;

    final source = await FolderPicker.materializeOpenedFile(path);

    expect(asked, 0);
    expect(source.staged, isFalse);
    expect(source.path, path);
  });

  test('a wait the user stops is CANCELLED, not failed — and with a cancel '
      'in hand there is NO deadline at all', () async {
    // 유저 2026-08-27: 「상한을 두는 게 아니라 … 유저가 보고 판단해서
    // 취소 버튼을 누르게」. A clock cannot tell a slow line from a dead
    // one; the person watching can. So `within: null` waits as long as
    // the file takes, and the only thing that ends it is the person.
    final path = placeholder('slow.tvpp');
    FolderPicker.debugDownloadRequester = (_) async {};
    var polls = 0;

    await expectLater(
      FolderPicker.materializeOpenedFile(
        path,
        within: null,
        step: const Duration(milliseconds: 1),
        isCancelled: () => ++polls > 3,
      ),
      throwsA(isA<MaterializeCancelled>()),
    );
    expect(polls, greaterThan(3), reason: 'it waited until it was stopped');
  });

  test('🚨 no deadline is REFUSED without a way to be stopped', () async {
    // Otherwise 「no deadline」 would mean 「no way out」 — a hang with a
    // nice name. Loud at the call site beats a silent substitution that
    // makes the caller think it got the wait it asked for.
    expect(
      () => FolderPicker.materializeOpenedFile(
        placeholder('nobody-watching.tvpp'),
        within: null,
      ),
      throwsArgumentError,
    );
  });

  test('the wait reports itself, so a door can draw it', () async {
    final path = placeholder('watched.tvpp');
    FolderPicker.debugDownloadRequester = (_) async {};
    final seen = <Duration>[];

    await expectLater(
      FolderPicker.materializeOpenedFile(
        path,
        within: const Duration(milliseconds: 20),
        step: const Duration(milliseconds: 5),
        onWaiting: seen.add,
      ),
      throwsA(isA<FileSystemException>()),
    );
    expect(seen, isNotEmpty);
    expect(
      seen.last,
      greaterThan(seen.first),
      reason: 'elapsed grows — that is what a waiting window shows',
    );
  });

  test('🚨 the LAST RESORT stages a copy and says so, for a door to '
      'announce', () async {
    final path = placeholder('never.tvpp');
    FolderPicker.debugDownloadRequester = (_) async {};
    FolderPicker.debugCoordinatedReader =
        ({required String sourcePath, required String destinationPath}) async {
          File(destinationPath).writeAsBytesSync(const [4, 5]);
          return true;
        };

    final source = await FolderPicker.materializeOpenedFile(
      path,
      within: const Duration(milliseconds: 20),
      step: const Duration(milliseconds: 5),
    );

    expect(
      source.staged,
      isTrue,
      reason: 'the caller has to be able to TELL the user a copy was made',
    );
    expect(source.path, isNot(path));
    expect(File(source.path).readAsBytesSync(), const [4, 5]);
    File(source.path).deleteSync();
  });

  test('a pick with no entry waits for nothing and asks for nothing', () async {
    var asked = 0;
    var staged = 0;
    FolderPicker.debugDownloadRequester = (_) async => asked += 1;
    FolderPicker.debugCoordinatedReader =
        ({required String sourcePath, required String destinationPath}) async {
          staged += 1;
          return false;
        };

    await expectLater(
      FolderPicker.materializeOpenedFile(
        '${temp.path}${Platform.pathSeparator}gone.anicel',
        // Long enough that waiting would be obvious: nothing is on its
        // way to a path that does not exist.
        within: const Duration(seconds: 30),
        step: const Duration(seconds: 1),
      ),
      throwsA(isA<FileSystemException>()),
    );
    expect(asked, 0);
    expect(staged, 1, reason: 'it still costs ONE attempt, not the road');
  });
}
