import 'dart:math' as math;
import 'dart:typed_data';

import '../../core/on_a_worker.dart';
import '../../models/bitmap_surface.dart';
import '../../models/brush_dab.dart';
import '../../models/brush_dab_sequence.dart';
import '../../models/brush_frame_key.dart';
import '../../models/brush_input_source.dart';
import '../../models/brush_pressure_curve.dart';
import '../../models/brush_shape.dart';
import '../../models/canvas_point.dart';
import '../../models/canvas_size.dart';
import '../../models/pasteboard_bounds.dart';
import '../../native/engine_tile_ledger.dart';
import '../brush_dab_interpolator.dart';
import '../brush_stroke_landing.dart';
import '../brush_pressure_dynamics.dart' show applyBrushInputDynamics;
import '../brush_stroke_blend.dart' show bitmapSurfaceRegionPixels;
import '../brush_tip_stamp_cache.dart';
import '../persistence/brush_drawing_binary_codec.dart'
    show onAWorkerWithCelCopy;
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
/// 🚨THE STROKES ARE PLANNED ON A WORKER AND LAID HERE, ON THE ENGINE
/// (🗣️clip-vector-import-draws-with-the-c-brush-Q1, 유저 2026-11-11; 관제:
/// 「워커에서 획 계획만 · 메인에서 엔진 착지」). A worker has no engine —
/// the engine and its pool's tiles are the main isolate's
/// (`appGpuEngineIsHere`) — so the worker reads the strokes and lays each
/// one's dabs along it ([_strokesLaid]), and asks this isolate to land it
/// ([onAWorkerAsking]): a stroke at a time, so a layer's dabs are never
/// held whole and the app has its turn between two strokes. ↩️Till
/// 2026-11-12 the worker drew them itself, with the C brush: the last road
/// the C brush, its blur and its span batch had in the app.
///
/// Each stroke lands as the brush lays a stroke ([_withStroke]: piled up,
/// then laid once at its opacity) on the canvas and no further, and the
/// picture is cut and baked as a stored one is ([clipCelTilesOf]) — through
/// [mask] as well — on a worker handed a copy of it
/// ([onAWorkerWithCelCopy]).
///
/// Throws [ClipFormatException] for strokes that would not read.
Future<({List<ClipCelTile> tiles, int unread})> clipVectorTiles(
  List<Uint8List> bodies,
  ({int x, int y}) offset,
  ClipCelTarget target, {
  ClipStoredMask? mask,
}) async {
  var surface = BitmapSurface(
    canvasSize: CanvasSize(
      width: target.canvasWidth,
      height: target.canvasHeight,
    ),
    pasteboardReach: PasteboardReach.none,
    tileSize: target.tileSize,
  );
  final unread = await onAWorkerAsking<BrushDabSequence, bool, int>((stroke) {
    surface = _withStroke(surface, stroke);
    return true;
  }, _strokesLaid(bodies, offset));
  return (
    tiles: await onAWorkerWithCelCopy(
      BrushFrameKey.noCel,
      surface,
      _cutOnto(target, mask),
    ),
    unread: unread,
  );
}

/// [picture] with [stroke] laid on it as the brush lays a stroke
/// ([strokeLandedOn]), the tiles it lay over let go now
/// ([EngineTileLedger.retire]).
///
/// 🚨THE PICTURE IS THE IMPORT'S ALONE AND BEGINS EMPTY: a tile a stroke
/// lays over is one an earlier stroke of the layer made, and nothing reads
/// it again. Left to its collection it stays for as long as the tile laid
/// over it is the engine's alone (`_Slot.under` — what a cel's tile reads as
/// where a device goes), and a layer's strokes leave no rest between them
/// for a copy to come here in: 🔬6,000 strokes at half opacity held 38,750
/// slots, 2,432 MB of the pool, for a picture of 247 tiles (main PC,
/// 2340 × 1654).
///
/// ⚠️What a tile let go was kept for goes with it: a device that goes while
/// a layer is drawn leaves nothing for the picture's tiles to read as. An
/// import that loses its device is not told apart yet, with or without
/// this (card `a-lost-gpu-device-keeps-the-unsaved-tiles`).
BitmapSurface _withStroke(BitmapSurface picture, BrushDabSequence stroke) {
  final landed = strokeLandedOn(picture, stroke);
  for (final (:coord, tile: _) in landed) {
    final under = picture.tileAt(coord);
    if (under != null) {
      EngineTileLedger.instance.retire(under);
    }
  }
  return picture.putMaterializedTiles(landed);
}

