import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/ui/debug/measurement_mode.dart';
import 'package:anicel/src/ui/debug/repaint_cause.dart';
import 'package:anicel/src/ui/editor_workspace.dart';
import 'package:anicel/src/ui/home_page.dart';
import 'package:anicel/src/ui/panels/editor_panel_tabs.dart';
import 'package:anicel/src/ui/widgets/static_raster.dart';

/// The rule this file exists to keep: **a docked panel is baked into one
/// image while it is not changing, and nobody has to remember to make
/// that happen.**
///
/// It is installed once, on the funnel every tab passes through, so a
/// panel added next month is light without its author doing anything.
/// What can silently undo it is a `RepaintBoundary` somewhere inside a
/// panel: an inner boundary can never be reached again once its layers
/// are detached, so [StaticRaster] notices one and paints through rather
/// than freeze the subtree. That failure is INVISIBLE — the panel looks
/// right and quietly costs its full price every frame.
///
/// 🚨 Two ways this file was blind, both found the hard way — by a user
/// turning on Show Repaints and reporting that three panels never
/// changed colour at all:
///
/// 1. **It only ever pumped the default layout.** Green meant "the
///    panels that ship open are free", not "the app's panels are free".
///    The storyboard, conte and cut-envelope panels were in NEITHER list.
/// 2. **It keyed surfaces by `debugLabel` in a `Map`.** Five command
///    groups share one label, so four of them lost the collision and
///    never entered the enforcement loop at all.
///
/// So: iterate [StaticRaster.census] as objects, and walk every tab the
/// app can build rather than the ones that happen to be on screen.
Iterable<RenderStaticRaster> _surfaces() =>
    StaticRaster.census.where((r) => r.attached);

Iterable<String> _labels() => _surfaces().map((r) => r.debugLabel);

Future<void> _pumpWorkspace(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(const Size(1600, 1000));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(const MaterialApp(home: HomePage()));
  await tester.pumpAndSettle();
}

/// Every entry here is an OUTER wrapper standing down for an inner one
/// that does the actual baking, except where noted. That is the design
/// working: a viewport is a repaint boundary, so a surface that scrolls
/// can only be baked from inside, and the outer wrapper then correctly
/// refuses rather than freeze it.
///
/// ⚠️ Before adding an entry, check for `Opacity` in the subtree.
/// `RenderOpacity.alwaysNeedsCompositing` is `child != null && _alpha > 0`
/// — **greater than zero, not less than 255** — so `Opacity(opacity: 1.0)`
/// is a full repaint boundary and therefore a bake killer, and you cannot
/// see that from the widget source. `AnimatedOpacity` and
/// `FadeTransition` are the same.
const _knownToPaintThrough = <String, String>{
  'panel:brushes': 'yields to body:Brushes inside EditorPanelBody',
  'edge-dock:tool-left': 'yields to tool-column inside the tool scroller',
  'panel:timeline':
      'partly addressed: the command bar bakes as five `command-group` '
      'zones inside. The grid below them is the most genuinely live '
      'surface in the app and is left alone deliberately — measured at '
      '1.7 ms for the whole panel.',
  'panel:storyboard':
      'same shape as panel:timeline — a TimelineCommandBar whose leading '
      'scroller is a viewport. The grid body below it is live and is '
      'exempted on purpose.',
  'panel:conte':
      'yields to conte-page inside. The shell boundary is '
      'brush_canvas_panel.dart:2641, which an earlier round placed there '
      'by bisection and must stay.',
  'panel:envelope': 'yields to envelope-page inside, same shell boundary',
  'panel:canvas-editor':
      'the canvas shell: boundaries throughout, and its live-stroke path '
      'must never be asked for a full-surface copy',
  'panel:media-viewer':
      'an InteractiveViewer around the media preview: the transform is '
      'the panel, so there is nothing static to bake.',
};

