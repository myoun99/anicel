import 'dart:typed_data';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/ui/home_page.dart';
import 'package:anicel/src/ui/theme/app_theme.dart';
import 'package:anicel/src/ui/timeline/timeline_grid_frame.dart';
import 'package:anicel/src/ui/widgets/press_face.dart';
import 'package:anicel/src/ui/widgets/static_raster.dart';
import 'package:anicel/src/ui/widgets/still_raster.dart';

/// Card a-hover-in-a-capsule-or-a-dock-takes-the-regions-image-again
/// (2026-11-24), on the real workspace: the timeline grid's header row — the
/// rail's legend and the ruler's corner — lays a sheet under its controls,
/// so a pointer going onto each leaves the dock drawn from its image, and
/// what each lights is seen where it stands.
const _capture = ValueKey<String>('header-row-capture');
const _away = Offset(800, 300);

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

  Future<TestGesture> pumpPage(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1600, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      RepaintBoundary(
        key: _capture,
        // The app's own theme: a plate's hover is its hover colour, which
        // the default light theme makes too faint to tell on a dark plate.
        child: MaterialApp(theme: buildAppTheme(), home: const HomePage()),
      ),
    );
    await tester.pumpAndSettle();
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: _away);
    addTearDown(mouse.removePointer);
    await frames(tester, 60);
    return mouse;
  }

  RenderStillRaster? regionOf(RenderObject box) {
    for (var above = box.parent; above != null; above = above.parent) {
      if (above is RenderStillRaster) {
        return above;
      }
    }
    return null;
  }

  /// Every live face on the header row, by the region holding it.
  Map<RenderStillRaster, List<PressFace>> headerFaces(WidgetTester tester) {
    final faces = <RenderStillRaster, List<PressFace>>{};
    for (final element in find
        .descendant(
          of: find.byType(TimelineGridHeaderRow),
          matching: find.byWidgetPredicate((_) => true),
        )
        .evaluate()) {
      final face = element.renderObject;
      if (face is! PressFace ||
          !face.attached ||
          face.size.isEmpty ||
          face.onPress == null) {
        continue;
      }
      final region = regionOf(face);
      if (region == null) {
        continue;
      }
      final inIt = faces[region] ??= [];
      if (!inIt.contains(face)) {
        inIt.add(face);
      }
    }
    return faces;
  }

  testWidgets('🎯a pointer going onto each control of the timeline grid\'s '
      'header leaves its dock drawn from its image, and takes none again', (
    tester,
  ) async {
    final mouse = await pumpPage(tester);
    final faces = headerFaces(tester);
    expect(faces, isNotEmpty, reason: 'the timeline has a header row');
    var hovered = 0;
    for (final MapEntry(key: region, value: inIt) in faces.entries) {
      final label = region.debugLabel;
      await mouse.moveTo(_away);
      await frames(tester, 30);
      final before = region.debugCaptureCount;
      for (final face in inIt) {
        await mouse.moveTo(face.localToGlobal(face.size.center(Offset.zero)));
        await frames(tester, 2);
        if (face.debugState.hovered) {
          hovered += 1;
        }
        expect(
          region.debugDrawnFrom,
          isNotNull,
          reason:
              '$label, on the control at '
              '${face.localToGlobal(Offset.zero)}',
        );
      }
      await mouse.moveTo(_away);
      await frames(tester, 30);
      expect(region.debugCaptureCount, before, reason: label);
    }
    expect(hovered, greaterThanOrEqualTo(3), reason: 'controls were hovered');
  });

  testWidgets('the legend\'s heading and the ruler\'s corner light across '
      'their faces', (tester) async {
    final mouse = await pumpPage(tester);

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
      const width = 1600;
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

    await mouse.moveTo(_away);
    await frames(tester, 3);
    final rest = await shot();
    // The two that light across themselves: the legend's heading (2227 of
    // 2574 pixels moved, on master) and the ruler's corner (223 of 288).
    // The columns' headings light none of theirs past 2 levels, on master
    // and on a sheet alike (measured 11-24), so they tell nothing here.
    for (final key in [
      'legend-heading',
      'timeline-time-display-toggle-button',
    ]) {
      final face = tester.renderObject<RenderBox>(
        find.byKey(ValueKey<String>(key)).first,
      );
      final box = face.localToGlobal(Offset.zero) & face.size;
      await mouse.moveTo(box.center);
      await frames(tester, 2);
      final hovered = await shot();
      final inside = box.deflate(2);
      expect(
        changedIn(inside, rest, hovered),
        greaterThan(inside.width * inside.height / 3),
        reason: 'the hover of the control at $box is seen',
      );
      await mouse.moveTo(_away);
      await frames(tester, 2);
    }
  });
}
