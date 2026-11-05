import 'dart:math' as math;

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';

import '../../models/project_frame_rate.dart';
import '../../services/audio/audio_peaks_extractor.dart';
import '../audio/waveform_painter.dart';
import '../brush/canvas_stage.dart';
import '../repaint_props.dart';
import '../text/laid_out_glyph.dart';
import '../theme/app_theme.dart';
import '../timeline/frame_ruler_view.dart';
import '../timeline/memo_token.dart' show ByIdentity;
import '../timeline/timeline_beat_lines.dart'
    show
        TimelineFrameMark,
        timelineFrameLineStep,
        timelineFrameMarkAt,
        timelineMarkGap;
import '../timeline/timeline_frame_ruler_painter.dart'
    show timelineFramePlaceLabel, timelineRulerPlayheadInk, timelineSecondsMark;
import '../timeline/timeline_glyph_cache.dart' show timelineSecondsType;
import '../timeline/timeline_ruler_playhead_writing.dart'
    show timelineMarkStandsDownFor;
import '../timeline/timeline_second.dart'
    show timelineSecondFrames, timelineSecondsHolding;
import '../widgets/owning_axis_grip.dart';
import '../widgets/transport_bar.dart';
import 'audio_viewer_document.dart';

/// A sound on a viewer's stage — its FACE: the whole file in the upper row,
/// and in the lower the stretch round the playhead at the view's zoom; over
/// each a ruler of its seconds, and through both the playhead's line.
///
/// 🗣️F-71 (유저, 09-11 카드): 「오디오를 뷰어에서 재생시 파형이 진짜 뒤 흰
/// 용지 위에 래스터화시킨거처럼 보이는데, 그게아니라 진짜 미디어
/// 플레이어처럼 해줬으면함」 — and F-71-Q7 (11-05) 「위 전체 · 아래 확대
/// (다빈치식)」: the lower row's zoom is the pill's, and it follows the
/// playhead, so nothing scrolls. The drawing it was answered on:
/// https://claude.ai/artifact/5eXirxvhBKyt9gssrMKztz
/// ↩️A sound was a PAGE — its band rasterised onto paper and zoomed as a
/// picture is, under a playhead painted over it.
///
/// It counts what the transport under it counts — [frameCount] frames,
/// [framesPerSecond] to a second, the playhead at [currentFrame] — and its
/// upper row spans them as the seek track does, end to end, so the two
/// lines stand at one x where the face stands as wide as the track
/// ([insetFromTheStage]). A press or a drag moves the playhead as the track
/// does ([onSeek]), measured against the row it landed in as that row stood
/// at the press: the lower row follows the playhead, and would run away
/// under the hand (「누른 순간의 줄 · 창으로 잰다」).
///
/// ⛔The playhead's line stands whenever the face does, not only while it
/// plays: a line that appears on the first press is UI that pops into
/// existence, and where the playhead STANDS is what tells you where a
/// second press would resume from.
///
/// It stands on its panel's stage ([CanvasStage]), in from it as far as
/// [insetFromTheStage] on every side — or fills its parent, outside one.
class SoundFace extends StatefulWidget {
  const SoundFace({
    super.key,
    required this.keyValue,
    required this.peaks,
    required this.frameRate,
    required this.frameCount,
    required this.framesPerSecond,
    required this.rulerView,
    required this.currentFrame,
    required this.zoom,
    required this.onSeek,
    this.kept,
  });

  final String keyValue;
  final AudioPeaks peaks;

  /// The rate [frameCount] is counted in — what the band is laid along.
  final ProjectFrameRate frameRate;

  /// The transport's count ([TransportBar.frameCount]).
  final int frameCount;

  /// How many frames make a second here ([TransportBar.framesPerSecond]).
  final int framesPerSecond;

  /// How the timeline's rulers count, which the playhead's writing follows
  /// ([TransportBar.rulerView]).
  final ValueListenable<FrameRulerView> rulerView;

  /// Where the playhead stands, from 0 ([TransportBar.currentFrame]).
  final int currentFrame;