/// Tabs the default layout cannot reach by selecting a tab, because their
/// dock is not mounted (a closed rail group, a floating-only panel).
/// Listed so that coverage is a decision rather than an accident.
///
/// ⚠️ Every one of these lives in a rail group that ships CLOSED, so no
/// `EditorPanelTabs` hosts it and selecting a tab cannot reach it. The
/// user's own working layout has several of them open — so this is a gap
/// in the sweep, not in the app, and it is listed rather than silently
/// skipped. Teaching the sweep to open a rail group closes it.
const _unreachableInDefaultLayout = <String, String>{
  EditorWorkspace.toolsTabId: 'rail group ships closed',
  EditorWorkspace.brushSettingsTabId: 'rail group ships closed',
  EditorWorkspace.colorWheelTabId: 'rail group ships closed',
  EditorWorkspace.colorRgbTabId: 'rail group ships closed',
  EditorWorkspace.colorPaletteTabId: 'rail group ships closed',
  EditorWorkspace.onionSkinTabId: 'rail group ships closed',
  EditorWorkspace.mediaTabId: 'rail group ships closed',
  // The sub viewer ships closed on purpose (유저 확정 ⑥): a reference
  // panel earns its height only once there is a reference in it. It is
  // the SAME widget as the floor's viewer, which this sweep does reach,
  // so the bake being audited on one of them audits the code on both.
  EditorWorkspace.mediaViewerSubTabId: 'rail group ships closed',
};

/// Named surfaces that MUST be baking while their tab is active.
///
/// The allowlist above says "this outer wrapper yields to an inner one",
/// and nothing checks that the inner one exists. A typo in a
/// `debugLabel`, or a bake that quietly moved, would leave the allowlist
/// entry telling a story about a surface that is not there — and the
/// panel would pay full price with every test in this file green. That is
/// exactly how three panels went a whole round unbaked.
const _mustBakeWhenActive = <String, List<String>>{
  EditorWorkspace.conteTabId: <String>['conte-page'],
  EditorWorkspace.envelopeTabId: <String>['envelope-page'],
  // ⚠️ `media-viewer-page` is deliberately absent: with nothing imported
  // the panel takes its "no media" branch and the page is never built, so
  // asserting it here would fail on an empty project rather than on a
  // defect. It IS baked — see media_viewer_tab_host.dart — and a fixture
  // with a loaded document is what would pin it.
  EditorWorkspace.timesheetTabId: <String>[
    'timesheet-form',
    'timesheet-content',
  ],
  // The command bar has no wrapper of its own — it was removed when the
  // bar became zones, because an outer bake around inner ones is the
  // nesting that freezes. Each group bakes itself instead.
  EditorWorkspace.timelineTabId: <String>['command-group'],
};

