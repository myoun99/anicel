import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/timeline_row_address.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/editor_workspace.dart';
import 'package:anicel/src/ui/home_page.dart';
import 'package:anicel/src/ui/storyboard_panel.dart';
import 'package:anicel/src/ui/timeline/layer_timeline_grid.dart';
import 'package:anicel/src/ui/timeline/property_lane_model.dart'
    show laneGroupKey;
import 'package:anicel/src/ui/timeline/timeline_row_selection_bands.dart'
    show TimelineRowSelectionBands;
import 'package:anicel/src/ui/timeline/transform_lane_policy.dart'
    show transformGroupHeaderLane;

import '../../helpers/home_page_probes.dart';
import '../../helpers/named_finders.dart';

/// A move of a windowed host's window keeps the rows that stayed in it —
/// handed back as the very widgets they were — and a build of the host
/// lays them fresh (card frame-panels-build-in-one-frame ③, 2026-10-29):
/// the timeline's rail and cells, the storyboard's rail and strips — and
/// builds nothing of the frame around them (④, 2026-10-29).
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
  /// that keeps a row in view, then through a build of the [host]. The row
  /// watched is the one a third down the view, else [probe].
  Future<void> expectKeptThroughAMove(
    WidgetTester tester, {
    required String viewport,
    required List<Finder> rows,
    required Finder host,
    Finder? probe,
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
    final watched =
        probe ??
        rows[before.firstWhere(
          (index) =>
              tester.getRect(rows[index].first).top >=
              view.top + view.height / 3,
        )];
    final widgetBefore = tester.widgetList(watched).first;

    position.jumpTo(view.height / 4);
    await tester.pumpAndSettle();
    expect(
      built(),
      isNot(before),
      reason: '⛔전제: the move carries the window to other rows',
    );
    expect(
      tester.widgetList(watched).first,
      same(widgetBefore),
      reason: '$watched stayed in the window: it is the widget it was',
    );

    tester.element(host).markNeedsBuild();
    await tester.pumpAndSettle();
    expect(
      tester.widgetList(watched).first,
      isNot(same(widgetBefore)),
      reason: 'a build of the host lays $watched afresh',
    );
  }

  Future<void> tapNamed(WidgetTester tester, String name) async {
    await tester.ensureVisible(find.named(name));
    await tester.pumpAndSettle();
    await tester.tap(find.named(name));
    await tester.pumpAndSettle();
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

    // ④: the window's token is heard where the rows are laid, nowhere
    // above them — ↩️a move built the frame around them again, 119–180
    // elements.
    testWidgets('the frame around them — the header, the rail, the body '
        'and the cells\' sheet', (tester) async {
      final ids = await pumpTimeline(tester);
      for (final frame in [
        'timeline-sticky-header-row',
        'timeline-layer-controls-rail',
        'timeline-scrollable-body',
        'timeline-frame-grid-area',
        'timeline-grid-sheet',
      ]) {
        await expectKeptThroughAMove(
          tester,
          viewport: 'timeline-vertical-scroll-viewport',
          rows: [for (final id in ids) find.named('timeline-rail-row-$id-row')],
          host: find.byType(LayerTimelineGrid),
          probe: find.byKey(ValueKey<String>(frame)),
        );
      }
    });

    // What the window lays is laid where the scroll stands, though nothing
    // around it is built again: the rail's selection bands with its rows,
    // and a sweep down its column over the rows a move brought in.
    testWidgets('the rail\'s selection bands move with its rows', (
      tester,
    ) async {
      await pumpTimeline(tester);
      const viewport = 'timeline-vertical-scroll-viewport';
      final position = rowsIn(tester, viewport)..jumpTo(0);
      await tester.pumpAndSettle();
      int bandsFrom() => tester
          .widget<TimelineRowSelectionBands>(
            find.descendant(
              of: find.byType(LayerTimelineGrid),
              matching: find.byType(TimelineRowSelectionBands),
            ),
          )
          .firstRow;
      final before = bandsFrom();
      final view = tester.getRect(find.byKey(const ValueKey(viewport)));
      position.jumpTo(view.height / 2);
      await tester.pumpAndSettle();
      expect(bandsFrom(), greaterThan(before));
    });

    testWidgets('a sweep down the rail reaches the rows a move brought in', (
      tester,
    ) async {
      final ids = await pumpTimeline(tester);
      final session = sessionOf(tester);
      const viewport = 'timeline-vertical-scroll-viewport';
      final position = rowsIn(tester, viewport)..jumpTo(0);
      await tester.pumpAndSettle();
      Finder eye(String id) => find.named('timeline-layer-visibility-$id');
      final before = {
        for (final id in ids)
          if (eye(id).evaluate().isNotEmpty) id,
      };
      final view = tester.getRect(find.byKey(const ValueKey(viewport)));
      position.jumpTo(view.height / 2);
      await tester.pumpAndSettle();
      final arrived = [
        for (final id in ids)
          if (!before.contains(id) &&
              eye(id).evaluate().isNotEmpty &&
              view.contains(tester.getCenter(eye(id))))
            id,
      ]..sort((a, b) => tester.getCenter(eye(a)).dy.compareTo(
            tester.getCenter(eye(b)).dy,
          ));
      expect(
        arrived.length,
        greaterThanOrEqualTo(2),
        reason: '⛔전제: the move brought rows into view',
      );
      bool visible(String id) => session.layers
          .firstWhere((layer) => layer.id == LayerId(id))
          .isVisible;
      final first = tester.getCenter(eye(arrived[0]));
      final second = tester.getCenter(eye(arrived[1]));
      final wasVisible = (visible(arrived[0]), visible(arrived[1]));
      // Latched near the top of the first row with a short move, as the
      // eye sweep's own test does: the recognizer reports where it won.
      final gesture = await tester.startGesture(
        first - Offset(0, (second.dy - first.dy) / 2 - 2),
      );
      await tester.pump();
      await gesture.moveBy(const Offset(0, 4));
      await tester.pump();
      await gesture.moveTo(second);
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();
      expect(
        (visible(arrived[0]), visible(arrived[1])),
        (!wasVisible.$1, !wasVisible.$2),
      );
    });

    testWidgets('a graph, drawn whole across its lanes', (tester) async {
      final ids = await pumpTimeline(tester);
      final view = tester.getRect(
        find.byKey(const ValueKey<String>('timeline-vertical-scroll-viewport')),
      );
      final rail = [
        for (final id in ids) find.named('timeline-rail-row-$id-row'),
      ];
      // The layer first below a third of the view: its graph opens below it.
      final below = [
        for (var index = 0; index < ids.length; index += 1)
          if (rail[index].evaluate().isNotEmpty &&
              tester.getRect(rail[index]).top >= view.top + view.height / 3)
            index,
      ];
      double topOf(int index) => tester.getRect(rail[index]).top;
      final id = ids[below.reduce((a, b) => topOf(a) <= topOf(b) ? a : b)];
      final lane = transformGroupHeaderLane.laneId;
      await tapNamed(tester, 'timeline-lane-toggle-$id');
      await tapNamed(tester, 'timeline-lane-group-toggle-$id-$lane');
      await tapNamed(tester, 'timeline-lane-group-graph-$id-$lane');
      await expectKeptThroughAMove(
        tester,
        viewport: 'timeline-vertical-scroll-viewport',
        rows: rail,
        host: find.byType(LayerTimelineGrid),
        probe: find.byKey(
          ValueKey<String>(
            'timeline-lane-graph-${laneGroupKey(LayerId(id), lane)}',
          ),
        ),
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

    testWidgets('rail: a label that stayed through a move is still the '
        'rail\'s own across a build (I-57), and one the window left is let '
        'go of', (tester) async {
      final track = await pumpStoryboard(tester);
      Finder label(int slot) =>
          find.byKey(ValueKey<String>('storyboard-se-label-$track-$slot'));
      const viewport = 'storyboard-vertical-viewport';
      final position = rowsIn(tester, viewport)..jumpTo(0);
      await tester.pumpAndSettle();
      final view = tester.getRect(find.byKey(const ValueKey(viewport)));
      final top = tester.widget(label(_rows));
      // Two thirds down: a move of half the view leaves it in view.
      var slot = _rows;
      while (tester.getRect(label(slot)).top <
          view.top + view.height * 2 / 3) {
        slot -= 1;
      }
      final stayed = tester.widget(label(slot));

      position.jumpTo(view.height / 2);
      await tester.pumpAndSettle();
      expect(label(_rows), findsNothing, reason: '⛔전제: the top row left');
      tester.element(find.byType(StoryboardPanel)).markNeedsBuild();
      await tester.pumpAndSettle();
      expect(tester.widget(label(slot)), same(stayed));

      position.jumpTo(0);
      await tester.pumpAndSettle();
      expect(tester.widget(label(_rows)), isNot(same(top)));
    });

    testWidgets('a section\'s zone beside the rail\'s rows (④)', (
      tester,
    ) async {
      final track = await pumpStoryboard(tester);
      await expectKeptThroughAMove(
        tester,
        viewport: 'storyboard-vertical-viewport',
        rows: [
          for (var slot = _rows; slot >= 1; slot -= 1)
            unitOf(
              find.byKey(ValueKey<String>('storyboard-se-label-$track-$slot')),
            ),
        ],
        host: find.byType(StoryboardPanel),
        probe: find.byKey(
          ValueKey<String>('storyboard-section-zone-$track-se'),
        ),
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
