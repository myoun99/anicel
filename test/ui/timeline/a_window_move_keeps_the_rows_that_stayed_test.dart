import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/timeline_row_address.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/editor_workspace.dart';
import 'package:anicel/src/ui/home_page.dart';
import 'package:anicel/src/ui/storyboard_panel.dart';
import 'package:anicel/src/ui/timeline/layer_timeline_grid.dart';

import '../../helpers/home_page_probes.dart';
import '../../helpers/named_finders.dart';

/// A move of a windowed host's window keeps the rows that stayed in it —
/// handed back as the very widgets they were — and a build of the host
/// lays them fresh (card frame-panels-build-in-one-frame ③, 2026-10-29):
/// the timeline's rail and cells, the storyboard's rail and strips.
/// ↩️Every move built every row the window held again.
void main() {
  EditorSessionManager sessionOf(WidgetTester tester) =>
      tester.widget<EditorWorkspace>(find.byType(EditorWorkspace)).session;

  ScrollPosition rowsIn(WidgetTester tester, String viewport) => tester
      .stateList<ScrollableState>(
        find.descendant(
          of: find.byKey(ValueKey<String>(viewport)),
          matching: find.byType(Scrollable),
        ),
      )
      .first
      .position;

  /// [rows] — a host's rows, top first — through a move of its window
  /// that keeps a row in view, then through a build of the [host].
  Future<void> expectKeptThroughAMove(
    WidgetTester tester, {
    required String viewport,
    required List<Finder> rows,
    required Finder host,
  }) async {
    final position = rowsIn(tester, viewport);
    position.jumpTo(0);
    await tester.pumpAndSettle();
    final view = tester.getRect(find.byKey(ValueKey<String>(viewport)));
    Set<int> built() => {
      for (var index = 0; index < rows.length; index += 1)
        if (rows[index].evaluate().isNotEmpty) index,
    };
    final before = built();
    // The probe stands a third down the view: a move of a quarter of it
    // brings rows in below and leaves the probe in view.
    final probe = before.firstWhere(
      (index) =>
          tester.getRect(rows[index].first).top >= view.top + view.height / 3,
    );
    final widgetBefore = tester.widgetList(rows[probe]).first;

    position.jumpTo(view.height / 4);
    await tester.pumpAndSettle();
    expect(
      built(),
      isNot(before),
      reason: '⛔전제: the move carries the window to other rows',
    );
    expect(
      tester.widgetList(rows[probe]).first,
      same(widgetBefore),
      reason: 'row $probe stayed in the window: it is the widget it was',
    );

    tester.element(host).markNeedsBuild();
    await tester.pumpAndSettle();
    expect(
      tester.widgetList(rows[probe]).first,
      isNot(same(widgetBefore)),
      reason: 'a build of the host lays row $probe afresh',
    );
  }

  Future<EditorSessionManager> pumpRows(
    WidgetTester tester,
    LayerKind kind,
    int count,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1600, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const MaterialApp(home: HomePage()));
    await tester.pumpAndSettle();
    final session = sessionOf(tester);
    session.selectLayer(
      session.layers.firstWhere((layer) => layer.kind == kind).id,
    );
    while (session.layers.where((layer) => layer.kind == kind).length <
        count) {
      session.layerStack.addLayerOfKind(kind);
    }
    await tester.pumpAndSettle();
    return session;
  }

  group('the timeline', () {
    Future<List<String>> pumpTimeline(WidgetTester tester) async {
      final session = await pumpRows(tester, LayerKind.animation, _rows);
      return [
        for (final layer in session.layers)
          if (layer.kind == LayerKind.animation) layer.id.value,
      ];
    }

    testWidgets('rail', (tester) async {
      final ids = await pumpTimeline(tester);
      await expectKeptThroughAMove(
        tester,
        viewport: 'timeline-vertical-scroll-viewport',
        rows: [for (final id in ids) find.named('timeline-rail-row-$id-row')],
        host: find.byType(LayerTimelineGrid),
      );
    });

    testWidgets('cells', (tester) async {
      final ids = await pumpTimeline(tester);
      await expectKeptThroughAMove(
        tester,
        viewport: 'timeline-vertical-scroll-viewport',
        rows: [for (final id in ids) find.named('timeline-row-$id-cells')],
        host: find.byType(LayerTimelineGrid),
      );
    });
  });

  group('the storyboard', () {
    Future<String> pumpStoryboard(WidgetTester tester) async {
      final session = await pumpRows(tester, LayerKind.se, _rows);
      await showStoryboardPanel(tester);
      return session.repository.requireProject().tracks.single.id.value;
    }

    /// What the window lays [row] in: its unit, held by the row's address
    /// — the rail's and the strips' alike.
    Finder unitOf(Finder row) => find.ancestor(
      of: row,
      matching: find.byWidgetPredicate(
        (widget) =>
            widget is Listener && widget.key is ValueKey<TimelineRowAddress>,
      ),
    );

    testWidgets('rail', (tester) async {
      final track = await pumpStoryboard(tester);
      await expectKeptThroughAMove(
        tester,
        viewport: 'storyboard-vertical-viewport',
        rows: [
          // Top first: the rail lays the top slot first.
          for (var slot = _rows; slot >= 1; slot -= 1)
            unitOf(
              find.byKey(ValueKey<String>('storyboard-se-label-$track-$slot')),
            ),
        ],
        host: find.byType(StoryboardPanel),
      );
    });

    testWidgets('strips', (tester) async {
      await pumpStoryboard(tester);
      await expectKeptThroughAMove(
        tester,
        viewport: 'storyboard-vertical-viewport',
        rows: [
          for (var slot = _rows; slot >= 1; slot -= 1)
            unitOf(find.byKey(ValueKey<String>('storyboard-se-row-0-$slot'))),
        ],
        host: find.byType(StoryboardPanel),
      );
    });
  });
}

/// The rows each host holds — more than its view shows.
const int _rows = 40;