  /// The lower row's zoom — the view's, as the pill shows it: at 1 a
  /// second is [AudioViewerDocument.pixelsPerSecondAtOne] wide.
  final double zoom;

  /// Null while nothing may move the playhead: the face stands, and a press
  /// on it is still its own.
  final ValueChanged<int>? onSeek;

  /// The span IN/OUT keep, or null where none is kept
  /// ([TransportTrack.kept]) — washed as the track washes it.
  final ({int first, int last})? kept;

  /// How far in from the stage's sides the face stands: as far as the seek
  /// track stands in from the transport's ([TransportBar.trackInset]), less
  /// the face's own rim — so where the transport spans the stage, the upper
  /// row's ends and the track's are one x.
  static const double insetFromTheStage = TransportBar.trackInset - _rim;

  /// Whether a press at [global] lands on the face [face] keys — what its
  /// panel lets through to it before any tool
  /// ([BrushCanvasPanel.contentTakesPressAt]): a press on a control is the
  /// control's.
  static bool takesPressAt(GlobalKey face, Offset global) {
    final state = face.currentState;
    return state is _SoundFaceState && state._takes(global);
  }

  @override
  State<SoundFace> createState() => _SoundFaceState();
}

/// A row of the face: where it stands, the frame at its left edge and how
/// wide a frame is along it.
typedef _Row = ({Rect rect, double from, double perFrame});

/// The face's rim, ringed in the hairline.
const double _rim = 1;

/// How tall a row's ruler stands — the drawing's.
const double _rulerHeight = 22;

/// The upper row's share of the face — the drawing's.
const double _wholeShare = 0.42;

/// The face's two rows in [size]: the upper over [lastFrame] frames end to
/// end, the lower at [nearPerFrame] a frame with [currentFrame] at its
/// middle.
({_Row whole, _Row near}) _rowsIn(
  Size size, {
  required int lastFrame,
  required double nearPerFrame,
  required int currentFrame,
}) {
  final inner = (Offset.zero & size).deflate(_rim);
  final split = (inner.height * _wholeShare).roundToDouble();
  final near = Rect.fromLTRB(
    inner.left,
    inner.top + split + 1,
    inner.right,
    math.max(inner.top + split + 1, inner.bottom),
  );
  return (
    whole: (
      rect: Rect.fromLTWH(inner.left, inner.top, inner.width, split),
      from: 0.0,
      perFrame: inner.width / math.max(1, lastFrame),
    ),
    near: (
      rect: near,
      from: currentFrame - inner.width / 2 / nearPerFrame,
      perFrame: nearPerFrame,
    ),
  );
}

class _SoundFaceState extends State<SoundFace> {
  /// The row a press landed in, as it stood then — what the hand is
  /// measured against until it lets go.
  _Row? _held;

  /// The frame this press last reported ([TransportTrack]'s own reason).
  int? _reported;

  /// The face itself, under the stage it stands on.
  final GlobalKey _grip = GlobalKey();

  bool _takes(Offset global) {
    final box = _grip.currentContext?.findRenderObject();
    return box is RenderBox &&
        box.hasSize &&
        (Offset.zero & box.size).contains(box.globalToLocal(global));
  }

  int get _lastFrame => widget.frameCount <= 1 ? 0 : widget.frameCount - 1;

  double get _nearPerFrame =>
      AudioViewerDocument.pixelsPerSecondAtOne *
      widget.zoom /
      widget.frameRate.approximateFps;

  ValueChanged<int>? get _seek => _lastFrame == 0 ? null : widget.onSeek;

  void _press(Offset local) {
    final box = _grip.currentContext?.findRenderObject();
    if (box is! RenderBox || !box.hasSize || _seek == null) {
      return;
    }
    final size = box.size;
    final rows = _rowsIn(
      size,
      lastFrame: _lastFrame,
      nearPerFrame: _nearPerFrame,
      currentFrame: widget.currentFrame,
    );
    _held = local.dy < rows.near.rect.top ? rows.whole : rows.near;
    _reported = null;
    _move(local);
  }

