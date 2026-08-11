import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/services/persistence/recent_projects.dart';
import 'package:anicel/src/services/persistence/recent_projects_store.dart';

/// PICK-4. The list itself is ordinary MRU arithmetic; what is worth testing
/// carefully is the two things that are NOT ordinary:
///
///   - the identity no-op, because the caller writes to disk on every change
///     and re-recording the already-open project would rewrite the file on
///     every save. That bug has already happened once in this codebase, to
///     the colour palette, which wrote its JSON on every stroke commit.
///   - the reconnect flag, because the alternative design — dropping an entry
///     whose bookmark went stale — throws away the one thing the user still
///     knows, which is which project they meant.
void main() {
  RecentProject project(String name, {String? bookmark, bool stale = false}) =>
      RecentProject(
        path: '/drive/work/$name.anicel',
        folderBookmark: bookmark,
        needsReconnect: stale,
      );

  group('recording an open', () {
    test('the newest comes first', () {
      final list = const RecentProjects()
          .withOpened(project('a'))
          .withOpened(project('b'));
      expect(list.entries.map((e) => e.name), [
        'b.anicel',
        'a.anicel',
      ]);
    });

    test('re-opening promotes without duplicating', () {
      final list = const RecentProjects()
          .withOpened(project('a'))
          .withOpened(project('b'))
          .withOpened(project('a'));
      expect(list.entries.map((e) => e.name), [
        'a.anicel',
        'b.anicel',
      ]);
      expect(list.entries, hasLength(2));
    });

    test('recording the one already at the front changes nothing at all', () {
      // Identity, not equality: the caller checks `identical` before writing,
      // so returning an equal-but-new list would still rewrite the file.
      final list = const RecentProjects().withOpened(project('a'));
      expect(identical(list.withOpened(project('a')), list), isTrue);
    });

    test('a changed bookmark for the same path is NOT a no-op', () {
      // Re-granting a folder mints a fresh bookmark, and dropping it would
      // leave the entry pointing at a token that no longer resolves.
      final list = const RecentProjects().withOpened(project('a'));
      final next = list.withOpened(project('a', bookmark: 'newtoken'));
      expect(identical(next, list), isFalse);
      expect(next.entries.first.folderBookmark, 'newtoken');
      expect(next.entries, hasLength(1));
    });

    test('the list is capped', () {
      var list = const RecentProjects();
      for (var i = 0; i < RecentProjects.maxEntries + 5; i += 1) {
        list = list.withOpened(project('p$i'));
      }
      expect(list.entries, hasLength(RecentProjects.maxEntries));
      expect(list.entries.first.name, 'p14.anicel');
    });
  });

  group('reconnecting', () {
    test('a stale entry is flagged, not removed', () {
      final list = const RecentProjects()
          .withOpened(project('a'))
          .withReconnectNeeded('/drive/work/a.anicel');
      expect(list.entries, hasLength(1));
      expect(list.entries.first.needsReconnect, isTrue);
    });

    test('flagging twice is a no-op', () {
      final list = const RecentProjects()
          .withOpened(project('a'))
          .withReconnectNeeded('/drive/work/a.anicel');
      expect(
        identical(list.withReconnectNeeded('/drive/work/a.anicel'), list),
        isTrue,
      );
    });

    test('flagging an unknown path changes nothing', () {
      final list = const RecentProjects().withOpened(project('a'));
      expect(identical(list.withReconnectNeeded('/elsewhere.anicel'), list),
          isTrue);
    });

    test('reconnecting stores the new bookmark and clears the flag', () {
      final list = const RecentProjects()
          .withOpened(project('a', bookmark: 'old'))
          .withReconnectNeeded('/drive/work/a.anicel');
      final fixed = list.withReconnected('/drive/work/a.anicel', 'fresh');
      expect(fixed.entries.first.folderBookmark, 'fresh');
      expect(fixed.entries.first.needsReconnect, isFalse);
    });

    test('removing an entry drops exactly it', () {
      final list = const RecentProjects()
          .withOpened(project('a'))
          .withOpened(project('b'));
      final next = list.without('/drive/work/a.anicel');
      expect(next.entries.map((e) => e.name), ['b.anicel']);
      expect(identical(list.without('/nope'), list), isTrue);
    });
  });

  group('on disk', () {
    late Directory dir;
    late String path;

    setUp(() {
      dir = Directory.systemTemp.createTempSync('qa_recent_');
      path = '${dir.path}/recent_projects.json';
    });
    tearDown(() {
      try {
        dir.deleteSync(recursive: true);
      } on Object {
        // A leaked handle on Windows must not fail the suite.
      }
    });

    test('round-trips, bookmark and flag included', () {
      final store = RecentProjectsStore(filePath: path);
      final list = const RecentProjects()
          .withOpened(project('a', bookmark: 'Ym0='))
          .withOpened(project('b'))
          .withReconnectNeeded('/drive/work/a.anicel');
      store.save(list);
      expect(RecentProjectsStore(filePath: path).load(), list);
    });

    test('a missing file is an empty list, not an error', () {
      expect(
        RecentProjectsStore(filePath: '${dir.path}/none.json').load().entries,
        isEmpty,
      );
    });

    test('a corrupt file is an empty list', () {
      File(path).writeAsStringSync('{not json');
      expect(RecentProjectsStore(filePath: path).load().entries, isEmpty);
    });

    test('a file from a newer version is ignored', () {
      File(path).writeAsStringSync(
        jsonEncode({'version': RecentProjectsStore.version + 1, 'entries': []}),
      );
      expect(RecentProjectsStore(filePath: path).load().entries, isEmpty);
    });

    test('an entry with no path is skipped rather than crashing', () {
      File(path).writeAsStringSync(
        jsonEncode({
          'version': RecentProjectsStore.version,
          'entries': [
            {'folderBookmark': 'x'},
            {'path': '/ok.anicel'},
          ],
        }),
      );
      final loaded = RecentProjectsStore(filePath: path).load();
      expect(loaded.entries.map((e) => e.path), ['/ok.anicel']);
    });

    test('a hand-edited file cannot grow the menu past the cap', () {
      File(path).writeAsStringSync(
        jsonEncode({
          'version': RecentProjectsStore.version,
          'entries': [
            for (var i = 0; i < 50; i += 1) {'path': '/p$i.anicel'},
          ],
        }),
      );
      expect(
        RecentProjectsStore(filePath: path).load().entries,
        hasLength(RecentProjects.maxEntries),
      );
    });

    test('the store redirects itself away from the real file under test', () {
      // Widget tests reach this through the production menu wiring, so the
      // default path must never be the developer's own list.
      expect(
        RecentProjectsStore.defaultFilePath(),
        contains('qa_test_recent_projects_'),
      );
    });
  });

  group('the write guard', () {
    late Directory dir;
    late RecentProjectsStore store;

    setUp(() {
      dir = Directory.systemTemp.createTempSync('qa_recent_guard_');
      store = RecentProjectsStore(filePath: '${dir.path}/r.json');
      AppRecent.projects.value = const RecentProjects();
    });
    tearDown(() {
      AppRecent.projects.value = const RecentProjects();
      try {
        dir.deleteSync(recursive: true);
      } on Object {
        // A leaked handle on Windows must not fail the suite.
      }
    });

    test('recording publishes to the live list', () {
      recordRecentProject(project('a'), store: store);
      expect(AppRecent.projects.value.entries.single.name, 'a.anicel');
    });

    test('recording the same project again does not touch the file', () {
      recordRecentProject(project('a'), store: store);
      final file = File('${dir.path}/r.json');
      final firstWrite = file.lastModifiedSync();
      file.setLastModifiedSync(firstWrite.subtract(const Duration(hours: 1)));
      final stamped = file.lastModifiedSync();

      recordRecentProject(project('a'), store: store);

      expect(
        file.lastModifiedSync(),
        stamped,
        reason: 'an unchanged list must not be rewritten',
      );
    });
  });
}
