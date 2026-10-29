import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/models/app_language.dart';
import 'package:anicel/src/services/launch_notice.dart';
import 'package:anicel/src/services/persistence/launch_notice_store.dart';

/// A dismissal kept in memory, read back by the next launch.
class _MemoryStore extends LaunchNoticeStore {
  _MemoryStore() : super(filePath: 'unused');

  String? dismissed;

  @override
  Future<String?> load() async => dismissed;

  @override
  Future<void> save(String dismissedKey) async => dismissed = dismissedKey;
}

/// A notice whose sections say [whatsNew] in [changedIn] and the same
/// words everywhere else.
LaunchNoticeContent _content({
  String whatsNew = '- One thing changed.',
  AppLanguage? changedIn,
  String lineEnd = '\n',
}) => LaunchNoticeContent(
  (language, section) => switch (section) {
    LaunchNoticeSection.notice => '## Pre-release${lineEnd}Body.$lineEnd',
    LaunchNoticeSection.whatsNew =>
      changedIn == null || language == changedIn
          ? whatsNew
          : '- One thing changed.',
    LaunchNoticeSection.feedback => 'Feedback ${language.name}.',
  },
);

/// 🗣️유저 2026-10-28: 「앱 실행시 앱 설명 넣고싶어. 다음부터 표시안함버튼
/// 있고. 빌드당 한번기억」 — a notice dismissed is not shown again until a
/// build says something else.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('the key is the notice', () {
    test('the same words are the same key', () {
      expect(_content().key, _content().key);
    });

    test('new words in any one language are a new key', () {
      for (final language in AppLanguage.values) {
        expect(
          _content(whatsNew: '- Another thing.', changedIn: language).key,
          isNot(_content().key),
          reason: language.name,
        );
      }
    });

    test('the line endings a checkout chose are not the words', () {
      // core.autocrlf: a Windows build bundles CRLF, the CI's LF.
      expect(_content(lineEnd: '\r\n').key, _content().key);
      expect(
        _content(lineEnd: '\r\n').textOf(
          AppLanguage.en,
          LaunchNoticeSection.notice,
        ),
        '## Pre-release\nBody.\n',
      );
    });
  });

  group('a launch', () {
    test('shows a notice nobody dismissed', () async {
      final notice = LaunchNotice(
        store: _MemoryStore(),
        content: () async => _content(),
      );
      expect(await notice.due(), isNotNull);
    });

    test('does not show the notice that was dismissed, and shows the '
        'next build\'s once', () async {
      final store = _MemoryStore();
      LaunchNotice launch(LaunchNoticeContent content) =>
          LaunchNotice(store: store, content: () async => content);

      final first = await launch(_content()).due();
      await launch(_content()).dismiss(first!);
      expect(await launch(_content()).due(), isNull);

      final next = _content(whatsNew: '- Another thing.');
      final shown = await launch(next).due();
      expect(shown?.key, next.key);
      await launch(next).dismiss(shown!);
      expect(await launch(next).due(), isNull);
    });
  });

  test('every language bundles every section', () async {
    // The folders `pubspec.yaml` lists, one per language: a folder entry
    // takes no subfolder, so one language left out of the list fails here.
    expect(
      LaunchNoticeSection.notice.assetIn(AppLanguage.zhHans),
      'assets/launch/zhHans/notice.md',
    );
    final bundled = await LaunchNoticeContent.bundled();
    for (final language in AppLanguage.values) {
      for (final section in LaunchNoticeSection.values) {
        expect(
          bundled.textOf(language, section),
          (await rootBundle.loadString(
            section.assetIn(language),
          )).replaceAll('\r\n', '\n'),
          reason: section.assetIn(language),
        );
        expect(
          bundled.textOf(language, section).trim(),
          isNotEmpty,
          reason: section.assetIn(language),
        );
      }
    }
  });
}
