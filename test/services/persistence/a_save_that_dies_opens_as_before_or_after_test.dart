import 'dart:io';
import 'dart:typed_data';

import 'package:anicel/src/services/persistence/anicel_incremental_writer.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/save_crash_replay.dart';

/// 🗣️유저 2026-09-23: 「전부 재사용으로 하고싶은데 거기서 저장중 크래시만
/// 어떻게 안전책 만들수없나?」 — every dead byte reused, and a save that
/// dies must not cost the file.
///
/// 🚨★★★THE SWEEP: a whole save — the 떼기 커밋, the push-down in rounds,
/// the cut — and the file as a crash after EVERY byte of it would leave
/// it ([SaveRecording]), each opened the way the app opens a file. It must
/// open as the file before the save or the file after it. The one allowed
/// blend is the one recovery names: a save that died writing the directory
/// that would have committed its entries keeps those entries, and the
/// names it removed come back (too much beats lost).
void main() {
  late Directory directory;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('anicel-dies');
  });

  tearDown(() => directory.delete(recursive: true));

  Uint8List filled(int length, int seed) => Uint8List.fromList(
    List<int>.generate(length, (i) => (i * seed + 7) & 0xFF),
  );

  /// A file whose garbage is spread through it, so the push-down takes
  /// rounds and every round lands where the one before it left.
  String spreadOutFixture() {
    final path = '${directory.path}/project.anicel';
    writeAnicelArchiveFile(
      path: path,
      entries: [
        for (var i = 0; i < 8; i += 1)
          (name: 'e$i', bytes: filled(24 + 5 * i, i + 2)),
      ],
    );
    appendAnicelEntries(
      path: path,
      newEntries: {for (var i = 0; i < 8; i += 2) 'e$i': filled(20 + i, 40 + i)},
    );
    return path;
  }

  /// The save under test: rewrite one entry, drop one, add one — then pack.
  Future<int> save(String path) async {
    final appended = appendAnicelEntries(
      path: path,
      newEntries: {'e1': filled(30, 77), 'fresh': filled(18, 5)},
      removeNames: const {'e5'},
    );
    var rounds = 0;
    await compactAnicelInPlace(
      path: path,
      layout: appended,
      release: (_) async => rounds += 1,
    );
    return rounds;
  }

  /// [run] against the file at [path], heard byte by byte.
  Future<SaveRecording> recorded(Future<void> Function() run) async {
    final recording = SaveRecording();
    anicelDebugWriteWatcher = recording;
    try {
      await run();
    } finally {
      anicelDebugWriteWatcher = null;
    }
    return recording;
  }

  test('🚨🚨a save stopped after ANY byte opens as before it or after it',
      () async {
    final path = spreadOutFixture();
    final beforeBytes = File(path).readAsBytesSync();
    final before = openedAsTheAppWould(beforeBytes);
    var rounds = 0;
    final recording = await recorded(() async => rounds = await save(path));
    final afterBytes = File(path).readAsBytesSync();
    final after = openedAsTheAppWould(afterBytes);
    // The one blend recovery allows: every entry the save wrote, and the
    // name it removed back from the state before it.
    final committingDied = {...after, 'e5': before['e5']!};
    expect(rounds, greaterThanOrEqualTo(2), reason: 'fixture: rounds');
    expect(sameContents(after, before), isFalse, reason: 'fixture');

    var states = 0;
    var sawBefore = 0;
    var sawAfter = 0;
    var sawBlend = 0;
    Uint8List? last;
    for (final state in recording.statesFrom(beforeBytes)) {
      final opened = openedAsTheAppWould(state);
      if (sameContents(opened, before)) {
        sawBefore += 1;
      } else if (sameContents(opened, after)) {
        sawAfter += 1;
      } else {
        expect(
          sameContents(opened, committingDied),
          isTrue,
          reason: 'stopped after byte $states the file opened as neither '
              'state: ${opened.keys.toList()..sort()}',
        );
        sawBlend += 1;
      }
      states += 1;
      last = state;
    }

    expect(
      last,
      afterBytes,
      reason: 'the replay ends where the real save ended — every write the '
          'save made was heard',
    );
    expect(sawBefore, greaterThan(0), reason: 'the sweep reached the start');
    expect(sawAfter, greaterThan(0), reason: 'the sweep reached the end');
    expect(
      sawBlend,
      greaterThan(0),
      reason: 'the sweep reached a save dying as it committed',
    );
  });

  test('🚨the save after a compaction dies just as safely — it starts from '
      'the directory the cut left', () async {
    final path = spreadOutFixture();
    // A finished save that packs the file and cuts it.
    await save(path);
    final beforeBytes = File(path).readAsBytesSync();
    final before = openedAsTheAppWould(beforeBytes);

    final recording = await recorded(() async {
      appendAnicelEntries(
        path: path,
        newEntries: {'e2': filled(26, 9), 'later': filled(12, 3)},
      );
    });
    final afterBytes = File(path).readAsBytesSync();
    final after = openedAsTheAppWould(afterBytes);

    var byte = 0;
    for (final state in recording.statesFrom(beforeBytes)) {
      final opened = openedAsTheAppWould(state);
      expect(
        sameContents(opened, before) || sameContents(opened, after),
        isTrue,
        reason: 'stopped after byte $byte',
      );
      byte += 1;
    }
  });
}
