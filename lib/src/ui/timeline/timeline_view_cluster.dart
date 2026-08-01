import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../widgets/app_icon_button.dart';
import '../widgets/field_slider.dart';
import 'timeline_panel.dart' show TimelinePanel;

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
  /// grid the slider already quantizes to, and never a no-op inside the
  /// range.
  double _steppedZoom({required bool zoomIn}) {
    final scaled = zoomIn ? pixelsPerFrame * 1.25 : pixelsPerFrame / 1.25;
    var next = scaled.roundToDouble();
    if (next == pixelsPerFrame) {
      next = zoomIn ? pixelsPerFrame + 1 : pixelsPerFrame - 1;
    }
    return next.clamp(
      TimelinePanel.minPixelsPerFrame,
      TimelinePanel.maxPixelsPerFrame,
    );
  }

  /// R26 #42: the app's standard icon button — the disabled look is
  /// IconButton's own (no hand-mixed alpha), same as the canvas bar.
  Widget _zoomStepButton({required bool zoomIn}) {
    final atBound = zoomIn
        ? pixelsPerFrame >= TimelinePanel.maxPixelsPerFrame
        : pixelsPerFrame <= TimelinePanel.minPixelsPerFrame;
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
        ListenableBuilder(
          listenable: globalFrame == null
              ? frameCursor
              : Listenable.merge([frameCursor, globalFrame]),
          builder: (context, _) {
            final local = _frameLabel(frameCursor.value + 1);
            final global = globalFrame?.value;
            return Text(
              global == null ? local : '${_frameLabel(global + 1)} · $local',
              key: const ValueKey<String>('timeline-current-frame-counter'),
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: colorScheme.primary,
              ),
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
            min: TimelinePanel.minPixelsPerFrame,
            max: TimelinePanel.maxPixelsPerFrame,
            value: pixelsPerFrame.clamp(
              TimelinePanel.minPixelsPerFrame,
              TimelinePanel.maxPixelsPerFrame,
            ),
            // Zoom reads as percent of the default frame width.
            valueText:
                '${(pixelsPerFrame / TimelinePanel.defaultPixelsPerFrame * 100).round()}%',
            valueTextBuilder: (value) =>
                '${(value / TimelinePanel.defaultPixelsPerFrame * 100).round()}%',
            height: 18,
            // Quantized to WHOLE pixels per frame (R4 #5): the raw drag
            // emitted sub-pixel widths, rebuilding the entire grid many
            // times per visually identical step — the drag felt heavy.
            // The bar itself echoes the gesture smoothly either way.
            onChanged: onPixelsPerFrameChanged == null
                ? null
                : (value) {
                    final stepped = value.roundToDouble();
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
