import 'package:flutter/services.dart' show rootBundle;

import '../core/build_stamp.dart' show buildNumber;
import '../core/path_names.dart' show pathHash;
import '../models/app_language.dart';
import 'persistence/launch_notice_store.dart';

/// The files the window the app opens at launch is drawn from — one
/// markdown file each, per language, under `assets/launch/<language>/` —
/// and which of them a build shows is [LaunchNoticeContent]'s to say.
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

  /// That this is a debug build: what opens [notice] in a build with no
  /// round's number, in place of the file's own opening
  /// ([LaunchNoticeContent.noticeIn]). Never shown by itself — and never on
  /// the site, which the release hands [notice] and the rest by name.
  debugOpening('debug_opening.md'),

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
  /// Every section in every language, as [textOf] answers it, in a build
  /// stamped [number].
  LaunchNoticeContent(
    String Function(AppLanguage, LaunchNoticeSection) textOf, {
    this.number = buildNumber,
  }) : _texts = {
         for (final language in AppLanguage.values)
           for (final section in LaunchNoticeSection.values)
             (language, section): _oneLineEnding(textOf(language, section)),
       };

  /// The round's number this build was stamped with ([buildNumber]) —
  /// empty in a debug build.
  ///
  /// 🗣️유저 2026-11-16 (관제's chat, board launch-notice-says-debug-build):
  /// 「디버그 빌드에서만 이번버전에서 바뀐게 계속 옛날거 낡은채로 남아있어서
  /// 디버그빌드는 매번 빌드하니까 새것유지 힘드니까 릴리즈빌드에서만 저번빌드에서
  /// 바뀐걸 보여주는건 지금처럼 남기고싶은거야」. A debug build is one no round
  /// stamped: the build the user makes from master in Android Studio — in
  /// release mode, so `kDebugMode` cannot tell it.
  final String number;

  bool get _debug => number.isEmpty;

  /// Whether the window carries the what's-new: a round's build only — a
  /// debug build is made anew every day, and its what's-new would say an
  /// older round's.
  bool get showsWhatsNew => !_debug;

  /// The notice as this build says it in [language]: the file's own words in
  /// a round's build; in a debug build, [LaunchNoticeSection.debugOpening]
  /// in place of the file's opening — its heading and the sentence under it,
  /// the first two blocks a blank line apart — and the rest as it stands.
  ///
  /// ⚠️THE REST IS NOT COPIED: the site shows the notice as it is, and the
  /// debug words differ in the heading and the first sentence alone, so
  /// every notice.md holds that sentence as a paragraph of its own.
  String noticeIn(AppLanguage language) {
    final notice = textOf(language, LaunchNoticeSection.notice);
    if (!_debug) return notice;
    return [
      textOf(language, LaunchNoticeSection.debugOpening).trimRight(),
      ...notice.split('\n\n').skip(2),
    ].join('\n\n');
  }

  /// What the window says in [language], by the file each part comes from.
  List<(LaunchNoticeSection, String)> _shownIn(AppLanguage language) => [
    (LaunchNoticeSection.notice, noticeIn(language)),
    if (showsWhatsNew)
      (
        LaunchNoticeSection.whatsNew,
        textOf(language, LaunchNoticeSection.whatsNew),
      ),
    (
      LaunchNoticeSection.feedback,
      textOf(language, LaunchNoticeSection.feedback),
    ),
  ];

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

  /// What a person who dismissed this notice dismissed: one hash over what
  /// the window says in every language.
  ///
  /// ↩️It hashed every file till 2026-11-16, when a debug build came to say
  /// less than a round's from the same files (launch-notice-says-debug-build):
  /// a notice dismissed in the debug build would have kept a round's
  /// what's-new from ever being shown.
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
      for (final language in AppLanguage.values)
        for (final (section, text) in _shownIn(language))
          '${section.assetIn(language)}\u0000$text',
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
