import 'dart:math' as math;

import 'package:flutter/gestures.dart'
    show DragGestureRecognizer, DragStartBehavior;
import 'package:flutter/material.dart';

import '../../models/project_frame_rate.dart';
import '../../services/audio/audio_peaks_extractor.dart';
import '../audio/audio_slide.dart';
import '../audio/engine_wave_band.dart';
import '../audio/engine_wave_views.dart';
import '../audio/waveform_painter.dart';
import '../effective_device_pixel_ratio.dart';
import '../repaint_props.dart';
import '../timeline/memo_token.dart' show ByIdentity;
import '../timeline/timeline_cell_style.dart';
import '../timeline/timeline_grid_metrics.dart' show timelineFrameCellWidth;
import '../timeline/timeline_grid_screen.dart';
import '../timeline/timeline_se_row_visual.dart' show SePaperSpan;
import '../widgets/owning_axis_grip.dart';

/// A linked sound's start offset, edited where its block is edited.
///
/// 🗣️유저 2026-09-27: 「오디오 배치된거 시작 오프셋 움직이는거 드래그중
/// 라이브로 파형움직이게 가볍게하고, 이거 블록별로 오프셋이 맞지않나?
/// 그래서 블록 편집창에서 하는게 맞을듯」.
///
/// The strip is the block's window over the sound: on the block's paper,
/// what plays; beyond it, faint, what the block cuts off. Dragging slides
/// the waveform under the window — toward the start plays a LATER part of
/// the file there ([slidAudioOffset]).
///
/// 🚨**LIGHT BY CONSTRUCTION.** A drag repaints THIS strip and nothing else:
/// no model write, no session notice. The offset reaches the window on
/// release and the project on the window's OK, like every field in it.
class SeOffsetStrip extends StatefulWidget {
  const SeOffsetStrip({
    super.key,
    required this.offsetFrames,
    required this.blockFrames,
    required this.frameRate,
    required this.peaks,
    required this.onChanged,
  });

  /// Frames skipped into the file where the block starts.
  final int offsetFrames;

  /// The block's length — the window the sound plays in.
  final int blockFrames;
  final ProjectFrameRate frameRate;

  /// Null until the sound's waveform is known; the offset cannot be dragged
  /// then, since how far it may go is the file's length.
  final AudioPeaks? peaks;
  final ValueChanged<int> onChanged;

  static const double height = 40;

  @override
  State<SeOffsetStrip> createState() => _SeOffsetStripState();
}

class _SeOffsetStripState extends State<SeOffsetStrip> {
  /// Pointer travel since the press, or null while nothing is dragged.
  double? _drag;

  /// The offset at the press — the drag measures from it.
  int _base = 0;

  /// The frame scale the strip was last laid out at.
  double _pixelsPerFrame = timelineFrameCellWidth;

  final EngineWaveBand _band = EngineWaveBand();

  @override
  void dispose() {
    _band.letGo();
    super.dispose();
  }

  bool get _editable => widget.peaks != null;

  int get _offset {
    final drag = _drag;
    final peaks = widget.peaks;
    if (drag == null || peaks == null) {
      return widget.offsetFrames;
    }
    return slidAudioOffset(
      base: _base,
      dragPixels: drag,
      pixelsPerFrame: _pixelsPerFrame,
      fileFrames: peaks.durationFrames(widget.frameRate),
    );
  }

  /// The block takes at most four fifths of the strip, so what it cuts off
  /// shows beside it — and never more per frame than the timeline's cell.
  double _scaleFor(double width) => math.min(
    timelineFrameCellWidth,
    width * 0.8 / math.max(1, widget.blockFrames),
  );

  void _configureDrag(DragGestureRecognizer recognizer) {
    // A strip that cannot be dragged still HOLDS the press — a dead control
    // is not a scroll either (`ControlPressClaim.onPressed`).
    recognizer
      ..dragStartBehavior = DragStartBehavior.down
      ..onStart = ((_) {
        if (_editable) {
          setState(() {
            _base = widget.offsetFrames;
            _drag = 0;
          });
        }
      })
      ..onUpdate = ((details) {
        final drag = _drag;
        if (drag != null) {
          setState(() => _drag = drag + details.primaryDelta!);
        }
      })
      ..onEnd = ((_) => _release(commit: true))
      ..onCancel = () => _release(commit: false);
  }

