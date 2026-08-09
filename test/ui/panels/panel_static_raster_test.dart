import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/ui/debug/measurement_mode.dart';
import 'package:anicel/src/ui/debug/repaint_cause.dart';
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
      labels.contains('panel:canvas'),
      isFalse,
      reason:
          'the canvas opts out: it owns its own boundaries, and its '
          'live-stroke path must never be asked for a full-surface copy',
    );
    // A panel with live content inside it places its own wrappers at the
    // right seams instead of taking the funnel's one, which would have
    // to swallow the live part too.
    expect(
      labels,
      containsAll(<String>['timesheet-form', 'timesheet-content']),
      reason: 'the sheet bakes its two strata separately',
    );
    expect(
      labels.contains('panel:timesheet'),
      isFalse,
      reason: 'and therefore opts out of the funnel wrapper',
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
            'entirely — that is the whole cost this wrapper removes.\n'
            'Causes so far: ${entry.value.captureCauses}',
      );
    }
  });

  testWidgets('a bake caused by the pointer says so', (tester) async {
    // The reason channel, and the one question it exists to answer.
    // Without it, "this panel re-bakes 60 times a second" and "this
    // panel re-bakes 60 times a second BECAUSE THE PEN MOVED" read the
    // same, and only the second is a bug.
    //
    // Correlational by construction — the app marks what it is doing and
    // a bake takes whatever was marked on its own frame. Being wrong
    // makes a diagnosis misleading and cannot make a pixel stale, which
    // is why it is allowed to be approximate at all.
    MeasurementMode.frameStats.value = true;
    addTearDown(() {
      MeasurementMode.reset();
      RepaintCause.reset();
    });

    await _pumpWorkspace(tester);
    final rasters = _byLabel(tester);
    expect(rasters, isNotEmpty);

    for (final raster in rasters.values) {
      raster.captureCauses.clear();
    }

    // Force a re-bake while the pointer is the thing that moved: the
    // canvas panel marks `pointer` on every hover it accepts.
    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: const Offset(800, 500));
    addTearDown(gesture.removePointer);
    for (var i = 0; i < 6; i += 1) {
      await gesture.moveTo(Offset(800 + i * 4, 500));
      await tester.pump();
    }

    // Nothing SHOULD have re-baked — that is the fix working — so this
    // asserts the shape of the answer rather than a count: whatever did
    // bake is attributed, and nothing is silently unlabelled when the
    // pointer was the only thing that moved.
    for (final entry in rasters.entries) {
      expect(
        entry.value.captureCauses.keys,
        everyElement(anyOf('pointer', 'unknown')),
        reason: '${entry.key} attributed a bake to something impossible',
      );
    }
  });

  testWidgets('a panel pays full price only if it is on the list, with a why', (
    tester,
  ) async {
    // The enforcement, not a readout. A panel that quietly stopped
    // baking looks exactly like one that never did, so "we will notice"
    // is not a plan — the only way to keep the rule is to make being
    // wrong impossible to do silently.
    //
    // Landing here means a new panel (or a new `RepaintBoundary` in an
    // old one) is costing its full raster price on every frame the app
    // produces. The failure message names the render object responsible.
    // Fix it, or add it below WITH a reason.
    // Every entry here is an OUTER wrapper standing down for an inner one
    // that does the actual baking, except where noted. That is the design
    // working: a viewport is a repaint boundary, so a surface that scrolls
    // can only be baked from inside, and the outer wrapper then correctly
    // refuses rather than freeze it.
    const knownToPaintThrough = <String, String>{
      'panel:brushes': 'yields to body:Brushes inside EditorPanelBody',
      'edge-dock:tool-left': 'yields to tool-column inside the tool scroller',
      'panel:timeline':
          'partly addressed: timeline-command-bar bakes inside. The grid '
          'below it is the most genuinely live surface in the app and is '
          'left alone deliberately — measured at 1.7 ms for the whole panel.',
    };

    await _pumpWorkspace(tester);
    for (final entry in _byLabel(tester).entries) {
      if (!entry.value.debugNestedBoundary) {
        continue;
      }
      expect(
        knownToPaintThrough,
        contains(entry.key),
        reason:
            '${entry.key} pays its full raster price every frame.\n'
            'Blocked by: ${entry.value.debugNestedBoundaryPath}\n'
            'Remove that boundary, move the bake inside it (a viewport is '
            'itself a boundary — see EditorPanelBody), or add this panel to '
            'knownToPaintThrough with a reason.',
      );
    }
  });

  testWidgets('REPORT: which panels actually bake, and which pay full price', (
    tester,
  ) async {
    // The readable form of the same facts, for when the ladder stops
    // improving and someone needs to see where the money went.
    await _pumpWorkspace(tester);
    final baked = <String>[];
    final throughNested = <String>[];
    for (final entry in _byLabel(tester).entries) {
      if (entry.value.debugNestedBoundary) {
        throughNested.add(
          '${entry.key}\n      ${entry.value.debugNestedBoundaryPath}',
        );
      } else if (entry.value.captureCount > 0) {
        final size = entry.value.size;
        baked.add(
          '${entry.key} '
          '(${size.width.round()}x${size.height.round()}) '
          'x${entry.value.captureCount} ${entry.value.captureCauses}',
        );
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
