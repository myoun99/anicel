import 'dart:math' as math;

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter/material.dart';

import '../../core/bounded_memo.dart';
import '../../models/project_frame_rate.dart';
import '../../services/audio/audio_peaks_extractor.dart';
import '../timeline/axis_turn.dart';
import '../repaint_props.dart';
import '../timeline/memo_token.dart';

/// Paints a clip's |peak| envelope as a filled band mirrored around the
/// row's center line, along [axis] (horizontal timeline rows, vertical
/// X-sheet columns). The widget's main-axis extent is expected to be
/// `durationFrames(frameRate) * pixelsPerFrame` — each bucket maps to
/// `pixelsPerFrame * fps / bucketsPerSecond` pixels.
class WaveformPainter extends CustomPainter with RepaintOnProps {
  const WaveformPainter({
    required this.peaks,
    required this.frameRate,
    required this.pixelsPerFrame,
    required this.color,
    this.axis = Axis.horizontal,
    this.leadingFrames = 0,
    this.gain = 1.0,
    this.fadeInFrames = 0,
    this.fadeOutFrames = 0,
  });

  final AudioPeaks peaks;
  final ProjectFrameRate frameRate;
  final double pixelsPerFrame;
  final Color color;
  final Axis axis;

  /// Frames skipped into the FILE before main-axis 0 — the clip's
  /// offsetFrames trim: the envelope starts mid-file, so the painted band
  /// stays aligned with what actually plays.
  final int leadingFrames;

  /// The clip's volume envelope, drawn INTO the band (amplitudes scale
  /// with what actually plays): [gain] scales the whole envelope (capped
  /// at 1 — the band cannot outgrow the row), [fadeInFrames] ramps up from
  /// the span start and [fadeOutFrames] ramps down toward the audible end
  /// (span end or file end, whichever comes first).
  final double gain;
  final int fadeInFrames;
  final int fadeOutFrames;

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
    Axis axis = Axis.horizontal,
  }) : this(
         peaks: peaks,
         frameRate: const ProjectFrameRate.integer(1),
         pixelsPerFrame: pixelsPerSecond,
         color: color,
         axis: axis,
       );

  @override
  void paint(Canvas canvas, Size size) {
    if (peaks.peaks.isEmpty ||
        frameRate.numerator <= 0 ||
        pixelsPerFrame <= 0) {
      return;
    }
    final mainExtent = extentAlong(axis, size);
    final pixelsPerBucket = _pixelsPerBucket;
    if (pixelsPerBucket <= 0) {
      return;
    }
    final leadingPixels = _leadingPixels;
    final startBucket = leadingPixels <= 0
        ? 0
        : (leadingPixels / pixelsPerBucket).floor();
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
    // The bucket before the clip's start — a bucket short of where its
    // floor lands, so a rounding can never start the band inside the clip —
    // and every bucket after it the band would draw, up to the first at or
    // past the clip's end: the whole band's own vertices, cut where nobody
    // sees.
    final firstShown = math.max(
      startBucket,
      ((shownFrom + leadingPixels) / pixelsPerBucket).floor() - 1,
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
        .resolve(
          (props, size, firstShown, shownTo),
          () => (band: _bandOf(size, firstShown, shownTo)),
        )
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

  /// The band over the buckets from [firstShown] to the first at or past
  /// [shownTo], on a strip of [size] — null where there is none.
  Path? _bandOf(Size size, int firstShown, double shownTo) {
    _bandsReckoned += 1;
    final pixelsPerBucket = _pixelsPerBucket;
    final leadingPixels = _leadingPixels;
    final mainExtent = extentAlong(axis, size);
    final crossExtent = extentAcross(axis, size);
    final center = crossExtent / 2;
    final maxAmplitude = (crossExtent / 2) - 1;

    // Where the audible part ends on the main axis: the span's own end or
    // the file running out, whichever is first — the fade-out anchor.
    final audibleEndPixels = math.min(
      mainExtent,
      (peaks.durationFrames(frameRate) - leadingFrames) * pixelsPerFrame,
    );
    final fadeInPixels = fadeInFrames * pixelsPerFrame;
    final fadeOutPixels = fadeOutFrames * pixelsPerFrame;
    final envelopeGain = math.min(1.0, gain);

    double envelopeAt(double main) {
      var factor = envelopeGain;
      if (fadeInPixels > 0 && main < fadeInPixels) {
        factor *= math.max(0, main / fadeInPixels);
      }
      final remaining = audibleEndPixels - main;
      if (fadeOutPixels > 0 && remaining < fadeOutPixels) {
        factor *= math.max(0, remaining / fadeOutPixels);
      }
      return factor;
    }

    final path = Path();
    final top = <Offset>[];
    final bottom = <Offset>[];
    for (var bucket = firstShown; bucket < peaks.peaks.length; bucket += 1) {
      var main = bucket * pixelsPerBucket - leadingPixels;
      var lastSample = false;
      // The offset usually lands MID-bucket: clamp the edge samples onto
      // the window instead of dropping them, or the band opens/closes up
      // to a bucket short — a gap that shifts with every dragged frame
      // (the "ends flicker while sliding" artifact).
      if (main < 0) {
        main = 0;
      }
      if (main >= mainExtent) {
        main = mainExtent;
        lastSample = true;
      }
      final amplitude = peaks.peaks[bucket] * maxAmplitude * envelopeAt(main);
      top.add(offsetAlong(axis, along: main, across: center - amplitude));
      bottom.add(offsetAlong(axis, along: main, across: center + amplitude));
      if (lastSample || main >= shownTo) {
        break;
      }
    }
    if (top.isEmpty) {
      return null;
    }
    path.moveTo(top.first.dx, top.first.dy);
    for (final point in top.skip(1)) {
      path.lineTo(point.dx, point.dy);
    }
    for (final point in bottom.reversed) {
      path.lineTo(point.dx, point.dy);
    }
    path.close();
    return path;
  }

  @override
  Object get props => (
    ByIdentity(peaks),
    frameRate,
    pixelsPerFrame,
    color,
    axis,
    leadingFrames,
    gain,
    fadeInFrames,
    fadeOutFrames,
  );
}
