import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/models/app_language.dart';
import 'package:anicel/src/services/launch_notice.dart';
import 'package:anicel/src/services/persistence/launch_notice_store.dart';
import 'package:anicel/src/ui/dialogs/launch_notice_window.dart';
import 'package:anicel/src/ui/shortcuts/editor_action_registry.dart'
    show EditorActionIds;
import 'package:anicel/src/ui/shortcuts/editor_shortcut_scope.dart'
    show editorActionLabel;
import 'package:anicel/src/ui/text/app_strings.dart';
import 'package:anicel/src/ui/theme/app_theme.dart';
import 'package:anicel/src/ui/widgets/content_scrollbar.dart';
import 'package:anicel/src/ui/widgets/markdown_subset.dart';
import 'package:anicel/src/ui/widgets/settings_rows.dart';

/// A dismissal kept in memory: one store, read by every launch of a test
/// as the settings file is read by every launch of the app.
class _MemoryStore extends LaunchNoticeStore {
  _MemoryStore() : super(filePath: 'unused');

  String? dismissed;

  @override
  Future<String?> load() async => dismissed;

  @override
  Future<void> save(String dismissedKey) async => dismissed = dismissedKey;
}

/// A notice whose 「what's new」 says [whatsNew], in every language but
/// for a word that says which.
LaunchNoticeContent _content({String whatsNew = '- One thing changed.'}) =>
    LaunchNoticeContent(
      (language, section) => switch (section) {
        LaunchNoticeSection.notice =>
          '## Pre-release ${language.name}\n\nA build before release.',
        LaunchNoticeSection.whatsNew => whatsNew,
        LaunchNoticeSection.feedback => 'Tell us ${language.name}.',
      },
    );

final _window = find.byKey(const ValueKey<String>('launch-notice'));
final _dontShowAgain = find.byKey(
  const ValueKey<String>('launch-notice-dont-show-again'),
);
final _close = find.byKey(const ValueKey<String>('launch-notice-close'));
final _sendFeedback = find.byKey(
  const ValueKey<String>('launch-notice-send-feedback'),
);
final _feedbackWindow = find.byKey(const ValueKey<String>('feedback-window'));
final _whatsNewFold = find.byKey(
  const ValueKey<String>('launch-notice-whats-new'),
);

