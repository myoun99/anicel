import 'dart:math' as math;

import 'package:flutter/gestures.dart' show DragStartBehavior;
import 'package:flutter/material.dart';

import '../../models/layer.dart';
import '../../models/layer_id.dart';
import '../../models/layer_kind.dart';
import '../../models/project_frame_rate.dart';
import '../../models/se_audio_spans.dart';
import '../../services/audio/audio_peaks_extractor.dart';
import '../audio/waveform_painter.dart';
import '../text/app_strings.dart';
import '../theme/app_theme.dart';
import 'property_lane_model.dart';
import 'timeline_cell_style.dart';
import 'timeline_frame_coordinate_policy.dart';
import 'timeline_grid_metrics.dart';
import 'axis_turn.dart';
import '../widgets/owning_axis_grip.dart';
import 'timeline_beat_lines.dart';

/// The SE audio lane: SE layers with sounds get ONE twirl-down lane — a
/// waveform editing strip where dragging a span's MIDDLE along the frame
/// axis slides the sound inside its block (the clip's offsetFrames trim)
/// and dragging its EDGES sets the fade in/out lengths. The context menu
/// edits the clip's gain. Shares the property-lane substrate (chevron,
/// display rows, label cell) but renders its own frame band; no key
/// semantics.

const String seAudioLaneId = 'se-audio';

/// Whether [lane] is the SE audio lane (the display-row builders dispatch
/// the frame band on this).
bool laneIsSeAudio(PropertyLaneRow lane) => lane.laneId == seAudioLaneId;

/// The span whose offset the audio lane's value field reads and edits:
/// the one covering [frameIndex] (AE semantics — the value column shows
/// the playhead's state), falling back to the layer's first span so the
/// field stays usable wherever the playhead sits.
SeAudioSpan? seAudioSpanForLaneValue(Layer layer, int frameIndex) {
  final spans = seAudioSpans(layer);
  if (spans.isEmpty) {
    return null;
  }
  for (final span in spans) {
    if (span.startFrame <= frameIndex && frameIndex < span.endFrameExclusive) {
      return span;
    }
  }
  return spans.first;
}

/// Parses the offset field's input: a frame count with optional sign and
/// trailing 'f' ('12', '12f', '-0f' → 12/12/0); negative offsets clamp to
/// 0 in the session (a sound cannot start before its block).
int? parseAudioOffsetInput(String input) {
  final match = RegExp(r'^-?\s*(\d+)\s*f?$').firstMatch(input.trim());
  return match == null ? null : int.parse(match.group(1)!);
}

String formatAudioOffset(int offsetFrames) => '${offsetFrames}f';

/// Value-scrub pixels per frame: 4px of drag per skipped frame (a finer
/// tool than the waveform's 1-cell-per-frame slide).
const double _offsetScrubPixelsPerFrame = 4;

/// The lanes an SE layer exposes: the audio lane while it carries sounds.
/// The label cell's value field shows/edits the playhead span's offset
/// trim AE-style (tap to type, drag to scrub; commits route through the
/// host into session.setAudioClipOffset — one undo).
List<PropertyLaneRow> seAudioLanesFor(Layer layer) {
  if (layer.kind != LayerKind.se || layer.audioClips.isEmpty) {
    return const [];
  }
  final hasSpans = seAudioSpans(layer).isNotEmpty;
  return [
    PropertyLaneRow(
      laneId: seAudioLaneId,
      // F-37: the word the storyboard's audio lane already read — the
      // timeline said 'Audio' in every language beside it.
      label: AppText.strings.tlAudioLane,
      keyedFrames: const {},
      showsKeyNavigator: false,
      valueLabel: !hasSpans
          ? null
          : (frameIndex) => formatAudioOffset(
              seAudioSpanForLaneValue(layer, frameIndex)!.clip.offsetFrames,
            ),
      scrubValue: !hasSpans
          ? null
          : (currentLabel, dragDelta) {
              final base = parseAudioOffsetInput(currentLabel);
              if (base == null) {
                return null;
              }
              final delta = (dragDelta.dx / _offsetScrubPixelsPerFrame).round();
              final next = base + delta;
              return formatAudioOffset(next < 0 ? 0 : next);
            },
    ),
  ];
}

