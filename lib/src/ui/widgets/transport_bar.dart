import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'app_icon_button.dart';
import 'drag_value_label.dart';

/// THE transport bar: a scrub track with IN/OUT handles, the player
/// buttons, and the two range fields at the ends.
///
/// One widget for three surfaces that were all going to want it — the
/// import window's preview, the media viewer panel, and the export
/// window's. Sequences, PDFs and GIFs are its first customers; a video
/// arrives the day there is a decoder, and this bar does not change when it
/// does, because it never learns what is behind the frames. It takes a
/// COUNT and an index and reports what the hand did.
///
/// A still image mounts it too, with one frame: the bar sits there inert
/// rather than appearing and disappearing under the picture.
class TransportBar extends StatelessWidget {
  const TransportBar({
    super.key,
    required this.frameCount,
    required this.currentFrame,
    required this.inFrame,
    required this.outFrame,
    required this.playing,
    required this.onSeek,
    required this.onPlayPause,
    required this.onRangeChanged,
    this.looping = false,
    this.onLoopingChanged,
    this.compact = false,
  });

  /// How many frames the source has. One means a still: every control
  /// still renders, and none of them can go anywhere.
  final int frameCount;

  /// All three are ZERO-based indices. The readout adds one, because a
  /// person counts pages and frames from one.
  final int currentFrame;
  final int inFrame;
  final int outFrame;

  final bool playing;
  final ValueChanged<int> onSeek;
  final VoidCallback onPlayPause;

  /// A new (in, out) pair, already ordered and inside the source.
  final void Function(int inFrame, int outFrame) onRangeChanged;

  final bool looping;
  final ValueChanged<bool>? onLoopingChanged;

  /// The narrow layout: the same controls, fewer of them. Used where the
  /// window has been dragged down to a tablet's width.
  final bool compact;

  int get _lastFrame => frameCount <= 1 ? 0 : frameCount - 1;

  int _clamp(int frame) =>
      frame < 0 ? 0 : (frame > _lastFrame ? _lastFrame : frame);