/// 🗣️유저 2026-10-28: 「앱 실행시 앱 설명 넣고싶어. 다음부터 표시안함버튼
/// 있고. 빌드당 한번기억」.
///
/// A LAUNCH is what the app's first frame does ([showLaunchNoticeIfDue] on
/// a fresh [LaunchNotice]); the next launch is another on the SAME store.
void main() {
  tearDown(() => AppText.settings.value = const AppLanguageSettings());

  /// A screen whose 'launch' is one launch of the app: a fresh notice on
  /// [store], saying what [content] says at that moment.
  Future<void> pumpHost(
    WidgetTester tester,
    _MemoryStore store, {
    LaunchNoticeContent Function()? content,
  }) async {
    await tester.binding.setSurfaceSize(const Size(1200, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showLaunchNoticeIfDue(
                context,
                LaunchNotice(
                  store: store,
                  content: () async => (content ?? _content)(),
                ),
              ),
              child: const Text('launch'),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> launch(WidgetTester tester) async {
    await tester.tap(find.text('launch'));
    await tester.pumpAndSettle();
  }

  testWidgets('🎯the first launch opens the notice, every section in it', (
    tester,
  ) async {
    await pumpHost(tester, _MemoryStore());
    await launch(tester);

    expect(_window, findsOneWidget);
    expect(find.text('Pre-release en'), findsOneWidget);
    expect(find.text('One thing changed.'), findsOneWidget);
    expect(find.text('Tell us en.'), findsOneWidget);
    // The build beside the title (app-version-shown) — `dev`, as a build
    // nobody stamped says.
    expect(find.text('About this build · dev'), findsOneWidget);
    expect(_dontShowAgain, findsOneWidget);
    expect(_close, findsOneWidget);
    expect(_sendFeedback, findsOneWidget);
    // ↩️The usage statistics are asked in a window of their own now
    // (유저 2026-10-29 08:1x): no switch in here.
    expect(
      find.descendant(of: _window, matching: find.byType(SettingsSwitchRow)),
      findsNothing,
    );
    // The content scrolls in its own lane, there whether it overflows or
    // not (CLAUDE.md: 스크롤바를 자동으로 숨기지 않는다).
    expect(
      find.descendant(of: _window, matching: find.byType(ContentScrollbar)),
      findsOneWidget,
    );
  });

  testWidgets('「다음부터 표시 안 함」 keeps the next launch of the same notice '
      'closed', (tester) async {
    final store = _MemoryStore();
    await pumpHost(tester, store);
    await launch(tester);

    await tester.tap(_dontShowAgain);
    await tester.pumpAndSettle();
    expect(_window, findsNothing);

    await launch(tester);
    expect(_window, findsNothing);
  });

  testWidgets('a build whose notice says something else opens it again — '
      'once', (tester) async {
    final store = _MemoryStore();
    var whatsNew = '- One thing changed.';
    await pumpHost(
      tester,
      store,
      content: () => _content(whatsNew: whatsNew),
    );
    await launch(tester);
    await tester.tap(_dontShowAgain);
    await tester.pumpAndSettle();

    whatsNew = '- Another thing changed.';
    await launch(tester);
    expect(_window, findsOneWidget);
    expect(find.text('Another thing changed.'), findsOneWidget);

    await tester.tap(_dontShowAgain);
    await tester.pumpAndSettle();
    await launch(tester);
    expect(_window, findsNothing);
  });

  testWidgets('closing without it opens the notice again next launch — by '
      'the footer\'s 닫기 or the title bar\'s ✕', (tester) async {
    final store = _MemoryStore();
    await pumpHost(tester, store);
    await launch(tester);

    await tester.tap(_close);
    await tester.pumpAndSettle();
    expect(_window, findsNothing);
    expect(store.dismissed, isNull);

    await launch(tester);
    expect(_window, findsOneWidget);
    await tester.tap(
      find.descendant(
        of: _window,
        matching: find.byKey(const ValueKey<String>('app-window-close')),
      ),
    );
    await tester.pumpAndSettle();
    expect(_window, findsNothing);
    expect(store.dismissed, isNull);

    await launch(tester);
    expect(_window, findsOneWidget);
  });

  testWidgets('the notice is in the program language — its sections and '
      'its frame', (tester) async {
    AppText.settings.value = const AppLanguageSettings(
      programLanguage: AppLanguage.ko,
    );
    await pumpHost(tester, _MemoryStore());
    await launch(tester);

    expect(find.text('Pre-release ko'), findsOneWidget);
    expect(find.text('Tell us ko.'), findsOneWidget);
    expect(find.text('안내 · dev'), findsOneWidget);
    expect(find.text('다음부터 표시 안 함'), findsOneWidget);
    expect(find.text('닫기'), findsOneWidget);
  });

  testWidgets('🎯the feedback stands above the what\'s-new, and the '
      'what\'s-new starts folded under its own heading (유저 2026-10-29: '
      '「업데이트내역항목 접어두고 아래의 의견보내기항목을 그 위로」)', (
    tester,
  ) async {
    await pumpHost(
      tester,
      _MemoryStore(),
      content: () =>
          _content(whatsNew: '## What changed\n\n- One thing changed.'),
    );
    await launch(tester);
    final heading = find.byWidgetPredicate(
      (widget) =>
          widget is SettingsSectionHeading && widget.label == 'What changed',
    );
    expect(heading, findsOneWidget);
    expect(find.text('One thing changed.'), findsNothing);
    final headingTop = tester.getTopLeft(heading).dy;
    expect(tester.getTopLeft(find.text('Tell us en.')).dy, lessThan(headingTop));
    expect(tester.getTopLeft(_sendFeedback).dy, lessThan(headingTop));

    await tester.tap(_whatsNewFold);
    await tester.pumpAndSettle();
    expect(find.text('One thing changed.'), findsOneWidget);
    expect(heading, findsOneWidget, reason: 'drawn once, as the fold\'s words');
  });

  test('every bundled what\'s-new opens with the `## ` heading its fold '
      'carries', () {
    for (final file in Directory('assets/launch').listSync(recursive: true)) {
      if (file is File && file.path.endsWith('whats_new.md')) {
        expect(
          MarkdownSubset.leadingHeadingOf(file.readAsStringSync()),
          isNotNull,
          reason: file.path,
        );
      }
    }
  });

  testWidgets('the sections are drawn in the markdown subset: headings, '
      'bullets, paragraphs and bold', (tester) async {
    await pumpHost(
      tester,
      _MemoryStore(),
      content: () => _content(
        whatsNew:
            '## What changed\n'
            '\n'
            'A paragraph with **bold words** in it\n'
            'and a second line of it.\n'
            '\n'
            '- First **item**\n'
            '- Second item\n'
            '  carried on\n'
            '\n'
            'A lone ** marker.\n'
            '## Then\n'
            'Right under it.',
      ),
    );
    await launch(tester);
    await tester.tap(_whatsNewFold);
    await tester.pumpAndSettle();

    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is SettingsSectionHeading && widget.label == 'What changed',
      ),
      findsOneWidget,
    );
    expect(find.text('•'), findsNWidgets(2));
    expect(find.text('Second item carried on'), findsOneWidget);
    expect(find.text('A lone ** marker.'), findsOneWidget);
    // A heading ends the paragraph above it, blank line or not.
    expect(find.text('Then'), findsOneWidget);
    expect(find.text('Right under it.'), findsOneWidget);

    final paragraph = _richText(
      tester,
      'A paragraph with bold words in it and a second line of it.',
    );
    expect(_boldRuns(paragraph), ['bold words']);
    expect(_boldRuns(_richText(tester, 'First item')), ['item']);
  });

  testWidgets('every bundled section draws with no marker left over — the '
      'release rewrites them, and a lone ** would print as it is', (
    tester,
  ) async {
    final bundled = (await tester.runAsync(LaunchNoticeContent.bundled))!;
    await tester.binding.setSurfaceSize(const Size(1200, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    for (final language in AppLanguage.values) {
      AppText.settings.value = AppLanguageSettings(programLanguage: language);
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(),
          home: LaunchNoticeWindow(content: bundled, onDontShowAgain: () {}),
        ),
      );
      // The what's-new starts folded; its words are drawn once opened.
      await tester.tap(_whatsNewFold);
      await tester.pumpAndSettle();
      final drawn = [
        for (final text in tester.widgetList<RichText>(
          find.descendant(
            of: find.byType(MarkdownSubset),
            matching: find.byType(RichText),
          ),
        ))
          text.text.toPlainText(),
      ];
      expect(drawn, isNotEmpty, reason: language.name);
      expect(
        drawn.where((text) => text.contains('**')),
        isEmpty,
        reason: language.name,
      );
    }
  });

  testWidgets('the feedback section\'s button is the ⚙ menu\'s 「의견 보내기」 '
      '— its name and its window (I-139)', (tester) async {
    for (final language in [AppLanguage.ko, AppLanguage.en]) {
      AppText.settings.value = AppLanguageSettings(programLanguage: language);
      await pumpHost(tester, _MemoryStore());
      await launch(tester);
      expect(
        find.descendant(
          of: _sendFeedback,
          matching: find.text(editorActionLabel(EditorActionIds.sendFeedback)),
        ),
        findsOneWidget,
        reason: language.name,
      );

      await tester.tap(_sendFeedback);
      await tester.pumpAndSettle();
      expect(_feedbackWindow, findsOneWidget, reason: language.name);
      // Over the notice, which is still there when it closes.
      expect(_window, findsOneWidget);
      await tester.tap(
        find.descendant(
          of: _feedbackWindow,
          matching: find.byKey(const ValueKey<String>('app-window-close')),
        ),
      );
      await tester.pumpAndSettle();
      expect(_feedbackWindow, findsNothing);
      expect(_window, findsOneWidget);
      await tester.tap(_close);
      await tester.pumpAndSettle();
    }
  });
}

/// The span of the one rich text that reads [plain].
InlineSpan _richText(WidgetTester tester, String plain) => tester
    .widget<RichText>(
      find.byWidgetPredicate(
        (widget) => widget is RichText && widget.text.toPlainText() == plain,
      ),
    )
    .text;

/// The words of [span] set in bold.
List<String> _boldRuns(InlineSpan span) {
  final bold = <String>[];
  span.visitChildren((child) {
    if (child is TextSpan &&
        child.text != null &&
        child.style?.fontWeight == FontWeight.bold) {
      bold.add(child.text!);
    }
    return true;
  });
  return bold;
}
