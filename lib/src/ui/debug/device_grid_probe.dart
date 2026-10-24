import 'package:flutter/widgets.dart';

import '../effective_device_pixel_ratio.dart';
import 'input_inspector.dart';

/// 🔬F-67 (2026-09-11): where [child]'s top-left lands on the DEVICE grid,
/// printed to the input inspector once per change — the editing canvas's
/// frame, which it wraps.
///
/// 유저 F-67: 「툴을 바꾸거나 선을 그리기 시작하거나 화면을 팬으로 이동할때,
/// 그 때만 … 일부 정해진 픽셀이 반픽셀 움직였다가 돌아오는 현상」, at zoom
/// ≥ 100% on the drawing. Three mechanisms were measured and cleared in
/// the test shell — the route flip inside the buffer (byte-identical), the
/// pan snap (whole device pixels), the display filter (`none` at ≥1) — and
/// the one left is the one a shell cannot see: the canvas's own device
/// offset, which layout owns. R11 put it on the grid at 1.25 and 1.35 in
/// the shell; the real app's panel set, ruler widths and UI scale are
/// what the shell does not have. When the fraction here is not 0 on the
/// frame the pixels move, #1100's mechanism (a stable picture replayed at
/// an integral offset, a live repaint at the fractional one) is the
/// cause; when it is 0, it is not, and the search moves on. Either way it
/// is a number rather than a guess.
///
/// ↩️It sat in the canvas's layer stack, which the onion ghosts alone
/// mount since a canvas that stands shows the frame's one picture
/// (one-picture-per-frame ②-3) — and went quiet without them, until it
/// wrapped the frame itself (②-5a).
class DeviceGridProbe extends StatefulWidget {
  const DeviceGridProbe({super.key, required this.child});

  final Widget child;

  @override
  State<DeviceGridProbe> createState() => _DeviceGridProbeState();
}

class _DeviceGridProbeState extends State<DeviceGridProbe> {
  @override
  void initState() {
    super.initState();
    InputInspector.visible.addListener(_rebuildForInspector);
  }

  @override
  void dispose() {
    InputInspector.visible.removeListener(_rebuildForInspector);
    super.dispose();
  }

  /// The card is opened AFTER this view settled, most of the time — and a
  /// layout fact is only measured on a build. So a rebuild follows the
  /// toggle, and the pin is there when the card is.
  void _rebuildForInspector() {
    if (InputInspector.visible.value && mounted) {
      setState(() {});
    }
  }

  /// Post-frame, because layout has to have run; deduplicated, because a
  /// probe that prints every frame is one nobody reads; behind the
  /// inspector's visibility, because release builds are the ones that get
  /// reported and this must cost nothing when it is off.
  void _noteBoundaryOnGrid(BuildContext context) {
    if (!InputInspector.visible.value) {
      return;
    }
    final ratio = EffectiveDevicePixelRatio.of(context);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      final box = context.findRenderObject();
      if (box is! RenderBox || !box.hasSize) {
        return;
      }
      final device = box.localToGlobal(Offset.zero) * ratio;
      String fraction(double v) => (v - v.floorToDouble()).toStringAsFixed(3);
      // PINNED, not noted: a layout fact, read whenever the card is looked
      // at — the noted line scrolled off under the paint probes before the
      // hands-on screenshot was taken.
      InputInspector.pin(
        'grid',
        'grid device=(${device.dx.toStringAsFixed(2)}, '
        '${device.dy.toStringAsFixed(2)}) '
        'frac=(${fraction(device.dx)}, ${fraction(device.dy)}) '
        'ratio=${ratio.toStringAsFixed(3)}',
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    _noteBoundaryOnGrid(context);
    return widget.child;
  }
}
