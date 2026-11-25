import 'dart:typed_data';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/ui/home_page.dart';
import 'package:anicel/src/ui/widgets/app_icon_button.dart';
import 'package:anicel/src/ui/widgets/press_face.dart';
import 'package:anicel/src/ui/widgets/rail_glyph_button.dart';
import 'package:anicel/src/ui/widgets/static_raster.dart';
import 'package:anicel/src/ui/widgets/still_raster.dart';

/// Card a-hover-in-a-capsule-or-a-dock-takes-the-regions-image-again
/// (2026-11-23), on the real workspace: a canvas capsule's ground is
/// painted around its region and a sheet lies on it (`CanvasCapsule`), so a
/// pointer going onto each of its faces leaves it drawn from its image —
/// and what each face lights is seen where it stands, on that sheet.
const _capture = ValueKey<String>('capsule-capture');
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

  /// Every face standing in a canvas capsule, by its region.
  ///
  /// ⚠️But a plate ([RenderRailPlateFace] — the brush pill's blend mode):
  /// its hover is the colour of its own opaque inside (유저
  /// a-live-dock-frame-costs-a-whole-draw-Q12, 11-08), which a sheet under
  /// it cannot show — card
  /// a-hover-in-a-capsule-or-a-dock-takes-the-regions-image-again-Q1.
  Map<RenderStillRaster, List<RenderBox>> capsuleFaces(WidgetTester tester) {
    final faces = <RenderStillRaster, List<RenderBox>>{};
    for (final element in find.byWidgetPredicate((_) => true).evaluate()) {
      final box = element.renderObject;
      if (box is! RenderBox || box is! PressFace || !box.attached) {
        continue;
      }
      if (box is RenderRailPlateFace) {
        continue;
      }
      final region = regionOf(box);
      if (region == null || !region.debugLabel.startsWith('capsule:')) {
        continue;
      }
      final list = faces[region] ??= [];
      if (!list.contains(box)) {
        list.add(box);
      }
    }
    return faces;
  }

  testWidgets('🎯a pointer going onto each face of a capsule leaves it drawn '
      'from its image, and takes none again', (tester) async {
    final mouse = await pumpPage(tester);
    final faces = capsuleFaces(tester);
    expect(
      faces.keys.map((region) => region.debugLabel),
      containsAll(const [
        'capsule:canvas-view-pill',
        'capsule:canvas-brush-pill',
      ]),
    );

    var hovered = 0;
    for (final MapEntry(key: region, value: inIt) in faces.entries) {
      final label = region.debugLabel;
      expect(region.debugDrawnFrom, isNotNull, reason: '$label, at rest');
      // Its ground is around it: no part of its image is one colour.
      final key = ValueKey<String>(label.substring('capsule:'.length));
      final grounds = tester.renderObjectList<RenderDecoratedBox>(
        find.byKey(key),
      );
      expect(grounds, isNotEmpty, reason: '$label has its ground');
      for (final ground in grounds) {
        expect(regionOf(ground), isNot(same(region)), reason: label);
      }
      for (final face in inIt) {
        final before = region.debugCaptureCount;
        await mouse.moveTo(face.localToGlobal(face.size.center(Offset.zero)));
        await frames(tester, 2);
        if ((face as PressFace).debugState.hovered) {
          hovered += 1;
        }
        expect(
          region.debugDrawnFrom,
          isNotNull,
          reason: '${region.debugLabel}, on ${face.runtimeType} at '
              '${face.localToGlobal(Offset.zero)}',
        );
        expect(region.debugCaptureCount, before);
        await mouse.moveTo(_away);
        await frames(tester, 2);
      }
    }
    expect(hovered, greaterThan(15), reason: 'faces were hovered');
  });

  testWidgets('every face of a capsule lights where it stands', (tester) async {
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
    for (final face in capsuleFaces(tester).values.expand((faces) => faces)) {
      final box = face.localToGlobal(Offset.zero) & face.size;
      await mouse.moveTo(box.center);
      await frames(tester, 2);
      final ink = switch (face) {
        RenderRailGlyphFace() => face.debugLayerInk,
        RenderIconButtonPressFace() => face.debugLayerInk,
        _ => null,
      };
      if (!(face as PressFace).debugState.hovered || ink == null) {
        // Covered there, or dead: a dead face shows no hover.
        continue;
      }
      lit += 1;
      final hovered = await shot();
      final inside = box.deflate(2);
      expect(
        changedIn(inside, rest, hovered),
        greaterThan(inside.width * inside.height / 3),
        reason: 'the hover of ${face.runtimeType} at $box is seen',
      );
      await mouse.moveTo(_away);
      await frames(tester, 2);
    }
    expect(lit, greaterThan(15), reason: 'faces were hovered');
  });
}
