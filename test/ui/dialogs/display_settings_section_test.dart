import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/app_accents.dart';
import 'package:anicel/src/models/app_frame_grid_settings.dart';
import 'package:anicel/src/models/app_input_settings.dart';
import 'package:anicel/src/models/inbetween_mark.dart';
import 'package:anicel/src/ui/dialogs/display_settings_section.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/shortcuts/editor_action_registry.dart';
import 'package:anicel/src/ui/shortcuts/editor_shortcut_scope.dart'
    show editorActionLabel;
import 'package:anicel/src/ui/text/app_strings.dart';
import 'package:anicel/src/ui/theme/app_theme.dart';
import 'package:anicel/src/ui/timeline/inbetween_mark_icon.dart';
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
      await pick(tester, picker, stop(1.3));
      expect(AppUiScale.value.value, 1.3);
      expect(said(tester, picker), AppUiScale.label(1.3));

      await pick(tester, picker, stop(0.7));
      expect(AppUiScale.value.value, 0.7);
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
      session.setUiScale(1.24);
      await tester.pump();
      expect(AppUiScale.value.value, 1.2);
      // ⚠️Otherwise no stop would look picked and the row would read as
      // "the scale is off".
      expect(find.text('124%'), findsNothing);
      expect(pickedIn(tester, picker), [stop(1.2)]);
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

  // 🗣️I-143 (유저 2026-10-29): 다크 · 라이트 둘(Q2), dark as the app has
  // always been.
  group('the palette', () {
    final picker = find.byKey(const ValueKey<String>('settings-color-mode'));
    String row(AppColorMode mode) => 'settings-color-mode-${mode.name}';

    tearDown(
      () => AppColors.accentSettings.value = const AppAccentSettings(),
    );

    testWidgets('is a list of dark and light, dark picked out of the box', (
      tester,
    ) async {
      await pump(tester);
      expect(find.text(AppText.strings.colorModeLabel), findsOneWidget);
      expect(
        [
          for (final item in rowsOf(tester, picker)) (item.keyValue, item.label),
        ],
        [
          (row(AppColorMode.dark), AppText.strings.colorModeDark),
          (row(AppColorMode.light), AppText.strings.colorModeLight),
        ],
      );
      expect(pickedIn(tester, picker), [row(AppColorMode.dark)]);
    });

    testWidgets('a pick wears the palette at once, keeping the accent', (
      tester,
    ) async {
      AppColors.accentSettings.value = const AppAccentSettings(
        accent: Color(0xFF5B9BD5),
      );
      await pump(tester);
      await pick(tester, picker, row(AppColorMode.light));
      expect(
        AppColors.accentSettings.value,
        const AppAccentSettings(
          accent: Color(0xFF5B9BD5),
          mode: AppColorMode.light,
        ),
      );
      expect(AppColors.surface, AppPalette.light.surface);
      expect(said(tester, picker), AppText.strings.colorModeLight);

      await pick(tester, picker, row(AppColorMode.dark));
      expect(AppColors.accentSettings.value.mode, AppColorMode.dark);
      expect(AppColors.surface, AppPalette.dark.surface);
    });
  });

  // 🗣️F-489 (유저 2026-10-27): 「이름 없는 블록의 기본 마크1,2인지
  // 설정할수있게 … 환경설정에서 바꾸도록. 화면 탭에서? 그런건 판단 맡기고 …
  // 기본값은 마크2로 둠」.
  group('the unnamed block\'s mark', () {
    final picker = find.byKey(const ValueKey<String>('settings-unnamed-mark'));
    String row(InbetweenMark mark) => 'settings-unnamed-mark-${mark.name}';

    setUp(() => AppFrameGridSettings.settings.value =
        const AppFrameGridSettings());
    tearDown(() => AppFrameGridSettings.settings.value =
        const AppFrameGridSettings());

    /// What the button wears: the face, any words, and its tooltip.
    (IconData?, String, String?) worn(WidgetTester tester) {
      final button = tester.widget<PanelFlyoutButton>(picker);
      return (button.icon, button.label, button.tooltip);
    }

    // 🗣️F-497 (유저 2026-10-28): 「이름없는 블록 마크 버튼 텍스트가 아니라
    // 마크 그대로사용 … 텍스트면 뭔지 알기힘드니」 — the face its toggle
    // button and the mark-every window's pick wear.
    testWidgets('is a list of the two marks, each wearing its button\'s face '
        'beside its name, mark 2 picked out of the box — and the button wears '
        'the mark alone, its name the tooltip', (tester) async {
      await pump(tester);
      expect(find.text(AppText.strings.unnamedMarkLabel), findsOneWidget);
      expect(
        [
          for (final item in rowsOf(tester, picker))
            (item.keyValue, item.icon, item.label),
        ],
        [
          for (final mark in InbetweenMark.values)
            (
              row(mark),
              inbetweenMarkIcon(mark),
              editorActionLabel(markToggleActionOf(mark)),
            ),
        ],
      );
      expect(pickedIn(tester, picker), [row(InbetweenMark.two)]);
      expect(worn(tester), (
        inbetweenMarkIcon(InbetweenMark.two),
        '',
        editorActionLabel(EditorActionIds.frameToggleMarkTwo),
      ));
      final face = find.descendant(
        of: picker,
        matching: find.byIcon(inbetweenMarkIcon(InbetweenMark.two)),
      );
      expect(face, findsOneWidget, reason: 'what the eye meets');
      expect(
        tester.getCenter(face).dx,
        moreOrLessEquals(tester.getCenter(picker).dx),
        reason: 'standing where the words would, not a gap before them',
      );
    });

    testWidgets('a pick sets the live setting, touching nothing else it '
        'holds, and the button wears it', (tester) async {
      AppFrameGridSettings.settings.value = const AppFrameGridSettings(
        blockFrameLines: true,
      );
      await pump(tester);
      await pick(tester, picker, row(InbetweenMark.one));
      expect(
        AppFrameGridSettings.settings.value,
        const AppFrameGridSettings(
          blockFrameLines: true,
          unnamedMark: InbetweenMark.one,
        ),
      );
      expect(pickedIn(tester, picker), [row(InbetweenMark.one)]);
      expect(worn(tester), (
        inbetweenMarkIcon(InbetweenMark.one),
        '',
        editorActionLabel(EditorActionIds.frameToggleMarkOne),
      ));
    });
  });
}