/// Live drag-session hooks for the audio lane's slide — the comma-drag
/// idiom: [onBegin] snapshots the clip list, [onUpdate] applies the
/// absolute offset as a repo-direct preview (every waveform view repaints
/// from the model in real time), [onEnd] commits ONE undo step and
/// [onCancel] reverts. When absent the span falls back to its local
/// preview + [SeAudioLaneFrameRow.onSetClipOffset] commit.
class AudioOffsetDragCallbacks {
  const AudioOffsetDragCallbacks({
    required this.onBegin,
    required this.onUpdate,
    required this.onEnd,
    required this.onCancel,
  });

  final bool Function(LayerId layerId, int clipIndex) onBegin;
  final ValueChanged<int> onUpdate;
  final VoidCallback onEnd;
  final VoidCallback onCancel;
}

/// Everything the audio lane can ask the session to do, in one place.
///
/// These six travelled as six separate constructor parameters through four
/// widgets — the tab host to the panel, the panel to each grid, each grid
/// to the rows body — so every widget on the way declared all six fields
/// and forwarded all six, and adding a seventh meant editing five files
/// that do not otherwise care.
///
/// Bundling them is the idiom this file already uses for the drag session
/// ([AudioOffsetDragCallbacks]); it is only the AXIS that stops the three
/// timeline surfaces sharing their assembly, and a callback has no axis.
///
/// Null anywhere means "this surface cannot do that" — a read-only host
/// passes no bundle at all and every lane control disables itself, exactly
/// as it did when the six were null one by one.
class TimelineAudioLaneCallbacks {
  const TimelineAudioLaneCallbacks({
    this.onDropMediaAsset,
    this.onSetClipOffset,
    this.offsetDrag,
    this.onSetClipFades,
  });

  /// Links a media-browser asset to an SE block (drag-drop).
  final void Function(LayerId layerId, int blockStartFrame, String path)?
  onDropMediaAsset;

  /// Commits an audio-lane slide (the clip's offset trim).
  final void Function(LayerId layerId, int clipIndex, int offsetFrames)?
  onSetClipOffset;

  /// Live drag session for the slide (repo-direct preview + one undo).
  final AudioOffsetDragCallbacks? offsetDrag;

  /// Commits an audio-lane fade-handle drag.
  final void Function(
    LayerId layerId,
    int clipIndex,
    int fadeInFrames,
    int fadeOutFrames,
  )?
  onSetClipFades;
}

/// [AudioOffsetDragCallbacks] bound to one span (the row closes over the
/// layer/clip ids).
class _SpanLiveOffsetDrag {
  const _SpanLiveOffsetDrag({
    required this.begin,
    required this.update,
    required this.end,
    required this.cancel,
  });

  final bool Function() begin;
  final ValueChanged<int> update;
  final VoidCallback end;
  final VoidCallback cancel;
}

/// The audio lane's frame band: one editable waveform window per audible
/// span, same geometry contract as TimelineLaneFrameRow (leading spacer +
/// band + trailing spacer, both orientations).
class SeAudioLaneFrameRow extends StatelessWidget {
  const SeAudioLaneFrameRow({
    super.key,
    required this.layer,
    required this.frameStartIndex,
    required this.frameEndIndexExclusive,
    required this.leadingFrameSpacerWidth,
    required this.trailingFrameSpacerWidth,
    required this.metrics,
    required this.frameRate,
    this.audioPeaksFor,
    this.onSetClipOffset,
    this.offsetDrag,
    this.onSetClipFades,
    this.spillInLeadFrames,
    this.axis = Axis.horizontal,
    this.keyPrefix = 'timeline',
  });

  final Layer layer;
  final int frameStartIndex;
  final int frameEndIndexExclusive;
  final double leadingFrameSpacerWidth;
  final double trailingFrameSpacerWidth;
  final TimelineGridMetrics metrics;
  final ProjectFrameRate frameRate;

  /// How far into its sound the block at frame 0 already is, when the row
  /// spills in from an earlier cut (F-113) — null when nothing does.
  final int? spillInLeadFrames;
  final AudioPeaks? Function(String filePath)? audioPeaksFor;

