import 'dart:io';
import 'dart:typed_data';

import 'package:anicel/src/services/persistence/anicel_incremental_writer.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/save_crash_replay.dart';
import '../../helpers/temp_dir.dart';

/// deleting-save-compacts-Q1 (유저 2026-09-23): 「한 번에 밀어 내리기 — 떼기
/// 커밋 → 구멍 뒤 살아 있는 바이트를 구멍으로 → 꼬리 자르기」.
///
/// 유저 2026-09-13, 실파일로: 품은 PDF 157MB 를 지우고 저장해도 파일이 안
/// 줄었고, 줄어들 때는 **전체 다시쓰기**(74MB 복사 + 옆 temp + 드라이브 전체
/// 업로드)로 줄었다. 한 파일 안에서, 그 저장에서 줄이는 것이 이 라운드다.
void main() {
  late Directory directory;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('anicel-pack');
  });

  tearDown(() => deleteTempQuietly(directory));

  Uint8List filled(int length, int seed) => Uint8List.fromList(
    List<int>.generate(length, (i) => (i * seed + 7) & 0xFF),
  );

  String archive(String name, List<(String, int, int)> entries) {
    final path = '${directory.path}/$name';
    writeAnicelArchiveFile(
      path: path,
      entries: [
        for (final (entryName, length, seed) in entries)
          (name: entryName, bytes: filled(length, seed)),
      ],
    );
    return path;
  }

  /// What the strict reader sees: every entry's bytes, by name.
  Map<String, Uint8List> contents(String path) {
    final layout = parseAnicelZipLayoutFile(path);
    final bytes = File(path).readAsBytesSync();
    return {
      for (final entry in layout.entries)
        entry.name: Uint8List.sublistView(
          bytes,
          entry.dataOffset,
          entry.dataOffset + entry.length,
        ),
    };
  }

  Future<AnicelZipLayout> packed(
    AnicelZipLayout layout,
    String path, {
    Future<void> Function(Map<int, AnicelRelocation> moved)? release,
  }) => compactAnicelInPlace(
    path: path,
    layout: layout,
    readers: (move: release ?? (_) async {}, holding: const {}),
  );

  test('🎯the 떼기 커밋 writes over NOTHING — every byte the file had before '
      'it is still there after it', () {
    final path = archive('detach.anicel', [
      ('head.bin', 1024, 3),
      ('big.bin', 64 * 1024, 5),
      ('tail.bin', 2048, 11),
    ]);
    final before = File(path).readAsBytesSync();

    appendAnicelEntries(
      path: path,
      newEntries: {'added.bin': filled(64, 2)},
      removeNames: const {'big.bin'},
    );

    expect(
      File(path).readAsBytesSync().sublist(0, before.length),
      before,
      reason: 'the old directory stays whole behind the new entries — a '
          'crash before the new one lands opens the file as it was',
    );
  });

  test('🎯dropping the big entry SHRINKS the file in that same save', () async {
    final path = archive('drop.anicel', [
      ('head.bin', 1024, 3),
      ('big.bin', 256 * 1024, 5),
      ('tail.bin', 2048, 11),
    ]);
    final before = File(path).lengthSync();

    final appended = appendAnicelEntries(
      path: path,
      newEntries: const {},
      removeNames: const {'big.bin'},
    );
    await packed(appended, path);

    expect(
      File(path).lengthSync(),
      lessThan(before - 200 * 1024),
      reason: 'the 256KB hole is taken back now, not two saves later',
    );
  });

  test('🚨what survives reads back byte for byte, and the strict reader '
      'finds exactly the survivors', () async {
    final path = archive('survive.anicel', [
      ('head.bin', 1024, 3),
      ('big.bin', 256 * 1024, 5),
      ('tail.bin', 2048, 11),
    ]);

    final appended = appendAnicelEntries(
      path: path,
      newEntries: {'added.bin': filled(64, 2)},
      removeNames: const {'big.bin'},
    );
    final layout = await packed(appended, path);

    expect(contents(path), {
      'head.bin': filled(1024, 3),
      'tail.bin': filled(2048, 11),
      'added.bin': filled(64, 2),
    });
    expect(
      [for (final entry in layout.entries) entry.name]..sort(),
      const ['added.bin', 'head.bin', 'tail.bin'],
      reason: 'the layout handed back is the file as it now reads',
    );
  });

  test('🚨nothing is written beside the file — that is the point of doing '
      'it here', () async {
    final path = archive('no-temp.anicel', [
      ('head.bin', 1024, 3),
      ('big.bin', 256 * 1024, 5),
      ('tail.bin', 2048, 11),
    ]);

    final appended = appendAnicelEntries(
      path: path,
      newEntries: const {},
      removeNames: const {'big.bin'},
    );
    await packed(appended, path);

    expect(
      [
        for (final item in directory.listSync())
          item.path.split(Platform.pathSeparator).last,
      ],
      const ['no-temp.anicel'],
      reason: '유저: 「temp도 되도록 안만들고싶고」',
    );
  });

  test('🚨🚨A REF IS NEVER WRITTEN OVER BEFORE IT IS RELEASED — the session '
      'reads cels by offset while the save runs', () async {
    // Garbage spread through the file, so the push-down takes rounds and
    // every round lands on bytes the round before it vacated.
    final path = archive('rounds.anicel', [
      for (var i = 0; i < 12; i += 1) ('e$i.bin', 200 + 37 * i, i + 2),
    ]);
    // Every other entry rewritten: its old bytes turn into holes.
    appendAnicelEntries(
      path: path,
      newEntries: {
        for (var i = 0; i < 12; i += 2) 'e$i.bin': filled(180 + 11 * i, 50 + i),
      },
    );
    final appended = appendAnicelEntries(
      path: path,
      newEntries: {'fresh.bin': filled(90, 7)},
    );
    final want = contents(path);

    // A session holding a ref to every entry, by data offset.
    final held = {
      for (final entry in appended.entries) entry.name: entry.dataOffset,
    };
    void everyRefReadsItsOwnBytes(String when) {
      final bytes = File(path).readAsBytesSync();
      for (final MapEntry(key: name, value: at) in held.entries) {
        expect(
          Uint8List.sublistView(bytes, at, at + want[name]!.length),
          want[name],
          reason: '$when: the ref to $name reads someone else\'s bytes',
        );
      }
    }

    var releases = 0;
    await packed(
      appended,
      path,
      release: (moved) async {
        releases += 1;
        // The session answers from another isolate — a hop, not a call.
        // A save that did not wait for the answer would be writing its next
        // round right here.
        await Future<void>.delayed(Duration.zero);
        // Before the refs move: every one of them still reads its bytes —
        // this round wrote only where nobody points.
        everyRefReadsItsOwnBytes('release $releases, before moving');
        for (final name in held.keys) {
          final to = moved[held[name]];
          if (to != null) {
            held[name] = to.dataOffset;
          }
        }
        // And where the save says they went, the bytes are already there.
        everyRefReadsItsOwnBytes('release $releases, after moving');
      },
    );

    expect(
      releases,
      greaterThanOrEqualTo(3),
      reason: 'fixture: the push-down must have taken rounds',
    );
    everyRefReadsItsOwnBytes('after the cut');
    expect(contents(path), want);
  });

  test('🚨a dead tail with nothing to move is cut to size', () async {
    final path = archive('tail.anicel', [
      ('head.bin', 1024, 3),
      ('last.bin', 64 * 1024, 5),
    ]);
    final before = File(path).lengthSync();

    final appended = appendAnicelEntries(
      path: path,
      newEntries: const {},
      removeNames: const {'last.bin'},
    );
    var releases = 0;
    await packed(appended, path, release: (_) async => releases += 1);

    expect(releases, 0, reason: 'nothing moved, so no ref had to');
    expect(File(path).lengthSync(), lessThan(before - 60 * 1024));
    expect(contents(path), {'head.bin': filled(1024, 3)});
  });

  test('🚨the directory coming down never lands on the committed one — when '
      'the gap is shorter than it, one more commit goes first', () async {
    // Built by hand, because no save of ours reaches this shape: x.bin
    // twice (the live copy first, a stale one behind it), a big entry the
    // stale gap is too small to take, many small entries (a directory far
    // bigger than the gap it has to come down into), and a small dead
    // tail. The stale copy is what makes losing the directory COST
    // something: the walk that runs when no directory is whole reads
    // local headers in file order and takes the LAST x.bin.
    final path = '${directory.path}/crowded.anicel';
    final template = '${directory.path}/crowded-template.anicel';
    writeAnicelArchiveFile(
      path: template,
      entries: [
        (name: 'x.bin', bytes: filled(24, 1)),
        (name: 'x.bin', bytes: filled(24, 2)),
        (name: 'big.bin', bytes: filled(4096, 3)),
        for (var i = 0; i < 30; i += 1)
          (name: 'entry-number-$i.bin', bytes: filled(8, i + 4)),
        (name: 'small-tail.bin', bytes: filled(16, 99)),
      ],
    );
    final onDisk = parseAnicelZipLayoutFile(template);
    // The directory on disk still names both copies and the tail; the
    // layout handed in has let go of the stale copy and the tail.
    final live = AnicelZipLayout(
      entries: [
        onDisk.entries.first,
        for (final entry in onDisk.entries.skip(2))
          if (entry.name != 'small-tail.bin') entry,
      ],
      centralDirectoryOffset: onDisk.centralDirectoryOffset,
    );

    File(template).copySync(path);
    final beforeBytes = File(path).readAsBytesSync();
    final recording = SaveRecording();
    anicelDebugWriteWatcher = recording;
    try {
      await packed(live, path);
    } finally {
      anicelDebugWriteWatcher = null;
    }
    final after = openedAsTheAppWould(File(path).readAsBytesSync());
    expect(after.containsKey('small-tail.bin'), isFalse, reason: 'fixture');

    var byte = 0;
    for (final state in recording.statesFrom(beforeBytes)) {
      final opened = openedAsTheAppWould(state);
      for (final MapEntry(key: name, value: bytes) in after.entries) {
        expect(
          opened[name],
          bytes,
          reason: 'stopped after byte $byte: $name',
        );
      }
      byte += 1;
    }
  });
}
