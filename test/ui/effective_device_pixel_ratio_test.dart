import 'package:anicel/src/ui/effective_device_pixel_ratio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The law: geometry reads the EFFECTIVE ratio (monitor × UI scale), and
/// `MediaQuery` is NOT that number.
///
/// This is not a hypothetical. The hook that owns the root device matrix
/// is `RendererBinding.createViewConfigurationFor`, and a probe overriding
/// it measured `MediaQuery` and `View.of` still reporting the raw monitor
/// ratio while the real root transform carried the product. Anything that
/// sizes a raster or snaps to the device grid off `MediaQuery` would be
/// silently wrong the day a UI scale ships.
///
/// ⚠️Fractional DPR throughout, and BOTH `devicePixelRatio` and
/// `physicalSize` are set: changing the ratio alone silently moves the
/// logical viewport from 800×600, and `setSurfaceSize` desynchronises
/// `MediaQuery` from the render tree.
void main() {
  /// Reads both ratios at one point in the tree.
  ({double effective, double mediaQuery}) probe(WidgetTester tester) {
    late double effective;
    late double mediaQuery;
    final finder = find.byType(Builder);
    expect(finder, findsOneWidget);
    final context = tester.element(finder);
    effective = EffectiveDevicePixelRatio.of(context);
    mediaQuery = MediaQuery.devicePixelRatioOf(context);
    return (effective: effective, mediaQuery: mediaQuery);
  }

  Widget harness({required double uiScale}) => MediaQuery(
    // The view's own ratio reaches the scope through here, exactly as it
    // does under `MaterialApp`.
    data: MediaQueryData.fromView(
      WidgetsBinding.instance.platformDispatcher.views.first,
    ),
    child: EffectiveDevicePixelRatioScope(
      uiScale: uiScale,
      child: Builder(builder: (_) => const SizedBox()),
    ),
  );

  testWidgets('scope multiplies the view ratio by the UI scale, and '
      'MediaQuery keeps reporting the RAW ratio', (tester) async {
    tester.view.devicePixelRatio = 1.25;
    tester.view.physicalSize = const Size(2000, 1250);
    addTearDown(tester.view.reset);

    await tester.pumpWidget(harness(uiScale: 0.9));

    final read = probe(tester);
    // 1.25 × 0.9 — the fractional product the canon names.
    expect(read.effective, closeTo(1.125, 1e-9));
    // ★The whole point: MediaQuery did NOT move. A geometry site reading
    // it would size against 1.25 while the compositor uses 1.125.
    expect(read.mediaQuery, closeTo(1.25, 1e-9));
    expect(read.effective, isNot(closeTo(read.mediaQuery, 1e-6)));
  });

  testWidgets('scale 1.0 is behaviour-neutral — effective == MediaQuery', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1.5;
    tester.view.physicalSize = const Size(2400, 1500);
    addTearDown(tester.view.reset);

    await tester.pumpWidget(harness(uiScale: 1.0));

    final read = probe(tester);
    expect(read.effective, closeTo(1.5, 1e-9));
    expect(read.effective, closeTo(read.mediaQuery, 1e-9));
  });

  testWidgets('no scope mounted falls back to the view ratio', (tester) async {
    tester.view.devicePixelRatio = 1.125;
    tester.view.physicalSize = const Size(1800, 1125);
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MediaQuery(
        data: MediaQueryData.fromView(
          WidgetsBinding.instance.platformDispatcher.views.first,
        ),
        child: Builder(builder: (_) => const SizedBox()),
      ),
    );

    // Widget tests and subtrees built outside the app shell keep working
    // rather than throwing — the fallback is deliberate.
    expect(probe(tester).effective, closeTo(1.125, 1e-9));
  });

  testWidgets('a scale change rebuilds dependents', (tester) async {
    tester.view.devicePixelRatio = 1.25;
    tester.view.physicalSize = const Size(2000, 1250);
    addTearDown(tester.view.reset);

    final seen = <double>[];
    Widget build(double uiScale) => MediaQuery(
      data: MediaQueryData.fromView(
        WidgetsBinding.instance.platformDispatcher.views.first,
      ),
      child: EffectiveDevicePixelRatioScope(
        uiScale: uiScale,
        child: Builder(
          builder: (context) {
            seen.add(EffectiveDevicePixelRatio.of(context));
            return const SizedBox();
          },
        ),
      ),
    );

    await tester.pumpWidget(build(1.0));
    await tester.pumpWidget(build(0.8));

    // Without `updateShouldNotify` comparing the ratio, the dependent
    // would keep painting on the old grid after a scale change.
    expect(seen.first, closeTo(1.25, 1e-9));
    expect(seen.last, closeTo(1.0, 1e-9));
  });
}