  /// Commits a span's dragged offset (one undo); null makes the slide
  /// display-only.
  final void Function(int clipIndex, int offsetFrames)? onSetClipOffset;

  /// Live drag session for the slide (repo-direct preview — the SE row's
  /// waveform and the block visuals follow in real time); falls back to
  /// the local preview + [onSetClipOffset] when null.
  final AudioOffsetDragCallbacks? offsetDrag;

  /// Commits a span's dragged fade lengths (one undo per handle drag);
  /// null hides the fade handles.
  final void Function(int clipIndex, int fadeInFrames, int fadeOutFrames)?
  onSetClipFades;

  // R10 R3: clip GAIN, the volume ENVELOPE and the fade CURVE left with
  // the span's context menu, together with the two dialogs it opened.
  // Their session APIs (`setAudioClipGain`, `setAudioClipEnvelope`,
  // `setAudioClipFadeCurve`) stand ready for the audio button that will
  // host them. The fade-handle drags on the span itself are untouched.

  final Axis axis;
  final String keyPrefix;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final band = DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.washDown.withValues(alpha: 0.6),
        border: _bandSeam(colorScheme),
      ),
      child: Stack(clipBehavior: Clip.hardEdge, children: _spans()),
    );
    return _withSpacers(band);
  }

  double get _cellExtent => metrics.frameCellWidth;
  double get _crossExtent => metrics.layerRowHeight;
  double get _visibleExtent =>
      (frameEndIndexExclusive - frameStartIndex) * _cellExtent;

  /// The divider faces the NEXT lane: below in the timeline, to the right
  /// in the X-sheet — and the ROW SEAM comes from the law, exactly as the
  /// property lanes' band reads it (D43-2 d: 「fx행엔 그리드의 가로선 있는데
  /// … 통일로 추가해주고」). This lane used to write its own — outlineVariant
  /// at half width — the very drift that round named.
  Border _bandSeam(ColorScheme colorScheme) {
    final ink = timelineGridRowSeamInk(colorScheme);
    final seam = BorderSide(color: ink.color, width: ink.strokeWidth);
    final horizontal = axis == Axis.horizontal;
    return Border(
      bottom: horizontal ? seam : BorderSide.none,
      right: horizontal ? BorderSide.none : seam,
    );
  }

  /// One clip span per audio span inside the visible window.
  List<Widget> _spans() => [
    for (final span in seAudioSpans(
      layer,
      leadInAtStart: spillInLeadFrames ?? 0,
    ))
      if (_visible(span)) _spanWidget(span),
  ];

  bool _visible(SeAudioSpan span) =>
      span.endFrameExclusive > frameStartIndex &&
      span.startFrame < frameEndIndexExclusive;

  Widget _spanWidget(SeAudioSpan span) {
    final startOffset = frameVisibleX(
      frameIndex: span.startFrame,
      frameStartIndex: frameStartIndex,
      frameCellWidth: _cellExtent,
      leadingFrameSpacerWidth: 0,
    );
    final onSetOffset = onSetClipOffset;
    final drag = offsetDrag;
    final onSetFades = onSetClipFades;
    return placedAlong(
      axis,
      along: startOffset,
      across: 0,
      alongExtent: span.lengthFrames * _cellExtent,
      acrossExtent: _crossExtent,
      child: _SeAudioLaneSpan(
        key: ValueKey<String>(
          '$keyPrefix-audio-lane-span-${layer.id}-${span.clipIndex}'
          '-b${span.startFrame}',
        ),
        span: span,
        peaks: audioPeaksFor?.call(span.clip.filePath),
        frameRate: frameRate,
        frameCellExtent: _cellExtent,
        crossExtent: _crossExtent,
        axis: axis,
        onSetOffset: onSetOffset == null
            ? null
            : (offsetFrames) => onSetOffset(span.clipIndex, offsetFrames),
        liveOffsetDrag: drag == null
            ? null
            : _SpanLiveOffsetDrag(
                begin: () => drag.onBegin(layer.id, span.clipIndex),
                update: drag.onUpdate,
                end: drag.onEnd,
                cancel: drag.onCancel,
              ),
        onSetFades: onSetFades == null
            ? null
            : (fadeIn, fadeOut) => onSetFades(span.clipIndex, fadeIn, fadeOut),
      ),
    );
  }

  /// The band between its two spacers, along the axis.
  Widget _withSpacers(Widget band) => Flex(
    direction: axis,
    key: ValueKey<String>('$keyPrefix-lane-row-${layer.id}-$seAudioLaneId'),
    children: [
      sizedAlong(axis, along: leadingFrameSpacerWidth, across: _crossExtent),
      sizedAlong(
        axis,
        along: _visibleExtent,
        across: _crossExtent,
        child: band,
      ),
      sizedAlong(axis, along: trailingFrameSpacerWidth, across: _crossExtent),
    ],
  );
}

