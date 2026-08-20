import 'dart:ui'
    show DisplayFeature, DisplayFeatureState, DisplayFeatureType;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/ui/effective_device_pixel_ratio.dart';
import 'package:anicel/src/ui/layout/device_grid.dart';
import 'package:anicel/src/ui/ui_scale.dart';

void main() {
  group('AppUiScale ladder', () {
    test('is ascending, positive and contains 100%', () {
      expect(AppUiScale.ladder, contains(1.0));
      expect(AppUiScale.ladder.first, greaterThan(0));
      for (var i = 1; i < AppUiScale.ladder.length; i += 1) {
        expect(
          AppUiScale.ladder[i],
          greaterThan(AppUiScale.ladder[i - 1]),
          reason: 'the settings row renders the ladder in order',
        );
      }
    });

    test('snap returns the nearest stop, and a stop is its own nearest', () {
      for (final stop in AppUiScale.ladder) {
        expect(AppUiScale.snap(stop), stop);
      }
      expect(AppUiScale.snap(1.02), 1.0);
      expect(AppUiScale.snap(1.19), 1.25);
      expect(AppUiScale.snap(0.2), 0.75, reason: 'clamps below the ladder');
      expect(AppUiScale.snap(9.0), 1.5, reason: 'clamps above the ladder');
    });

    test('snap refuses values that would make the ratio a bad divisor', () {
      // The scale multiplies into a number every quantizer DIVIDES by.
      expect(AppUiScale.snap(0), AppUiScale.defaultScale);
      expect(AppUiScale.snap(-1.25), AppUiScale.defaultScale);
      expect(AppUiScale.snap(double.nan), AppUiScale.defaultScale);
      expect(AppUiScale.snap(double.infinity), AppUiScale.defaultScale);
    });

    test('stepped walks the ladder and stops at both ends', () {
      expect(AppUiScale.stepped(1.0, 1), 1.1);
      expect(AppUiScale.stepped(1.0, -1), 0.9);
      expect(AppUiScale.stepped(AppUiScale.ladder.last, 1), AppUiScale.ladder.last);
      expect(
        AppUiScale.stepped(AppUiScale.ladder.first, -1),
        AppUiScale.ladder.first,
      );
      // An off-ladder input snaps first rather than falling off the end.
      expect(AppUiScale.stepped(1.03, 1), 1.1);
    });

    test('label reads as a percentage with no trailing zero', () {
      expect(AppUiScale.label(1.0), '100%');
      expect(AppUiScale.label(0.9), '90%');
      expect(AppUiScale.label(1.25), '125%');
    });
  });

  group('scaledViewConfiguration', () {
    const physical = BoxConstraints.tightFor(width: 2400, height: 1600);

    test('multiplies the ratio and divides the logical box by the scale', () {
      final config = scaledViewConfiguration(
        physicalConstraints: physical,
        rawDevicePixelRatio: 1.5,
        uiScale: 1.25,
      );
      expect(config.devicePixelRatio, 1.5 * 1.25);
      // 🚨The pair that must move together: scaling the chrome up without
      // shrinking the logical box lays a window's worth of UI out past the
      // window's edge.
      expect(config.logicalConstraints.maxWidth, 2400 / (1.5 * 1.25));
      expect(config.logicalConstraints.maxHeight, 1600 / (1.5 * 1.25));
      expect(config.physicalConstraints, physical);
    });

    test('at 100% it matches what the framework would have produced', () {
      final scaled = scaledViewConfiguration(
        physicalConstraints: physical,
        rawDevicePixelRatio: 1.75,
        uiScale: 1.0,
      );
      expect(scaled.devicePixelRatio, 1.75);
      expect(scaled.logicalConstraints, physical / 1.75);
    });

    test('a hostile ratio or scale degrades to 1 rather than to infinity', () {
      for (final bad in <double>[0, -2, double.nan, double.infinity]) {
        expect(
          scaledViewConfiguration(
            physicalConstraints: physical,
            rawDevicePixelRatio: bad,
            uiScale: 1.25,
          ).devicePixelRatio,
          1.25,
        );
        expect(
          scaledViewConfiguration(
            physicalConstraints: physical,
            rawDevicePixelRatio: 1.25,
            uiScale: bad,
          ).devicePixelRatio,
          1.25,
        );
      }
    });
  });

  group('scaleMediaQueryData', () {
    const base = MediaQueryData(
      size: Size(1000, 800),
      devicePixelRatio: 1.5,
      padding: EdgeInsets.only(top: 24, bottom: 16),
      viewPadding: EdgeInsets.only(top: 24, bottom: 34),
      viewInsets: EdgeInsets.only(bottom: 300),
      systemGestureInsets: EdgeInsets.only(left: 20, right: 20),
    );

    test('every LENGTH divides and only the ratio multiplies', () {
      final scaled = scaleMediaQueryData(base, 1.25);
      expect(scaled.size, const Size(1000 / 1.25, 800 / 1.25));
      expect(scaled.devicePixelRatio, 1.5 * 1.25);
      expect(scaled.padding.top, 24 / 1.25);
      expect(scaled.viewPadding.bottom, 34 / 1.25);
      expect(scaled.viewInsets.bottom, 300 / 1.25);
      expect(scaled.systemGestureInsets.left, 20 / 1.25);
    });

    test('the corrected size matches the box the binding hands the child', () {
      // The whole point: `MediaQuery.sizeOf` must agree with the logical
      // constraints. Physical 2400 at raw 1.5, scaled 1.25.
      const physical = BoxConstraints.tightFor(width: 2400, height: 1600);
      final config = scaledViewConfiguration(
        physicalConstraints: physical,
        rawDevicePixelRatio: 1.5,
        uiScale: 1.25,
      );
      final raw = base.copyWith(size: const Size(2400 / 1.5, 1600 / 1.5));
      final scaled = scaleMediaQueryData(raw, 1.25);
      expect(scaled.size.width, closeTo(config.logicalConstraints.maxWidth, 1e-9));
      expect(
        scaled.size.height,
        closeTo(config.logicalConstraints.maxHeight, 1e-9),
      );
    });

    test('is identity at 100% and at a hostile scale', () {
      expect(scaleMediaQueryData(base, 1.0), base);
      expect(scaleMediaQueryData(base, 0), base);
      expect(scaleMediaQueryData(base, double.nan), base);
    });

    test('carries a foldable hinge with everything else', () {
      final folded = base.copyWith(
        displayFeatures: const <DisplayFeature>[
          DisplayFeature(
            bounds: Rect.fromLTRB(495, 0, 505, 800),
            type: DisplayFeatureType.hinge,
            state: DisplayFeatureState.postureFlat,
          ),
        ],
      );
      final scaled = scaleMediaQueryData(folded, 1.25);
      expect(scaled.displayFeatures.single.bounds, const Rect.fromLTRB(396, 0, 404, 640));
      expect(scaled.displayFeatures.single.type, DisplayFeatureType.hinge);
    });
  });

  group('EffectiveDevicePixelRatioScope mounts both halves', () {
    testWidgets('the ratio is the product and MediaQuery agrees with it', (
      tester,
    ) async {
      late double gridRatio;
      late Size mediaSize;
      late double mediaRatio;
      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(
            size: Size(1000, 800),
            devicePixelRatio: 1.5,
            padding: EdgeInsets.only(top: 30),
          ),
          child: EffectiveDevicePixelRatioScope(
            uiScale: 1.25,
            child: Builder(
              builder: (context) {
                gridRatio = DeviceGrid.of(context).ratio;
                mediaSize = MediaQuery.sizeOf(context);
                mediaRatio = MediaQuery.devicePixelRatioOf(context);
                return const SizedBox.shrink();
              },
            ),
          ),
        ),
      );
      expect(gridRatio, 1.5 * 1.25);
      expect(mediaRatio, 1.5 * 1.25);
      expect(mediaSize, const Size(1000 / 1.25, 800 / 1.25));
    });

    testWidgets('the product is built ONCE, not compounded by its own output', (
      tester,
    ) async {
      // Regression guard for the ordering inside `build`: the raw ratio is
      // read before the corrected MediaQuery is mounted. Reading it after
      // would give `raw × scale × scale`.
      late double gridRatio;
      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(size: Size(400, 400), devicePixelRatio: 2),
          child: EffectiveDevicePixelRatioScope(
            uiScale: 1.5,
            child: Builder(
              builder: (context) {
                gridRatio = DeviceGrid.of(context).ratio;
                return const SizedBox.shrink();
              },
            ),
          ),
        ),
      );
      expect(gridRatio, 3.0);
      expect(gridRatio, isNot(4.5));
    });

    testWidgets('moving off 100% does NOT rebuild the subtree from scratch', (
      tester,
    ) async {
      // ⛔The MediaQuery must be mounted unconditionally. Mounting it only
      // when the scale differs from 1 changes the widget type at that slot,
      // which deactivates every element below — in the app, the entire
      // editor session.
      Widget app(double scale) => MediaQuery(
        data: const MediaQueryData(size: Size(800, 600), devicePixelRatio: 1.5),
        child: EffectiveDevicePixelRatioScope(
          uiScale: scale,
          child: const _InitCounter(),
        ),
      );
      _InitCounterState.inits = 0;
      await tester.pumpWidget(app(1.0));
      expect(_InitCounterState.inits, 1);
      await tester.pumpWidget(app(1.25));
      await tester.pumpWidget(app(1.5));
      await tester.pumpWidget(app(1.0));
      expect(
        _InitCounterState.inits,
        1,
        reason: 'the scoped subtree survives every scale change',
      );
    });

    testWidgets('with no ambient MediaQuery it still publishes a ratio', (
      tester,
    ) async {
      late double gridRatio;
      await tester.pumpWidget(
        EffectiveDevicePixelRatioScope(
          uiScale: 1.25,
          child: Builder(
            builder: (context) {
              gridRatio = DeviceGrid.of(context).ratio;
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      // Falls through to the View's own ratio × the scale.
      expect(gridRatio, closeTo(tester.view.devicePixelRatio * 1.25, 1e-9));
    });
  });
}

class _InitCounter extends StatefulWidget {
  const _InitCounter();

  @override
  State<_InitCounter> createState() => _InitCounterState();
}

class _InitCounterState extends State<_InitCounter> {
  static int inits = 0;

  @override
  void initState() {
    super.initState();
    inits += 1;
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
