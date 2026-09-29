import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/canvas_viewport.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/ui/brush/sheet_canvas_panel.dart';
import 'package:anicel/src/ui/conte/conte_tab_host.dart';
import 'package:anicel/src/ui/envelope/cut_envelope_tab_host.dart';
import 'package:anicel/src/ui/home_page.dart';
import 'package:anicel/src/ui/theme/app_theme.dart';
import 'package:anicel/src/ui/timesheet_tab_host.dart';
import 'package:anicel/src/ui/widgets/still_raster.dart';
import 'package:anicel/src/ui/widgets/tick_layer.dart';

import '../../helpers/repaint_strays.dart';

/// 🚨A SHEET PANS AND TURNS OVER ON A LAYER OF ITS OWN
/// (timesheet-rebuilds-on-every-scrub-move, found by I-22's scrub
/// measurement 09-27).
///
/// A sheet tab's host is rebuilt by its tab on every pan or zoom — the view
/// it is printed through — and, for the two that show the cut under the
/// playhead (F-90), on every crossing a scrub makes: at a far zoom, every
/// move. Rebuilt bare in the dock's layout scope, each laid the dock out
/// again and repainted it whole. This moves each sheet and names, at every
/// step, any boundary of the dock region waiting to repaint that is not a
/// [TickLayer]'s or inside one.
void main() {
  // Short cuts: a move of a scrub crosses into the next.
  const cuts = 12;
  const frames = 8;

  Project project() => Project(
    id: const ProjectId('sheet-layers'),
    name: 'Sheet layers',
    createdAt: DateTime.utc(2026, 9, 29),
    tracks: [
      Track(
        id: const TrackId('t'),
        name: 'Video',
        cuts: [
          for (var i = 0; i < cuts; i += 1)
            Cut(
              id: CutId('cut-$i'),
              name: 'cut-$i',
              duration: frames,
              canvasSize: const CanvasSize(width: 640, height: 360),
              layers: [
                Layer(id: LayerId('cut-$i-cel'), name: 'A', frames: const []),
              ],
            ),
        ],
      ),
    ],
  );

  /// The app with [tab]'s sheet brought forward in the dock beside the
  /// drawing, and the storyboard on the floor.
  Future<Finder> pumpSheet(WidgetTester tester, String tab) async {
    await tester.binding.setSurfaceSize(const Size(1600, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: HomePage(initialProject: project()),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey<String>('timeline-mode-storyboard-button')),
    );
    await tester.pumpAndSettle();
    final host = find.byType(switch (tab) {
      'conte' => ConteTabHost,
      'envelope' => CutEnvelopeTabHost,
      _ => TimesheetTabHost,
    });
    if (host.hitTestable().evaluate().isEmpty) {
      await tester.tap(
        find.byKey(ValueKey<String>('timeline-mode-$tab-button')),
      );
      await tester.pumpAndSettle();
    }
    expect(host.hitTestable(), findsOneWidget, reason: 'fixture: $tab shows');
    return host;
  }

  /// Every boundary of the dock region around [host] waiting to repaint in
  /// the scene that is not a tick layer's, or inside one. The REGION, not
  /// the sheet: a layout in the sheet marks the boundary above it, and that
  /// is the region's.
  List<String> strays(WidgetTester tester, Finder host) {
    final region = find
        .ancestor(of: host, matching: find.byType(StillRaster))
        .first;
    return [
      for (final stray in repaintStrays(
        tester.renderObject(region),
        allowed: {
          for (final layer in find
              .descendant(of: region, matching: find.byType(TickLayer))
              .evaluate())
            layer.renderObject!,
        },
      ))
        nameOfBoundary(stray),
    ];
  }

  /// [steps] steps of [gesture], [by] each, and what each one repaints of
  /// the dock around [host] outside its tick layers — [afterEach] told of
  /// every step once it has landed.
  Future<List<String>> movesOf(
    WidgetTester tester,
    Finder host,
    TestGesture gesture,
    Offset by, {
    int steps = 12,
    void Function()? afterEach,
  }) async {
    final moves = <String>[];
    for (var move = 1; move <= steps; move += 1) {
      await gesture.moveBy(by);
      // The move's frame, run to its layout and stopped before the paint.
      await tester.pump(const Duration(milliseconds: 16), EnginePhase.layout);
      final now = strays(tester, host);
      if (now.isNotEmpty) {
        moves.add('move $move:\n${now.join('\n')}');
      }
      await tester.pump();
      afterEach?.call();
    }
    await gesture.up();
    await tester.pumpAndSettle();
    return moves;
  }

  for (final tab in const ['timesheet', 'conte', 'envelope']) {
    testWidgets('a pan of the $tab repaints its tick layers and nothing else '
        'of the dock', (tester) async {
      final host = await pumpSheet(tester, tab);
      final panel = find.descendant(
        of: host,
        matching: find.byType(SheetCanvasPanel),
      );
      CanvasViewport? view() {
        final sheet = tester.widget<SheetCanvasPanel>(panel.first);
        return sheet.viewportController?.value ?? sheet.viewport;
      }

      final before = view();
      final gesture = await tester.startGesture(
        tester.getCenter(panel.first),
        kind: PointerDeviceKind.mouse,
      );
      await tester.pump();

      // A short pan: over twelve of these part-frames the conte's teardown
      // tripped flushPaint's `layer != null` — a boundary disposed while
      // still waiting to repaint (measured: twelve steps trip it, three do
      // not). The app's frames never stop before their paint.
      final moves = await movesOf(
        tester,
        host,
        gesture,
        const Offset(0, -9),
        steps: 4,
      );
      expect(view(), isNot(before), reason: 'fixture: the $tab panned');
      expect(moves, isEmpty, reason: moves.join('\n\n'));
    });
  }

  for (final tab in const ['timesheet', 'envelope']) {
    testWidgets('a scrub across cuts turns the $tab over on its tick layers '
        'and nothing else of the dock', (tester) async {
      final host = await pumpSheet(tester, tab);
      final ruler = find.byKey(const ValueKey<String>('storyboard-ruler'));
      final area = tester.getRect(ruler.first);
      // Over the middle of the ruler only: a scrub that reaches the edge
      // pans the storyboard.
      final step = area.width * 0.55 / 12;
      final session = switch (tester.widget(host)) {
        final TimesheetTabHost sheet => sheet.session,
        final CutEnvelopeTabHost envelope => envelope.session,
        final other => throw StateError('not a sheet: $other'),
      };
      final crossed = <CutId?>{};
      final gesture = await tester.startGesture(
        Offset(area.left + 4, area.center.dy),
      );
      await tester.pump();

      final moves = await movesOf(
        tester,
        host,
        gesture,
        Offset(step, 0),
        afterEach: () =>
            crossed.add(session.cutUnderPlayhead.listenable.value),
      );
      expect(
        crossed.length,
        greaterThan(5),
        reason: 'fixture: the scrub crossed cut after cut',
      );
      expect(moves, isEmpty, reason: moves.join('\n\n'));
    });
  }
}
