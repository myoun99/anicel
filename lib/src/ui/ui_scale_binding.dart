import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

import 'ui_scale.dart';

/// The binding that puts [AppUiScale] into the root device matrix.
///
/// ## Why the binding and not a `Transform` at the top of the tree
///
/// `RenderView` installs a PURE SCALE with no translation, which is the one
/// fact the whole quantization round rests on: the root child's origin is
/// exactly on the device grid, so an app-chosen offset that is an integral
/// count of device pixels keeps every descendant on it. A `Transform.scale`
/// wrapped around the app would compose a SECOND scale below that origin —
/// correct arithmetically, but it puts a layer over the entire app and it
/// moves the grid the audit sweeps against out from under the root. Scaling
/// the root matrix itself keeps the invariant literally true.
///
/// ⚠️`MediaQuery` does NOT follow this. It is built by the `View` widget
/// from the raw `FlutterView`, which the override never touches, so a
/// matching correction is mounted in the widget tree by
/// [EffectiveDevicePixelRatioScope]. The two must ship together; either one
/// alone leaves the app measuring against a box it is not laid out in.
/// The override itself, as a mixin, so a test binding can install the
/// PRODUCTION code path rather than a copy of it.
///
/// `flutter_test` supplies its own binding, and its own
/// `createViewConfigurationFor` — so without this the one claim this file
/// exists to make ("a scale change reaches the root device matrix") could
/// only be checked by reading the code.
mixin UiScaleViewConfiguration on RendererBinding {
  /// 🚨Reads the scale LIVE rather than caching it. The binding is asked
  /// for a configuration on `addRenderView` and on every metrics change,
  /// both of which can happen before or after a scale change, in either
  /// order.
  @override
  ViewConfiguration createViewConfigurationFor(RenderView renderView) {
    final view = renderView.flutterView;
    return scaledViewConfiguration(
      physicalConstraints: BoxConstraints.fromViewConstraints(
        view.physicalConstraints,
      ),
      rawDevicePixelRatio: view.devicePixelRatio,
      uiScale: AppUiScale.value.value,
    );
  }

  /// A scale change IS a metrics change: the same handler that answers a
  /// window resize re-derives every render view's configuration and forces
  /// a frame. `RenderView.configuration=` then replaces the root layer,
  /// because the matrix differs, and marks the tree for layout.
  void handleUiScaleChanged() => handleMetricsChanged();
}

class AnicelBinding extends WidgetsFlutterBinding with UiScaleViewConfiguration {
  /// Initializes the binding (creating it on the first call, as
  /// `WidgetsFlutterBinding.ensureInitialized` does) and starts following
  /// the UI scale.
  ///
  /// 🚨Must be called before ANY platform channel — the pen sidecars reach
  /// for one — for the same reason `WidgetsFlutterBinding.ensureInitialized`
  /// must: a `MethodChannel` needs the binding's messenger to exist. iPad
  /// and iPhone stopped at a white screen the one time that ordering was
  /// wrong.
  static AnicelBinding ensureInitialized() {
    if (_instance == null) {
      AnicelBinding();
    }
    return _instance!;
  }

  static AnicelBinding? _instance;

  @override
  void initInstances() {
    super.initInstances();
    _instance = this;
    AppUiScale.value.addListener(handleUiScaleChanged);
  }
}
