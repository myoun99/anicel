import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../widgets/app_icon_button.dart';
import '../widgets/field_slider.dart';
import 'timeline_zoom_limits.dart';

import '../../models/project_frame_rate.dart';

/// The right-side view cluster shared VERBATIM by the timeline and
/// storyboard tabs: frame counter + zoom slider, plus host-specific
/// trailing controls (the timeline's orientation toggle).
///
/// The seconds TOGGLE left this bar in the rail-window round — it lives
/// in each grid's top-left corner now, over the layer-axis scrollbar,
/// beside the axis whose labels it rewrites. [showSeconds] stays because
/// the counter beside it still reads in that notation.
///
/// One widget instead of two hand-copied Rows — the key strings
/// ('timeline-current-frame-counter', 'timeline-zoom-slider') stay unique
/// on screen because only one tab is ever mounted.
class TimelineViewCluster extends StatelessWidget {
  const TimelineViewCluster({
    super.key,
    required this.frameCursor,
    required this.projectFrameRate,
    required this.showSeconds,
    required this.pixelsPerFrame,
    required this.onPixelsPerFrameChanged,
    this.globalFrame,
    this.trailing = const <Widget>[],
  });

  /// The editing/playback cursor — the counter subscribes to this alone so
  /// a tick rebuilds one Text, nothing else (playback-perf architecture).
  final ValueListenable<int> frameCursor;

  /// Track-global playhead frame (UI-R9 #6, storyboard only): when set,
  /// the counter reads `<global> · <cut-local>` — the global number LEFT
  /// of the local one. The counter subscribes to both, so gap parking
  /// (which moves the global without touching the cut-local cursor)
  /// refreshes the label too. Null (the timeline tab) keeps the plain
  /// cut-local counter.
  final ValueListenable<int?>? globalFrame;

  final ProjectFrameRate projectFrameRate;
  final bool showSeconds;
  final double pixelsPerFrame;
  final ValueChanged<double>? onPixelsPerFrameChanged;

  /// Host-specific controls after the zoom slider (orientation toggle).
  final List<Widget> trailing;

  String _frameLabel(int oneBasedFrame) => showSeconds
      ? secondsPlusFramesLabel(oneBasedFrame, projectFrameRate.countingBase)
      : '$oneBasedFrame';

  /// One −/+ button step (UI-R11 #11): multiplicative (×1.25) like editor
  /// zooms so a step feels equal at 4px and 96px, rounded to the whole-px
  /// grid the slider already quantizes to.
  ///
  /// ⛔THE ±1 FALLBACK IS GONE (2026-09-16). It read 「where ×1.25 lands back
  /// on the same whole pixel, the step is that pixel」 — a guard against a
  /// step that stands still. Measured across the WHOLE grid the quantizer
  /// can produce ({2.4} ∪ 3…96): ×1.25 lands back on the same pixel only AT
  /// THE TWO BOUNDS — 2.4 stepping out, 96 stepping in — and there the ±1
  /// answer is the value the main line already gives, because
  /// [TimelineZoomLimits.quantize] clamps. The branch could not change an
  /// outcome, which is exactly why its mutant would not die: the gate said
  /// so before anyone read the arithmetic.
  double _steppedZoom({required bool zoomIn}) =>
      TimelineZoomLimits.quantize(
        zoomIn ? pixelsPerFrame * 1.25 : pixelsPerFrame / 1.25,
      );

