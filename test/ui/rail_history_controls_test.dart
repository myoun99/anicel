import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/ui/brush/tools_panel.dart';
import 'package:anicel/src/models/drawing_guide.dart';
import 'package:anicel/src/services/canvas_selection.dart';
import 'package:anicel/src/services/canvas_selection_region.dart';
import 'package:anicel/src/ui/editor_workspace.dart';
import 'package:anicel/src/ui/home_page.dart';

/// Undo, redo and the onion toggle moved from the top strip to the head of
/// the tool rail — the verbs a hand reaches for BETWEEN strokes belong
/// where the hand already is. The top strip is on its way out entirely, so
/// nothing may be left holding these there.
void main() {
  Future<void> pumpHome(WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: HomePage()));
    await tester.pumpAndSettle();
  }

  Finder railButton(String key) => find.byWidgetPredicate(
    (widget) => widget is RailButton && widget.keyValue == key,
  );

  testWidgets('undo, redo and onion sit on the rail — and only there', (
    tester,
  ) async {
    await pumpHome(tester);

    for (final key in [
      'undo-button',
      'redo-button',
      'rail-onion-skin-button',
    ]) {
      expect(railButton(key), findsOneWidget, reason: key);
    }

    // The keys are old ones a good number of tests hold; if the strip ever
    // grew them back, every one of those tests would start matching two
    // widgets instead of one.
    expect(find.byKey(const ValueKey<String>('undo-button')), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('redo-button')), findsOneWidget);
  });

  testWidgets('undo is dead until there is something to undo', (tester) async {
    await pumpHome(tester);

    final undo = tester.widget<RailButton>(railButton('undo-button'));
    expect(undo.onPressed, isNull);
  });

  testWidgets(
    'the onion button reports the active layer, not a master switch',
    (tester) async {
      await pumpHome(tester);

      final before = tester.widget<RailButton>(
        railButton('rail-onion-skin-button'),
      );
      expect(before.selected, isFalse);

      await tester.tap(railButton('rail-onion-skin-button'));
      await tester.pumpAndSettle();

      final after = tester.widget<RailButton>(
        railButton('rail-onion-skin-button'),
      );
      expect(
        after.selected,
        isTrue,
        reason: 'onion is per layer — the button shows the ACTIVE row',
      );
    },
  );

  // ㉜ (user, 2026-08-12): 「선택 해제 버튼이 없다」. The verb was already
  // bound to Ctrl+D; this is the entrance and nothing else.
  testWidgets('deselect joins them, dimmed until something is selected', (
    tester,
  ) async {
    await pumpHome(tester);

    final deselect = railButton('rail-deselect-button');
    expect(deselect, findsOneWidget);
    expect(
      tester.widget<RailButton>(deselect).onPressed,
      isNull,
      reason: 'dimmed rather than hidden — a button that comes and goes is '
          'one you have to look for',
    );
  });

  // T23 (user, 2026-08-13): 「선택해제가 선택툴일때만 조작가능. 다른툴로
  // 이동하면 선택중인상태인데도 비활성화되있어」.
  //
  // The region is a DOCUMENT-level fact and outlives the selection layer
  // (R28-S) — which is why Ctrl+D never went dead on a tool switch. The
  // button asked `hasSelection`, which asks the MOUNTED layer, so it dimmed
  // the moment that layer unbound while the selection was still on screen.
  testWidgets('deselect follows the SELECTION, not the tool — nothing is '
      'bound here and the button still works', (tester) async {
    await pumpHome(tester);

    final commands = tester
        .widget<EditorWorkspace>(find.byType(EditorWorkspace))
        .canvasSelectionCommands!;

    expect(
      commands.hasSelection,
      isFalse,
      reason:
          'no selection layer is bound in this fixture — which is the point: '
          'that is what "some other tool is active" looks like',
    );

    commands.setRegion(
      CanvasSelectionRegion.shape(
        CanvasSelectionShape.rect(left: 0, top: 0, right: 8, bottom: 8),
      ),
    );
    await tester.idle();
    await tester.pump();

    expect(
      tester.widget<RailButton>(railButton('rail-deselect-button')).onPressed,
      isNotNull,
      reason:
          'There IS a selection — the ants are on screen and Ctrl+D would '
          'clear it. A button that asks the mounted layer answers "nothing '
          'selected" about a selection the user is looking at.',
    );

    commands.setRegion(null);
    await tester.idle();
    await tester.pump();

    expect(
      tester.widget<RailButton>(railButton('rail-deselect-button')).onPressed,
      isNull,
      reason: 'and it dims again when the region really is gone',
    );
  });

  // 🚨The doors rebuild when an ANSWER moves, not when news arrives
  // (2026-09-26): the rail hears the session, the history, the tool and the
  // held stroke, and every one of them speaks far more often than a door
  // lights or dims — every pen-up, every frame of a brush-size drag.
  testWidgets('news that moves no door rebuilds none of them; a door that '
      'moves rebuilds them', (tester) async {
    await pumpHome(tester);
    final workspace = tester.widget<EditorWorkspace>(
      find.byType(EditorWorkspace),
    );
    final session = workspace.session;
    final tool = workspace.brushTool!;

    // The five doors of the head — the rail's group buttons below them are
    // other widgets with other news.
    const doors = {
      'undo-button',
      'redo-button',
      'rail-onion-skin-button',
      'rail-deselect-button',
      'rail-confirm-button',
    };
    Future<List<String>> railRebuildsAfter(void Function() act) async {
      final rebuilt = <String>[];
      debugOnRebuildDirtyWidget = (element, _) {
        final widget = element.widget;
        if (widget is RailButton && doors.contains(widget.keyValue)) {
          rebuilt.add(widget.keyValue);
        }
      };
      try {
        act();
        await tester.pump();
      } finally {
        debugOnRebuildDirtyWidget = null;
      }
      return rebuilt;
    }

    var toolNews = 0;
    void heardTool() => toolNews += 1;
    tool.addListener(heardTool);
    addTearDown(() => tool.removeListener(heardTool));
    final quietTool = await railRebuildsAfter(
      () => tool.value = tool.value.copyWith(size: tool.value.size + 3),
    );
    expect(toolNews, 1, reason: 'premise: the tool did speak');
    expect(quietTool, isEmpty, reason: 'a brush size lights no door');

    var sessionNews = 0;
    void heardSession() => sessionNews += 1;
    session.addListener(heardSession);
    addTearDown(() => session.removeListener(heardSession));
    final quietSession = await railRebuildsAfter(
      () => session.selectedGuideId = const GuideId('rail-quiet-news'),
    );
    expect(sessionNews, greaterThan(0), reason: 'premise: the session spoke');
    expect(quietSession, isEmpty, reason: 'a guide pick lights no door');

    final moved = await railRebuildsAfter(
      session.onionSkin.toggleOnionSkin,
    );
    expect(
      moved,
      containsAll(doors),
      reason: 'the onion door moved, so the head is built again',
    );
    expect(
      tester.widget<RailButton>(railButton('rail-onion-skin-button')).selected,
      isTrue,
    );
  });
}