  void _move(Offset local) {
    final row = _held;
    final seek = _seek;
    if (row == null || seek == null) {
      return;
    }
    final at = row.from + (local.dx - row.rect.left) / row.perFrame;
    final frame = at.round().clamp(0, _lastFrame);
    if (frame == _reported) {
      return;
    }
    _reported = frame;
    seek(frame);
  }

  @override
  Widget build(BuildContext context) {
    final stage = CanvasStage.maybeOf(context);
    final face = KeyedSubtree(key: _grip, child: _face(context));
    return stage == null
        ? face
        : Stack(
            children: [
              Positioned.fromRect(
                rect: stage.deflate(SoundFace.insetFromTheStage),
                child: face,
              ),
            ],
          );
  }

  Widget _face(BuildContext context) {
    final words = TransportBar.wordsStyleIn(context);
    final colorScheme = Theme.of(context).colorScheme;
    return OwningAxisGrip(
      key: ValueKey<String>(widget.keyValue),
      axis: Axis.horizontal,
      configure: (recognizer) {
        recognizer.onDown = (details) => _press(details.localPosition);
        recognizer.onStart = (details) => _move(details.localPosition);
        recognizer.onUpdate = (details) => _move(details.localPosition);
      },
      child: ValueListenableBuilder<FrameRulerView>(
        valueListenable: widget.rulerView,
        builder: (context, view, _) => CustomPaint(
          painter: _SoundFacePainter(
            peaks: widget.peaks,
            frameRate: widget.frameRate,
            lastFrame: _lastFrame,
            framesPerSecond: widget.framesPerSecond,
            currentFrame: widget.currentFrame,
            nearPerFrame: _nearPerFrame,
            kept: widget.kept,
            place: timelineFramePlaceLabel(
              frameIndex: widget.currentFrame,
              framesPerSecond: widget.framesPerSecond,
              showSeconds: view.seconds,
            ),
            ink: (
              band: AudioViewerDocument.ink,
              line: AppColors.text,
              ground: AppColors.washDown,
              past: AppColors.backdrop,
              rule: AppColors.hairline,
              tick: AppColors.hairlineStrong,
              edge: AppColors.accent,
              wash: TransportBar.rangeWash,
            ),
            // The timeline's seconds, in the transport's words: what a
            // style with no size is set at, where the theme names none.
            marks: timelineSecondsType(
              words,
              words.fontSize ?? 14,
            ).copyWith(color: colorScheme.onSurfaceVariant),
            playheadWords: words.merge(timelineRulerPlayheadInk(colorScheme)),
          ),
          child: const SizedBox.expand(),
        ),
      ),
    );
  }
}

/// The face's colours, handed in rather than read in paint: the accent is
/// live, and a painter that read it there would keep the old one until
/// something else moved ([TransportTrack]'s own note).
typedef _FaceInk = ({
  Color band,
  Color line,
  Color ground,
  Color past,
  Color rule,
  Color tick,
  Color edge,
  Color wash,
});

class _SoundFacePainter extends CustomPainter with RepaintOnProps {
  const _SoundFacePainter({
    required this.peaks,
    required this.frameRate,
    required this.lastFrame,
    required this.framesPerSecond,
    required this.currentFrame,
    required this.nearPerFrame,
    required this.kept,
    required this.place,
    required this.ink,
    required this.marks,
    required this.playheadWords,
  });

  final AudioPeaks peaks;
  final ProjectFrameRate frameRate;
  final int lastFrame;
  final int framesPerSecond;
  final int currentFrame;
  final double nearPerFrame;
  final ({int first, int last})? kept;

  /// What the playhead writes over its ruler ([timelineFramePlaceLabel]).
  final String place;
  final _FaceInk ink;
  final TextStyle marks;
  final TextStyle playheadWords;

