import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/brush_settings.dart';
import 'package:anicel/src/models/brush_tip_mask.dart';
import 'package:anicel/src/ui/brush/brush_tip_preview.dart';
import 'package:anicel/src/ui/widgets/static_raster.dart';

/// 🔬H40 (2026-09-24): a sampled tip's preview is a grid of up to 256
/// translucent rects, and replaying them every frame was most of what the
/// brush library cost under Impeller (its tip icons alone ≈2.6 ms an idle
/// frame, the real Windows app). So a sampled preview is a DENSE surface:
/// it bakes even where [StaticRaster.capturePays] says bakes do not pay.
void main() {
  tearDown(() => StaticRaster.debugCapturePaysOverride = null);

  final mask = BrushTipMask(
    id: 'test-mask',
    size: 4,
    alpha: Uint8List.fromList(List<int>.filled(16, 200)),
  );

  Future<RenderStaticRaster> pump(WidgetTester tester, Widget preview) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Center(child: SizedBox(width: 24, height: 24, child: preview)),
      ),
    );
    return tester.renderObject<RenderStaticRaster>(find.byType(StaticRaster));
  }

  testWidgets('a sampled tip preview bakes where captures do not pay', (
    tester,
  ) async {
    StaticRaster.debugCapturePaysOverride = false;
    final raster = await pump(
      tester,
      BrushTipPreview(settings: BrushSettings(tipMask: mask)),
    );
    expect(raster.captureCount, 1);
    expect(raster.standDown, StandDownReason.none);
  });

  testWidgets('a mask preview — the picker grid\'s cell — bakes there too', (
    tester,
  ) async {
    StaticRaster.debugCapturePaysOverride = false;
    final raster = await pump(
      tester,
      BrushTipMaskPreview(alpha: mask.alpha, side: mask.size),
    );
    expect(raster.captureCount, 1);
  });

  testWidgets('a parametric tip — two ovals — paints through there', (
    tester,
  ) async {
    StaticRaster.debugCapturePaysOverride = false;
    final raster = await pump(
      tester,
      BrushTipPreview(settings: BrushSettings()),
    );
    expect(raster.captureCount, 0);
    expect(raster.standDown, StandDownReason.renderer);
  });
}