/// What a drag on the span edits, decided by where it started: the edges
/// own the fade handles, the middle slides the sound.
enum _SpanDragMode { slide, fadeIn, fadeOut }

/// One span's editing window: paper block + the trimmed waveform. Dragging
/// the middle along the frame axis slides the sound under the block —
/// moving the waveform left plays a LATER part of the file at the block
/// start (offset grows). Dragging within an edge zone drags that end's
/// fade length instead (the waveform's envelope previews live). Live
/// preview repaints only this span, release commits once.
class _SeAudioLaneSpan extends StatefulWidget {
  const _SeAudioLaneSpan({
    super.key,
    required this.span,
    required this.peaks,
    required this.frameRate,
    required this.frameCellExtent,
    required this.crossExtent,
    required this.axis,
    required this.onSetOffset,
    this.liveOffsetDrag,
    this.onSetFades,
  });

  final SeAudioSpan span;
  final AudioPeaks? peaks;
  final ProjectFrameRate frameRate;
  final double frameCellExtent;

  /// The lane's own height across the frame axis — the block corner law's
  /// other side.
  final double crossExtent;
  final Axis axis;
  final ValueChanged<int>? onSetOffset;
  final _SpanLiveOffsetDrag? liveOffsetDrag;
  final void Function(int fadeInFrames, int fadeOutFrames)? onSetFades;

  @override
  State<_SeAudioLaneSpan> createState() => _SeAudioLaneSpanState();
}

class _SeAudioLaneSpanState extends State<_SeAudioLaneSpan> {
  /// Pointer travel from an edge zone this wide grabs a fade handle
  /// instead of sliding the sound.
  static const double _fadeHandleExtent = 12;

  double _dragDelta = 0;
  bool _dragging = false;
  _SpanDragMode _mode = _SpanDragMode.slide;

  /// The offset at pointer-down: the live drag path updates the MODEL per
  /// move, so the preview math must not re-read the drifting clip value.
  int _dragBaseOffset = 0;

  /// Whether the current slide rides the session drag (repo-direct live
  /// preview, one undo on release).
  bool _liveActive = false;

  int get _fileFrames =>
      widget.peaks?.durationFrames(widget.frameRate) ?? (1 << 20);

  int get _deltaFrames => (_dragDelta / widget.frameCellExtent).round();

  /// The offset the current drag previews: dragging the waveform toward
  /// the span start (negative pixels) skips further into the file.
  int get _previewOffset {
    final base = _dragging ? _dragBaseOffset : widget.span.clip.offsetFrames;
    return (base - _deltaFrames).clamp(0, math.max(0, _fileFrames - 1));
  }

  int get _previewFadeIn {
    final base = widget.span.clip.fadeInFrames;
    if (!_dragging || _mode != _SpanDragMode.fadeIn) {
      return base;
    }
    return (base + _deltaFrames).clamp(0, widget.span.lengthFrames);
  }

  int get _previewFadeOut {
    final base = widget.span.clip.fadeOutFrames;
    if (!_dragging || _mode != _SpanDragMode.fadeOut) {
      return base;
    }
    return (base - _deltaFrames).clamp(0, widget.span.lengthFrames);
  }

  bool get _editable =>
      (widget.onSetOffset != null ||
          widget.liveOffsetDrag != null ||
          widget.onSetFades != null) &&
      widget.peaks != null;

