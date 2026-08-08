import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/ui/home_page.dart';
import 'package:anicel/src/ui/widgets/static_raster.dart';

/// The rule this file exists to keep: **a docked panel is baked into one
/// image while it is not changing, and nobody has to remember to make
/// that happen.**
///
/// It is installed once, on the funnel every tab passes through
/// (`EditorPanelTabs._buildTabContent`), so a panel added next month is
/// light without its author doing anything. What can silently undo it is
/// a `RepaintBoundary` somewhere inside a panel: an inner boundary can
/// never be reached again once its layers are detached, so [StaticRaster]
/// notices one and paints through rather than freeze the subtree. That
/// failure is INVISIBLE — the panel looks right and quietly costs its
/// full price every frame.
///
/// So the reporting test below is not decoration. It is the only thing
/// that would tell you a panel stopped being free.
Future<void> _pumpWorkspace(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(const Size(1600, 1000));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(const MaterialApp(home: HomePage()));
  await tester.pumpAndSettle();
}

Iterable<RenderStaticRaster> _rasters(WidgetTester tester) => tester
    .renderObjectList<RenderStaticRaster>(find.byType(StaticRaster))
    .where((r) => r.attached);

Map<String, RenderStaticRaster> _byLabel(WidgetTester tester) => <String, RenderStaticRaster>{
  for (final raster in _rasters(tester)) raster.debugLabel: raster,
};

void main() {
  testWidgets('every docked panel is wrapped, and the canvas is not', (
    tester,
  ) async {
    await _pumpWorkspace(tester);
    final labels = _byLabel(tester).keys.toSet();

    expect(
      labels,
      isNotEmpty,
      reason: 'the funnel must reach the panels that ship open',
    );
    expect(
      labels.every((l) => l.startsWith('panel:')),
      isTrue,
      reason: 'every wrapper is named for the tab it wraps',
    );
    expect(
      labels.contains('panel:canvas'),
      isFalse,
      reason:
          'the canvas opts out: it owns its own boundaries, and its '
          'live-stroke path must never be asked for a full-surface copy',
    );
  });

  testWidgets('a pointer moving over the canvas does not re-bake a panel', (
    tester,
  ) async {
    // This is the measured bug in one assertion. Before the wrapper, a
    // mouse moving a few pixels over the canvas cost every open panel a
    // full re-raster: 24.0 of 27.6 ms/frame.
    await _pumpWorkspace(tester);
    final before = <String, int>{
      for (final entry in _byLabel(tester).entries)
        entry.key: entry.value.captureCount,
    };
    expect(before, isNotEmpty);

    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: const Offset(800, 500));
    addTearDown(gesture.removePointer);
    for (var i = 0; i < 12; i += 1) {
      await gesture.moveTo(Offset(800 + i * 4, 500 + i * 3));
      await tester.pump();
    }

    for (final entry in _byLabel(tester).entries) {
      expect(
        entry.value.captureCount,
        before[entry.key],
        reason:
            '${entry.key} re-baked while the pointer was somewhere else '
            'entirely — that is the whole cost this wrapper removes',
      );
    }
  });

  testWidgets('REPORT: which panels actually bake, and which pay full price', (
    tester,
  ) async {
    // Not an assertion about a number — a standing readout. A panel in
    // the "paints through" list is one where someone added a
    // RepaintBoundary inside, and it is costing its full raster price on
    // every frame the app produces. Read this when the ladder stops
    // improving.
    await _pumpWorkspace(tester);
    final baked = <String>[];
    final throughNested = <String>[];
    for (final entry in _byLabel(tester).entries) {
      if (entry.value.debugNestedBoundary) {
        throughNested.add(entry.key);
      } else if (entry.value.captureCount > 0) {
        baked.add(entry.key);
      }
    }
    baked.sort();
    throughNested.sort();
    debugPrint('StaticRaster BAKED: $baked');
    debugPrint('StaticRaster PAINTS THROUGH (nested boundary): $throughNested');

    expect(
      baked.isNotEmpty || throughNested.isNotEmpty,
      isTrue,
      reason: 'the workspace must have mounted at least one panel',
    );
  });
}
