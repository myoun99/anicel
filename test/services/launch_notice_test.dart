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
/// words everywhere else, in a build stamped [number].
LaunchNoticeContent _content({
  String whatsNew = '- One thing changed.',
  AppLanguage? changedIn,
  String lineEnd = '\n',
  String debugOpening = '## Debug\n\nA debug build.\n',
  String number = '1091',
}) => LaunchNoticeContent(
  (language, section) => switch (section) {
    LaunchNoticeSection.notice => '## Pre-release${lineEnd}Body.$lineEnd',
    LaunchNoticeSection.debugOpening => debugOpening,
    LaunchNoticeSection.whatsNew =>
      changedIn == null || language == changedIn
          ? whatsNew
          : '- One thing changed.',
    LaunchNoticeSection.feedback => 'Feedback ${language.name}.',
  },
  number: number,
);

/// A notice whose own opening is a heading and one sentence, with more
/// under it — the shape of every bundled notice.md.
LaunchNoticeContent _withBody({required String number}) => LaunchNoticeContent(
  (language, section) => switch (section) {
    LaunchNoticeSection.notice =>
      '## Pre-release\n\nA build before release.\n\n'
          'Keep your **files**.\n\nThey open later.\n',
    LaunchNoticeSection.debugOpening => '## Debug\n\nA **debug** build.\n',
    LaunchNoticeSection.whatsNew => '- One thing changed.',
    LaunchNoticeSection.feedback => 'Feedback.',
  },
  number: number,
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

  // 🗣️유저 2026-11-16 (board launch-notice-says-debug-build): a build no
  // round stamped is a debug build — no what's-new in it, and it says it is
  // a debug build. A round's build says what it said before.
  group('a build with no round\'s number', () {
    test('carries no what\'s-new — a round\'s build does', () {
      expect(_content(number: '').showsWhatsNew, isFalse);
      expect(_content(number: '1091').showsWhatsNew, isTrue);
    });

    test('opens its notice with the debug words, and says the rest as the '
        'file does', () {
      expect(
        _withBody(number: '').noticeIn(AppLanguage.en),
        '## Debug\n\nA **debug** build.\n\n'
        'Keep your **files**.\n\nThey open later.\n',
      );
    });

    test('a round\'s build says its notice as the file does', () {
      expect(
        _withBody(number: '1091').noticeIn(AppLanguage.en),
        '## Pre-release\n\nA build before release.\n\n'
        'Keep your **files**.\n\nThey open later.\n',
      );
    });

    test('its key is what it shows — the what\'s-new it does not show is '
        'not in it, the debug words are', () {
      String key({required String number, String? whatsNew, String? opening}) =>
          _content(
            number: number,
            whatsNew: whatsNew ?? '- One thing changed.',
            debugOpening: opening ?? '## Debug\n\nA debug build.\n',
          ).key;

      expect(
        key(number: '', whatsNew: '- Another thing.'),
        key(number: ''),
      );
      expect(
        key(number: '', opening: '## Debug\n\nAnother build.\n'),
        isNot(key(number: '')),
      );
      expect(
        key(number: '1091', opening: '## Debug\n\nAnother build.\n'),
        key(number: '1091'),
      );
      expect(
        key(number: '1091', whatsNew: '- Another thing.'),
        isNot(key(number: '1091')),
      );
      expect(
        key(number: ''),
        isNot(key(number: '1091')),
        reason: 'a notice dismissed in a debug build keeps no round\'s '
            'what\'s-new from being shown',
      );
    });

    test('every bundled notice opens with a heading and its first sentence '
        'alone, each its own block — and the debug words with the same two',
        () async {
      final bundled = await LaunchNoticeContent.bundled();
      for (final language in AppLanguage.values) {
        final notice = bundled
            .textOf(language, LaunchNoticeSection.notice)
            .split('\n\n');
        final opening = bundled
            .textOf(language, LaunchNoticeSection.debugOpening)
            .trimRight()
            .split('\n\n');
        expect(notice.first, startsWith('## '), reason: language.name);
        expect(notice, hasLength(greaterThan(2)), reason: language.name);
        expect(opening, hasLength(2), reason: language.name);
        expect(opening.first, startsWith('## '), reason: language.name);
        expect(
          notice[1],
          isNot(contains('\n')),
          reason: '${language.name}: the first sentence, alone',
        );
      }
    });

    test('the debug words the user asked for, in every language', () async {
      final bundled = await LaunchNoticeContent.bundled();
      const headings = {
        AppLanguage.ko: '## 디버그 버전입니다',
        AppLanguage.ja: '## デバッグ版です',
        AppLanguage.en: '## A debug version',
        AppLanguage.fr: '## Une version de débogage',
        AppLanguage.zhHans: '## 调试版本',
      };
      expect(headings.keys.toSet(), AppLanguage.values.toSet());
      for (final MapEntry(key: language, value: heading) in headings.entries) {
        expect(
          bundled.textOf(language, LaunchNoticeSection.debugOpening),
          startsWith('$heading\n\n'),
          reason: language.name,
        );
      }
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