void main() {
  testWidgets('every docked panel is wrapped, and the canvas is not', (
    tester,
  ) async {
    await _pumpWorkspace(tester);
    final labels = _labels().toSet();

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

  testWidgets('every command group is its own zone, and all of them count', (
    tester,
  ) async {
    // The label collision, stated as an assertion. A `Map` keyed by
    // `debugLabel` kept one of these and silently dropped four — so four
    // zones could stop baking and every test in this file would stay
    // green.
    await _pumpWorkspace(tester);
    final groups = _labels().where((l) => l == 'command-group').length;
    expect(
      groups,
      greaterThan(1),
      reason:
          'the command bar is baked per group so a change in one does not '
          're-bake the others; finding one means the census is being '
          'deduplicated somewhere it must not be',
    );
  });

  testWidgets('a pointer moving over the canvas does not re-bake a panel', (
    tester,
  ) async {
    // This is the measured bug in one assertion. Before the wrapper, a
    // mouse moving a few pixels over the canvas cost every open panel a
    // full re-raster: 24.0 of 27.6 ms/frame.
    await _pumpWorkspace(tester);
    final before = <RenderStaticRaster, int>{
      for (final raster in _surfaces()) raster: raster.captureCount,
    };
    expect(before, isNotEmpty);

    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: const Offset(800, 500));
    addTearDown(gesture.removePointer);
    for (var i = 0; i < 12; i += 1) {
      await gesture.moveTo(Offset(800 + i * 4, 500 + i * 3));
      await tester.pump();
    }

    for (final entry in before.entries) {
      expect(
        entry.key.captureCount,
        entry.value,
        reason:
            '${entry.key.debugLabel} re-baked while the pointer was somewhere '
            'else entirely — that is the whole cost this wrapper removes.\n'
            'Causes so far: ${entry.key.captureCauses}',
      );
    }
  });

  testWidgets('a bake caused by the pointer says so', (tester) async {
    MeasurementMode.frameStats.value = true;
    RepaintCause.install();
    addTearDown(() {
      MeasurementMode.reset();
      RepaintCause.reset();
    });

    await _pumpWorkspace(tester);
    final rasters = _surfaces().toList();
    expect(rasters, isNotEmpty);
    for (final raster in rasters) {
      raster.captureCauses.clear();
    }

    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: const Offset(800, 500));
    addTearDown(gesture.removePointer);
    for (var i = 0; i < 6; i += 1) {
      await gesture.moveTo(Offset(800 + i * 4, 500));
      await tester.pump();
    }

    // 🚨 What used to be here was vacuous twice over: `everyElement` over
    // a map that is always empty passes, and `'unknown'` was in the
    // allowed set, so it also passed when the channel could only ever say
    // `unknown` — which for a while was the only thing it could say.
    //
    // 1. The app still MARKS. A channel with nothing wired into it looks
    //    exactly like a channel reporting good news.
    expect(
      RepaintCause.debugMarkedCause,
      'pointer',
      reason:
          'the canvas stopped marking hover, so every future bake would be '
          'attributed to `unknown` and read as "nothing to see here"',
    );

    // 2. And no panel re-baked BECAUSE of it.
    for (final raster in rasters) {
      expect(
        raster.captureCauses.containsKey('pointer'),
        isFalse,
        reason:
            '${raster.debugLabel} re-baked on a pointer move — the panel is '
            'paying its full price again and looks identical while doing it.\n'
            'Causes: ${raster.captureCauses}',
      );
    }
  });

  testWidgets('🥇 every tab the app can open is audited, not just the open ones', (
    tester,
  ) async {
    // The blindness this file shipped with. `_tabFor` builds fifteen
    // panels; the default layout shows five of them. Everything the
    // enforcement below asserts was only ever asserted about those five.
    //
    // Tabs are activated through `EditorPanelTabs.onTabSelected` rather
    // than by tapping buttons, which side-steps four separate traps: the
    // button key is `tab.buttonKey ?? ValueKey('panel-tab-<id>')` and
    // four of the panels under investigation use the first form; a
    // prefix match also finds the overflow menu; the rail group buttons
    // are toggles that would CLOSE the groups that ship open; and an
    // offstage tab's `StaticRaster` is not in the tree at all, so
    // anything collected after the loop has already lost it.
    await _pumpWorkspace(tester);

    final byGroup = <String, List<String>>{};
    for (final host in tester.widgetList<EditorPanelTabs>(
      find.byType(EditorPanelTabs),
    )) {
      final group = host.groupId;
      if (group != null) {
        byGroup[group] = host.tabs.map((t) => t.id).toList();
      }
    }
    expect(byGroup, isNotEmpty, reason: 'no tab host had a group id');

    final visited = <String>{};
    final offenders = <String>[];
    final report = <String>[];

    for (final entry in byGroup.entries) {
      for (final tabId in entry.value) {
        // Re-find the host every time: selecting a tab rebuilds the tree.
        final host = tester
            .widgetList<EditorPanelTabs>(find.byType(EditorPanelTabs))
            .where((h) => h.groupId == entry.key)
            .firstOrNull;
        if (host == null) {
          continue;
        }
        host.onTabSelected(tabId);
        await tester.pumpAndSettle();
        visited.add(tabId);

        // Collect INSIDE the loop — the surfaces vanish when the tab does.
        final live = _surfaces().toList();
        final baked = live.where((r) => r.captureCount > 0).length;
        report.add('$tabId: ${live.length} surfaces, $baked baked');

        for (final label in _mustBakeWhenActive[tabId] ?? const <String>[]) {
          final named = live.where((r) => r.debugLabel == label).toList();
          expect(
            named,
            isNotEmpty,
            reason:
                'no surface called `$label` exists while `$tabId` is active, '
                'so whatever the allowlist says it yields to is not there',
          );
          for (final raster in named) {
            expect(
              raster.captureCount,
              greaterThan(0),
              reason:
                  '$label exists but has never baked while `$tabId` is '
                  'active.\nRefused because: ${raster.debugCaptureRefusal}\n'
                  'Nested boundary: ${raster.debugNestedBoundaryPath}',
            );
          }
        }

        for (final raster in live) {
          if (!raster.debugNestedBoundary) {
            continue;
          }
          if (!_knownToPaintThrough.containsKey(raster.debugLabel)) {
            offenders.add(
              '$tabId → ${raster.debugLabel}\n'
              '      blocked by: ${raster.debugNestedBoundaryPath}',
            );
          }
        }
      }
    }

    debugPrint('StaticRaster TAB SWEEP:\n${report.join('\n')}');

    expect(
      offenders,
      isEmpty,
      reason:
          'these panels pay their full raster price on every frame the app '
          'produces, and look identical while doing it:\n'
          '${offenders.join('\n')}\n'
          'Remove the boundary, move the bake inside it (a viewport is '
          'itself a boundary — see EditorPanelBody), or add it to '
          '_knownToPaintThrough WITH a reason.',
    );

    final missed = EditorWorkspace.debugAllTabIds
        .where((id) => !visited.contains(id))
        .where((id) => !_unreachableInDefaultLayout.containsKey(id))
        .toList();
    expect(
      missed,
      isEmpty,
      reason:
          'these tabs exist in `_tabFor` and this sweep never opened them, '
          'so nothing above says anything about them: $missed\n'
          'Either make the sweep reach them or list them in '
          '_unreachableInDefaultLayout with a reason.',
    );
  });

  testWidgets('a wrapped panel that is on screen really does bake', (
    tester,
  ) async {
    // The other way a panel can quietly stop being free, and the one the
    // allowlist above cannot see.
    //
    // A bake is only a COPY when the surface's device rectangle is whole
    // pixels, so [RenderStaticRaster] aligns its capture — and refuses
    // outright when it cannot (a rotation or a non-uniform scale above
    // it). That refusal is correct and it is also invisible: the panel
    // looks right and pays its full raster price.
    await _pumpWorkspace(tester);
    for (final raster in _surfaces()) {
      if (raster.debugNestedBoundary ||
          !raster.enabled ||
          raster.debugStoodDown ||
          raster.size.isEmpty) {
        continue;
      }
      expect(
        raster.captureCount,
        greaterThan(0),
        reason:
            '${raster.debugLabel} is wrapped, enabled, on screen and '
            'unblocked, and has still never baked.\n'
            'Refused because: ${raster.debugCaptureRefusal}',
      );
    }
  });

  testWidgets('REPORT: which panels actually bake, and which pay full price', (
    tester,
  ) async {
    await _pumpWorkspace(tester);
    final baked = <String>[];
    final throughNested = <String>[];
    for (final raster in _surfaces()) {
      if (raster.debugNestedBoundary) {
        throughNested.add(
          '${raster.debugLabel}\n      ${raster.debugNestedBoundaryPath}',
        );
      } else if (raster.captureCount > 0) {
        final size = raster.size;
        baked.add(
          '${raster.debugLabel} '
          '(${size.width.round()}x${size.height.round()}) '
          'x${raster.captureCount} ${raster.captureCauses}',
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
