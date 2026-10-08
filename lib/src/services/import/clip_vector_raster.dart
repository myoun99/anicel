import 'dart:math' as math;
import 'dart:typed_data';

import '../../models/bitmap_surface.dart';
import '../../models/brush_dab.dart';
import '../../models/brush_dab_sequence.dart';
import '../../models/brush_input_source.dart';
import '../../models/brush_pressure_curve.dart';
import '../../models/brush_shape.dart';
import '../../models/canvas_point.dart';
import '../../models/canvas_size.dart';
import '../../models/dirty_region.dart';
import '../../models/frame_id.dart';
import '../../models/layer_id.dart';
import '../brush_commit_builder.dart';
import '../brush_dab_interpolator.dart';
import '../brush_pressure_dynamics.dart' show applyBrushInputDynamics;
import '../brush_stroke_blend.dart' show bitmapSurfaceRegionPixels;
import 'clip_cel_raster.dart';
import 'clip_container.dart' show ClipFormatException;

/// One point a vector stroke runs through: where it is, in the layer's own
/// pixels, and how wide the pen is there.
typedef ClipVectorPoint = ({double x, double y, double width});

/// One stroke of a vector layer: its colour (opaque 0xAARRGGBB), how dark
/// the whole stroke may get, and the points it runs through — a curve
/// already laid out as the short straight steps along it.
typedef ClipVectorStroke = ({
  int color,
  double opacity,
  List<ClipVectorPoint> points,
});

/// What one vector datum holds: the strokes this reader draws, and how many
/// records were of a kind it does not.
typedef ClipVectorBody = ({List<ClipVectorStroke> strokes, int unread});

/// The strokes [body] stores — a vector layer's external data (memory
/// `csp-clip-format-notes` §7; the one sample with vectors chains every
/// record to its data's end): stroke records end to end, big-endian, each
/// a head of its own size and its points.
///
/// · head: its size `u32 @0` (88 or 92), one point's size `u32 @8` (88 a
///   brush stroke, 104 a curve tool's), the point count `u32 @16`, flags
///   `u32 @20`; the colour's red · green · blue at `@40 · @44 · @48` (the
///   top byte of each 32 bits), the opacity `f64 @64`, the radius `f64 @76`
///   (head 88) or `@80` (head 92).
/// · point: `f64 x @0 · f64 y @8`, the radius's factor there `f32 @56`; a
///   104-byte point bends toward the control point `f64 @88 · @96` on its
///   way to the next — a quadratic Bézier, 0,0 a straight step.
///
/// ⛔ONLY FLAGS `& 13 == 1` ARE DRAWN — the reference this format was
/// learnt from (MoArt, read for its facts only) reads no other; the rest are
/// counted, so the door can say so. Unverified on a sample: the curve
/// tool's points (none of ours has one).
ClipVectorBody parseClipVectorBody(Uint8List body) {
  final data = ByteData.sublistView(body);
  final strokes = <ClipVectorStroke>[];
  var unread = 0;
  var at = 0;
  while (at < body.length) {
    if (at + 24 > body.length) {
      throw ClipFormatException('a vector stroke is cut short at $at');
    }
    final head = data.getUint32(at);
    final pointSize = data.getUint32(at + 8);
    final count = data.getUint32(at + 16);
    final end = at + head + count * pointSize;
    if (!_heads.contains(head) ||
        !_pointSizes.contains(pointSize) ||
        end > body.length) {
      throw ClipFormatException(
        'a vector stroke of a shape this reader does not know at $at',
      );
    }
    if (data.getUint32(at + 20) & 13 == 1) {
      final record = (at: at, head: head, pointSize: pointSize, count: count);
      strokes.add(_strokeAt(data, record));
    } else {
      unread += 1;
    }
    at = end;
  }
  return (strokes: strokes, unread: unread);
}

const _heads = {88, 92};
const _pointSizes = {88, 104};

/// Where a stroke record stands in its body, and the shape its head says
/// it has.
typedef _Record = ({int at, int head, int pointSize, int count});

ClipVectorStroke _strokeAt(ByteData data, _Record record) {
  final (:at, :head, :pointSize, :count) = record;
  final radius = data.getFloat64(at + (head == 92 ? 80 : 76));
  final stored = [
    for (var p = 0; p < count; p += 1)
      _pointAt(data, at + head + p * pointSize, pointSize, radius),
  ];
  return (
    color:
        0xFF000000 |
        data.getUint8(at + 40) << 16 |
        data.getUint8(at + 44) << 8 |
        data.getUint8(at + 48),
    opacity: data.getFloat64(at + 64).clamp(0.0, 1.0).toDouble(),
    points: _laidOut(stored),
  );
}

/// One stored point, and the control point it bends toward — null for a
/// straight step.
typedef _StoredPoint = ({ClipVectorPoint point, ({double x, double y})? bend});

_StoredPoint _pointAt(ByteData data, int at, int pointSize, double radius) {
  final point = (
    x: data.getFloat64(at),
    y: data.getFloat64(at + 8),
    width: 2 * radius * data.getFloat32(at + 56),
  );
  if (!point.x.isFinite || !point.y.isFinite || !point.width.isFinite) {
    throw ClipFormatException('a vector point that is not a number at $at');
  }
  if (pointSize < 104) {
    return (point: point, bend: null);
  }
  final bend = (x: data.getFloat64(at + 88), y: data.getFloat64(at + 96));
  if (!bend.x.isFinite || !bend.y.isFinite) {
    throw ClipFormatException('a control point that is not a number at $at');
  }
  return (point: point, bend: bend.x == 0 && bend.y == 0 ? null : bend);
}

