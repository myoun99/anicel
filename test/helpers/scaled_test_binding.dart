import 'dart:ui' as ui show PointerDataPacket;

import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/ui/ui_scale_binding.dart';

/// The test binding with the PRODUCTION override mixed in.
///
/// 🚨**Without this, a UI-scale test runs only half the feature.** The scale
/// has two halves: the widget one — the corrected `MediaQuery` and the
/// effective ratio a `EffectiveDevicePixelRatioScope` publishes — and the
/// BINDING one, `createViewConfigurationFor`, which is what actually
/// multiplies the scale into the root device matrix. A test that mounts the
/// scope under the default binding gets the first half only: the widgets
/// believe the ratio is `monitor × scale` while the compositor is still
/// scaling by the raw monitor ratio, so an on-the-grid assertion names a
/// grid nobody rasterises to. It is self-consistent and it proves nothing.
///
/// `AnicelBinding` itself cannot be the binding under `flutter_test` — the
/// framework installs its own — so the override lives in
/// [UiScaleViewConfiguration] and both bindings wear the same one.
///
/// ⚠️It replaces `AutomatedTestWidgetsFlutterBinding`'s own configuration
/// hook, which is what forces the 800×600 test surface — so sizes in a file
/// using this binding come from the `TestFlutterView`, not from the usual
/// test surface. That is the point: it is the real path. Set
/// `tester.view.physicalSize` explicitly and never `setSurfaceSize`, which
/// desynchronises MediaQuery from the render tree and builds a letterbox
/// scale into the root.
class ScaledTestBinding extends AutomatedTestWidgetsFlutterBinding
    with UiScaleViewConfiguration {
  static ScaledTestBinding ensureInitialized() {
    if (_instance == null) {
      ScaledTestBinding();
    }
    return _instance!;
  }

  static ScaledTestBinding? _instance;

  @override
  void initInstances() {
    super.initInstances();
    _instance = this;
    // ⛔No `AppUiScale.value.addListener` here. It used to be, and that is
    // exactly what made the production wire untestable: deleting the
    // `addListener` from `UiScaleViewConfiguration` left the binding pins
    // green because the copy here still fired. The subscription lives in
    // the mixin, so this binding wears the real one.
  }

  /// Pushes a REAL pointer packet through the production conversion.
  ///
  /// ⚠️`withPointerEventSource(test, …)` is not cosmetic. A packet arrives
  /// tagged as coming from the device, and the test binding routes device
  /// events to a live-test dispatcher that does not exist here — they are
  /// converted correctly and then dropped, which looks exactly like a
  /// conversion bug. Tagging the dispatch as test-sourced sends it down the
  /// same path `WidgetTester.tap` uses, while the CONVERSION above it is
  /// still the shipped one. That conversion is the thing under test.
  void pumpPointerPacket(ui.PointerDataPacket packet) {
    withPointerEventSource(TestBindingEventSource.test, () {
      platformDispatcher.onPointerDataPacket!(packet);
    });
  }
}
