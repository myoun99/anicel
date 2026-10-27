import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import '../../helpers/boolean_dot_probe.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/ui/dialogs/input_settings_dialog.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/text/app_strings.dart' show AppText;
import 'package:anicel/src/models/app_input_settings.dart';
import 'package:anicel/src/ui/widgets/owning_axis_grip.dart';
import 'package:anicel/src/ui/theme/app_theme.dart' show AppColors;
import 'package:anicel/src/ui/widgets/app_icon_button.dart';
import 'package:anicel/src/ui/widgets/content_scrollbar.dart';
import 'package:anicel/src/ui/widgets/field_slider.dart';
import 'package:anicel/src/ui/widgets/panel_flyout.dart';

import '../../helpers/app_icon_button_probe.dart';

/// PEN-2: the Input Settings dialog's tablet-service switch (Windows
/// only — the CSP-style dual backend).
void main() {
  tearDown(() {
    AppInput.settings.value = AppInputSettings.testCorpusBaseline;
  });

  Future<EditorSessionManager> pumpDialog(WidgetTester tester) async {
    final session = EditorSessionManager(
      initialProject: createDefaultProject(),
    );
    addTearDown(session.dispose);
    // The section itself, as the Preferences dialog mounts it (SAVE-1).
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          // In the content's own lane, as the window holds it (F-440): a
          // bare scroll view lays the framework's bar OVER the content on a
          // desktop, and over the ring at the row's end (F-439).
          body: ContentScrollbar(
            builder: (context, controller) => SingleChildScrollView(
              controller: controller,
              primary: false,
              child: InputSettingsSection(session: session),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return session;
  }

  testWidgets('Windows shows the tablet-service pair and Wintab applies', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    await pumpDialog(tester);

    expect(
      find.byKey(const ValueKey<String>('settings-tablet-standard')),
      findsOneWidget,
    );
    final wintab = find.byKey(const ValueKey<String>('settings-tablet-wintab'));
    expect(wintab, findsOneWidget);

    // The dialog scrolls now (PEN-7a grew it) — bring the row into view.
    await tester.ensureVisible(wintab);
    await tester.pumpAndSettle();
    await tester.pressRingIn(wintab);
    await tester.pumpAndSettle();
    expect(AppInput.settings.value.tabletService, TabletService.wintab);

    await tester.pressRingIn(
      find.byKey(const ValueKey<String>('settings-tablet-standard')),
    );
    await tester.pumpAndSettle();
    expect(AppInput.settings.value.tabletService, TabletService.standard);

    // A press SELECTS — pressing the one that is on leaves it on: there is
    // always a service, and the radio this pair used to be never let go of
    // one either.
    await tester.pressRingIn(
      find.byKey(const ValueKey<String>('settings-tablet-standard')),
    );
    await tester.pumpAndSettle();
    expect(AppInput.settings.value.tabletService, TabletService.standard);
    // 유저 named this pair as the pick-one group (guide-sym ⑥⑧), so the
    // idle one steps back.
    expect(tester.booleanDotIn(wintab).inPickOneGroup, isTrue);

    // Foundation debug vars must be back BEFORE the binding's invariant
    // check (which runs ahead of tearDown).
    debugDefaultTargetPlatformOverride = null;
  });

  // 🗣️I-27 (유저 2026-09-13): 「설정 줌 스냅 근처에 최대 줌 제한기능」, one
  // line under the zoom snaps (I-27-Q1). 🗣️F-480 (유저 2026-10-26):
  // 「리스트 팝오버로 없음이랑 항목하나 100 이렇게 두고 고르게하도록. 줌 스냅
  // 추가하듯이 똑같은 공용ui로. 다만 줌 잠금은 1개값만 허용」.
  group('the lock on zooming in is the snaps\' list, of at most one', () {
    final button = find.byKey(const ValueKey<String>('settings-zoom-ceiling'));
    Finder row(String percent) =>
        find.byKey(ValueKey<String>('settings-zoom-ceiling-$percent'));
    Finder remove(String percent) =>
        find.byKey(ValueKey<String>('settings-zoom-ceiling-$percent-remove'));
    final add = find.byKey(
      const ValueKey<String>('settings-zoom-ceiling-add'),
    );

    Future<void> open(WidgetTester tester) async {
      await tester.ensureVisible(button);
      await tester.pumpAndSettle();
      await tester.tap(button);
      await tester.pumpAndSettle();
    }

    Future<void> typeToPutIn(WidgetTester tester, String text) async {
      await tester.tap(
        find.byKey(const ValueKey<String>('settings-zoom-ceiling-new-edit')),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey<String>('settings-zoom-ceiling-new-input')),
        text,
      );
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
    }

    bool canPress(WidgetTester tester, Finder command) =>
        tester.widget<AppIconButtonFace>(command).onPressed != null;

    String said(WidgetTester tester) =>
        tester.widget<PanelFlyoutButton>(button).label;

    testWidgets('stands right under the zoom snaps, in their column', (
      tester,
    ) async {
      await pumpDialog(tester);
      final snaps = tester.getRect(
        find.byKey(const ValueKey<String>('settings-snap-zoom')),
      );
      final lock = tester.getRect(button);
      expect(lock.top, greaterThan(snaps.bottom - 1));
      expect(lock.left, snaps.left);
      expect(lock.width, snaps.width);
    });

    testWidgets('🚨empty, it reads 「없음」; the ＋ locks at the number at the '
        'foot, and then takes no more', (tester) async {
      await pumpDialog(tester);
      expect(said(tester), AppText.strings.commonNone);
      expect(AppInput.settings.value.zoomCeiling, isNull);

      await open(tester);
      expect(canPress(tester, add), isTrue, reason: 'empty, it takes one');
      await tester.tap(add);
      await tester.pumpAndSettle();

      expect(AppInput.settings.value.zoomCeiling, 100);
      expect(row('100'), findsOneWidget, reason: 'the list stays open');
      expect(said(tester), '100');
      expect(canPress(tester, add), isFalse, reason: 'one is all it holds');

      await typeToPutIn(tester, '250');
      expect(
        canPress(tester, add),
        isFalse,
        reason: 'a number it does not have yet still finds it full',
      );
    });

    testWidgets('🚨its − lets the lock go, and the next ＋ locks at the '
        'number at the foot', (tester) async {
      AppInput.settings.value = AppInputSettings.testCorpusBaseline.copyWith(
        zoomCeiling: 100,
      );
      await pumpDialog(tester);
      await open(tester);
      expect(
        tester.widget<AppIconButtonFace>(remove('100')).onPressed,
        isNotNull,
        reason: 'unlike the snaps, it may stand empty',
      );

      await tester.tap(remove('100'));
      await tester.pumpAndSettle();
      expect(AppInput.settings.value.zoomCeiling, isNull);
      expect(row('100'), findsNothing);
      expect(said(tester), AppText.strings.commonNone);

      await typeToPutIn(tester, '9000');
      await tester.tap(add);
      await tester.pumpAndSettle();
      expect(
        AppInput.settings.value.zoomCeiling,
        1600,
        reason: 'a number no view can stand on becomes the nearest one can',
      );
    });
  });

  // 🗣️F-391 (유저 2026-10-17): 「회전 스냅은 하나만 … 쓰기쉽게」 — one number,
  // the bar the window's other single numbers are.
  testWidgets('the rotation snap is ONE number: a bar whose steps move it a '
      'degree, kept when let go', (tester) async {
    await pumpDialog(tester);
    final bar = find.byKey(const ValueKey<String>('settings-snap-rotation'));
    await tester.ensureVisible(bar);
    await tester.pumpAndSettle();
    expect(tester.widget<FieldSlider>(bar).value, 15);

    await tester.tap(
      find.descendant(
        of: bar,
        matching: find.byKey(const ValueKey<String>('field-slider-step-up')),
      ),
    );
    await tester.pumpAndSettle();

    expect(AppInput.settings.value.rotationSnapDegrees, 16);
    expect(tester.widget<FieldSlider>(bar).value, 16);
  });

  // 🗣️F-480 (유저 2026-10-26): 「왼쪽 UI크기 텍스트, 오른쪽에 고르는거. 이렇게
  // 다른탭도 통일」 · 「세로가 서로 어긋나있음」 — a bar's control stands in the
  // pickers' column, at their width.
  testWidgets('a bar stands in the pickers\' column, at their width', (
    tester,
  ) async {
    await pumpDialog(tester);
    final picker = tester.getRect(
      find.byKey(const ValueKey<String>('settings-snap-zoom')),
    );
    final bar = tester.getRect(
      find.byKey(const ValueKey<String>('settings-snap-rotation')),
    );
    expect(bar.left, picker.left);
    expect(bar.width, picker.width);
  });

  // The window's bars are one code (`_SettingsBar`): what one does while
  // held, they all do. Its let-go is `a_setting_survives_a_restart_test`'s.
  testWidgets('a bar moves its setting while it is held, before it is let '
      'go', (tester) async {
    await pumpDialog(tester);
    final bar = find.descendant(
      of: find.byKey(const ValueKey<String>('settings-snap-rotation')),
      matching: find.byType(OwningAxisGrip),
    );
    await tester.ensureVisible(bar);
    await tester.pumpAndSettle();
    expect(AppInput.settings.value.rotationSnapDegrees, 15);

    final hand = await tester.startGesture(tester.getCenter(bar));
    await hand.moveBy(const Offset(30, 0));
    await hand.moveBy(const Offset(30, 0));
    await tester.pump();
    expect(AppInput.settings.value.rotationSnapDegrees, isNot(15));

    await hand.up();
    await tester.pumpAndSettle();
  });

  // 🗣️F-391 (유저 2026-10-17): 「이런 스냅 숫자 적는거 … 리스트팝오버형식으로?
  // 추가/삭제 할수있게?」 — F-391-Q1 a: a list that stays open.
  group('the zoom snaps are a list edited where it opens', () {
    final button = find.byKey(const ValueKey<String>('settings-snap-zoom'));
    Finder row(String percent) =>
        find.byKey(ValueKey<String>('settings-zoom-snap-$percent'));
    Finder remove(String percent) =>
        find.byKey(ValueKey<String>('settings-zoom-snap-$percent-remove'));
    final add = find.byKey(const ValueKey<String>('settings-zoom-snap-add'));
    final toPutIn = find.byKey(
      const ValueKey<String>('settings-zoom-snap-new'),
    );

    Future<void> open(WidgetTester tester) async {
      await tester.ensureVisible(button);
      await tester.pumpAndSettle();
      await tester.tap(button);
      await tester.pumpAndSettle();
    }

    Future<void> typeToPutIn(WidgetTester tester, String text) async {
      await tester.tap(
        find.byKey(const ValueKey<String>('settings-zoom-snap-new-edit')),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey<String>('settings-zoom-snap-new-input')),
        text,
      );
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
    }

    bool canPress(WidgetTester tester, Finder command) =>
        tester.widget<AppIconButtonFace>(command).onPressed != null;

    Color? glyphOf(WidgetTester tester, Finder command) =>
        tester.appIconButton(command).iconColor;

    testWidgets('the button writes the list, 800 and 1600 at its end', (
      tester,
    ) async {
      await pumpDialog(tester);
      expect(
        tester.widget<PanelFlyoutButton>(button).label,
        '10, 25, 50, 75, 100, 125, 150, 200, 300, 400, 800, 1600',
      );
    });

    testWidgets('🚨a − takes its number away and the list stays open for '
        'the next', (tester) async {
      await pumpDialog(tester);
      await open(tester);
      expect(row('25'), findsOneWidget);

      await tester.tap(remove('25'));
      await tester.pumpAndSettle();
      expect(row('25'), findsNothing, reason: 'the row goes where it stood');
      expect(row('75'), findsOneWidget, reason: 'and the list is still open');

      await tester.tap(remove('75'));
      await tester.pumpAndSettle();
      expect(AppInput.settings.value.zoomSnapPercents, [
        10,
        50,
        100,
        125,
        150,
        200,
        300,
        400,
        800,
        1600,
      ]);
    });

    testWidgets('🚨the foot puts its number in where it belongs, once — and '
        'the list stays open', (tester) async {
      await pumpDialog(tester);
      await open(tester);
      expect(
        canPress(tester, add),
        isFalse,
        reason: 'it starts at 100%, which the list has',
      );

      await typeToPutIn(tester, '600');
      expect(
        find.descendant(of: toPutIn, matching: find.text('600%')),
        findsOneWidget,
      );
      await tester.tap(add);
      await tester.pumpAndSettle();

      expect(row('600'), findsOneWidget);
      expect(
        AppInput.settings.value.zoomSnapPercents.sublist(9),
        [400, 600, 800, 1600],
        reason: 'in order, not at the end',
      );
      expect(canPress(tester, add), isFalse, reason: 'once');
      expect(
        glyphOf(tester, add),
        AppColors.addGlyph(enabled: false),
        reason: 'and dim, where it stands',
      );
    });

    testWidgets('a drag on the number to put in stops where a view can '
        'stand', (tester) async {
      await pumpDialog(tester);
      await open(tester);

      await tester.drag(toPutIn, const Offset(-300, 0));
      await tester.pumpAndSettle();

      expect(
        find.descendant(of: toPutIn, matching: find.text('10%')),
        findsOneWidget,
      );
    });

    testWidgets('a number no view stands on is put in as the nearest one a '
        'view can', (tester) async {
      await pumpDialog(tester);
      await open(tester);

      await typeToPutIn(tester, '5');
      expect(
        find.descendant(of: toPutIn, matching: find.text('10%')),
        findsOneWidget,
      );
      await typeToPutIn(tester, '33.3');
      await tester.tap(add);
      await tester.pumpAndSettle();
      expect(AppInput.settings.value.zoomSnapPercents.take(3), [10, 25, 33.3]);
    });

    testWidgets('the last one cannot be taken away', (tester) async {
      AppInput.settings.value = AppInputSettings.testCorpusBaseline.copyWith(
        zoomSnapPercents: const [100],
      );
      await pumpDialog(tester);
      await open(tester);

      expect(canPress(tester, remove('100')), isFalse);
      expect(
        glyphOf(tester, remove('100')),
        AppColors.deleteGlyph(enabled: false),
        reason: 'dim, where every row\'s − stands',
      );
    });
  });

  testWidgets('non-Windows hides the tablet-service section', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    await pumpDialog(tester);

    expect(
      find.byKey(const ValueKey<String>('settings-tablet-wintab')),
      findsNothing,
    );
    // A row that is NOT platform-conditional stays, or this case would
    // also pass on a dialog that rendered nothing at all.
    expect(
      find.byKey(const ValueKey<String>('settings-extra-finger')),
      findsOneWidget,
    );

    debugDefaultTargetPlatformOverride = null;
  });

  // 🗣️I-61-Q3 (유저 2026-10-14): 「해당 손가락 스트로크 수정자 기능 옵션으로
  // on off 제공 … 기본값은 off」.
  testWidgets('the finger stroke modifier is a switch of its own: off as it '
      'comes, and pressed it is on — the navigation\'s left as it was', (
    tester,
  ) async {
    await pumpDialog(tester);
    final row = find.byKey(const ValueKey<String>('settings-stroke-finger'));
    await tester.ensureVisible(row);
    await tester.pumpAndSettle();
    final navigation = AppInput.settings.value.extraFingerModifier;
    expect(AppInput.settings.value.strokeFingerModifier, isFalse);

    await tester.pressRingIn(row);
    await tester.pumpAndSettle();

    expect(AppInput.settings.value.strokeFingerModifier, isTrue);
    expect(AppInput.settings.value.extraFingerModifier, navigation);
  });

  // 🗣️I-124 (유저 2026-10-22): 「모든 터치입력 무시하는 옵션」.
  testWidgets('ignoring every finger is a switch in the touch section: off '
      'as it comes, and pressed it is on', (tester) async {
    await pumpDialog(tester);
    final row = find.byKey(const ValueKey<String>('settings-ignore-touch'));
    await tester.ensureVisible(row);
    await tester.pumpAndSettle();
    expect(AppInput.settings.value.touchIgnored, isFalse);

    await tester.pressRingIn(row);
    await tester.pumpAndSettle();

    expect(AppInput.settings.value.touchIgnored, isTrue);
  });
}