/// [stored] as the points a pen goes through: a bent step laid out as
/// steps of a pixel or less along its curve, the width going from one end's
/// to the other's.
List<ClipVectorPoint> _laidOut(List<_StoredPoint> stored) {
  final points = <ClipVectorPoint>[];
  for (var i = 0; i < stored.length; i += 1) {
    final (:point, :bend) = stored[i];
    points.add(point);
    if (bend == null || i + 1 == stored.length) {
      continue;
    }
    final next = stored[i + 1].point;
    final reach =
        _distance(point.x, point.y, bend.x, bend.y) +
        _distance(bend.x, bend.y, next.x, next.y);
    final steps = math.max(1, reach.ceil());
    for (var s = 1; s < steps; s += 1) {
      final t = s / steps;
      final u = 1 - t;
      points.add((
        x: u * u * point.x + 2 * u * t * bend.x + t * t * next.x,
        y: u * u * point.y + 2 * u * t * bend.y + t * t * next.y,
        width: point.width + (next.width - point.width) * t,
      ));
    }
  }
  return points;
}

double _distance(double ax, double ay, double bx, double by) =>
    math.sqrt((bx - ax) * (bx - ax) + (by - ay) * (by - ay));

/// The pen a vector stroke is drawn with: round, at the brush model's own
/// hardness, flow and spacing, its size following pressure in a straight
/// line — what the file cannot say of its brush (shape, texture) is not
/// guessed at.
final _pen = const BrushShape().withCurve(
  BrushPressureTarget.size,
  BrushInputSource.pressure,
  BrushPressureCurve(const [BrushCurvePoint(0, 0), BrushCurvePoint(1, 1)]),
);

/// [bodies] — a vector layer's data — drawn on [target]'s canvas with the
/// layer's strokes moved by [offset] (its `LayerOffset`: the strokes are
/// stored in the layer's own pixels), as cel tiles; and how many records
/// were of a kind this reader does not draw.
///
/// Each stroke lands as the brush lands one re-derived from its dabs
/// ([brushCommitResultForBrushDabSequenceOnBitmapSurface]: piled up, then
/// laid once at its opacity) and the picture is cut and baked as a stored
/// one is ([clipCelTilesOf]). Pure, so it runs on a worker.
({List<ClipCelTile> tiles, int unread}) clipVectorTiles(
  List<Uint8List> bodies,
  ({int x, int y}) offset,
  ClipCelTarget target,
) {
  final width = target.canvasWidth;
  final height = target.canvasHeight;
  var surface = BitmapSurface(
    canvasSize: CanvasSize(width: width, height: height),
    tileSize: target.tileSize,
  );
  var unread = 0;
  for (final body in bodies) {
    final read = parseClipVectorBody(body);
    unread += read.unread;
    for (final stroke in read.strokes) {
      final dabs = _dabsAlong(stroke, offset);
      if (dabs.isEmpty) {
        continue;
      }
      surface = brushCommitResultForBrushDabSequenceOnBitmapSurface(
        surface: surface,
        sequence: BrushDabSequence(dabs, stroke.opacity),
        layerId: const LayerId('clip-vector'),
        frameId: const FrameId('clip-vector'),
      ).afterSurface;
    }
  }
  final rgba = bitmapSurfaceRegionPixels(
    surface,
    DirtyRegion(
      left: 0,
      top: 0,
      rightExclusive: width,
      bottomExclusive: height,
    ),
  );
  return (
    tiles: clipCelTilesOf((rgba: rgba, width: width, height: height), (
      left: 0,
      top: 0,
      canvasWidth: width,
      canvasHeight: height,
      alpha: target.alpha,
      tileSize: target.tileSize,
    )),
    unread: unread,
  );
}

/// [stroke]'s dabs, laid along it the way the pen lays them: the stroke's
/// widest point is the pen's size, and each point's width rides as its
/// pressure — carried between two readings ([BrushDabInterpolator]) and
/// turned back into a size by the pen's own dynamics
/// ([applyBrushInputDynamics]), so a line narrows toward a thin point as a
/// pressed pen's does.
List<BrushDab> _dabsAlong(ClipVectorStroke stroke, ({int x, int y}) offset) {
  final widest = stroke.points.fold(0.0, (w, p) => math.max(w, p.width));
  if (widest <= 0) {
    return const [];
  }
  final dabs = <BrushDab>[];
  BrushDab? previous;
  for (final point in stroke.points) {
    final laid = const BrushDabInterpolator().interpolate(
      previous: previous,
      nextRaw: BrushDab(
        center: CanvasPoint(x: point.x + offset.x, y: point.y + offset.y),
        color: stroke.color,
        size: widest,
        opacity: 1,
        flow: _pen.flow,
        hardness: _pen.hardness,
        pressure: (point.width / widest).clamp(0.0, 1.0),
        sequence: dabs.length,
      ),
      firstSequence: dabs.length,
      spacingRatio: _pen.spacing,
    );
    if (laid.isNotEmpty) {
      dabs.addAll(laid);
      previous = laid.last;
    }
  }
  return [for (final dab in dabs) applyBrushInputDynamics(dab, shape: _pen)];
}
