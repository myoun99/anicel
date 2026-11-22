import 'dart:typed_data';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/ui/editor_workspace.dart';
import 'package:anicel/src/ui/home_page.dart';
import 'package:anicel/src/ui/widgets/app_icon_button.dart';
import 'package:anicel/src/ui/widgets/live_sheet.dart';
import 'package:anicel/src/ui/widgets/press_face.dart';
import 'package:anicel/src/ui/widgets/rail_glyph_button.dart';
import 'package:anicel/src/ui/widgets/static_raster.dart';
import 'package:anicel/src/ui/widgets/still_raster.dart';

import '../../helpers/rail_group_button.dart';

/// Card the-left-tool-strip-rebakes-on-every-hover (11-22), on the real
/// workspace: the strips no dock holds — the two tool strips and the top
/// strip — keep their images under a pointer passing along them, and what
/// their buttons light is seen where each button stands.
///
/// 🚨Pinned on the real page for the half a unit test cannot see: a look
/// laid on the sheet under a strip is drawn under ALL the strip paints
/// (`LiveSheet`), so a button standing on a ground painted inside the strip
/// would light nothing — and nothing about the capture counts says so.
const _capture = ValueKey<String>('strip-capture');
const _away = Offset(800, 500);

const _left = 'strip:${EditorWorkspace.toolLeftGroupId}';
const _right = 'strip:${EditorWorkspace.toolRightGroupId}';
const _top = 'top-strip';

