import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/editor_workspace.dart';
import 'package:anicel/src/ui/home_page.dart';
import 'package:anicel/src/ui/timeline/timeline_layer_controls_header.dart'
    show TimelineLayerControlsHeader;
import 'package:anicel/src/ui/timeline/layer_rail_window.dart';
import 'package:anicel/src/ui/timeline/memo_token.dart' show KeptPiece;

import '../../helpers/frame_census.dart';

/// I-57 (10-14): a notify that changed nothing in a frame panel built, laid
/// out and painted its grid's chrome again — the corner toggle, the rail's
/// splitter and scrollbar, the frame axes' scrollbars, the timeline's
/// legend — all three grids alike, and every cut crossed is such a notify
/// for them.
void main() {
  EditorSessionManager sessionOf(WidgetTester tester) =>
      tester.widget<EditorWorkspace>(find.byType(EditorWorkspace)).session;

  /// The app with its timeline panel showing [grid].
  Future<void> pumpApp(WidgetTester tester, String grid) async {
    await tester.binding.setSurfaceSize(const Size(1600, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(home: HomePage(initialProject: createDefaultProject())),
    );
    await tester.pumpAndSettle();
    final button = switch (grid) {
      'x-sheet' => 'timeline-orientation-toggle-button',
      'storyboard' => 'timeline-mode-storyboard-button',
      _ => null,
    };
    if (button != null) {
      await tester.tap(find.byKey(ValueKey<String>(button)));
      await tester.pumpAndSettle();
    }
  }

  /// [matching] in the panel [panel] — the timeline's, which holds the
  /// x-sheet too, or the storyboard's.
  Finder inThePanel(Finder matching, {String panel = 'timeline'}) =>
      find.descendant(
        of: find.byKey(ValueKey<String>('panel-content-$panel')),
        matching: matching,
      );

  /// Every kept piece of the grid in [panel] — after checking the corner,
  /// the splitter and the rail's scrollbar are among them.
  List<RenderObject> chrome(WidgetTester tester, {required String panel}) {
    for (final kind in [
      TimelineSecondsToggleCorner,
      LayerRailSplitter,
      LayerRailScrollbar,
    ]) {
      expect(
        inThePanel(find.byType(kind), panel: panel),
        findsWidgets,
        reason: 'premise: the grid has its $kind',
      );
    }
    return tester
        .renderObjectList(
          inThePanel(
            find.byWidgetPredicate((widget) => widget is KeptPiece),
            panel: panel,
          ),
        )
        .toList();
  }

  void expectNonePainted(
    List<RenderObject> pieces,
    ({List<Type> rebuilt, List<RenderObject> painted}) frame,
  ) {
    expect(
      frame.rebuilt,
      contains(TimelineSecondsToggleCorner),
      reason: 'premise: the grid built its chrome again',
    );
    for (final piece in pieces) {
      expect(
        paintedInside(frame.painted, piece),
        isFalse,
        reason: '$piece was painted again',
      );
    }
  }

  for (final grid in ['timeline', 'x-sheet', 'storyboard']) {
    testWidgets('a notify that changes nothing paints none of the $grid\'s '
        'chrome', (tester) async {
      await pumpApp(tester, grid);
      final pieces = chrome(
        tester,
        panel: grid == 'storyboard' ? 'storyboard' : 'timeline',
      );

      final frame = await frameCensus(tester, sessionOf(tester).notifyChanged);

      expectNonePainted(pieces, frame);
    });
  }

  testWidgets('nor any of the timeline\'s legend', (tester) async {
    await pumpApp(tester, 'timeline');
    final legend = tester.renderObject(
      inThePanel(find.byType(TimelineLayerControlsHeader)),
    );

    final frame = await frameCensus(tester, sessionOf(tester).notifyChanged);

    expect(
      paintedInside(frame.painted, legend),
      isFalse,
      reason: '↩️the grid laid out again painted it whole — 255 of a '
          'notify\'s 567 render objects',
    );
  });

  testWidgets('and crossing to another cut paints neither the corner nor '
      'the rail\'s splitter and scrollbar', (tester) async {
    await pumpApp(tester, 'timeline');
    final session = sessionOf(tester);
    session.cutVerbs.createCut();
    await tester.pumpAndSettle();
    final cuts = session.repository.requireProject().tracks.first.cuts;
    session.selectCut(cuts.first.id);
    await tester.pumpAndSettle();
    final pieces = [
      for (final kind in [
        TimelineSecondsToggleCorner,
        LayerRailSplitter,
        LayerRailScrollbar,
      ])
        tester.renderObject(inThePanel(find.byType(kind))),
    ];

    final frame = await frameCensus(
      tester,
      () => session.selectCut(cuts.last.id),
    );

    expectNonePainted(pieces, frame);
  });
}
