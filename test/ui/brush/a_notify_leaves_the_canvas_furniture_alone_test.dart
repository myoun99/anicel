import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/ui/brush/brush_canvas_panel.dart';
import 'package:anicel/src/ui/brush/brush_edit_cache_invalidation_sink.dart';
import 'package:anicel/src/ui/brush/canvas_floor_insets.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/editor_workspace.dart';
import 'package:anicel/src/ui/home_page.dart';

import '../../helpers/frame_census.dart';

/// I-57 (10-13): a notify that changed nothing in a canvas panel painted
/// its whole shell again — the pill with its swatches and readouts, the
/// panbars — on the floor and on a docked panel alike. The shell measured
/// the room in three LayoutBuilders that ran again whenever the panel was
/// built, and a docked panel's host laid its layer out with every rebuild.
/// Every cut a run crosses is such a notify, for the shell.
void main() {
  EditorSessionManager sessionOf(WidgetTester tester) =>
      tester.widget<EditorWorkspace>(find.byType(EditorWorkspace)).session;

  Future<void> pumpApp(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1500, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(home: HomePage(initialProject: createDefaultProject())),
    );
    await tester.pumpAndSettle();
  }

  /// The pills and panbars of every canvas panel on screen — after
  /// checking there is one on the floor and one docked.
  List<RenderObject> furniture(WidgetTester tester) {
    const pill = ValueKey<String>('canvas-view-pill');
    for (final panel in ['canvas', 'timesheet']) {
      expect(
        find.descendant(
          of: find.byKey(ValueKey<String>('panel-content-$panel')),
          matching: find.byKey(pill),
        ),
        findsOneWidget,
        reason: 'premise: the $panel panel shows its pill',
      );
    }
    return [
      for (final key in [
        'canvas-view-pill',
        'canvas-panbar-vertical',
        'canvas-panbar-horizontal',
      ])
        ...tester.renderObjectList(find.byKey(ValueKey<String>(key))),
    ];
  }

  void expectNonePainted(
    List<RenderObject> pieces,
    ({List<Type> rebuilt, List<RenderObject> painted}) frame,
  ) {
    expect(
      frame.rebuilt,
      contains(BrushCanvasPanel),
      reason: 'premise: the panels were built again',
    );
    for (final piece in pieces) {
      expect(
        frame.painted.any((object) => identical(object, piece)) ||
            paintedInside(frame.painted, piece),
        isFalse,
        reason: '$piece was painted again',
      );
    }
  }

  testWidgets('a notify that changes nothing paints none of the canvas '
      'furniture, on the floor or docked', (tester) async {
    await pumpApp(tester);
    final pieces = furniture(tester);

    final frame = await frameCensus(tester, sessionOf(tester).notifyChanged);

    expectNonePainted(pieces, frame);
  });

  /// A canvas panel on a floor of 900×420 under [cover] — mounted afresh
  /// for every new [mount].
  Widget floor(EdgeInsets cover, {required String mount}) => MaterialApp(
    home: Scaffold(
      body: Center(
        child: SizedBox(
          width: 900,
          height: 420,
          child: CanvasFloorInsets(
            key: ValueKey<String>(mount),
            insets: cover,
            child: BrushCanvasPanel(
              coordinator: null,
              availableFrameKeys: const [],
              cacheInvalidationSink: BrushEditCacheInvalidationSink(),
              canvasSize: const CanvasSize(width: 300, height: 300),
              floorCover: cover,
              contentOverride: (context, viewport) => const SizedBox.expand(),
            ),
          ),
        ),
      ),
    ),
  );

  testWidgets('and a cover that moves over a floor of the same size moves '
      'the panbars where a floor laid under it puts them', (tester) async {
    const near = EdgeInsets.only(top: 30, bottom: 40);
    const far = EdgeInsets.only(top: 90, bottom: 110);
    await tester.binding.setSurfaceSize(const Size(1000, 600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    List<Rect> panbars() => [
      for (final key in ['canvas-panbar-vertical', 'canvas-panbar-horizontal'])
        tester.getRect(find.byKey(ValueKey<String>(key))),
    ];
    await tester.pumpWidget(floor(far, mount: 'laid under it'));
    await tester.pumpAndSettle();
    final laidUnder = panbars();
    await tester.pumpWidget(floor(near, mount: 'moved'));
    await tester.pumpAndSettle();
    final before = panbars();
    for (var bar = 0; bar < 2; bar += 1) {
      expect(before[bar], isNot(laidUnder[bar]), reason: 'premise');
    }

    await tester.pumpWidget(floor(far, mount: 'moved'));
    await tester.pumpAndSettle();

    expect(panbars(), laidUnder);
  });

  testWidgets('nor does crossing to another cut', (tester) async {
    await pumpApp(tester);
    final session = sessionOf(tester);
    session.cutVerbs.createCut();
    await tester.pumpAndSettle();
    final cuts = session.repository.requireProject().tracks.first.cuts;
    session.selectCut(cuts.first.id);
    await tester.pumpAndSettle();
    final pieces = furniture(tester);

    final frame = await frameCensus(
      tester,
      () => session.selectCut(cuts.last.id),
    );

    expectNonePainted(pieces, frame);
  });
}
