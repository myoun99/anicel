import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/ui/home_page.dart';
import 'package:anicel/src/ui/panels/editor_dock_host.dart';
import 'package:anicel/src/ui/widgets/field_slider.dart';

/// 🚨Every dock region, the canvas panel and every value bar is its own
/// SEMANTICS boundary (2026-09-26).
///
/// A layout anywhere re-walks the nearest semantics boundary's whole share
/// of the tree — and a boundary is exactly where that walk stops. With none
/// at these three, a brush pick re-walked about 2300 nodes: the root's share
/// (the docks, the canvas and the strips together) and the settings panel's
/// scroll view (about a thousand, for five changed numbers). With them,
/// about 1160 — measured on the real app with the accessibility tree on,
/// which is how this machine's release build runs.
///
/// ⚠️What is pinned is the boundary itself; the walk it saves is not
/// observable through any public hook, so the numbers above live on the
/// board (H40, semantics-tree-cost) with the probe that measured them.
void main() {
  Future<void> pumpHome(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1600, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const MaterialApp(home: HomePage()));
    await tester.pumpAndSettle();
  }

  /// The first semantics annotation under [of] — the boundary a region
  /// puts round its content.
  Semantics firstSemanticsUnder(WidgetTester tester, Finder of) =>
      tester.widget<Semantics>(
        find.descendant(of: of, matching: find.byType(Semantics)).first,
      );

  testWidgets('every dock region wraps its panels in a boundary', (
    tester,
  ) async {
    await pumpHome(tester);
    final docks = find.byType(EditorDockHost);
    expect(docks, findsWidgets, reason: 'premise: the layout has docks');
    for (final dock in docks.evaluate()) {
      final semantics = firstSemanticsUnder(
        tester,
        find.byElementPredicate((element) => identical(element, dock)),
      );
      expect(
        semantics.container,
        isTrue,
        reason: '${(dock.widget as EditorDockHost).dockId} is a boundary',
      );
    }
  });

  testWidgets('the canvas panel is a boundary of its own', (tester) async {
    await pumpHome(tester);
    final semantics = firstSemanticsUnder(
      tester,
      find.byKey(const ValueKey<String>('brush-canvas-panel')).first,
    );
    expect(semantics.container, isTrue);
  });

  // The bar's node is said by the box its grip is (2026-10-28), not by a
  // [Semantics] widget — so it is read off the tree: the node the track's
  // box belongs to is a slider's, and it is the BAR's alone. Merged into a
  // node above, the node found would be that region's, a box bigger than
  // the bar.
  testWidgets('every value bar is a boundary of its own', (tester) async {
    final semantics = tester.ensureSemantics();
    await pumpHome(tester);
    final bars = find.byType(FieldSlider);
    expect(bars, findsWidgets, reason: "premise: the brush's bars stand");
    for (final bar in bars.evaluate()) {
      final track = find.descendant(
        of: find.byElementPredicate((element) => identical(element, bar)),
        matching: find.byType(FieldSliderTrack),
      );
      final node = tester.getSemantics(track);
      expect(node.getSemanticsData().flagsCollection.isSlider, isTrue);
      expect(node.rect, Offset.zero & tester.getSize(track));
    }
    semantics.dispose();
  });
}
