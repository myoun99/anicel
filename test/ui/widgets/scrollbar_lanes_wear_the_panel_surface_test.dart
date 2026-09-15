import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/ui/theme/app_theme.dart';
import 'package:anicel/src/ui/timeline/layer_rail_window.dart';
import 'package:anicel/src/ui/timeline/timeline_horizontal_scrollbar_rail.dart';
import 'package:anicel/src/ui/timeline/timeline_vertical_scrollbar_rail.dart';
import 'package:anicel/src/ui/widgets/content_scrollbar.dart';

/// 🚨F-73 ② (유저 2026-09-11): 「공용 스크롤바의 배경색을 패널색이랑
/// 맞추고싶음. 타임라인패널의 스크롤바도 배경이 검정색이니까. 그냥 투명하게
/// 할수는없나? 그리고 캔버스패널은 지금 배경색이 존재하는데, 그거는 그대로
/// 상관없」.
///
/// Read off the pixels: each lane laid over a panel-coloured ground and
/// sampled at its outer edge, at the end the thumb is not — the ground has to
/// come through. (The canvas panel keeps its own, as the user said.)
void main() {
  /// A colour no theme token uses, so a fill of any of them reads as wrong.
  const panel = 0xFF3A5F2B;

  Future<int> argbAt(
    WidgetTester tester, {
    required Widget lane,
    required Size size,
    required Offset at,
  }) async {
    await tester.binding.setSurfaceSize(const Size(400, 400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: Align(
          alignment: Alignment.topLeft,
          child: RepaintBoundary(
            key: const ValueKey<String>('lane-capture'),
            child: ColoredBox(
              color: const Color(panel),
              child: SizedBox.fromSize(size: size, child: lane),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(const ValueKey<String>('lane-capture')),
    );
    final image = boundary.toImageSync();
    late ByteData data;
    await tester.runAsync(() async {
      data = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
    });
    final width = image.width;
    image.dispose();
    final i = (at.dy.toInt() * width + at.dx.toInt()) * 4;
    return (data.getUint8(i + 3) << 24) |
        (data.getUint8(i) << 16) |
        (data.getUint8(i + 1) << 8) |
        data.getUint8(i + 2);
  }

  testWidgets('the shared content lane is the panel it sits in', (
    tester,
  ) async {
    final argb = await argbAt(
      tester,
      lane: ContentScrollbar(
        builder: (context, controller) => ListView(
          controller: controller,
          children: const [SizedBox(height: 1200)],
        ),
      ),
      size: const Size(200, 300),
      // The lane's outer edge, at the bottom: the thumb starts at the top.
      at: const Offset(199, 298),
    );
    expect(argb, panel, reason: 'the lane painted a fill of its own');
  });

  testWidgets('the timeline rails are the panel they sit in — both axes', (
    tester,
  ) async {
    final vertical = ScrollController();
    addTearDown(vertical.dispose);
    expect(
      await argbAt(
        tester,
        lane: TimelineVerticalScrollbarRail(
          controller: vertical,
          viewportHeight: 300,
          contentHeight: 1200,
          width: 16,
        ),
        size: const Size(16, 300),
        at: const Offset(0, 298),
      ),
      panel,
      reason: 'the right-edge rail painted a fill of its own',
    );

    final horizontal = ScrollController();
    addTearDown(horizontal.dispose);
    expect(
      await argbAt(
        tester,
        lane: TimelineHorizontalScrollbarRail(
          controller: horizontal,
          viewportWidth: 300,
          contentWidth: 1200,
          height: 16,
        ),
        size: const Size(300, 16),
        // Below the top hairline, which stays: it is a separator.
        at: const Offset(298, 15),
      ),
      panel,
      reason: 'the bottom rail painted a fill of its own',
    );
  });

  testWidgets('the layer rail\'s own lane is the panel it sits in', (
    tester,
  ) async {
    final rail = LayerRailExtent();
    addTearDown(rail.dispose);
    final argb = await argbAt(
      tester,
      lane: LayerRailScrollbar(
        axis: Axis.vertical,
        rail: rail,
        naturalExtent: 1200,
        availableExtent: 300,
      ),
      size: const Size(16, 300),
      at: const Offset(0, 298),
    );
    expect(argb, panel, reason: 'the rail lane painted a fill of its own');
  });
}
