import 'package:anicel/src/models/canvas_viewport.dart';
import 'package:anicel/src/ui/canvas/canvas_zoom_scale.dart';
import 'package:flutter_test/flutter_test.dart';

/// A `viewport:` seed written in the LOGICAL units a geometry pin reasons
/// in, converted to the DEVICE units the panel's viewport channels take.
///
/// 🚨Everything that crosses `BrushCanvasPanel`'s boundary is in device
/// pixels — the seed prop, the controller, `publishedViewport` and
/// `onViewportChanged` alike — because a value that does not depend on the
/// effective ratio cannot go stale while a panel is unmounted. That is the
/// right law for the app and the wrong unit for a test whose subject is
/// "one screen pixel is a third of a canvas pixel": written as a device
/// number, the literal stops matching the sentence above it.
///
/// So the conversion lives here, once, and the pins keep saying what they
/// mean. ⛔Do NOT hardcode the factor at the call site: the widget-test
/// ratio is 3.0 today, and a pin that bakes that in fails the day the
/// harness default moves, for a reason that has nothing to do with it.
CanvasViewport seedFromRender(WidgetTester tester, CanvasViewport render) =>
    CanvasZoomScale(tester.view.devicePixelRatio).toDevice(render);

/// The other direction: a viewport the panel HANDED OUT — through
/// `onViewportChanged` or `publishedViewport` — back in logical units, so a
/// pin can compare it against the render numbers it was written with.
///
/// ⚠️Use it on anything that crossed the boundary. A pin that reads a device
/// value and compares it to a render literal passes or fails by the
/// harness's ratio, which is the one thing it is not about.
CanvasViewport renderOf(WidgetTester tester, CanvasViewport device) =>
    CanvasZoomScale(tester.view.devicePixelRatio).fromDevice(device);