  void _release({required bool commit}) {
    if (_drag == null) {
      return;
    }
    final offset = _offset;
    setState(() => _drag = null);
    if (commit && offset != widget.offsetFrames) {
      widget.onChanged(offset);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: SeOffsetStrip.height,
      child: LayoutBuilder(
        builder: (context, constraints) {
          _pixelsPerFrame = _scaleFor(constraints.maxWidth);
          return OwningAxisGrip(
            axis: Axis.horizontal,
            configure: _configureDrag,
            child: MouseRegion(
              cursor: _editable
                  ? SystemMouseCursors.resizeLeftRight
                  : MouseCursor.defer,
              child: Stack(
                clipBehavior: Clip.hardEdge,
                children: _layers(
                  Theme.of(context),
                  window: widget.blockFrames * _pixelsPerFrame,
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  /// The block's paper as long as the block, the sound across the strip on
  /// the grid's screen over it ([SeOffsetBandsPainter]), and the offset.
  List<Widget> _layers(ThemeData theme, {required double window}) {
    final peaks = widget.peaks;
    return [
      Positioned(
        left: 0,
        top: 0,
        bottom: 0,
        width: window,
        child: SePaperSpan(
          axis: Axis.horizontal,
          frameCellExtent: _pixelsPerFrame,
          startFrame: 0,
        ),
      ),
      if (peaks != null)
        Positioned.fill(
          child: TimelineGridScreenHost(
            child: TimelineGridScreenSlot(
              child: CustomPaint(
                key: const ValueKey<String>('se-offset-bands'),
                painter: SeOffsetBandsPainter(
                  band: _band,
                  peaks: peaks,
                  frameRate: widget.frameRate,
                  pixelsPerFrame: _pixelsPerFrame,
                  leadingFrames: _offset,
                  blockFrames: widget.blockFrames,
                  cutOff: theme.colorScheme.onSurface.withValues(alpha: 0.2),
                  plays: timelineDrawingInkColor.withValues(alpha: 0.7),
                  devicePixelRatio: EffectiveDevicePixelRatio.of(context),
                ),
              ),
            ),
          ),
        ),
      Positioned(
        right: 4,
        top: 2,
        child: Text(
          formatAudioOffset(_offset),
          key: const ValueKey<String>('se-offset-value'),
          style: theme.textTheme.labelSmall,
        ),
      ),
    ];
  }
}

/// The sound across the strip from [leadingFrames] into its file: faint
/// where the block cuts it off, in the block's ink over that where it plays
/// — the timeline's own band, baked on the engine and laid on the grid's
/// screen ([EngineWaveBand]), or drawn here where no screen lays.
class SeOffsetBandsPainter extends CustomPainter with RepaintOnProps {
  const SeOffsetBandsPainter({
    required this.band,
    required this.peaks,
    required this.frameRate,
    required this.pixelsPerFrame,
    required this.leadingFrames,
    required this.blockFrames,
    required this.cutOff,
    required this.plays,
    required this.devicePixelRatio,
  });

  final EngineWaveBand band;
  final AudioPeaks peaks;
  final ProjectFrameRate frameRate;
  final double pixelsPerFrame;

  /// Frames of the file before the strip's start — the offset it shows.
  final int leadingFrames;
  final int blockFrames;
  final Color cutOff;
  final Color plays;
  final double devicePixelRatio;

  @override
  void paint(Canvas canvas, Size size) {
    final heard = peaks.durationFrames(frameRate) - leadingFrames;
    EngineWaveDrawing drawn(int audibleFrames, Color ink) => (
      peaks: peaks,
      views: engineWaveViewsOf(
        (
          peaks: peaks,
          startFrame: 0,
          audibleFrames: audibleFrames,
          leadingFrames: leadingFrames,
          gain: 1,
        ),
        on: (
          along: (frame) => frame * pixelsPerFrame,
          origin: 0,
          from: 0,
          to: (size.width / pixelsPerFrame).ceil(),
          axis: Axis.horizontal,
          across: size.height,
          devicePixelRatio: devicePixelRatio,
          frameRate: frameRate,
        ),
        ink: ink,
      ),
    );
    if (band.layOn(Offset.zero & size, [
      drawn(heard, cutOff),
      drawn(math.min(blockFrames, heard), plays),
    ], devicePixelRatio)) {
      return;
    }
    _waveform(cutOff).paint(canvas, size);
    canvas.save();
    canvas.clipRect(
      Offset.zero & Size(blockFrames * pixelsPerFrame, size.height),
    );
    _waveform(plays).paint(canvas, size);
    canvas.restore();
  }

  WaveformPainter _waveform(Color color) => WaveformPainter(
    peaks: peaks,
    frameRate: frameRate,
    pixelsPerFrame: pixelsPerFrame,
    color: color,
    devicePixelRatio: devicePixelRatio,
    leadingFrames: leadingFrames,
  );

  @override
  Object get props => (
    ByIdentity(band),
    ByIdentity(peaks),
    frameRate,
    pixelsPerFrame,
    leadingFrames,
    blockFrames,
    cutOff,
    plays,
    devicePixelRatio,
  );
}
