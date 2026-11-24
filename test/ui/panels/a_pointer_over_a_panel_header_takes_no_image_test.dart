import 'dart:typed_data';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/ui/home_page.dart';
import 'package:anicel/src/ui/widgets/press_face.dart';
import 'package:anicel/src/ui/widgets/static_raster.dart';
import 'package:anicel/src/ui/widgets/still_raster.dart';

/// Card a-hover-in-a-capsule-or-a-dock-takes-the-regions-image-again
/// (2026-11-24), on the real workspace: a panel's header lays a sheet on its
/// ground (`EditorPanelHeader`), so a pointer going onto each of its controls
/// leaves the dock drawn from its image — what each lights is seen where it
/// stands — and the sheet cuts the dock's image no wider than the controls.
const _capture = ValueKey<String>('header-capture');
const _header = ValueKey<String>('editor-panel-header');
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

  Future<TestGesture> pumpPage(WidgetTester tester) async {
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

  /// The controls of every header on screen, by the dock holding them —
  /// every face that lights, whatever button it is (an icon button, a rail
  /// glyph).
  Map<RenderStillRaster, List<PressFace>> headerFaces(WidgetTester tester) {
    final faces = <RenderStillRaster, List<PressFace>>{};
    for (final element in find
        .descendant(
          of: find.byKey(_header),
          matching: find.byWidgetPredicate((_) => true),
        )
        .evaluate()) {
      final face = element.renderObject;
      if (face is! PressFace || !face.attached) {
        continue;
      }
      final region = regionOf(face);
      if (region == null || !region.debugLabel.startsWith('dock:')) {
        continue;
      }
      final inIt = faces[region] ??= [];
      if (!inIt.contains(face)) {
        inIt.add(face);
      }
    }
    return faces;
  }

  testWidgets('🎯a pointer going onto each control of a panel header leaves '
      'its dock drawn from its image, and takes none again', (tester) async {
    final mouse = await pumpPage(tester);
    final faces = headerFaces(tester);
    expect(faces, isNotEmpty, reason: 'the brush library has a header');

    var hovered = 0;
    for (final MapEntry(key: region, value: inIt) in faces.entries) {
      final label = region.debugLabel;
      expect(region.debugDrawnFrom, isNotNull, reason: '$label, at rest');
      // Onto the panel first, by its header's bare ground left of its
      // controls: what coming onto a panel takes is its own (its scrollbar,
      // the band on its tabs — card a-hover-in-a-capsule-or-a-dock-takes-
      // the-regions-image-again, 2026-11-24 16:xx), and this reads what
      // the header's controls take.
      final header = tester.renderObject<RenderBox>(find.byKey(_header));
      await mouse.moveTo(
        header.localToGlobal(Offset(8, header.size.height / 2)),
      );
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
      await mouse.moveTo(
        header.localToGlobal(Offset(8, header.size.height / 2)),
      );
      await frames(tester, 30);
      expect(region.debugCaptureCount, before, reason: label);
    }
    expect(hovered, greaterThanOrEqualTo(2), reason: 'controls were hovered');
  });

  testWidgets('the sheet cuts the dock\'s image no wider than the controls '
      'over it', (tester) async {
    await pumpPage(tester);
    final ratio = tester.view.devicePixelRatio;
    for (final region in headerFaces(tester).keys) {
      final size = region.size * ratio;
      final whole = size.width.ceil() * size.height.ceil() * 4;
      // ⚠️A picture painted after the header in the dock's own picture
      // reaches the whole dock, touches the sheet and holds a part of the
      // image the dock's size above it (`_Strata._lowest`) — twice the dock.
      expect(
        region.rasterBytes,
        lessThan(whole * 1.2),
        reason: '${region.debugLabel}: ${region.debugLiveTicks}',
      );
    }
  });

  testWidgets('every control of a panel header lights where it stands', (
    tester,
  ) async {
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

    final rest = await shot();
    var lit = 0;
    for (final face in headerFaces(tester).values.expand((faces) => faces)) {
      final box = face.localToGlobal(Offset.zero) & face.size;
      await mouse.moveTo(box.center);
      await frames(tester, 2);
      if (!face.debugState.hovered) {
        continue;
      }
      lit += 1;
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
    expect(lit, greaterThanOrEqualTo(2), reason: 'controls were hovered');
  });
}
