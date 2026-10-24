import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart' show SemanticsAction;
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/input/arena_tap_hold.dart';
import 'package:anicel/src/ui/theme/app_theme.dart';
import 'package:anicel/src/ui/timeline/timeline_layer_controls_row.dart';
import 'package:anicel/src/ui/timeline/timeline_orientation.dart';
import 'package:anicel/src/ui/timeline_tab_host.dart';
import 'package:anicel/src/ui/widgets/instant_tap_region.dart';

/// A timeline row's BODY — its pick, its label's double click and the tap it
/// holds in the arena — is three light boxes (card
/// frame-panels-build-in-one-frame, 2026-10-25): a state and its listener,
/// and two `RawGestureDetector`s of three elements each, were made again for
/// every row a tab reopens.
void main() {
  testWidgets('🚨from its pick to its plate a rail row holds no state and no '
      'detector — one element a box', (tester) async {
    final session = EditorSessionManager(
      initialProject: createDefaultProject(),
    );
    addTearDown(session.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: Scaffold(
          body: TimelineTabHost(
            session: session,
            orientation: TimelineOrientation.horizontal,
            onOrientationChanged: (_) {},
            pixelsPerFrame: 24,
            onPixelsPerFrameChanged: (_) {},
            showSeconds: false,
            onShowSecondsChanged: (_) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final rows = find.byType(TimelineLayerControlsRow).evaluate().toList();
    expect(rows, isNotEmpty, reason: 'fixture: the rail draws rows');
    for (final row in rows) {
      final pick = find
          .descendant(
            of: find.byElementPredicate((e) => identical(e, row)),
            matching: find.byType(InstantTapRegion),
          )
          .evaluate()
          .first;
      // Down the one-child chain from the pick to the plate.
      final chain = <Element>[];
      var at = pick;
      while (at.widget is! Container) {
        chain.add(at);
        Element? only;
        at.visitChildren((child) => only = child);
        at = only!;
      }
      final kinds = [for (final e in chain) '${e.widget.runtimeType}'];
      expect(kinds, [
        'InstantTapRegion',
        '_LabelDoubleTap',
        'Named',
        'ArenaTapHold',
      ], reason: 'the body\'s boxes, in the order they hear a press');
      expect(chain.whereType<StatefulElement>(), isEmpty);
    }

    // Drain the prerender scheduler's debounced warming.
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
  });

  group('the tap a row holds', () {
    // A row that holds its tap, inside a tap of its own surroundings when
    // [onOuterTap] is given — a screen reader's node is the row's alone.
    Future<void> pumpHold(
      WidgetTester tester, {
      required bool holds,
      VoidCallback? onOuterTap,
    }) {
      Widget row = Semantics(
        container: true,
        label: 'row',
        child: ArenaTapHold(
          holds: holds,
          child: const ColoredBox(
            color: Color(0xFF000000),
            child: SizedBox(width: 100, height: 40),
          ),
        ),
      );
      if (onOuterTap != null) {
        row = GestureDetector(onTap: onOuterTap, child: row);
      }
      return tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Center(child: row),
        ),
      );
    }

    testWidgets('wins the arena over a tap around it — and a row that holds '
        'none lets that tap through, and holds again when it is made to', (
      tester,
    ) async {
      var outer = 0;
      void tapped() => outer += 1;

      await pumpHold(tester, holds: true, onOuterTap: tapped);
      await tester.tap(find.byType(ColoredBox));
      expect(outer, 0, reason: 'the row\'s own tap, answered with nothing');

      await pumpHold(tester, holds: false, onOuterTap: tapped);
      await tester.tap(find.byType(ColoredBox));
      expect(outer, 1, reason: '⛔CONTROL: a row that holds nothing');

      await pumpHold(tester, holds: true, onOuterTap: tapped);
      await tester.tap(find.byType(ColoredBox));
      expect(outer, 1, reason: 'held again, in the same box');
    });

    testWidgets('a screen reader may tap a row that holds — as the detector '
        'it was said — and not one that holds nothing', (tester) async {
      final handle = tester.ensureSemantics();
      bool canTap() => tester
          .getSemantics(find.bySemanticsLabel('row'))
          .getSemanticsData()
          .hasAction(SemanticsAction.tap);

      await pumpHold(tester, holds: true);
      expect(canTap(), isTrue);

      await pumpHold(tester, holds: false);
      expect(canTap(), isFalse);

      await pumpHold(tester, holds: true);
      expect(canTap(), isTrue, reason: 'told the moment it holds again');
      handle.dispose();
    });
  });
}
