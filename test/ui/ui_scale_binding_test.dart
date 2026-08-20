import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/ui/ui_scale.dart';
import 'package:anicel/src/ui/ui_scale_binding.dart';

/// The test binding with the PRODUCTION override mixed in.
///
/// `AnicelBinding` itself cannot be the binding under `flutter_test` — the
/// framework installs its own — so the override lives in
/// [UiScaleViewConfiguration] and both bindings wear the same one. Without
/// this file the round's central claim ("a scale change reaches the root
/// device matrix") would rest on reading the code.
///
/// ⚠️It replaces `AutomatedTestWidgetsFlutterBinding`'s own configuration
/// hook, which is what forces the 800×600 test surface — so sizes in THIS
/// file come from the `TestFlutterView` (2400×1800 at ratio 3), not from
/// the usual test surface. That is the point: it is the real path.
class _ScaledTestBinding extends AutomatedTestWidgetsFlutterBinding
    with UiScaleViewConfiguration {
  static _ScaledTestBinding ensureInitialized() {
    if (_instance == null) {
      _ScaledTestBinding();
    }
    return _instance!;
  }

  static _ScaledTestBinding? _instance;

  @override
  void initInstances() {
    super.initInstances();
    _instance = this;
    AppUiScale.value.addListener(handleUiScaleChanged);
  }
}

void main() {
  final binding = _ScaledTestBinding.ensureInitialized();

  tearDown(() => AppUiScale.value.value = AppUiScale.defaultScale);

  testWidgets('the scale multiplies into the ROOT device matrix', (
    tester,
  ) async {
    await tester.pumpWidget(const SizedBox.expand());
    final raw = tester.view.devicePixelRatio;
    expect(binding.renderViews.single.configuration.devicePixelRatio, raw);

    AppUiScale.value.value = 1.25;
    await tester.pump();
    expect(binding.renderViews.single.configuration.devicePixelRatio, raw * 1.25);

    AppUiScale.value.value = 0.75;
    await tester.pump();
    expect(binding.renderViews.single.configuration.devicePixelRatio, raw * 0.75);
  });

  testWidgets('the root matrix is a PURE SCALE — no translation', (
    tester,
  ) async {
    // The invariant the whole quantization round rests on: the root child's
    // origin is exactly on the device grid, so any app-chosen integral
    // device offset keeps its descendants there. A UI scale must not put a
    // translation into that matrix.
    AppUiScale.value.value = 1.1;
    await tester.pumpWidget(const SizedBox.expand());
    final matrix = binding.renderViews.single.configuration.toMatrix();
    expect(matrix.getTranslation().x, 0);
    expect(matrix.getTranslation().y, 0);
    expect(matrix.getTranslation().z, 0);
    final raw = tester.view.devicePixelRatio;
    expect(matrix.entry(0, 0), raw * 1.1);
    expect(matrix.entry(1, 1), raw * 1.1);
  });

  testWidgets('scaling up SHRINKS the logical box the child is given', (
    tester,
  ) async {
    // 🚨The half that is easy to forget. Chrome that scales up without a
    // smaller logical box lays a window's worth of UI out past the edge of
    // the window, and nothing reports it — the overflow banner only fires
    // inside a flex.
    late Size given;
    Widget probe() => LayoutBuilder(
      builder: (context, constraints) {
        given = constraints.biggest;
        return const SizedBox.expand();
      },
    );
    await tester.pumpWidget(probe());
    final unscaled = given;

    AppUiScale.value.value = 1.25;
    await tester.pumpWidget(probe());
    expect(given.width, closeTo(unscaled.width / 1.25, 1e-9));
    expect(given.height, closeTo(unscaled.height / 1.25, 1e-9));

    AppUiScale.value.value = 0.9;
    await tester.pumpWidget(probe());
    expect(given.width, closeTo(unscaled.width / 0.9, 1e-9));
  });

  testWidgets('a scale change forces a frame on its own', (tester) async {
    // Nobody calls `setState` for the binding half: the notifier's listener
    // is the only path from "the user picked 125%" to a relaid-out window.
    late Size given;
    await tester.pumpWidget(
      LayoutBuilder(
        builder: (context, constraints) {
          given = constraints.biggest;
          return const SizedBox.expand();
        },
      ),
    );
    final unscaled = given;
    AppUiScale.value.value = 1.5;
    // ⛔No `pumpWidget` — the widget tree is untouched. Only the binding's
    // listener can produce a new layout here.
    await tester.pump();
    expect(given.width, closeTo(unscaled.width / 1.5, 1e-9));
  });

  testWidgets('every ladder stop lands its exact product', (tester) async {
    await tester.pumpWidget(const SizedBox.expand());
    final raw = tester.view.devicePixelRatio;
    for (final stop in AppUiScale.ladder) {
      AppUiScale.value.value = stop;
      await tester.pump();
      expect(
        binding.renderViews.single.configuration.devicePixelRatio,
        raw * stop,
        reason: 'stop ${AppUiScale.label(stop)}',
      );
    }
  });
}