  _SpanDragMode _zoneAt(Offset localPosition) {
    if (widget.onSetFades == null) {
      return _SpanDragMode.slide;
    }
    final box = context.findRenderObject() as RenderBox?;
    if (box == null) {
      return _SpanDragMode.slide;
    }
    final horizontal = widget.axis == Axis.horizontal;
    final main = horizontal ? localPosition.dx : localPosition.dy;
    final extent = horizontal ? box.size.width : box.size.height;
    // Tiny spans stay slide-only — three zones need room to coexist.
    if (extent <= _fadeHandleExtent * 3) {
      return _SpanDragMode.slide;
    }
    if (main <= _fadeHandleExtent) {
      return _SpanDragMode.fadeIn;
    }
    if (main >= extent - _fadeHandleExtent) {
      return _SpanDragMode.fadeOut;
    }
    return _SpanDragMode.slide;
  }

  void _startDrag(Offset localPosition) {
    setState(() {
      _mode = _zoneAt(localPosition);
      _dragging = true;
      _dragDelta = 0;
      _dragBaseOffset = widget.span.clip.offsetFrames;
    });
    if (_mode == _SpanDragMode.slide && widget.liveOffsetDrag != null) {
      _liveActive = widget.liveOffsetDrag!.begin();
    }
  }

  void _updateDrag(double delta) {
    setState(() => _dragDelta += delta);
    if (_liveActive && _mode == _SpanDragMode.slide) {
      widget.liveOffsetDrag!.update(_previewOffset);
    }
  }

  void _endDrag() {
    final mode = _mode;
    final live = _liveActive;
    final offset = _previewOffset;
    final fadeIn = _previewFadeIn;
    final fadeOut = _previewFadeOut;
    setState(() {
      _dragging = false;
      _dragDelta = 0;
      _mode = _SpanDragMode.slide;
      _liveActive = false;
    });
    switch (mode) {
      case _SpanDragMode.slide:
        if (live) {
          widget.liveOffsetDrag!.end();
        } else if (offset != widget.span.clip.offsetFrames) {
          widget.onSetOffset?.call(offset);
        }
      case _SpanDragMode.fadeIn:
      case _SpanDragMode.fadeOut:
        if (fadeIn != widget.span.clip.fadeInFrames ||
            fadeOut != widget.span.clip.fadeOutFrames) {
          widget.onSetFades?.call(fadeIn, fadeOut);
        }
    }
  }

  void _cancelDrag() {
    final live = _liveActive;
    setState(() {
      _dragging = false;
      _dragDelta = 0;
      _mode = _SpanDragMode.slide;
      _liveActive = false;
    });
    if (live) {
      widget.liveOffsetDrag!.cancel();
    }
  }

  @override
  Widget build(BuildContext context) {
    final peaks = widget.peaks;
    final offset = _dragging && _mode == _SpanDragMode.slide
        ? _previewOffset
        : widget.span.clip.offsetFrames;
    final fadeIn = _previewFadeIn;
    final fadeOut = _previewFadeOut;
    final editable = _editable;
    final showFadeMarks = widget.onSetFades != null && peaks != null;
    // 🚨A DRAG FROM THE SOUND IS THE SOUND'S (F-163 재발, 유저 2026-09-23:
    // 「버튼은 무조건 강한클레임이라는거 감안해서 같은법 적용해줘」). Sliding
    // the sound is this span's verb, so it wears the grips' own pair
    // ([OwningAxisGrip]). ↩️A plain one-axis drag: a pull across the lane
    // moved 0 along it and the timeline's scroller walked over.
    //
    // A span that cannot be edited still HOLDS the press — the handlers stay
    // mounted and do nothing — because a dead control is not a scroll either
    // (`ControlPressClaim.onPressed`: 「a press on a dead button is still not
    // a scroll」). A recogniser with no handlers is never offered the pointer.
    return OwningAxisGrip(
      axis: widget.axis,
      configure: (recognizer) => recognizer
        // .down: the drag measures from the pointer-down origin, so the
        // recognizer's slop never eats into the slid amount.
        ..dragStartBehavior = DragStartBehavior.down
        ..onStart = ((details) {
          if (editable) {
            _startDrag(details.localPosition);
          }
        })
        ..onUpdate = ((details) {
          if (editable) {
            _updateDrag(details.primaryDelta!);
          }
        })
        ..onEnd = ((_) {
          if (editable) {
            _endDrag();
          }
        })
        ..onCancel = () {
          if (editable) {
            _cancelDrag();
          }
        },
      child: MouseRegion(
        cursor: editable ? _resizeCursor : MouseCursor.defer,
        child: Stack(
          clipBehavior: Clip.hardEdge,
          children: [
            _backdrop(),
            ?_waveform(peaks, offset, fadeIn: fadeIn, fadeOut: fadeOut),
            // Fade ramp ends: accent ticks the handle drags travel with.
            if (showFadeMarks && fadeIn > 0) _fadeMark(fadeIn, leading: true),
            if (showFadeMarks && fadeOut > 0)
              _fadeMark(fadeOut, leading: false),
            ?_dragBadge(offset, fadeIn: fadeIn, fadeOut: fadeOut),
          ],
        ),
      ),
    );
  }

