import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:anicel/src/models/canvas_viewport.dart';
import 'package:anicel/src/ui/brush/brush_canvas_panel.dart';
import 'package:anicel/src/ui/brush/canvas_visible_rect.dart';
import 'package:anicel/src/ui/editor_workspace.dart';
import 'package:anicel/src/ui/effective_device_pixel_ratio.dart';
import 'package:anicel/src/ui/home_page.dart';
import 'package:anicel/src/ui/ui_scale.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/scaled_test_binding.dart';

/// F-67 (유저 2026-09-10): 「선을 그리기 시작하거나 … 일부 정해진 픽셀이
/// 반픽셀 움직였다가 돌아오는」, at zoom >= 100%. The hands-on of 09-11 read
/// the canvas chain ON the grid (device (40, 40), ratio 1.0) while it
/// happened, which retired the layout-offset explanation. This measures the
/// half a test CAN reach: the canvas content boundary's OWN raster, in the
/// real shell, through pen-down, mid-stroke and pen-up at 110% — where
/// nearest sampling would turn any sub-pixel phase change into moved
/// columns. It holds still, byte for byte, in the tile row the stroke is
/// in and in a row it is not. Whatever flips on the device flips BELOW
/// this raster — between the engine's cached and live rendering of the
/// same display list, which is why the drawing pictures refuse the cache
/// (`bypass_raster_cache_wiring_test.dart`, R12).
void main() {
  ScaledTestBinding.ensureInitialized();
  tearDown(() => AppUiScale.value.value = AppUiScale.defaultScale);

  Widget shell() => ValueListenableBuilder<double>(
    valueListenable: AppUiScale.value,
    builder: (context, scale, _) => MaterialApp(
      builder: (context, child) => EffectiveDevicePixelRatioScope(
        uiScale: scale,
        child: child ?? const SizedBox.shrink(),
      ),
      home: const HomePage(),
    ),
  );

  RenderRepaintBoundary boundary(WidgetTester tester) {
    final boxes = [
      for (final element in find
          .byKey(const ValueKey<String>('canvas-content-boundary'))
          .evaluate())
        element.renderObject! as RenderRepaintBoundary,
    ]..sort(
        (a, b) => (b.size.width * b.size.height).compareTo(
          a.size.width * a.size.height,
        ),
      );
    return boxes.first;
  }

  Future<({Uint8List bytes, int width})> capture(WidgetTester tester) async {
    final box = boundary(tester);
    final result = await tester.runAsync(() async {
      final image = await box.toImage();
      final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      final out = (
        bytes: Uint8List.fromList(data!.buffer.asUint8List()),
        width: image.width,
      );
      image.dispose();
      return out;
    });
    return result!;
  }

  Future<void> letDecodesLand(WidgetTester tester) async {
    for (var i = 0; i < 12; i += 1) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 16)),
      );
      await tester.pump();
    }
  }

  testWidgets('at 110% the settled picture holds still, byte for byte, '
      'through pen-down, mid-stroke and pen-up', (tester) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(1600, 1000);
    addTearDown(tester.view.reset);

    await tester.pumpWidget(shell());
    await tester.pumpAndSettle();
    // A new project has no cel under the playhead: make one, or every
    // press is refused and the capture holds nothing but paper.
    final session = tester
        .widget<EditorWorkspace>(find.byType(EditorWorkspace))
        .session;
    session.selectFrameIndex(0);
    session.createDrawingAtCurrentFrame();
    await tester.pumpAndSettle();

    final panel = tester.widget<BrushCanvasPanel>(
      find.byType(BrushCanvasPanel).first,
    );
    const zoom = 1.1;
    const pan = Offset(37, 23);
    panel.viewportController!.value = CanvasViewport(
      zoom: zoom,
      panX: pan.dx,
      panY: pan.dy,
    );
    await tester.pumpAndSettle();

    final box = boundary(tester);
    final origin = box.localToGlobal(Offset.zero);
    // Everything is aimed inside the WINDOW the artist sees — the panels
    // float over the canvas floor (a press under the brush panel or the
    // timeline lands on the panel, and the stroke never starts) — and in
    // its right half, clear of the panels that float at the top left.
    final visible = canvasVisibleRect(box.size, panel.floorCover);
    Offset local(double fx, double fy) => Offset(
      visible.left + visible.width * fx,
      visible.top + visible.height * fy,
    );
    Offset screen(Offset localPoint) => origin + localPoint;

    Future<void> stroke(double fy, double fromFx, double toFx) async {
      final pen = await tester.startGesture(
        screen(local(fromFx, fy)),
        kind: PointerDeviceKind.stylus,
      );
      await tester.pump();
      for (var i = 1; i <= 8; i += 1) {
        await pen.moveTo(screen(local(fromFx + (toFx - fromFx) * i / 8, fy)));
        await tester.pump();
      }
      await pen.up();
      await tester.pump();
      await tester.pumpAndSettle();
    }

    // Two references, a quarter of the window apart; the live stroke goes
    // between them, close enough to share tiles with the lower one.
    const upperRow = 0.30;
    const lowerRow = 0.55;
    const liveRow = 0.62;
    await stroke(upperRow, 0.55, 0.9);
    await stroke(lowerRow, 0.55, 0.9);
    await letDecodesLand(tester);
    final settled = await capture(tester);
    final settled2 = await capture(tester);
    expect(
      settled.bytes,
      equals(settled2.bytes),
      reason: 'the settled capture is not stable — everything below is noise',
    );

    // The live stroke, held between the captures.
    final pen = await tester.startGesture(
      screen(local(0.6, liveRow)),
      kind: PointerDeviceKind.stylus,
    );
    await tester.pump();
    final penDown = await capture(tester);
    await pen.moveTo(screen(local(0.7, liveRow)));
    await tester.pump();
    final midStroke = await capture(tester);
    await pen.moveTo(screen(local(0.8, liveRow)));
    await tester.pump();
    await pen.up();
    await tester.pump();
    final penUp = await capture(tester);
    await tester.pumpAndSettle();
    await letDecodesLand(tester);
    final after = await capture(tester);

    // A band 40 px tall around a reference row, over the stroke's span
    // plus a margin — in the boundary's own pixels, which the capture is.
    ({int x0, int y0, int x1, int y1}) bandAt(double fy) {
      final p0 = local(0.5, fy) - const Offset(0, 20);
      final p1 = local(0.95, fy) + const Offset(0, 20);
      return (
        x0: p0.dx.round(),
        y0: p0.dy.round(),
        x1: p1.dx.round(),
        y1: p1.dy.round(),
      );
    }

    final width = settled.width;
    bool ink(Uint8List px, int x, int y) => px[(y * width + x) * 4] < 128;

    ({int ink, int diff, String bestShift}) judge(
      Uint8List probe,
      ({int x0, int y0, int x1, int y1}) b,
    ) {
      var inkSettled = 0;
      var diff = 0;
      for (var y = b.y0; y < b.y1; y += 1) {
        for (var x = b.x0; x < b.x1; x += 1) {
          if (ink(settled.bytes, x, y)) inkSettled += 1;
          if (ink(settled.bytes, x, y) != ink(probe, x, y)) diff += 1;
        }
      }
      var bestAgree = -1;
      var best = '';
      for (var dy = -2; dy <= 2; dy += 1) {
        for (var dx = -2; dx <= 2; dx += 1) {
          var agree = 0;
          for (var y = b.y0; y < b.y1; y += 1) {
            for (var x = b.x0; x < b.x1; x += 1) {
              if (ink(settled.bytes, x, y) == ink(probe, x + dx, y + dy)) {
                agree += 1;
              }
            }
          }
          if (agree > bestAgree) {
            bestAgree = agree;
            best = '($dx,$dy)';
          }
        }
      }
      return (ink: inkSettled, diff: diff, bestShift: best);
    }

    for (final (row, band) in <(String, ({int x0, int y0, int x1, int y1}))>[
      ('upper reference', bandAt(upperRow)),
      ('lower reference', bandAt(lowerRow)),
    ]) {
      expect(
        judge(settled.bytes, band).ink,
        greaterThan(1000),
        reason: '$row: the reference stroke did not land — bad premise',
      );
      for (final (moment, probe) in <(String, Uint8List)>[
        ('pen-down', penDown.bytes),
        ('mid-stroke', midStroke.bytes),
        ('pen-up', penUp.bytes),
        ('after', after.bytes),
      ]) {
        final verdict = judge(probe, band);
        expect(
          verdict.diff,
          0,
          reason:
              '$row at $moment: ${verdict.diff} band pixels changed under '
              'the user (best whole-pixel shift ${verdict.bestShift})',
        );
      }
    }

    session.playbackRig.prerenderScheduler.cancel();
  });
}
