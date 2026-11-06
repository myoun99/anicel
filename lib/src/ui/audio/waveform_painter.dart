import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../core/bounded_memo.dart';
import '../../models/project_frame_rate.dart';
import '../../services/audio/audio_peaks_extractor.dart';
import '../timeline/axis_turn.dart';
import '../repaint_props.dart';
import '../timeline/memo_token.dart';

/// Paints a clip's |peak| envelope as a band mirrored around the row's
/// center line, along [axis] (horizontal timeline rows, vertical X-sheet
/// columns). The widget's main-axis extent is expected to be
/// `durationFrames(frameRate) * pixelsPerFrame` — each bucket maps to
/// `pixelsPerFrame * fps / bucketsPerSecond` pixels.
///
/// 🧭THE BAND IS gpu-int-spec-timeline ②'s, column by column (관제 F-71 ⑤,
/// 2026-11-05): each device pixel column along the strip stands as high as
/// the straight line through the buckets reaches inside that column — the
/// line at the column's two ends and every bucket between them — and the
/// band is that height either side of the center, so a silent stretch
/// draws nothing. The same one definition zoomed in or out. ↩️It was one
/// polygon with a vertex per bucket: 🔬a five-minute sound's whole-file row
/// on the viewer (11 buckets a pixel) cost 0.75–0.8ms of raster on every
/// playing frame, both rows 1.0–1.2ms, re-tessellated each frame; a column
/// per pixel took it to 0.1–0.4ms (Surface, profile). ⚠️This is the CPU's
/// way until the engine's waveform kernel takes the four places over — not
/// that kernel's oracle (관제 12:33).
///
/// A band per channel ([AudioPeaks.lanes]), each in its own equal share of
/// the block across [axis] — the first on top, or on the left down a
/// column. 🗣️F-71-Q4 (유저 2026-11-05) 「L · R 두 줄」, its note 「블록
/// 안에서 두줄로 보여준다거나? 그런부분 알아서」 — so inside the block, as
/// Premiere and DaVinci stack a clip's channels, wherever a sound is drawn
/// (the viewer, the timeline's SE rows, the sheet's SE columns, the offset
/// strip). ⛔Mine: no setting that folds them to one, and no drawing that
/// changes with a panel's state — the same sound looks one way.
class WaveformPainter extends CustomPainter with RepaintOnProps {
  const WaveformPainter({
    required this.peaks,
    required this.frameRate,
    required this.pixelsPerFrame,
    required this.color,
    required this.devicePixelRatio,
    this.axis = Axis.horizontal,
    this.leadingFrames = 0,
    this.gain = 1.0,
  });

  final AudioPeaks peaks;
  final ProjectFrameRate frameRate;
  final double pixelsPerFrame;
  final Color color;

  /// Device pixels to a logical one — what a column of the band is
  /// ([EffectiveDevicePixelRatio]).
  final double devicePixelRatio;
  final Axis axis;

  /// Frames skipped into the FILE before main-axis 0 — the clip's
  /// offsetFrames trim: the envelope starts mid-file, so the painted band
  /// stays aligned with what actually plays.
  final int leadingFrames;

  /// The clip's gain, drawn INTO the band (amplitudes scale with what
  /// actually plays), capped at 1 — the band cannot outgrow the row.
  /// ↩️The clip's fades were drawn here too, until a row's volume took
  /// them over (I-140).
  final double gain;

