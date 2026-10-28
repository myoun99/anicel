import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/app_input_settings.dart';
import 'package:anicel/src/models/brush_pressure_curve.dart';
import 'package:anicel/src/ui/dialogs/input_settings_dialog.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/widgets/content_scrollbar.dart';
import 'package:anicel/src/ui/widgets/pressure_curve_popup.dart';
import 'package:anicel/src/ui/widgets/setting_source_button.dart';

import '../../helpers/dart_sources.dart';

/// 🗣️F-480 (유저 2026-10-26): 「필압곡선은 클튜처럼 그래프창으로」.
///
/// Preferences ▸ Input's pen response is a graph in a window, edited by the
/// hand a brush's curves are edited by — the same graph, not a second one.
void main() {
  tearDown(() {
    AppInput.settings.value = AppInputSettings.testCorpusBaseline;
  });

  final button = find.byKey(const ValueKey<String>('settings-pressure-curve'));
  final window = find.byKey(const ValueKey<String>('pen-response-popup'));
  final graph = find.byKey(const ValueKey<String>('pen-response-graph'));

  Future<void> pumpInputTab(WidgetTester tester) async {
    final session = EditorSessionManager(
      initialProject: createDefaultProject(),
    );
    addTearDown(session.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
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
  }

  Future<void> openTheGraph(WidgetTester tester) async {
    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(window, findsOneWidget);
  }

  /// A press in the graph's middle adds a point there; the hand pulls it up
  /// by [lift] of the graph's height and lets go.
  Future<void> pullTheMiddleUp(WidgetTester tester, double lift) async {
    final rect = tester.getRect(graph);
    final hand = await tester.startGesture(rect.center);
    await tester.pump();
    await hand.moveBy(Offset(0, -rect.height * lift));
    await tester.pump();
    await hand.up();
    await tester.pumpAndSettle();
  }

  bool lit(WidgetTester tester) => tester
      .widget<SettingSourceButton>(
        find.byWidgetPredicate(
          (widget) =>
              widget is SettingSourceButton &&
              widget.keyValue == 'settings-pressure-curve',
        ),
      )
      .active;

  testWidgets('the row opens a graph window, and the pen follows the hand '
      'on it before it lets go', (tester) async {
    await pumpInputTab(tester);
    expect(AppInput.applyPressureCurve(0.5), 0.5, reason: 'premise');
    await openTheGraph(tester);

    final rect = tester.getRect(graph);
    final hand = await tester.startGesture(rect.center);
    await tester.pump();
    await hand.moveBy(Offset(0, -rect.height * 0.3));
    await tester.pump();
    expect(AppInput.settings.value.pressureCurve.points, hasLength(3));
    expect(
      AppInput.applyPressureCurve(0.5),
      greaterThan(0.6),
      reason: 'a point pulled up is a softer pen',
    );
    await hand.up();
    await tester.pumpAndSettle();
  });

  testWidgets('the window opens on the curve the pen has', (tester) async {
    AppInput.settings.value = AppInputSettings.testCorpusBaseline.copyWith(
      pressureCurve: BrushPressureCurve(const [
        BrushCurvePoint(0, 0),
        BrushCurvePoint(0.5, 0.2),
        BrushCurvePoint(1, 1),
      ]),
    );
    await pumpInputTab(tester);
    await openTheGraph(tester);
    expect(tester.widget<PressureCurveGraph>(graph).points, hasLength(3));
  });

  testWidgets('the button wears the line: dim while it is straight, lit once '
      'it bends, and the reset lays the straight line back', (tester) async {
    await pumpInputTab(tester);
    expect(lit(tester), isFalse);
    await openTheGraph(tester);
    await pullTheMiddleUp(tester, 0.3);
    expect(lit(tester), isTrue);

    await tester.tap(find.byKey(const ValueKey<String>('pen-response-reset')));
    await tester.pumpAndSettle();
    expect(AppInput.settings.value.pressureCurve, BrushPressureCurve.linear);
    expect(tester.widget<PressureCurveGraph>(graph).points, hasLength(2));
    expect(lit(tester), isFalse);
  });

  testWidgets('a reset under a hand that holds a point lets the point go', (
    tester,
  ) async {
    AppInput.settings.value = AppInputSettings.testCorpusBaseline.copyWith(
      pressureCurve: BrushPressureCurve(const [
        BrushCurvePoint(0, 0),
        BrushCurvePoint(0.5, 0.2),
        BrushCurvePoint(1, 1),
      ]),
    );
    await pumpInputTab(tester);
    await openTheGraph(tester);
    final rect = tester.getRect(graph);
    // The hand holds the last of three points, at the top right.
    final hand = await tester.startGesture(
      rect.topRight + const Offset(-2, 2),
    );
    await tester.pump();
    await hand.moveBy(const Offset(0, 10));
    await tester.pump();

    // Another finger resets: the line has two points, and the third is gone.
    await tester.tap(find.byKey(const ValueKey<String>('pen-response-reset')));
    await tester.pump();
    await hand.moveBy(const Offset(0, 10));
    await tester.pump();
    await hand.up();
    await tester.pumpAndSettle();
    expect(AppInput.settings.value.pressureCurve, BrushPressureCurve.linear);
  });

  testWidgets("its graph is the brush window's graph", (tester) async {
    await pumpInputTab(tester);
    await openTheGraph(tester);
    expect(
      find.descendant(of: window, matching: find.byType(PressureCurveGraph)),
      findsOneWidget,
    );
  });

  test('the hand a graph is edited by is written once', () {
    // The slack that deletes a point is the grammar's own number: a second
    // graph would have to carry it too.
    final holders = [
      for (final file in dartFilesUnder('lib'))
        if (file.readAsStringSync().contains('removeSlack')) libPath(file),
    ];
    expect(holders, ['lib/src/ui/widgets/pressure_curve_popup.dart']);
  });
}