  MouseCursor get _resizeCursor => widget.axis == Axis.horizontal
      ? SystemMouseCursors.resizeLeftRight
      : SystemMouseCursors.resizeUpDown;

  /// The block's paper backdrop so the lane reads as the block's own
  /// editing strip — and so it wears the block's own corner, the one law
  /// ([timelineBlockCornerRadiusAt]); a hand-typed 4 had it rounder or
  /// squarer than the block above it depending on the zoom.
  Widget _backdrop() => Positioned.fill(
    child: DecoratedBox(
      decoration: BoxDecoration(
        color: timelineDrawingHeldColor.withValues(alpha: 0.6),
        borderRadius: BorderRadius.all(
          timelineBlockCornerRadiusAt(
            cellExtent: widget.frameCellExtent,
            crossExtent: widget.crossExtent,
          ),
        ),
        border: Border.all(color: timelineDrawingStartBorderColor),
      ),
    ),
  );

  Widget? _waveform(
    AudioPeaks? peaks,
    int offset, {
    required int fadeIn,
    required int fadeOut,
  }) {
    if (peaks == null) return null;
    return Positioned.fill(
      child: IgnorePointer(
        child: CustomPaint(
          painter: WaveformPainter(
            peaks: peaks,
            frameRate: widget.frameRate,
            pixelsPerFrame: widget.frameCellExtent,
            // Editing strip: stronger ink than the row's underlay.
            color: timelineDrawingInkColor.withValues(alpha: 0.45),
            axis: widget.axis,
            // A spill-in's lead rides on top of the trim (F-113): the strip
            // starts where the sound already is when the cut begins.
            leadingFrames: offset + widget.span.leadInFrames,
            gain: widget.span.clip.gain,
            fadeInFrames: fadeIn,
            fadeOutFrames: fadeOut,
          ),
        ),
      ),
    );
  }

  /// An accent tick [frames] in from the clip's start (leading) or its end.
  Widget _fadeMark(int frames, {required bool leading}) => stripAlong(
    widget.axis,
    along: frames * widget.frameCellExtent - 1,
    alongExtent: 2,
    fromEnd: !leading,
    child: IgnorePointer(
      child: ColoredBox(color: AppColors.accent.withValues(alpha: 0.9)),
    ),
  );

  String _dragHint(int offset, {required int fadeIn, required int fadeOut}) =>
      switch (_mode) {
        _SpanDragMode.slide => '-${offset}f',
        _SpanDragMode.fadeIn => 'in ${fadeIn}f',
        _SpanDragMode.fadeOut => 'out ${fadeOut}f',
      };

  Widget? _dragBadge(int offset, {required int fadeIn, required int fadeOut}) {
    if (!_dragging) return null;
    return Positioned(
      left: 4,
      top: 2,
      child: IgnorePointer(
        child: DecoratedBox(
          decoration: ShapeDecoration(
            color: AppColors.accent.withValues(alpha: 0.85),
            shape: AppShapes.container(3),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
            child: Text(
              _dragHint(offset, fadeIn: fadeIn, fadeOut: fadeOut),
              style: const TextStyle(fontSize: 9, color: Colors.black),
            ),
          ),
        ),
      ),
    );
  }
}
