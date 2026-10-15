// 🗣️I-40 — the timeline bar's view buttons are actions: the zoom − and +
// of the panel being worked in, the timeline's ⇄ X-sheet, and the sill's
// camera view. A key presses what the button presses, on the panel the
// button is on — and the buttons speak the program language (they were
// English everywhere until this round).
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/main.dart';
import 'package:anicel/src/models/app_language.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/working_panel.dart';
import 'package:anicel/src/ui/editor_canvas_area.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/editor_workspace.dart';
import 'package:anicel/src/ui/shortcuts/editor_action_registry.dart';
import 'package:anicel/src/ui/shortcuts/editor_shortcut_bindings.dart';
import 'package:anicel/src/ui/shortcuts/editor_shortcut_scope.dart';
import 'package:anicel/src/ui/text/app_strings.dart';
import 'package:anicel/src/ui/widgets/app_icon_button.dart';

/// None of the four ships with a key; this one is recorded per press.
const k = LogicalKeyboardKey.keyK;

Future<EditorSessionManager> pumpApp(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(const Size(1700, 900));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(const AnicelApp());
  await tester.pumpAndSettle();
  return tester.widget<EditorWorkspace>(find.byType(EditorWorkspace)).session;
}

EditorShortcutBindings keys(WidgetTester tester) => EditorShortcutScope.peek(
  tester.element(find.byType(EditorWorkspace)),
)!;

String? _held;

/// Records [k] for [actionId] — alone — and presses it.
Future<void> pressKeyOf(WidgetTester tester, String actionId) async {
  if (_held case final before? when before != actionId) {
    keys(tester).resetAction(before);
  }
  _held = actionId;
  keys(tester).setActivators(actionId, const [SingleActivator(k)]);
  await tester.pump();
  await tester.sendKeyEvent(k);
  await tester.pumpAndSettle();
}

Future<void> workIn(WidgetTester tester, WorkingPanel panel) async {
  await tester.tap(
    find.byKey(
      ValueKey<String>(switch (panel) {
        WorkingPanel.timeline => 'timeline-mode-timeline-button',
        WorkingPanel.storyboard => 'timeline-mode-storyboard-button',
      }),
    ),
  );
  await tester.pumpAndSettle();
}

AppIconButton button(WidgetTester tester, String keyValue) =>
    tester.widget<AppIconButton>(
      find.byWidgetPredicate(
        (widget) => widget is AppIconButton && widget.keyValue == keyValue,
      ),
    );

void main() {
  setUp(() => _held = null);

  testWidgets('the zoom keys step the zoom of the panel being worked in, '
      'and only that one', (tester) async {
    final session = await pumpApp(tester);
    double timeline() => session.timelineZoom.zoomOf(session.activeCutId)!;
    double storyboard() => session.panelViews.storyboardPixelsPerFrame.value;

    await workIn(tester, WorkingPanel.timeline);
    await pressKeyOf(tester, EditorActionIds.timelineZoomIn);
    final timelineIn = timeline();
    final storyboardBefore = storyboard();
    await pressKeyOf(tester, EditorActionIds.timelineZoomOut);
    expect(timeline(), lessThan(timelineIn));
    expect(storyboard(), storyboardBefore, reason: 'not the conte\'s');

    await workIn(tester, WorkingPanel.storyboard);
    final timelineBefore = timeline();
    await pressKeyOf(tester, EditorActionIds.timelineZoomIn);
    expect(storyboard(), greaterThan(storyboardBefore));
    expect(timeline(), timelineBefore, reason: 'not the timeline\'s');
  });

  testWidgets('the ⇄ key turns the timeline into the X-sheet and back — and '
      'the conte, whose bar has no ⇄, answers nothing', (tester) async {
    await pumpApp(tester);
    String tip() =>
        button(tester, 'timeline-orientation-toggle-button').tooltip;

    await workIn(tester, WorkingPanel.timeline);
    expect(tip(), AppText.strings.tlShowXSheet);
    await pressKeyOf(tester, EditorActionIds.timelineOrientationToggle);
    expect(tip(), AppText.strings.tlShowTimeline);
    await pressKeyOf(tester, EditorActionIds.timelineOrientationToggle);
    expect(tip(), AppText.strings.tlShowXSheet);

    await workIn(tester, WorkingPanel.storyboard);
    await pressKeyOf(tester, EditorActionIds.timelineOrientationToggle);
    await workIn(tester, WorkingPanel.timeline);
    expect(tip(), AppText.strings.tlShowXSheet);
  });

  testWidgets('the camera view key is the sill\'s switch', (tester) async {
    final session = await pumpApp(tester);
    await workIn(tester, WorkingPanel.timeline);
    bool lit() => button(tester, 'timeline-camera-view-button').isSelected;
    final before = lit();

    await pressKeyOf(tester, EditorActionIds.cameraViewToggle);
    expect(lit(), !before);
    expect(button(tester, 'timeline-camera-view-button').shortcuts, [
      EditorActionIds.cameraViewToggle,
    ]);

    // 🗣️F-363: the switch is the camera row's eye — and the canvas reads
    // the project's own view, never a value the window held.
    expect(session.activeCutOrNull!.layers.cameraLayer!.isVisible, !before);
    final canvas = tester.widget<EditorCanvasArea>(
      find.byType(EditorCanvasArea),
    );
    expect(canvas.cameraViewEnabled, same(session.cameraViewMode.enabled));
    expect(canvas.cameraDimOpacity, same(session.cameraViewMode.dim));
    expect(canvas.cameraViewEnabled.value, !before);
  });

  testWidgets('the bar\'s buttons speak the program language', (
    tester,
  ) async {
    addTearDown(() => AppText.settings.value = const AppLanguageSettings());
    AppText.settings.value = const AppLanguageSettings(
      programLanguage: AppLanguage.ko,
    );
    await pumpApp(tester);
    await workIn(tester, WorkingPanel.timeline);
    final ko = AppStrings.of(AppLanguage.ko);

    expect(
      button(tester, 'timeline-zoom-in-button').tooltip,
      ko.shortcutLabel(EditorActionIds.timelineZoomIn, 'Timeline Zoom In'),
    );
    expect(
      button(tester, 'timeline-orientation-toggle-button').tooltip,
      ko.tlShowXSheet,
    );
    // A new project's camera is born with its view on (F-363-Q1).
    String camera() => button(tester, 'timeline-camera-view-button').tooltip;
    expect(camera(), ko.cameraViewOn);
    await pressKeyOf(tester, EditorActionIds.cameraViewToggle);
    expect(camera(), ko.cameraViewOff);
    expect(ko.tlShowXSheet, isNot('Show X-sheet'), reason: 'premise');
    expect(ko.cameraViewOn, isNot('Camera view (on)'), reason: 'premise');
  });

  testWidgets('the region\'s fold key is its chevron — and the chevron says '
      'the key', (tester) async {
    await pumpApp(tester);
    String tip() => button(tester, 'floating-bottom-collapse').tooltip;
    expect(tip(), AppText.strings.panelCollapseRegion, reason: 'premise');

    await pressKeyOf(tester, EditorActionIds.regionFold);
    expect(tip(), AppText.strings.panelExpandRegion);
    await pressKeyOf(tester, EditorActionIds.regionFold);
    expect(tip(), AppText.strings.panelCollapseRegion);
    expect(button(tester, 'floating-bottom-collapse').shortcuts, [
      EditorActionIds.regionFold,
    ]);
  });
}