  /// R26 #42: the app's standard icon button — the disabled look is
  /// IconButton's own (no hand-mixed alpha), same as the canvas bar.
  Widget _zoomStepButton({required bool zoomIn}) {
    final atBound = zoomIn
        ? pixelsPerFrame >= TimelineZoomLimits.maxPixelsPerFrame
        : pixelsPerFrame <= TimelineZoomLimits.minPixelsPerFrame;
    final enabled = onPixelsPerFrameChanged != null && !atBound;
    return AppIconButton(
      keyValue: zoomIn ? 'timeline-zoom-in-button' : 'timeline-zoom-out-button',
      tooltip: zoomIn ? 'Zoom In' : 'Zoom Out',
      icon: Icon(zoomIn ? Icons.zoom_in : Icons.zoom_out),
      onPressed: enabled
          ? () => onPixelsPerFrameChanged!(_steppedZoom(zoomIn: zoomIn))
          : null,
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final globalFrame = this.globalFrame;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // TWO LINES, one number each: the TRACK-global frame on top, the
        // cut-local one under it (유저 확정, 2026-08-10). Stacking costs no
        // width, absorbs a digit's growth into the line that grew, and — the
        // reason it is stated for BOTH panels rather than for the storyboard
        // alone — puts the local number at the SAME height whichever panel
        // is open. The timeline leaves the top line EMPTY (it is one cut's
        // window; there is no global frame to print) and keeps the line
        // rather than dropping it, which is what makes the heights agree.
        //
        // 🚫No `G`/`L` labels (유저 확정): above and below IS the label.
        // 🚫No width reserved for the widest number either — it grows into
        // the free space on its left, and the bar's own scroller takes the
        // squeeze exactly as every other overflow on this row does.
        ListenableBuilder(
          listenable: globalFrame == null
              ? frameCursor
              : Listenable.merge([frameCursor, globalFrame]),
          builder: (context, _) {
            final local = _frameLabel(frameCursor.value + 1);
            final global = globalFrame?.value;
            final style = TextStyle(
              fontFamily: 'monospace',
              fontSize: 10.5,
              height: 1.24,
              fontWeight: FontWeight.w600,
              color: colorScheme.primary,
            );
            return Column(
              key: const ValueKey<String>('timeline-current-frame-counter'),
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                // Dimmer, never smaller: the two numbers have to line up
                // digit for digit, and a second size would break that at
                // the one moment it matters — reading them together.
                //
                // 🪦The dimming was an `Opacity(0.62)` around this one
                // `Text`, and an `Opacity` is a repaint boundary at any
                // alpha above zero — a permanent one, in the bar that bakes
                // itself in zones. ⛔For a single run of opaque glyphs the
                // two are the same pixels: a layer at 62% over the ground
                // and a glyph colour at 62% alpha are one expression
                // (`test/architecture/an_opacity_is_a_boundary_test.dart`
                // carries the law).
                Text(
                  global == null ? '' : _frameLabel(global + 1),
                  key: const ValueKey<String>('timeline-global-frame-counter'),
                  style: style.copyWith(
                    color: style.color!.withValues(alpha: 0.62),
                  ),
                ),
                Text(
                  local,
                  key: const ValueKey<String>('timeline-local-frame-counter'),
                  style: style,
                ),
              ],
            );
          },
        ),
        const SizedBox(width: 4),
        // UI-R11 #11: the flanking glyphs are real STEP buttons now, not
        // decorations — click-to-zoom without the slider's drag precision.
        _zoomStepButton(zoomIn: false),
        SizedBox(
          width: 140,
          child: FieldSlider(
            key: const ValueKey<String>('timeline-zoom-slider'),
            min: TimelineZoomLimits.minPixelsPerFrame,
            max: TimelineZoomLimits.maxPixelsPerFrame,
            value: pixelsPerFrame.clamp(
              TimelineZoomLimits.minPixelsPerFrame,
              TimelineZoomLimits.maxPixelsPerFrame,
            ),
            // Zoom reads as percent of the default frame width.
            unit: '%',
            displayScale: 100 / TimelineZoomLimits.defaultPixelsPerFrame,
            height: 18,
            // 🚨MULTIPLICATIVE track (I-22 ②-1): a linear one spent 97% of
            // its length on 24→96px and left the whole narrow half — the
            // half the user zooms out into — inside its first few pixels.
            // Equal travel is equal RATIO here, as it is on every editor
            // zoom in the app.
            scale: FieldSliderScale.exponential,
            // Quantized by the range's own law (R4 #5 kept: a sub-pixel
            // drag above 1px rebuilt the entire grid for a visually
            // identical step). The bar echoes the gesture smoothly either
            // way.
            onChanged: onPixelsPerFrameChanged == null
                ? null
                : (value) {
                    final stepped = TimelineZoomLimits.quantize(value);
                    if (stepped != pixelsPerFrame) {
                      onPixelsPerFrameChanged!(stepped);
                    }
                  },
          ),
        ),
        _zoomStepButton(zoomIn: true),
        ...trailing,
      ],
    );
  }
}
