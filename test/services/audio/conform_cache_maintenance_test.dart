import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/services/audio/conform_cache_maintenance.dart';
import 'package:anicel/src/services/persistence/app_save_settings.dart';

/// The conform cache's lifetime.
///
/// Nothing ever collected it. A conform is about twelve times its source,
/// so a working month of dialogue quietly became gigabytes — and inside an
/// iPad's app container that is a pile the user can neither see nor empty,
/// growing until the device is full with no explanation attached.
void main() {
  late Directory root;

  setUp(() {
    root = Directory.systemTemp.createTempSync('qa_conform_cache_');
    AppSave.settings.value = AppSaveSettings(
      conformDirectory: root.path.replaceAll('\\', '/'),
    );
  });

  tearDown(() {
    AppSave.settings.value = const AppSaveSettings();
    try {
      root.deleteSync(recursive: true);
    } on Object {
      // A locked file on Windows must not fail the suite.
    }
  });

  /// A cache entry of [bytes], last used [agoMinutes] ago.
  String writeEntry(String name, int bytes, {int agoMinutes = 0}) {
    final file = File('${root.path}/$name')
      ..writeAsBytesSync(List<int>.filled(bytes, 0));
    file.setLastModifiedSync(
      DateTime.now().subtract(Duration(minutes: agoMinutes)),
    );
    return file.path.replaceAll('\\', '/');
  }

  test('an absent cache measures zero rather than throwing', () {
    // The first run of a fresh install, and every run before any audio is
    // imported. Preferences asks for this number on open.
    root.deleteSync(recursive: true);
    expect(conformCacheEntries(), isEmpty);
    expect(conformCacheBytes(), 0);
    expect(pruneConformCache(), 0);
  });

  test('the size is the sum of what is there', () {
    writeEntry('a.wav', 1000);
    writeEntry('b.wav', 2000);
    expect(conformCacheBytes(), 3000);
  });

  test('a cache inside the budget is left alone', () {
    final kept = writeEntry('a.wav', 1000);
    expect(pruneConformCache(budgetBytes: 5000), 0);
    expect(File(kept).existsSync(), isTrue);
  });

  test('eviction takes the COLDEST first, not the oldest built', () {
    // The distinction is the whole reason reuse touches the file. A sound
    // used in every cut was built once, long ago; dropping it because of
    // that would rebuild the entry that earns its keep the most and spare
    // the one imported by mistake and never played.
    final stale = writeEntry('stale.wav', 1000, agoMinutes: 600);
    final middling = writeEntry('middling.wav', 1000, agoMinutes: 60);
    final hot = writeEntry('hot.wav', 1000);

    expect(pruneConformCache(budgetBytes: 2000), 1000);

    expect(File(stale).existsSync(), isFalse);
    expect(File(middling).existsSync(), isTrue);
    expect(File(hot).existsSync(), isTrue);
  });

  test('it keeps evicting until it actually fits', () {
    writeEntry('a.wav', 1000, agoMinutes: 300);
    writeEntry('b.wav', 1000, agoMinutes: 200);
    final hot = writeEntry('c.wav', 1000);

    expect(pruneConformCache(budgetBytes: 1000), 2000);
    expect(conformCacheBytes(), 1000);
    expect(File(hot).existsSync(), isTrue);
  });

  test('the per-project folders an older build wrote are collected', () {
    // They are unreachable now — the cache is keyed by source, so nothing
    // will ever look inside one again. Leaving them would mean the pile
    // this exists to bound is partly made of entries it cannot see.
    final legacy = Directory('${root.path}/scene.anicel.0badf00d')
      ..createSync(recursive: true);
    File('${legacy.path}/대사.m4a.wav').writeAsBytesSync(
      List<int>.filled(4000, 0),
    );
    final current = writeEntry('current.wav', 100);

    expect(pruneConformCache(), 4000);

    expect(legacy.existsSync(), isFalse);
    expect(
      File(current).existsSync(),
      isTrue,
      reason: 'the new flat entries are not what is being collected',
    );
  });

  test('emptying it removes everything', () {
    writeEntry('a.wav', 1000);
    writeEntry('b.wav', 2000);

    expect(clearConformCache(), 3000);
    expect(conformCacheBytes(), 0);
  });

  test('a subdirectory is never counted as an entry', () {
    // conformCacheEntries feeds both the size shown in Preferences and the
    // eviction order; a directory in either would be a size nobody can
    // explain and a delete that fails every pass.
    Directory('${root.path}/sub').createSync();
    writeEntry('a.wav', 500);
    expect(conformCacheEntries().map((entry) => entry.bytes), [500]);
  });
}
