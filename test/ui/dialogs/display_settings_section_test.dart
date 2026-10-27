import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/app_frame_grid_settings.dart';
import 'package:anicel/src/models/app_input_settings.dart';
import 'package:anicel/src/ui/dialogs/display_settings_section.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/text/app_strings.dart';
import 'package:anicel/src/ui/ui_scale.dart';
import 'package:anicel/src/ui/widgets/boolean_dot.dart';
import 'package:anicel/src/ui/widgets/panel_flyout.dart';

import '../../helpers/boolean_dot_probe.dart';

/// Preferences ▸ Display. 🗣️F-480 (유저 2026-10-26): 「화면탭의 UI크기
/// 이런거 그냥 리스트팝오버로 … 왼쪽 UI크기 텍스트, 오른쪽에 고르는거 …
/// 커서도 리스트팝오버」 — each choice a picker at the end of its row.
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

  /// What [picker]'s list holds, read off the button as it would open.
  List<PanelFlyoutItem> rowsOf(WidgetTester tester, Finder picker) => [
    for (final entry
        in tester.widget<PanelFlyoutButton>(picker).entriesBuilder())
      if (entry is PanelFlyoutItem) entry,
  ];

  List<String> pickedIn(WidgetTester tester, Finder picker) => [
    for (final row in rowsOf(tester, picker))
      if (row.selected) row.keyValue,
  ];

  String said(WidgetTester tester, Finder picker) =>
      tester.widget<PanelFlyoutButton>(picker).label;

  /// Opens [picker]'s list and picks the row keyed [row], as a hand does.
  Future<void> pick(WidgetTester tester, Finder picker, String row) async {
    await tester.tap(picker);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(ValueKey<String>(row)));
    await tester.pumpAndSettle();
  }

  group('the interface scale', () {
    final picker = find.byKey(const ValueKey<String>('settings-ui-scale'));
    String stop(double scale) => 'ui-scale-stop-${(scale * 100).round()}';

    testWidgets('its list offers every ladder stop, and only those', (
      tester,
    ) async {
      await pump(tester);
      expect(
        find.descendant(
          of: find.byType(ListTile),
          matching: find.text(AppText.strings.uiScaleLabel),
        ),
        findsOneWidget,
        reason: 'its words at the start of the row its picker ends',
      );
      expect([for (final row in rowsOf(tester, picker)) row.keyValue], [
        for (final scale in AppUiScale.ladder) stop(scale),
      ]);
      expect([for (final row in rowsOf(tester, picker)) row.label], [
        for (final scale in AppUiScale.ladder) AppUiScale.label(scale),
      ]);
      // ⛔A slider would show a continuum; this is a ladder (유저 확정).
      expect(find.byType(Slider), findsNothing);
    });

    testWidgets('picking a stop sets the live scale', (tester) async {
      await pump(tester);
      await pick(tester, picker, stop(1.25));
      expect(AppUiScale.value.value, 1.25);
      expect(said(tester, picker), AppUiScale.label(1.25));

      await pick(tester, picker, stop(0.75));
      expect(AppUiScale.value.value, 0.75);
    });

    testWidgets('the row follows the value it did not set', (tester) async {
      // The scale is app-wide, so something else can move it — the restore
      // in `main()` does exactly that, before any of this is mounted.
      await pump(tester);
      session.setUiScale(1.5);
      await tester.pump();
      expect(said(tester, picker), AppUiScale.label(1.5));
      expect(pickedIn(tester, picker), [stop(1.5)]);
    });

    testWidgets('an off-ladder value from outside is snapped, not shown '
        'raw', (tester) async {
      await pump(tester);
      session.setUiScale(1.2);
      await tester.pump();
      expect(AppUiScale.value.value, 1.25);
      // ⚠️Otherwise no stop would look picked and the row would read as
      // "the scale is off".
      expect(find.text('120%'), findsNothing);
      expect(pickedIn(tester, picker), [stop(1.25)]);
    });
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

    // ↩️ON by default until 2026-10-01 (유저: 「기본값 off로」).
    testWidgets('are a switch in this section, OFF by default', (tester) async {
      await pump(tester);
      expect(find.byKey(row), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(row),
          matching: find.text(AppText.strings.blockFrameLinesLabel),
        ),
        findsOneWidget,
      );
      expect(shown(tester), isFalse);
    });

    testWidgets('a press flips the live setting, and a second one puts it '
        'back', (tester) async {
      await pump(tester);
      await tester.pressRingIn(find.byKey(row));
      await tester.pump();
      expect(AppFrameGridSettings.settings.value.blockFrameLines, isTrue);
      expect(shown(tester), isTrue);
      await tester.pressRingIn(find.byKey(row));
      await tester.pump();
      expect(AppFrameGridSettings.settings.value.blockFrameLines, isFalse);
      expect(shown(tester), isFalse);
    });

    testWidgets('the row follows a value it did not set', (tester) async {
      await pump(tester);
      session.appSettings.setFrameGridSettings(
        const AppFrameGridSettings(blockFrameLines: true),
      );
      await tester.pump();
      expect(shown(tester), isTrue);
    });
  });

  // 🗣️I-54 (유저 2026-09-30): 「브러시커서, 펜 커서 …, 십자커서 이렇게 세개」 —
  // in Preferences › Display, one for every drawing tool (I-54-Q1).
  group('the drawing tools\' cursor', () {
    final picker = find.byKey(
      const ValueKey<String>('settings-drawing-cursor'),
    );
    String row(DrawingCursor cursor) =>
        'settings-drawing-cursor-${cursor.name}';

    setUp(() => AppInput.settings.value = const AppInputSettings());
    tearDown(
      () => AppInput.settings.value = AppInputSettings.testCorpusBaseline,
    );

    testWidgets('is a list of three, in the order the user named them', (
      tester,
    ) async {
      await pump(tester);
      expect(find.text(AppText.strings.drawingCursorLabel), findsOneWidget);
      final strings = AppText.strings;
      expect(
        [
          for (final item in rowsOf(tester, picker)) (item.keyValue, item.label),
        ],
        [
          (row(DrawingCursor.brush), strings.drawingCursorBrush),
          (row(DrawingCursor.pen), strings.drawingCursorPen),
          (row(DrawingCursor.crosshair), strings.drawingCursorCrosshair),
        ],
      );
    });

    // 🗣️유저 2026-10-16: 「기본값은 십자가로 하잿나」.
    testWidgets('the crosshair is picked out of the box', (tester) async {
      await pump(tester);
      expect(pickedIn(tester, picker), [row(DrawingCursor.crosshair)]);
      expect(said(tester, picker), AppText.strings.drawingCursorCrosshair);
    });

    testWidgets('a pick sets the live setting, and the button says it', (
      tester,
    ) async {
      await pump(tester);
      await pick(tester, picker, row(DrawingCursor.pen));
      expect(AppInput.settings.value.drawingCursor, DrawingCursor.pen);
      expect(said(tester, picker), AppText.strings.drawingCursorPen);
      expect(pickedIn(tester, picker), [row(DrawingCursor.pen)]);

      await pick(tester, picker, row(DrawingCursor.brush));
      expect(AppInput.settings.value.drawingCursor, DrawingCursor.brush);
      expect(pickedIn(tester, picker), [row(DrawingCursor.brush)]);
    });

    testWidgets('it touches nothing else the input settings hold', (
      tester,
    ) async {
      AppInput.settings.value = const AppInputSettings(
        touchDragOneFinger: CanvasTouchDragAction.flip,
      );
      await pump(tester);
      await pick(tester, picker, row(DrawingCursor.brush));
      expect(
        AppInput.settings.value,
        const AppInputSettings(
          touchDragOneFinger: CanvasTouchDragAction.flip,
          drawingCursor: DrawingCursor.brush,
        ),
      );
    });
  });
}