void main() {
  setUp(() {
    StillRaster.debugCachePaysOverride = true;
    // Where the still images run, the bakes paint through (Impeller).
    StaticRaster.debugCapturePaysOverride = false;
  });

  tearDown(() {
    StillRaster.debugCachePaysOverride = null;
    StaticRaster.debugCapturePaysOverride = null;
  });

  Future<void> frames(WidgetTester tester, int count) async {
    for (var i = 0; i < count; i += 1) {
      tester.binding.scheduleFrame();
      await tester.pump();
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
    // One region is taken a frame.
    await frames(tester, 30);
    return mouse;
  }

  Map<String, RenderStillRaster> strips() => {
    for (final region in StillRaster.census.where((r) => r.attached))
      if (const [_left, _right, _top].contains(region.debugLabel))
        region.debugLabel: region,
  };

  testWidgets('🎯a pointer passing along a strip leaves it drawn from its '
      'image on every frame, and takes none again', (tester) async {
    final mouse = await pumpPage(tester);
    final regions = strips();
    expect(regions.keys, containsAll(const [_left, _right, _top]));

    // ⚠️A project's tab aside: a `Material` and an `InkWell`, whose ✕
    // lights in place on the tab's own fill (`_ProjectTab`) — the strip is
    // taken again for it, as it was (card
    // an-ink-well-repaints-its-material-for-a-hover-it-lays-no-ink-for).
    final tabs = [
      for (final tab in find
          .byWidgetPredicate(
            (widget) =>
                widget is InkWell &&
                widget.key is ValueKey<String> &&
                (widget.key! as ValueKey<String>).value.startsWith(
                  'project-tab-',
                ),
          )
          .evaluate())
        tester.getRect(find.byWidget(tab.widget)).inflate(4),
    ];
    expect(tabs, isNotEmpty, reason: 'the open project has a tab');

    final taken = <String, int>{};
    for (final MapEntry(key: label, value: region) in regions.entries) {
      expect(region.debugDrawnFromImage, isTrue, reason: '$label, at rest');
      final box = region.localToGlobal(Offset.zero) & region.size;
      final down = box.height > box.width;
      final length = down ? box.height : box.width;
      final before = region.debugCaptureCount;
      for (var along = 2.0; along < length - 2; along += 6) {
        final at = down
            ? Offset(box.center.dx, box.top + along)
            : Offset(box.left + along, box.center.dy);
        if (tabs.any((tab) => tab.contains(at))) {
          continue;
        }
        await mouse.moveTo(at);
        await tester.pump();
        expect(
          region.debugDrawnFromImage,
          isTrue,
          reason: '$label, the pointer ${along.round()} along it',
        );
      }
      await mouse.moveTo(_away);
      await frames(tester, 30);
      taken[label] = region.debugCaptureCount - before;
    }
    expect(taken[_left], 0, reason: 'the tools and the panel buttons');
    expect(taken[_top], 0);
    // The colour pair stands on a tick of its own: cut out as it first
    // moves, and taken back once it has stood still — the tick's law
    // (`TickSceneLayer`), not the hover's.
    expect(taken[_right], lessThanOrEqualTo(2));
  });

  testWidgets('every button on a strip lights where it stands', (tester) async {
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

    /// How many pixels of [box] differ between [a] and [b].
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

    bool onAStrip(RenderObject face) {
      for (var above = face.parent; above != null; above = above.parent) {
        if (above is RenderStillRaster) {
          return const [_left, _right, _top].contains(above.debugLabel);
        }
      }
      return false;
    }

    final faces = <RenderBox>[
      ...tester.renderObjectList<RenderRailGlyphFace>(
        find.byType(RailGlyphButton, skipOffstage: true),
      ),
      ...tester.renderObjectList<RenderIconButtonPressFace>(
        find.byType(IconButtonPressFace, skipOffstage: true),
      ),
    ].where(onAStrip).toList();
    expect(faces.length, greaterThan(12), reason: 'the strips hold buttons');

    // ⚠️A look laid on the sheet keeps none of an opacity its box is
    // painted under (`LiveSheet`): a face under one stands aside
    // (`LiveSheet.inPlace`).
    for (final face in faces) {
      for (
        var above = face.parent;
        above is! RenderStillRaster;
        above = above!.parent
      ) {
        expect(
          above,
          isNot(anyOf(isA<RenderOpacity>(), isA<RenderAnimatedOpacity>())),
          reason: 'over the face at ${face.localToGlobal(Offset.zero)}',
        );
      }
    }

    final rest = await shot();
    var lit = 0;
    for (final face in faces) {
      final box = face.localToGlobal(Offset.zero) & face.size;
      await mouse.moveTo(box.center);
      await frames(tester, 2);
      final state = (face as PressFace).debugState;
      final ink = switch (face) {
        RenderRailGlyphFace() => face.debugLayerInk,
        RenderIconButtonPressFace() => face.debugLayerInk,
        _ => null,
      };
      if (!state.hovered || ink == null) {
        // Covered there, or dead: a dead face shows no hover.
        continue;
      }
      lit += 1;
      final hovered = await shot();
      expect(
        changedIn(box.deflate(2), rest, hovered),
        greaterThan(box.deflate(2).size.width * box.deflate(2).size.height / 3),
        reason: 'the hover of the face at $box is seen',
      );
      await mouse.moveTo(_away);
      await frames(tester, 2);
    }
    expect(lit, greaterThan(12), reason: 'buttons were hovered');
  });

  testWidgets('a button offered a thing in flight paints itself, under the '
      'outline it is offered with', (tester) async {
    await pumpPage(tester);
    final band = find.byKey(
      const ValueKey<String>(
        'rail-group-band-${EditorWorkspace.leftGroupId}',
      ),
    );
    final offered = railGroupButton(
      EditorWorkspace.railGroupId(right: true, slot: 6),
    );
    expect(offered, findsNothing, reason: 'an empty slot shows for a carry');
    expect(LiveSheet.overOf(tester.element(band)), isNotNull);

    final lift = await tester.startGesture(tester.getCenter(band));
    await tester.pump(const Duration(milliseconds: 20));
    await lift.moveBy(const Offset(30, 0));
    await tester.pump();
    // The outline lies over the button: a look on the sheet over the
    // strip would lie over the outline.
    expect(LiveSheet.underOf(tester.element(offered)), isNull);
    expect(LiveSheet.overOf(tester.element(offered)), isNull);
    // What is carried is offered nothing, and is on its strip's sheet yet.
    expect(LiveSheet.overOf(tester.element(band)), isNotNull);
    await lift.up();
    await tester.pumpAndSettle();
  });
}