  /// How far each kind of mark stands up from a ruler's foot — a second's
  /// and a frame's the drawing's, a beat's between them (mine: the grid
  /// rules its beats apart from its frames, and so does this).
  static double _tickOf(TimelineFrameMark mark) => switch (mark) {
    TimelineFrameMark.second => 7,
    TimelineFrameMark.beat => 5,
    TimelineFrameMark.base => 3,
  };

  @override
  void paint(Canvas canvas, Size size) {
    final well = RRect.fromRectAndRadius(
      (Offset.zero & size).deflate(_rim / 2),
      const Radius.circular(AppShapes.wellRadius),
    );
    canvas.drawRRect(well, Paint()..color = ink.ground);
    canvas.drawRRect(
      well,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = _rim
        ..color = ink.rule,
    );
    if (nearPerFrame <= 0 || size.isEmpty) {
      return;
    }
    final rows = _rowsIn(
      size,
      lastFrame: lastFrame,
      nearPerFrame: nearPerFrame,
      currentFrame: currentFrame,
    );
    canvas.drawRect(
      Rect.fromLTWH(
        rows.near.rect.left,
        rows.near.rect.top - 1,
        rows.near.rect.width,
        1,
      ),
      Paint()..color = ink.tick,
    );
    for (final row in [rows.whole, rows.near]) {
      canvas.save();
      canvas.clipRect(row.rect);
      _paintRow(canvas, row);
      canvas.restore();
    }
  }

  double _xOf(_Row row, double frame) =>
      row.rect.left + (frame - row.from) * row.perFrame;

  void _paintRow(Canvas canvas, _Row row) {
    final lanes = Rect.fromLTRB(
      row.rect.left,
      row.rect.top + _rulerHeight + 1,
      row.rect.right,
      row.rect.bottom,
    );
    // Past the file's ends, where a row round the playhead runs over them.
    final past = Paint()..color = ink.past;
    final start = _xOf(row, 0);
    final end = _xOf(row, lastFrame.toDouble());
    if (start > lanes.left) {
      canvas.drawRect(
        Rect.fromLTRB(lanes.left, lanes.top, start, lanes.bottom),
        past,
      );
    }
    if (end < lanes.right) {
      canvas.drawRect(
        Rect.fromLTRB(end, lanes.top, lanes.right, lanes.bottom),
        past,
      );
    }
    _paintLanes(canvas, row, lanes);
    _paintKept(canvas, row, lanes);
    _paintRuler(canvas, row);
    final x = _xOf(row, currentFrame.toDouble());
    canvas.drawRect(
      Rect.fromLTWH(x.floorToDouble(), row.rect.top, 1, row.rect.height),
      Paint()..color = ink.line,
    );
  }

  /// A band per channel, each in its share of [lanes] with its rule through
  /// the middle — the timeline's own band ([WaveformPainter]), laid along
  /// the row from the file's first frame.
  void _paintLanes(Canvas canvas, _Row row, Rect lanes) {
    final rule = Paint()..color = ink.rule;
    final count = peaks.lanes.length;
    final share = lanes.height / math.max(1, count);
    void across(double y) => canvas.drawRect(
      Rect.fromLTWH(lanes.left, y.floorToDouble(), lanes.width, 1),
      rule,
    );
    for (var lane = 0; lane < count; lane += 1) {
      final top = lanes.top + share * lane;
      if (lane > 0) {
        across(top);
      }
      across(top + share / 2);
    }
    canvas.save();
    canvas.clipRect(lanes);
    canvas.translate(_xOf(row, 0), lanes.top);
    WaveformPainter(
      peaks: peaks,
      frameRate: frameRate,
      pixelsPerFrame: row.perFrame,
      color: ink.band,
    ).paint(
      canvas,
      Size(
        peaks.durationSeconds * frameRate.approximateFps * row.perFrame,
        lanes.height,
      ),
    );
    canvas.restore();
  }