/// The worker's half of [clipVectorTiles] that plans: [bodies]' strokes,
/// each laid along by the pen ([clipVectorDabs]) and handed to `land` — waited
/// for, one at a time, in the file's order — and how many records were of a
/// kind this reader does not draw.
///
/// ⚠️Made HERE: the closure crosses, and one made beside the answer would
/// carry the surface, whose tiles no isolate message carries
/// (`on_a_worker.dart`'s `_reportingInto`).
Future<int> Function(Future<bool> Function(BrushDabSequence stroke) land)
_strokesLaid(List<Uint8List> bodies, ({int x, int y}) offset) => (land) async {
  var unread = 0;
  for (final body in bodies) {
    final read = parseClipVectorBody(body);
    unread += read.unread;
    for (final stroke in read.strokes) {
      final dabs = clipVectorDabs(stroke, offset);
      await land(BrushDabSequence(dabs, stroke.opacity));
    }
  }
  return unread;
};

/// The worker's half of [clipVectorTiles] that cuts: the canvas read out of
/// the picture's copy, as cel tiles on [target]'s canvas through [mask].
/// ⚠️Made HERE for the reason [_strokesLaid] is.
List<ClipCelTile> Function(BitmapSurface copy) _cutOnto(
  ClipCelTarget target,
  ClipStoredMask? mask,
) => (copy) {
  final canvas = copy.canvasSize;
  return clipCelTilesOf(
    (
      rgba: bitmapSurfaceRegionPixels(copy, canvas.canvasRegion),
      width: canvas.width,
      height: canvas.height,
    ),
    (
      left: 0,
      top: 0,
      canvasWidth: canvas.width,
      canvasHeight: canvas.height,
      alpha: target.alpha,
      tileSize: target.tileSize,
    ),
    mask: mask,
  );
};

/// [stroke]'s dabs, moved by [offset] and laid along it the way the pen
/// lays them — what [clipVectorTiles] has a worker plan: the stroke's
/// widest point is the pen's size, and each point's width rides as its
/// pressure — carried between two readings ([BrushDabInterpolator]) and
/// turned back into a size by the pen's own dynamics
/// ([applyBrushInputDynamics]), so a line narrows toward a thin point as a
/// pressed pen's does.
///
/// 🚨EACH IN THE FORM A STROKE'S DAB IS LAID IN
/// ([BrushTipStampCache.resolveDab] — 「every dab a stroke lays comes
/// through here」): its size on the steps a pen's is. ↩️Till 2026-11-12 a
/// dab was lifted to a pixel ([liftedToOnePixel], that law's first half)
/// and its size left as the width made it — so no two dabs of a narrowing
/// line were one size, and a round tip is a table for each size
/// (`RoundTipProfile.of`): 🔬735 dabs of a 300 px stroke at 2.4–6 px made
/// 735 tables, 230–270 ms of the 300 ms the stroke took (main PC, a test's
/// VM; 0.33 ms a table of a nib under 5 px built ahead of time) — 148 s
/// for a layer of 500 such strokes, by the C brush as much as the engine.
List<BrushDab> clipVectorDabs(
  ClipVectorStroke stroke,
  ({int x, int y}) offset,
) {
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
  return BrushTipStampCache.instance.resolveDabs([
    for (final dab in dabs) applyBrushInputDynamics(dab, shape: _pen),
  ]);
}
