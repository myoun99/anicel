import 'dart:typed_data';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/ui/panels/editor_panel_tabs.dart';
import 'package:anicel/src/ui/widgets/static_raster.dart';
import 'package:anicel/src/ui/widgets/still_raster.dart';

/// Card a-hover-in-a-capsule-or-a-dock-takes-the-regions-image-again
/// (2026-11-24): a dock's tab behind another is a clear plate, its hover
/// laid on the strip's sheet — a pointer going onto it leaves the dock drawn
/// from its image, and what it lights is seen where it stands.
const _capture = ValueKey<String>('tabs-capture');
const _tabs = ['one', 'two', 'three'];

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

  Finder tab(String id) => find.byKey(ValueKey<String>('panel-tab-$id'));

  final body = find.text('one-content');

  Future<({TestGesture mouse, List<String> chosen})> pumpDock(
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(600, 500));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final chosen = <String>[];
    await tester.pumpWidget(
      RepaintBoundary(
        key: _capture,
        child: MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 400,
                height: 400,
                child: StillRaster(
                  debugLabel: 'dock:tabs',
                  child: EditorPanelTabs(
                    tabs: [
                      for (final id in _tabs)
                        EditorPanelTab(
                          id: id,
                          label: id,
                          icon: Icons.palette,
                          builder: (context) => Text('$id-content'),
                        ),
                    ],
                    activeTabId: 'one',
                    onTabSelected: chosen.add,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: const Offset(5, 5));
    addTearDown(mouse.removePointer);
    await frames(tester, 60);
    // Onto the panel first, by its body: what coming onto a panel takes is
    // its own (the band on its tabs).
    await mouse.moveTo(tester.getCenter(body));
    await frames(tester, 60);
    return (mouse: mouse, chosen: chosen);
  }

  testWidgets('🎯a pointer going onto a tab behind another leaves its dock '
      'drawn from its image, and takes none again', (tester) async {
    final (:mouse, chosen: _) = await pumpDock(tester);
    final region = tester.renderObject<RenderStillRaster>(
      find.byType(StillRaster),
    );
    final before = region.debugCaptureCount;
    for (final id in ['two', 'three']) {
      await mouse.moveTo(tester.getCenter(tab(id)));
      await frames(tester, 3);
      expect(region.debugDrawnFrom, isNotNull, reason: 'on the tab $id');
      await mouse.moveTo(tester.getCenter(body));
      await frames(tester, 30);
    }
    expect(region.debugCaptureCount, before);
  });

  testWidgets('every tab lights where it stands, and a press on one '
      'behind chooses it', (tester) async {
    final (:mouse, :chosen) = await pumpDock(tester);

    Future<Uint8List> shot() async {
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

    int changedIn(Rect box, Uint8List a, Uint8List b) {
      const width = 600;
      var changed = 0;
      for (var y = box.top.ceil(); y < box.bottom.floor(); y += 1) {
        for (var x = box.left.ceil(); x < box.right.floor(); x += 1) {
          final i = (y * width + x) * 4;
          if ((a[i] - b[i]).abs() > 2 ||
              (a[i + 1] - b[i + 1]).abs() > 2 ||
              (a[i + 2] - b[i + 2]).abs() > 2) {
            changed += 1;
          }
        }
      }
      return changed;
    }

    final rest = await shot();
    for (final id in _tabs) {
      final box = tester.getRect(tab(id));
      await mouse.moveTo(box.center);
      await frames(tester, 3);
      final hovered = await shot();
      // The tab's own padding, left of its glyph: what the hover lights.
      final lit = Rect.fromLTRB(
        box.left + 1,
        box.top + 8,
        box.left + 7,
        box.bottom - 2,
      );
      expect(
        changedIn(lit, rest, hovered),
        greaterThan(lit.width * lit.height / 3),
        reason: 'the hover of the tab $id at $box is seen',
      );
      await mouse.moveTo(tester.getCenter(body));
      await frames(tester, 3);
    }

    await tester.tap(tab('two'));
    await tester.pump();
    expect(chosen, ['two']);
  });
}