  /// The span IN/OUT keep: washed, and edged where IN and OUT stand.
  void _paintKept(Canvas canvas, _Row row, Rect lanes) {
    final span = kept;
    if (span == null) {
      return;
    }
    final from = _xOf(row, span.first.toDouble());
    final to = _xOf(row, span.last + 1.0);
    canvas.drawRect(
      Rect.fromLTRB(from, lanes.top, to, lanes.bottom),
      Paint()..color = ink.wash,
    );
    final edge = Paint()..color = ink.edge;
    for (final x in [from, to]) {
      canvas.drawRect(
        Rect.fromLTWH(x.floorToDouble(), lanes.top, 1, lanes.height),
        edge,
      );
    }
  }

  /// The row's ruler: the timeline's marks at their boundaries
  /// ([timelineFrameMarkAt]), its seconds written on the rung that holds the
  /// widest ([timelineSecondsHolding]), and the playhead's place over them
  /// in its own ink — the marks it touches stand down (I-16).
  void _paintRuler(Canvas canvas, _Row row) {
    final foot = row.rect.top + _rulerHeight;
    canvas.drawRect(
      Rect.fromLTWH(row.rect.left, foot, row.rect.width, 1),
      Paint()..color = ink.rule,
    );
    final first = math.max(0, row.from.ceil());
    final last = math.min(
      lastFrame,
      (row.from + row.rect.width / row.perFrame).floor(),
    );
    final tick = Paint()..color = ink.tick;
    final step = timelineFrameLineStep(row.perFrame, framesPerSecond);
    for (var frame = first + (step - first % step) % step;
        frame <= last;
        frame += step) {
      final mark = timelineFrameMarkAt(
        frameIndex: frame,
        frameCellExtent: row.perFrame,
        framesPerSecond: framesPerSecond,
      );
      if (mark == null) {
        continue;
      }
      final length = _tickOf(mark);
      final x = _xOf(row, frame.toDouble()).floorToDouble();
      canvas.drawRect(Rect.fromLTWH(x, foot - length, 1, length), tick);
    }

    final playhead = _playheadWriting(row);
    final second = timelineSecondFrames(framesPerSecond);
    final widest = laidOutGlyph(
      timelineSecondsMark(lastFrame ~/ second),
      marks,
    ).width;
    final every = timelineSecondsHolding(
      widest + timelineMarkGap,
      second * row.perFrame,
    );
    final stride = second * every;
    for (var frame = first + (stride - first % stride) % stride;
        frame <= last;
        frame += stride) {
      final glyph = laidOutGlyph(timelineSecondsMark(frame ~/ second), marks);
      final at = Offset(
        _xOf(row, frame.toDouble()) + 3,
        row.rect.top + (_rulerHeight - glyph.height) / 2,
      );
      if (playhead != null &&
          timelineMarkStandsDownFor(at & glyph.size, [playhead.rect])) {
        continue;
      }
      glyph.paint(canvas, at);
    }
    if (playhead != null) {
      canvas.drawRect(playhead.rect, Paint()..color = ink.ground);
      playhead.glyph.paint(canvas, playhead.rect.topLeft + const Offset(3, 0));
    }
  }

  /// The playhead's place written beside its line, kept inside [row] — or
  /// null where the line stands outside it.
  ({TextPainter glyph, Rect rect})? _playheadWriting(_Row row) {
    final x = _xOf(row, currentFrame.toDouble());
    if (x < row.rect.left || x > row.rect.right) {
      return null;
    }
    final glyph = laidOutGlyph(place, playheadWords);
    final width = glyph.width + 6;
    final left = (x + 1).clamp(
      row.rect.left,
      math.max(row.rect.left, row.rect.right - width),
    ).toDouble();
    return (
      glyph: glyph,
      rect: Rect.fromLTWH(
        left,
        row.rect.top + (_rulerHeight - glyph.height) / 2,
        width,
        glyph.height,
      ),
    );
  }

  @override
  Object get props => (
    ByIdentity(peaks),
    frameRate,
    lastFrame,
    framesPerSecond,
    currentFrame,
    nearPerFrame,
    kept,
    place,
    ink,
    marks,
    playheadWords,
  );
}
