import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/models/app_language.dart';
import 'package:anicel/src/services/launch_notice.dart';
import 'package:anicel/src/services/persistence/launch_notice_store.dart';
import 'package:anicel/src/ui/dialogs/launch_notice_window.dart';
import 'package:anicel/src/ui/text/app_strings.dart';
import 'package:anicel/src/ui/theme/app_theme.dart';
import 'package:anicel/src/ui/widgets/content_scrollbar.dart';
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
    VoidCallback? onSendFeedback,
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
                onSendFeedback: onSendFeedback,
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
    expect(find.text('About this build'), findsOneWidget);
    expect(_dontShowAgain, findsOneWidget);
    expect(_close, findsOneWidget);
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
    expect(find.text('안내'), findsOneWidget);
    expect(find.text('다음부터 표시 안 함'), findsOneWidget);
    expect(find.text('닫기'), findsOneWidget);
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
            'A lone ** marker.',
      ),
    );
    await launch(tester);

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

    final paragraph = _richText(
      tester,
      'A paragraph with bold words in it and a second line of it.',
    );
    expect(_boldRuns(paragraph), ['bold words']);
    expect(_boldRuns(_richText(tester, 'First item')), ['item']);
  });

  testWidgets('the feedback button is there only when something sends it', (
    tester,
  ) async {
    await pumpHost(tester, _MemoryStore());
    await launch(tester);
    expect(_sendFeedback, findsNothing);
    await tester.tap(_close);
    await tester.pumpAndSettle();

    var sent = 0;
    await pumpHost(tester, _MemoryStore(), onSendFeedback: () => sent++);
    await launch(tester);
    await tester.tap(_sendFeedback);
    await tester.pumpAndSettle();
    expect(sent, 1);
    expect(find.text('Send feedback'), findsOneWidget);
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
