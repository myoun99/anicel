import 'package:flutter/services.dart' show rootBundle;

import '../core/path_names.dart' show pathHash;
import '../models/app_language.dart';
import 'persistence/launch_notice_store.dart';

/// The parts of the window the app opens at launch, in the order it shows
/// them — one markdown file each, per language, under
/// `assets/launch/<language>/`.
///
/// 🗣️유저 2026-10-28: 「앱 실행시 앱 설명 넣고싶어. 다음부터 표시안함버튼
/// 있고. 빌드당 한번기억」.
///
/// ⚠️The files are read ON THEIR OWN as well: the release copies the same
/// files to the public site, so the window and the site say one thing from
/// one source — which is why they are plain markdown and not string-table
/// rows.
enum LaunchNoticeSection {
  /// That this is a pre-release build.
  notice('notice.md'),

  /// What changed in this build — rewritten for every release build.
  whatsNew('whats_new.md'),

  /// Where feedback goes.
  feedback('feedback.md');

  const LaunchNoticeSection(this.fileName);

  final String fileName;

  /// The bundled file that holds this section in [language].
  String assetIn(AppLanguage language) =>
      'assets/launch/${language.name}/$fileName';
}

/// What a build says at launch: every section in every language.
class LaunchNoticeContent {
  /// Every section in every language, as [textOf] answers it.
  LaunchNoticeContent(String Function(AppLanguage, LaunchNoticeSection) textOf)
    : _texts = {
        for (final language in AppLanguage.values)
          for (final section in LaunchNoticeSection.values)
            (language, section): _oneLineEnding(textOf(language, section)),
      };

  /// The sections this build carries ([LaunchNoticeSection.assetIn]).
  static Future<LaunchNoticeContent> bundled() async {
    final texts = {
      for (final language in AppLanguage.values)
        for (final section in LaunchNoticeSection.values)
          (language, section): await rootBundle.loadString(
            section.assetIn(language),
          ),
    };
    return LaunchNoticeContent(
      (language, section) => texts[(language, section)]!,
    );
  }

  final Map<(AppLanguage, LaunchNoticeSection), String> _texts;

  String textOf(AppLanguage language, LaunchNoticeSection section) =>
      _texts[(language, section)]!;

  /// What a person who dismissed this notice dismissed: one hash over every
  /// section in every language.
  ///
  /// ⚠️THE CONTENT, NOT THE BUILD'S STAMP: `buildStamp` names a release
  /// build alone, and a build made from master in Android Studio — what the
  /// user runs every day — says `dev` for ever. A build whose notice says
  /// the same thing is the same notice; one that says anything else is new,
  /// and is shown once.
  ///
  /// ★EVERY LANGUAGE, NOT THE ONE ON SCREEN: 「빌드당 한번」 is once per
  /// BUILD. A key over the program language alone would bring a dismissed
  /// notice back the next launch after the person switched languages, with
  /// the build unchanged.
  ///
  /// ⛔Through the app's one hash ([pathHash]): an FNV loop written out here
  /// would be the fourth copy that function's doc says it ended.
  late final String key = pathHash(
    [
      for (final entry in _texts.entries)
        '${entry.key.$2.assetIn(entry.key.$1)}\u0000${entry.value}',
    ].join('\u0000'),
  ).toRadixString(16).padLeft(8, '0');

  /// [text] with its lines ended by `\n` alone.
  ///
  /// ⚠️This checkout runs under `core.autocrlf`, so a build made on Windows
  /// bundles the files with CRLF where the CI's builds bundle LF — the same
  /// words would be two keys, and a person moving between the two builds
  /// would be shown the notice they dismissed.
  static String _oneLineEnding(String text) => text.replaceAll('\r\n', '\n');
}

/// Whether this build's notice is still to be shown, and the one way to
/// stop it ([dismiss]).
class LaunchNotice {
  LaunchNotice({
    LaunchNoticeStore? store,
    Future<LaunchNoticeContent> Function()? content,
  }) : _store = store ?? LaunchNoticeStore(),
       _content = content ?? LaunchNoticeContent.bundled;

  final LaunchNoticeStore _store;
  final Future<LaunchNoticeContent> Function() _content;

  /// This build's notice — or null when it was dismissed already.
  Future<LaunchNoticeContent?> due() async {
    final content = await _content();
    return await _store.load() == content.key ? null : content;
  }

  /// Not again for [content]: until a build says something else.
  Future<void> dismiss(LaunchNoticeContent content) =>
      _store.save(content.key);
}
