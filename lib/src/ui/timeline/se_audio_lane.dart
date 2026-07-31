import 'dart:math' as math;

import 'package:flutter/gestures.dart' show DragStartBehavior;
import 'package:flutter/material.dart';

import '../../models/app_language.dart' show AppLanguage;
import '../../models/audio_clip.dart' show AudioFadeCurve, AudioVolumeKey;
import '../../models/layer.dart';
import '../../models/layer_id.dart';
import '../../models/layer_kind.dart';
import '../../models/project_frame_rate.dart';
import '../../models/se_audio_spans.dart';
import '../../services/audio/audio_peaks_extractor.dart';
import '../audio/waveform_painter.dart';
import '../text/app_strings.dart';
import '../theme/app_theme.dart';
import '../widgets/field_slider.dart';
import 'property_lane_model.dart';
import 'timeline_cell_style.dart';
import 'timeline_frame_coordinate_policy.dart';
import 'timeline_grid_metrics.dart';
import '../widgets/app_window.dart';

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
      label: 'Audio',
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
    final cellExtent = metrics.frameCellWidth;
    final crossExtent = metrics.layerRowHeight;
    final visibleExtent =
        (frameEndIndexExclusive - frameStartIndex) * cellExtent;
    final horizontal = axis == Axis.horizontal;

    final spans = <Widget>[];
    for (final span in seAudioSpans(layer)) {
      if (span.endFrameExclusive <= frameStartIndex ||
          span.startFrame >= frameEndIndexExclusive) {
        continue;
      }
      final startOffset = frameVisibleX(
        frameIndex: span.startFrame,
        frameStartIndex: frameStartIndex,
        frameCellWidth: cellExtent,
        leadingFrameSpacerWidth: 0,
      );
      final mainExtent = span.lengthFrames * cellExtent;
      final content = _SeAudioLaneSpan(
        key: ValueKey<String>(
          '$keyPrefix-audio-lane-span-${layer.id}-${span.clipIndex}'
          '-b${span.startFrame}',
        ),
        span: span,
        peaks: audioPeaksFor?.call(span.clip.filePath),
        frameRate: frameRate,
        frameCellExtent: cellExtent,
        axis: axis,
        onSetOffset: onSetClipOffset == null
            ? null
            : (offsetFrames) => onSetClipOffset!(span.clipIndex, offsetFrames),
        liveOffsetDrag: offsetDrag == null
            ? null
            : _SpanLiveOffsetDrag(
                begin: () => offsetDrag!.onBegin(layer.id, span.clipIndex),
                update: offsetDrag!.onUpdate,
                end: offsetDrag!.onEnd,
                cancel: offsetDrag!.onCancel,
              ),
        onSetFades: onSetClipFades == null
            ? null
            : (fadeIn, fadeOut) =>
                  onSetClipFades!(span.clipIndex, fadeIn, fadeOut),
      );
      spans.add(
        horizontal
            ? Positioned(
                left: startOffset,
                top: 0,
                width: mainExtent,
                height: crossExtent,
                child: content,
              )
            : Positioned(
                top: startOffset,
                left: 0,
                height: mainExtent,
                width: crossExtent,
                child: content,
              ),
      );
    }

    final band = DecoratedBox(
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow.withValues(alpha: 0.6),
        border: horizontal
            ? Border(
                bottom: BorderSide(
                  color: colorScheme.outlineVariant,
                  width: 0.5,
                ),
              )
            : Border(
                right: BorderSide(
                  color: colorScheme.outlineVariant,
                  width: 0.5,
                ),
              ),
      ),
      child: Stack(clipBehavior: Clip.hardEdge, children: spans),
    );

    if (horizontal) {
      return Row(
        key: ValueKey<String>('$keyPrefix-lane-row-${layer.id}-$seAudioLaneId'),
        children: [
          SizedBox(width: leadingFrameSpacerWidth, height: crossExtent),
          SizedBox(width: visibleExtent, height: crossExtent, child: band),
          SizedBox(width: trailingFrameSpacerWidth, height: crossExtent),
        ],
      );
    }
    return Column(
      key: ValueKey<String>('$keyPrefix-lane-row-${layer.id}-$seAudioLaneId'),
      children: [
        SizedBox(width: crossExtent, height: leadingFrameSpacerWidth),
        SizedBox(width: crossExtent, height: visibleExtent, child: band),
        SizedBox(width: crossExtent, height: trailingFrameSpacerWidth),
      ],
    );
  }
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
    required this.axis,
    required this.onSetOffset,
    this.liveOffsetDrag,
    this.onSetFades,
  });

  final SeAudioSpan span;
  final AudioPeaks? peaks;
  final ProjectFrameRate frameRate;
  final double frameCellExtent;
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
    final horizontal = widget.axis == Axis.horizontal;
    final peaks = widget.peaks;
    final offset = _dragging && _mode == _SpanDragMode.slide
        ? _previewOffset
        : widget.span.clip.offsetFrames;
    final fadeIn = _previewFadeIn;
    final fadeOut = _previewFadeOut;
    final editable = _editable;
    final showFadeMarks = widget.onSetFades != null && peaks != null;

    String dragHint() => switch (_mode) {
      _SpanDragMode.slide => '-${offset}f',
      _SpanDragMode.fadeIn => 'in ${fadeIn}f',
      _SpanDragMode.fadeOut => 'out ${fadeOut}f',
    };

    Positioned fadeMark(int frames, {required bool leading}) {
      final along = frames * widget.frameCellExtent;
      final mark = IgnorePointer(
        child: ColoredBox(color: AppColors.accent.withValues(alpha: 0.9)),
      );
      if (horizontal) {
        return leading
            ? Positioned(
                left: along - 1,
                top: 0,
                bottom: 0,
                width: 2,
                child: mark,
              )
            : Positioned(
                right: along - 1,
                top: 0,
                bottom: 0,
                width: 2,
                child: mark,
              );
      }
      return leading
          ? Positioned(
              top: along - 1,
              left: 0,
              right: 0,
              height: 2,
              child: mark,
            )
          : Positioned(
              bottom: along - 1,
              left: 0,
              right: 0,
              height: 2,
              child: mark,
            );
    }

    final children = <Widget>[
      // The block's paper backdrop so the lane reads as the block's own
      // editing strip.
      Positioned.fill(
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: timelineDrawingHeldColor.withValues(alpha: 0.6),
            borderRadius: const BorderRadius.all(Radius.circular(4)),
            border: Border.all(color: timelineDrawingStartBorderColor),
          ),
        ),
      ),
      if (peaks != null)
        Positioned.fill(
          child: IgnorePointer(
            child: CustomPaint(
              painter: WaveformPainter(
                peaks: peaks,
                frameRate: widget.frameRate,
                pixelsPerFrame: widget.frameCellExtent,
                // Editing strip: stronger ink than the row's underlay.
                color: timelineDrawingInkColor.withValues(alpha: 0.45),
                axis: widget.axis,
                leadingFrames: offset,
                gain: widget.span.clip.gain,
                fadeInFrames: fadeIn,
                fadeOutFrames: fadeOut,
              ),
            ),
          ),
        ),
      // Fade ramp ends: accent ticks the handle drags travel with.
      if (showFadeMarks && fadeIn > 0) fadeMark(fadeIn, leading: true),
      if (showFadeMarks && fadeOut > 0) fadeMark(fadeOut, leading: false),
      if (_dragging)
        Positioned(
          left: 4,
          top: 2,
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: AppColors.accent.withValues(alpha: 0.85),
                borderRadius: BorderRadius.circular(3),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                child: Text(
                  dragHint(),
                  style: const TextStyle(fontSize: 9, color: Colors.black),
                ),
              ),
            ),
          ),
        ),
    ];

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      // .down: the drag measures from the pointer-down origin, so the
      // recognizer's slop never eats into the slid amount.
      dragStartBehavior: DragStartBehavior.down,
      onHorizontalDragStart: editable && horizontal
          ? (details) => _startDrag(details.localPosition)
          : null,
      onHorizontalDragUpdate: editable && horizontal
          ? (details) => _updateDrag(details.delta.dx)
          : null,
      onHorizontalDragEnd: editable && horizontal ? (_) => _endDrag() : null,
      onHorizontalDragCancel: editable && horizontal ? _cancelDrag : null,
      onVerticalDragStart: editable && !horizontal
          ? (details) => _startDrag(details.localPosition)
          : null,
      onVerticalDragUpdate: editable && !horizontal
          ? (details) => _updateDrag(details.delta.dy)
          : null,
      onVerticalDragEnd: editable && !horizontal ? (_) => _endDrag() : null,
      onVerticalDragCancel: editable && !horizontal ? _cancelDrag : null,
      child: MouseRegion(
        cursor: editable
            ? (horizontal
                  ? SystemMouseCursors.resizeLeftRight
                  : SystemMouseCursors.resizeUpDown)
            : MouseCursor.defer,
        child: Stack(clipBehavior: Clip.hardEdge, children: children),
      ),
    );
  }
}

