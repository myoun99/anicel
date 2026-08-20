import 'dart:collection' show Queue;
import 'dart:ui' as ui show PointerDataPacket;

import 'package:flutter/gestures.dart';
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

  /// 🚨🚨**THE THIRD HALF.** The scale has to reach the POINTER as well as
  /// the matrix and the MediaQuery, and this is the piece that is easiest
  /// to miss because nothing complains.
  ///
  /// `GestureBinding` converts incoming pointer data to logical pixels by
  /// dividing by `FlutterView.devicePixelRatio` — the RAW ratio, which
  /// [createViewConfigurationFor] does not touch. Everything below the root
  /// is laid out in `raw × uiScale` instead, so at any stop but 100% the
  /// hit-test space and the layout space differ by exactly the scale: at
  /// 125% on a 1.0 monitor a click lands 25% down and right of the pixel
  /// the user aimed at, and the right fifth of the window cannot be hit at
  /// all. Hover, drag deltas, touch slop and every stylus sample are off by
  /// the same factor.
  ///
  /// ⛔It is fixed HERE, at the packet, and not by overriding
  /// `handlePointerEvent` and dividing `position`/`delta`. `copyWith`
  /// carries neither `scrollDelta` nor the pan/zoom fields, so a wheel step
  /// and a trackpad pan would keep the raw-ratio value — and every
  /// `globalToLocal(event.position)` in the app would still be reading a
  /// coordinate from the wrong space. Handing the converter the effective
  /// ratio corrects every field at once, including ones added later.
  ///
  /// ⚠️`WidgetTester` feeds `handlePointerEvent` already-logical positions
  /// and never runs `PointerEventConverter`, so a normal widget test cannot
  /// see any of this. `ui_scale_binding_test.dart` drives a real packet.
  @override
  void initInstances() {
    super.initInstances();
    // `GestureBinding.initInstances` installed its own handler on the way
    // up; take it over now that it is there.
    platformDispatcher.onPointerDataPacket = _handleScaledPointerDataPacket;
    // ⛔The subscription lives HERE and not in `AnicelBinding`, so the
    // test binding cannot wear a copy of it. It used to, and that made the
    // wire untestable: deleting the production `addListener` left every
    // test green because the test binding had its own.
    AppUiScale.value.addListener(handleUiScaleChanged);
  }

  /// Mirrors `GestureBinding`'s own queue, whose field is private. Without
  /// it, events that arrive while the binding is locked (a reassemble)
  /// would be dispatched into a half-rebuilt tree instead of waiting.
  final Queue<PointerEvent> _pendingScaledPointerEvents = Queue<PointerEvent>();

  double? _effectiveRatioOfView(int viewId) {
    final raw = platformDispatcher.view(id: viewId)?.devicePixelRatio;
    if (raw == null) {
      return null;
    }
    final scale = AppUiScale.value.value;
    return raw * (scale.isFinite && scale > 0 ? scale : 1.0);
  }

  void _handleScaledPointerDataPacket(ui.PointerDataPacket packet) {
    try {
      _pendingScaledPointerEvents.addAll(
        PointerEventConverter.expand(packet.data, _effectiveRatioOfView),
      );
      if (!locked) {
        _flushScaledPointerEvents();
      }
    } on Object catch (error, stack) {
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stack,
          library: 'anicel ui scale',
          context: ErrorDescription('while handling a pointer data packet'),
        ),
      );
    }
  }

  @override
  void unlocked() {
    super.unlocked();
    _flushScaledPointerEvents();
  }

  void _flushScaledPointerEvents() {
    while (_pendingScaledPointerEvents.isNotEmpty) {
      handlePointerEvent(_pendingScaledPointerEvents.removeFirst());
    }
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
  }
}