  /// The same band asked in SECONDS — what a media viewer has instead of a
  /// frame rate.
  ///
  /// 🚨★★★**A SECOND PAINTER WOULD BE A CLONE.** Everything below reduces
  /// [frameRate] and [pixelsPerFrame] to ONE number — `pixelsPerFrame *
  /// fps`, pixels per second — and that is the number a viewer already
  /// knows. So this is not a conversion layer: at one frame per second a
  /// frame IS a second, and every quantity in `paint` lands on the same
  /// arithmetic the timeline gets.
  ///
  /// ⛔No trim and no envelope: a viewer shows a whole FILE, not a clip
  /// placed on a lane, so `leadingFrames`, `gain` and the two fades have
  /// no subject here. A caller that grows one is looking at a clip and
  /// belongs on the main constructor.
  WaveformPainter.perSecond({
    required AudioPeaks peaks,
    required double pixelsPerSecond,
    required Color color,
    required double devicePixelRatio,
    Axis axis = Axis.horizontal,
  }) : this(
         peaks: peaks,
         frameRate: const ProjectFrameRate.integer(1),
         pixelsPerFrame: pixelsPerSecond,
         color: color,
         devicePixelRatio: devicePixelRatio,
         axis: axis,
       );

  @override
  void paint(Canvas canvas, Size size) {
    if (peaks.peaks.isEmpty ||
        frameRate.numerator <= 0 ||
        pixelsPerFrame <= 0 ||
        devicePixelRatio <= 0 ||
        _pixelsPerBucket <= 0) {
      return;
    }
    final mainExtent = extentAlong(axis, size);
    // 🚨I-57 (10-13, profile, the user's project): the band is drawn as far
    // as THIS PICTURE can show it — read off the canvas's own clip, as the
    // bitmap surface reads its own (`BitmapSurfacePainter
    // ._visibleCanvasRect`): the strip clips to its box, the row to its
    // window. A sound running far past the window built every bucket of its
    // length into the path at every paint — 6–20ms of a cut crossing's
    // frame, more than all the rest of its paint. What the clip hides, no
    // picture of this paint can show, so not drawing it moves no pixel.
    final clip = canvas.getLocalClipBounds();
    final shownFrom = math.max(0.0, startAlong(axis, clip));
    final shownTo = math.min(mainExtent, endAlong(axis, clip));
    if (shownTo <= shownFrom) {
      return;
    }
    // Every device column the clip touches, and none it does not.
    final shown = (
      first: (shownFrom * devicePixelRatio).floor(),
      end: (shownTo * devicePixelRatio).ceil(),
    );

    // 🚨THE BAND IS RECKONED ONCE FOR WHAT IT IS DRAWN FROM
    // (frame-panels-build-in-one-frame, 10-24, profile, the user's project):
    // a strip built again — a tab opened again, a panel unfolded — is a new
    // painter over the same sound, and the storyboard's rows show their
    // whole sound at once (their strips stand on a tick layer, so this
    // canvas knows the strip's own clip and no window): 21,000 and 11,000
    // buckets, the largest paint of the storyboard tab's opening (10–17% of
    // it). 🔬Handing the vertices over in one call (`addPolygon`) moved
    // nothing (12.4 → 12.5%) — the cost is reckoning them. So the path is
    // kept by everything it is drawn from: the painter's [props] (the ink
    // too — a band reckoned again when only it moves), the size, and the
    // stretch the clip shows. The same path draws the same pixels.
    final band = _bands
        .resolve((props, size, shown), () => (band: _bandOf(size, shown)))
        .band;
    if (band == null) {
      return;
    }
    canvas.drawPath(band, Paint()..color = color);
  }

  /// The bands painted lately, by what each is drawn from ([paint]).
  ///
  /// Sixteen: every strip a screen shows, twice over. A row scrolled under
  /// its window is a new stretch at every paint, and starting over costs
  /// each kept band one reckoning — what every paint paid before.
  static final BoundedMemo<Object, ({Path? band})> _bands = BoundedMemo(16);

  /// How many bands have been reckoned — the work [_bands] saves, read by
  /// the test that pins it.
  @visibleForTesting
  static int get debugBandsReckoned => _bandsReckoned;
  static int _bandsReckoned = 0;

  /// How many pixels one bucket of [peaks] spans along [axis].
  double get _pixelsPerBucket =>
      pixelsPerFrame * frameRate.approximateFps / peaks.bucketsPerSecond;

  /// How far into the file main-axis 0 stands — the clip's trim.
  double get _leadingPixels => leadingFrames * pixelsPerFrame;

