import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/ui/widgets/static_raster.dart';
import 'package:anicel/src/ui/widgets/still_raster.dart';

import '../../helpers/look_test_binding.dart';

/// 🚨A TEXTURE UNDER A TICK THAT IS ALWAYS LIVE LEAVES ITS REGION ITS IMAGE
/// (card the-grid-screen-keeps-the-dock-from-baking, 11-09): a dock showing
/// a frame grid's screen went live for as long as it showed one, and was
/// drawn whole under every dab of a stroke that changed none of it.
void main() {
  LookTestBinding.ensureInitialized();

  setUpAll(StaticRaster.ensureFrameClock);

  setUp(() {
    StillRaster.debugCachePaysOverride = true;
    StaticRaster.debugCapturePaysOverride = false;
  });

  tearDown(() {
    StillRaster.debugCachePaysOverride = null;
    StaticRaster.debugCapturePaysOverride = null;
  });

  RenderStillRaster region(WidgetTester tester) =>
      tester.renderObject<RenderStillRaster>(find.byType(StillRaster));

  Future<void> standStill(WidgetTester tester) async {
    for (var i = 0; i < StillRaster.maxStillFrames * 4; i += 1) {
      tester.binding.scheduleFrame();
      await tester.pump();
    }
  }

  Widget aRegion(ValueNotifier<int> added, {required bool alwaysLive}) =>
      Directionality(
        textDirection: TextDirection.ltr,
        child: Center(
          child: SizedBox(
            width: 200,
            height: 100,
            child: StillRaster(
              debugLabel: 'test',
              child: Stack(
                fit: StackFit.expand,
                children: [
                  const RepaintBoundary(
                    child: ColoredBox(color: Color(0xFF1E88E5)),
                  ),
                  _Textured(added, alwaysLive: alwaysLive),
                ],
              ),
            ),
          ),
        ),
      );

  testWidgets('a region holding one is drawn from its image', (tester) async {
    final added = ValueNotifier<int>(0);
    addTearDown(added.dispose);
    await tester.pumpWidget(aRegion(added, alwaysLive: true));
    await standStill(tester);

    expect(region(tester).debugDrawnFromImage, isTrue);
    expect(region(tester).standDown, StillStandDown.none);
  });

  testWidgets('the texture is in every scene its image is drawn in', (
    tester,
  ) async {
    final added = ValueNotifier<int>(0);
    addTearDown(added.dispose);
    await tester.pumpWidget(aRegion(added, alwaysLive: true));
    await standStill(tester);
    expect(region(tester).debugDrawnFromImage, isTrue, reason: '⛔premise');
    final taken = region(tester).debugCaptureCount;
    final before = added.value;

    for (var i = 0; i < 5; i += 1) {
      tester.binding.scheduleFrame();
      await tester.pump();
    }

    expect(added.value - before, 5);
    expect(region(tester).debugCaptureCount, taken, reason: 'not retaken');
  });

  testWidgets('under any other tick it still stands the region down', (
    tester,
  ) async {
    final added = ValueNotifier<int>(0);
    addTearDown(added.dispose);
    await tester.pumpWidget(aRegion(added, alwaysLive: false));
    await standStill(tester);

    expect(region(tester).debugDrawnFromImage, isFalse);
  });
}

class _Textured extends LeafRenderObjectWidget {
  const _Textured(this.added, {required this.alwaysLive});

  final ValueNotifier<int> added;
  final bool alwaysLive;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderTextured(added, alwaysLive: alwaysLive);
}

class _RenderTextured extends RenderProxyBox {
  _RenderTextured(this.added, {required this.alwaysLive});

  final ValueNotifier<int> added;
  final bool alwaysLive;

  @override
  bool get alwaysNeedsCompositing => true;

  @override
  void paint(PaintingContext context, Offset offset) {
    context.addLayer(
      TickSceneLayer(alwaysLive: alwaysLive)
        ..offset = offset
        ..size = size
        ..append(_CountedTexture(Offset.zero & size, added)),
    );
  }
}

class _CountedTexture extends TextureLayer {
  _CountedTexture(Rect rect, this.added) : super(rect: rect, textureId: 7);

  final ValueNotifier<int> added;

  @override
  bool get alwaysNeedsAddToScene => true;

  @override
  void addToScene(ui.SceneBuilder builder) {
    added.value += 1;
    super.addToScene(builder);
  }
}