  @override
  Widget build(BuildContext context) {
    final digits = '$frameCount'.length;
    String label(int frame) => '${frame + 1}'.padLeft(digits, '0');
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TransportTrack(
          frameCount: frameCount,
          currentFrame: currentFrame,
          inFrame: inFrame,
          outFrame: outFrame,
          onSeek: (frame) => onSeek(_clamp(frame)),
          onRangeChanged: onRangeChanged,
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            SizedBox(
              width: compact ? 64 : 84,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('In', style: _dimStyle(context)),
                    const SizedBox(width: 4),
                    DragValueLabel(
                      keyValue: 'transport-in',
                      text: label(inFrame),
                      width: compact ? 34 : 44,
                      unitsPerPixel: 1,
                      onDragDelta: (delta) => _setIn(inFrame + delta.round()),
                      onEditSubmit: (text) {
                        final typed = int.tryParse(text.trim());
                        if (typed != null) {
                          _setIn(typed - 1);
                        }
                      },
                    ),
                  ],
                ),
              ),
            ),
            // The buttons are CENTRED in the bar, and squeezing the window
            // must not throw an overflow at the one moment the user is
            // dragging its edge: below the width they need, they scale
            // instead of overrunning.
            Expanded(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    AppIconButton(
                      keyValue: 'transport-to-in',
                      tooltip: 'In',
                      icon: const Icon(Icons.first_page),
                      size: AppIconButtonSize.strip,
                      onPressed: () => onSeek(inFrame),
                    ),
                    if (!compact)
                      AppIconButton(
                        keyValue: 'transport-step-back',
                        tooltip: 'Previous frame',
                        icon: const Icon(Icons.chevron_left),
                        size: AppIconButtonSize.strip,
                        onPressed: () => onSeek(_clamp(currentFrame - 1)),
                      ),
                    AppIconButton(
                      keyValue: 'transport-play',
                      tooltip: playing ? 'Pause' : 'Play',
                      icon: Icon(playing ? Icons.pause : Icons.play_arrow),
                      size: AppIconButtonSize.bar,
                      isSelected: playing,
                      onPressed: onPlayPause,
                    ),
                    if (!compact)
                      AppIconButton(
                        keyValue: 'transport-step-forward',
                        tooltip: 'Next frame',
                        icon: const Icon(Icons.chevron_right),
                        size: AppIconButtonSize.strip,
                        onPressed: () => onSeek(_clamp(currentFrame + 1)),
                      ),
                    AppIconButton(
                      keyValue: 'transport-to-out',
                      tooltip: 'Out',
                      icon: const Icon(Icons.last_page),
                      size: AppIconButtonSize.strip,
                      onPressed: () => onSeek(outFrame),
                    ),
                    if (onLoopingChanged != null)
                      AppIconButton(
                        keyValue: 'transport-loop',
                        tooltip: 'Loop',
                        icon: const Icon(Icons.repeat),
                        size: AppIconButtonSize.strip,
                        isSelected: looping,
                        onPressed: () => onLoopingChanged!(!looping),
                      ),
                  ],
                ),
              ),
            ),
            SizedBox(
              width: compact ? 64 : 84,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerRight,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    DragValueLabel(
                      keyValue: 'transport-out',
                      text: label(outFrame),
                      width: compact ? 34 : 44,
                      unitsPerPixel: 1,
                      onDragDelta: (delta) => _setOut(outFrame + delta.round()),
                      onEditSubmit: (text) {
                        final typed = int.tryParse(text.trim());
                        if (typed != null) {
                          _setOut(typed - 1);
                        }
                      },
                    ),
                    const SizedBox(width: 4),
                    Text('Out', style: _dimStyle(context)),
                  ],
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 2),
        Center(
          child: Text(
            '${label(currentFrame)} / $frameCount',
            key: const ValueKey<String>('transport-position'),
            style: _dimStyle(context),
          ),
        ),
      ],
    );
  }

  /// IN never passes OUT, and a typed value that would is pulled back to
  /// it rather than refused: the field's contract everywhere in this app is
  /// that it takes what you typed and lands on the nearest legal value.
  void _setIn(int frame) {
    final next = _clamp(frame);
    onRangeChanged(next > outFrame ? outFrame : next, outFrame);
  }

  void _setOut(int frame) {
    final next = _clamp(frame);
    onRangeChanged(inFrame, next < inFrame ? inFrame : next);
  }

  TextStyle? _dimStyle(BuildContext context) => Theme.of(
    context,
  ).textTheme.labelSmall?.copyWith(color: AppColors.textDim);
}

/// The scrub track: the range between the handles is lit, the playhead is a
/// hairline, and the handles are grabbed by proximity.
///
/// Pointer rules, in the order they are tested: a press within
/// [_handleGrabPixels] of a handle takes that handle for the whole drag;
/// anything else seeks, and keeps seeking while the finger moves. A tablet
/// hand is not precise, so the grab radius is generous and the handles win
/// ties — a mis-seek is undone by seeking again, a mis-dragged IN edits the
/// import.
class TransportTrack extends StatefulWidget {
  const TransportTrack({
    super.key,
    required this.frameCount,
    required this.currentFrame,
    required this.inFrame,
    required this.outFrame,
    required this.onSeek,
    required this.onRangeChanged,
    this.height = 16,
  });

  final int frameCount;
  final int currentFrame;
  final int inFrame;
  final int outFrame;
  final ValueChanged<int> onSeek;
  final void Function(int inFrame, int outFrame) onRangeChanged;
  final double height;

  @override
  State<TransportTrack> createState() => _TransportTrackState();
}

enum _Grab { seek, inHandle, outHandle }

const double _handleGrabPixels = 10;

class _TransportTrackState extends State<TransportTrack> {
  _Grab _grab = _Grab.seek;
  double _width = 0;