  /// The bands over the device columns [shown] of a strip of [size], a
  /// lane's in each share of it — null where there is none.
  Path? _bandOf(Size size, ({int first, int end}) shown) {
    _bandsReckoned += 1;
    final lanes = peaks.lanes;
    final share = extentAcross(axis, size) / lanes.length;
    final path = Path();
    var drawn = false;
    for (var lane = 0; lane < lanes.length; lane += 1) {
      drawn |= _addLane(
        path,
        lanes[lane],
        shown: (
          first: shown.first,
          end: shown.end,
          extent: extentAlong(axis, size),
        ),
        across: (
          center: share * (lane + 0.5),
          reach: math.max(0.0, share / 2 - 1) * math.min(1.0, gain),
        ),
      );
    }
    return drawn ? path : null;
  }

  /// One lane's band added to [path]: each device column [shown] on a strip
  /// that long stands either side of its [across] center as far as the
  /// envelope stands highest in it, at its reach for full amplitude — a run
  /// of columns standing alike as one rect. False where it stands nowhere.
  bool _addLane(
    Path path,
    Float32List envelope, {
    required ({int first, int end, double extent}) shown,
    required ({double center, double reach}) across,
  }) {
    final (:first, :end, :extent) = shown;
    final (:center, :reach) = across;
    final last = (envelope.length - 1).toDouble();
    final pixelsPerBucket = _pixelsPerBucket;
    final leadingPixels = _leadingPixels;
    var drawn = false;
    var run = (from: 0.0, to: 0.0, height: 0.0);
    void lay() {
      if (run.height > 0) {
        path.addRect(
          rectAlong(
            axis,
            along: (from: run.from, to: run.to),
            across: (from: center - run.height, to: center + run.height),
          ),
        );
        drawn = true;
      }
    }

    for (var column = first; column < end; column += 1) {
      final from = column / devicePixelRatio;
      // The strip's own end cuts its last column: a clip trimmed short
      // stops its band where its block does.
      final to = math.min(extent, (column + 1) / devicePixelRatio);
      // Read on the envelope's own line, from its first bucket to its last
      // — a trim landing mid-bucket starts the band on the line rather
      // than a bucket short (the "ends flicker while sliding" artifact),
      // and a column before the file, past it or on a one-bucket sound has
      // no stretch of it and stands nowhere.
      final height =
          _highest(
            envelope,
            from: math.max(0.0, (from + leadingPixels) / pixelsPerBucket),
            to: math.min(last, (to + leadingPixels) / pixelsPerBucket),
          ) *
          reach;
      if (height == run.height && from == run.to) {
        run = (from: run.from, to: to, height: height);
        continue;
      }
      lay();
      run = (from: from, to: to, height: height);
    }
    lay();
    return drawn;
  }

  /// The highest the straight line through [envelope]'s buckets stands
  /// [from] one place [to] another, in buckets — at one of the two ends or
  /// on a bucket between them, as a straight line is highest at an end —
  /// or 0 where there is no stretch between them.
  static double _highest(
    Float32List envelope, {
    required double from,
    required double to,
  }) {
    if (to <= from) {
      return 0;
    }
    var highest = math.max(_lineAt(envelope, from), _lineAt(envelope, to));
    for (var bucket = from.floor() + 1; bucket < to; bucket += 1) {
      highest = math.max(highest, envelope[bucket]);
    }
    return highest;
  }

  /// The line through [envelope]'s buckets at [at], from its first bucket
  /// to its last.
  static double _lineAt(Float32List envelope, double at) {
    final bucket = at.floor();
    if (bucket >= envelope.length - 1) {
      return envelope[envelope.length - 1];
    }
    final t = at - bucket;
    return envelope[bucket] * (1 - t) + envelope[bucket + 1] * t;
  }

  @override
  Object get props => (
    ByIdentity(peaks),
    frameRate,
    pixelsPerFrame,
    color,
    devicePixelRatio,
    axis,
    leadingFrames,
    gain,
  );
}
