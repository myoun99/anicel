import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/app_frame_grid_settings.dart';
import 'package:anicel/src/ui/dialogs/display_settings_section.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/text/app_strings.dart';
import 'package:anicel/src/ui/ui_scale.dart';
import 'package:anicel/src/ui/widgets/boolean_dot.dart';

void main() {
  late EditorSessionManager session;

  setUp(() {
    // No stores: the section must work with persistence absent, which is
    // also how every widget test runs the app.
    session = EditorSessionManager(initialProject: createDefaultProject());
    AppUiScale.value.value = AppUiScale.defaultScale;
  });

  tearDown(() {
    session.dispose();
    AppUiScale.value.value = AppUiScale.defaultScale;
  });

  Future<void> pump(WidgetTester tester) => tester.pumpWidget(
    MaterialApp(
      home: Scaffold(body: DisplaySettingsSection(session: session)),
    ),
  );

  Finder stop(double scale) =>
      find.byKey(ValueKey<String>('ui-scale-stop-${(scale * 100).round()}'));

  testWidgets('every ladder stop is offered, and only those', (tester) async {
    await pump(tester);
    for (final scale in AppUiScale.ladder) {
      expect(stop(scale), findsOneWidget, reason: AppUiScale.label(scale));
      expect(find.text(AppUiScale.label(scale)), findsOneWidget);
    }
    // ⛔A slider would show a continuum; this is a ladder (유저 확정).
    expect(find.byType(Slider), findsNothing);
  });

  testWidgets('tapping a stop sets the live scale', (tester) async {
    await pump(tester);
    await tester.tap(stop(1.25));
    await tester.pump();
    expect(AppUiScale.value.value, 1.25);

    await tester.tap(stop(0.75));
    await tester.pump();
    expect(AppUiScale.value.value, 0.75);
  });

  testWidgets('the section follows the value it did not set', (tester) async {
    // The scale is app-wide, so something else can move it — the restore
    // in `main()` does exactly that, before any of this is mounted.
    await pump(tester);
    session.setUiScale(1.5);
    await tester.pump();
    ShapeDecoration decorationOf(double scale) =>
        tester.widget<Container>(
              find.descendant(of: stop(scale), matching: find.byType(Container)),
            ).decoration!
            as ShapeDecoration;

    final selected = decorationOf(1.5);
    final unselected = decorationOf(1.0);
    expect(
      selected.color,
      isNotNull,
      reason: 'selection is COLOR only (법) — the chosen stop is filled',
    );
    expect(unselected.color, isNull);
    // ⛔And nothing that changes the chip's SIZE may change with selection,
    // or the whole row slides sideways when a stop lands. Two of those:
    // the border width, and the font weight — a w600 digit is wider than a
    // w400 one. ⚠️Neither is observable by measuring the rendered box: the
    // test font gives every glyph the same advance, so this has to read
    // the resolved style.
    expect(
      (selected.shape as RoundedSuperellipseBorder).side.width,
      (unselected.shape as RoundedSuperellipseBorder).side.width,
    );
    TextStyle styleOf(double scale) => tester
        .widget<Text>(find.descendant(of: stop(scale), matching: find.byType(Text)))
        .style!;
    expect(styleOf(1.5).fontWeight, styleOf(1.0).fontWeight);
  });

  testWidgets('an off-ladder value from outside is snapped, not shown raw', (
    tester,
  ) async {
    await pump(tester);
    session.setUiScale(1.2);
    await tester.pump();
    expect(AppUiScale.value.value, 1.25);
    // ⚠️Otherwise no stop would look selected and the row would read as
    // "the scale is off".
    expect(find.text('120%'), findsNothing);
  });

  // 🗣️유저 2026-09-24: 「블록 세로선 역시 있는것도 좋아서 환경설정에 옵션으로
  // 두고싶어. 기본값은 있음으로」.
  group('the frame lines on a block', () {
    const row = ValueKey<String>('settings-block-frame-lines');

    bool shown(WidgetTester tester) => tester
        .widget<BooleanDot>(
          find.descendant(of: find.byKey(row), matching: find.byType(BooleanDot)),
        )
        .value;

    setUp(
      () => AppFrameGridSettings.settings.value = const AppFrameGridSettings(),
    );
    tearDown(
      () => AppFrameGridSettings.settings.value = const AppFrameGridSettings(),
    );

    testWidgets('are a switch in this section, ON by default', (tester) async {
      await pump(tester);
      expect(find.byKey(row), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(row),
          matching: find.text(AppText.strings.blockFrameLinesLabel),
        ),
        findsOneWidget,
      );
      expect(shown(tester), isTrue);
    });

    testWidgets('a press flips the live setting, and a second one puts it '
        'back', (tester) async {
      await pump(tester);
      await tester.tap(find.byKey(row));
      await tester.pump();
      expect(AppFrameGridSettings.settings.value.blockFrameLines, isFalse);
      expect(shown(tester), isFalse);
      await tester.tap(find.byKey(row));
      await tester.pump();
      expect(AppFrameGridSettings.settings.value.blockFrameLines, isTrue);
      expect(shown(tester), isTrue);
    });

    testWidgets('the row follows a value it did not set', (tester) async {
      await pump(tester);
      session.appSettings.setFrameGridSettings(
        const AppFrameGridSettings(blockFrameLines: false),
      );
      await tester.pump();
      expect(shown(tester), isFalse);
    });
  });
}
