
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/ui/home_page.dart';
import 'package:anicel/src/ui/panels/editor_panel_tabs.dart';
import 'package:anicel/src/ui/widgets/grip_band.dart';
import 'package:anicel/src/ui/widgets/live_sheet.dart';
import 'package:anicel/src/ui/widgets/static_raster.dart';
import 'package:anicel/src/ui/widgets/still_raster.dart';

/// Card a-hover-in-a-capsule-or-a-dock-takes-the-regions-image-again
/// (2026-11-24), on the real workspace: a pointer coming onto a panel lights
/// the band on its tabs ([LiftingGripBand.nearby], 유저 R3 #9 「패널에 호버하면
/// 기본색」), and lays it on the sheet over the tab strip — the dock keeps its
/// image, and the band is seen.
const _capture = ValueKey<String>('panel-capture');
const _away = Offset(800, 500);

void main() {
  setUp(() {
    StillRaster.debugCachePaysOverride = true;
    StaticRaster.debugCapturePaysOverride = false;
  });

  tearDown(() {
    StillRaster.debugCachePaysOverride = null;
    StaticRaster.debugCapturePaysOverride = null;
  });

  Future<void> frames(WidgetTester tester, int count) async {
    for (var i = 0; i < count; i += 1) {
      tester.binding.scheduleFrame();
      await tester.pump(const Duration(milliseconds: 16));
    }
  }

  Future<Uint8List> shot(WidgetTester tester) async {
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(_capture),
    );
    late ByteData data;
    await tester.runAsync(() async {
      final image = await boundary.toImage();
      data = (await image.toByteData())!;
      image.dispose();
    });
    return data.buffer.asUint8List();
  }

  RenderStillRaster? regionOf(RenderObject box) {
    for (var above = box.parent; above != null; above = above.parent) {
      if (above is RenderStillRaster) {
        return above;
      }
    }
    return null;
  }

  /// A point of [panel] where the one thing a pointer meets that hears it
  /// is the panel's own region — no button, no row, no scrollbar.
  Offset? bareOf(WidgetTester tester, RenderBox panel) {
    final origin = panel.localToGlobal(Offset.zero);
    for (var y = 4.0; y < panel.size.height - 4; y += 8) {
      for (var x = 4.0; x < panel.size.width - 4; x += 8) {
        final at = origin + Offset(x, y);
        // In the panel: what holds it (the window, the dock) hears where
        // it is wherever it is.
        bool inPanel(RenderObject box) {
          for (RenderObject? above = box; above != null; above = above.parent) {
            if (identical(above, panel)) {
              return true;
            }
          }
          return false;
        }

        // Whatever hears a pointer come — a region, and a face that hears
        // it itself (`PressFace`).
        final hearers = [
          for (final entry in tester.hitTestOnBinding(at).path)
            if (entry.target case final RenderObject box
                when box is MouseTrackerAnnotation &&
                    ((box as MouseTrackerAnnotation).onEnter != null ||
                        box is RenderMouseRegion &&
                            box.onHover != null) &&
                    inPanel(box))
              box,
        ];
        // The panel's box is its own region (its build's first widget).
        if (hearers.length == 1 && identical(hearers.single, panel)) {
          return at;
        }
      }
    }
    return null;
  }

  /// Each panel of the workspace with a band on its tabs, the dock that
  /// holds it, its first band and a bare spot of it, the pointer away.
  Future<
    (TestGesture, List<(RenderStillRaster, Finder, Offset)>)
  > comeOntoPanels(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1600, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      const RepaintBoundary(
        key: _capture,
        child: MaterialApp(home: HomePage()),
      ),
    );
    await tester.pumpAndSettle();
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: _away);
    addTearDown(mouse.removePointer);
    await frames(tester, 60);
    final panels = <(RenderStillRaster, Finder, Offset)>[];
    for (final element in find.byType(EditorPanelTabs).evaluate()) {
      final panel = element.renderObject! as RenderBox;
      final region = regionOf(panel);
      if (region == null || !region.debugLabel.startsWith('dock:')) {
        continue;
      }
      final bands = find.descendant(
        of: find.byWidget(element.widget),
        matching: find.byType(LiftingGripBand<EditorPanelTabDragData>),
      );
      if (bands.evaluate().isEmpty) {
        continue;
      }
      // Where no face of it is: nothing a pointer lights there but the
      // panel itself.
      final bare = bareOf(tester, panel);
      expect(bare, isNotNull, reason: '${region.debugLabel} has a bare spot');
      panels.add((region, bands.first, bare!));
    }
    expect(panels.length, greaterThanOrEqualTo(2), reason: 'panels');
    return (mouse, panels);
  }

  testWidgets('🎯a pointer coming onto each panel leaves its dock drawn from '
      'its image, and takes none again', (tester) async {
    final (mouse, panels) = await comeOntoPanels(tester);
    for (final (region, bands, bare) in panels) {
      final label = region.debugLabel;
      final before = region.debugCaptureCount;
      await mouse.moveTo(bare);
      await frames(tester, 3);
      expect(region.debugDrawnFromImage, isTrue, reason: '$label, on it');
      expect(
        LiveSheet.overOf(tester.element(bands))!.debugLaid,
        greaterThanOrEqualTo(1),
        reason: '$label: its bands lie on the sheet',
      );
      await mouse.moveTo(_away);
      await frames(tester, 30);
      expect(region.debugCaptureCount, before, reason: label);
    }
  });

  testWidgets('the band a pointer coming onto a panel lights is seen', (
    tester,
  ) async {
    final (mouse, panels) = await comeOntoPanels(tester);
    for (final (region, bands, bare) in panels) {
      final band = tester.renderObject<RenderBox>(bands);
      final bandBox = band.localToGlobal(Offset.zero) & band.size;
      final rest = await shot(tester);
      await mouse.moveTo(bare);
      await frames(tester, 3);
      final hovered = await shot(tester);
      var changed = 0;
      for (var y = bandBox.top.ceil(); y < bandBox.bottom.floor(); y += 1) {
        for (var x = bandBox.left.ceil(); x < bandBox.right.floor(); x += 1) {
          final i = (y * 1600 + x) * 4;
          if ((rest[i] - hovered[i]).abs() > 2 ||
              (rest[i + 1] - hovered[i + 1]).abs() > 2 ||
              (rest[i + 2] - hovered[i + 2]).abs() > 2) {
            changed += 1;
          }
        }
      }
      expect(changed, greaterThan(0), reason: region.debugLabel);
      await mouse.moveTo(_away);
      await frames(tester, 30);
    }
  });
}