  int get _lastFrame => widget.frameCount <= 1 ? 0 : widget.frameCount - 1;

  double _xFor(int frame) =>
      _lastFrame == 0 ? 0 : (frame / _lastFrame) * _width;

  int _frameFor(double x) {
    if (_width <= 0 || _lastFrame == 0) {
      return 0;
    }
    final frame = (x / _width * _lastFrame).round();
    return frame < 0 ? 0 : (frame > _lastFrame ? _lastFrame : frame);
  }

  void _begin(Offset local) {
    final inX = _xFor(widget.inFrame);
    final outX = _xFor(widget.outFrame);
    final toIn = (local.dx - inX).abs();
    final toOut = (local.dx - outX).abs();
    if (toIn <= _handleGrabPixels && toIn <= toOut) {
      _grab = _Grab.inHandle;
    } else if (toOut <= _handleGrabPixels) {
      _grab = _Grab.outHandle;
    } else {
      _grab = _Grab.seek;
    }
    _apply(local);
  }

  void _apply(Offset local) {
    final frame = _frameFor(local.dx);
    switch (_grab) {
      case _Grab.seek:
        widget.onSeek(frame);
      case _Grab.inHandle:
        widget.onRangeChanged(
          frame > widget.outFrame ? widget.outFrame : frame,
          widget.outFrame,
        );
      case _Grab.outHandle:
        widget.onRangeChanged(
          widget.inFrame,
          frame < widget.inFrame ? widget.inFrame : frame,
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        _width = constraints.maxWidth;
        // A Listener, not a GestureDetector: a scrub track has to move on
        // the press itself. A drag recognizer would hold the first ~18px
        // of every scrub waiting to see whether this is a drag, and the
        // handle you grabbed would sit still while your finger left it.
        return Listener(
          key: const ValueKey<String>('transport-track'),
          behavior: HitTestBehavior.opaque,
          onPointerDown: (event) => _begin(event.localPosition),
          onPointerMove: (event) => _apply(event.localPosition),
          child: CustomPaint(
            size: Size(constraints.maxWidth, widget.height),
            painter: _TrackPainter(
              position: _lastFrame == 0 ? 0 : widget.currentFrame / _lastFrame,
              rangeStart: _lastFrame == 0 ? 0 : widget.inFrame / _lastFrame,
              rangeEnd: _lastFrame == 0 ? 1 : widget.outFrame / _lastFrame,
            ),
            child: SizedBox(height: widget.height),
          ),
        );
      },
    );
  }
}

class _TrackPainter extends CustomPainter {
  const _TrackPainter({
    required this.position,
    required this.rangeStart,
    required this.rangeEnd,
  });

  final double position;
  final double rangeStart;
  final double rangeEnd;

  @override
  void paint(Canvas canvas, Size size) {
    final track = Rect.fromLTWH(0, 0, size.width, size.height);
    canvas.drawRect(track, Paint()..color = AppColors.washUp);
    canvas.drawRect(
      track.deflate(0.5),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = AppColors.hairline,
    );
    final startX = rangeStart * size.width;
    final endX = rangeEnd * size.width;
    canvas.drawRect(
      Rect.fromLTRB(startX, 0, endX, size.height),
      Paint()..color = AppColors.accent.withValues(alpha: 0.18),
    );
    final handle = Paint()..color = AppColors.accent;
    canvas.drawRect(Rect.fromLTWH(startX - 1, -2, 3, size.height + 4), handle);
    canvas.drawRect(Rect.fromLTWH(endX - 2, -2, 3, size.height + 4), handle);
    final headX = position * size.width;
    canvas.drawRect(
      Rect.fromLTWH(headX, -3, 1, size.height + 6),
      Paint()..color = AppColors.text,
    );
  }

  @override
  bool shouldRepaint(_TrackPainter old) =>
      old.position != position ||
      old.rangeStart != rangeStart ||
      old.rangeEnd != rangeEnd;
}
