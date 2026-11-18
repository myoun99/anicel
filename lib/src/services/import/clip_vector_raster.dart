import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:gpu_engine/gpu_engine.dart'
    show GpuBlend, GpuComposite, GpuEngine, GpuMask, GpuRefused;

import '../../core/on_a_worker.dart';
import '../../models/bitmap_surface.dart';
import '../../models/bitmap_tile.dart';
import '../../models/brush_dab.dart';
import '../../models/brush_dab_sequence.dart';
import '../../models/brush_frame_key.dart';
import '../../models/brush_input_source.dart';
import '../../models/brush_pressure_curve.dart';
import '../../models/brush_shape.dart';
import '../../models/canvas_point.dart';
import '../../models/tile_coord.dart';
import '../../native/app_gpu_engine.dart' show appGpuComposite, appGpuEngine;
import '../../native/engine_tile_ledger.dart';
import '../brush_dab_interpolator.dart';
import '../brush_stroke_landing.dart';
import '../brush_pressure_dynamics.dart' show applyBrushInputDynamics;
import '../brush_tip_stamp_cache.dart';
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

/// [bodies] — a vector layer's data — drawn on [target]'s cel with the
/// layer's strokes moved by [offset] (its `LayerOffset`: the strokes are
/// stored in the layer's own pixels), as the cel's tiles; and how many
/// records were of a kind this reader does not draw.
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
/// then laid once at its opacity) inside its wall and no further, and the
/// picture lands where it lies through the layer's alpha and [mask]
/// ([_throughTheLayer]): its tiles the engine's alone.
///
/// 🚨THE PICTURE IS NOT READ BACK (card
/// a-clip-vector-layer-is-read-back-to-be-tiled-again, 관제 2026-11-15:
/// 「리드백은 그때까지 쌓인 GPU 일 전부를 기다린다」 — 351–425 ms on the
/// Surface Pro 11, 5–7 on the main PC). ↩️Till 2026-11-16 it was read back
/// whole (`onAWorkerWithCelCopy`), made a canvas of RGBA on a worker, baked
/// through the mask there and cut into tiles again as a stored picture is
/// (`clipCelTiles`) — a canvas's work for each vector layer — which the
/// door stored again.
///
/// Throws [ClipFormatException] for strokes that would not read, and the
/// device's refusal ([GpuRefused]) where the engine the picture was drawn
/// on lost its device before the GPU had made it.
///
/// 🚨A LAYER WHOSE DEVICE WENT AS IT WAS DRAWN FAILS THE IMPORT WHOLE, as
/// one refused at its first stroke does, and is told as the device's (card
/// `a-vector-layer-read-as-its-device-goes-opens-blank`, 관제 2026-11-13).
/// ↩️브러시 measured it otherwise (main PC, 2026-11-13): a device gone as
/// the picture was read back read no tile — the layer opened empty and
/// nothing said so — or, where a stroke had lain over a tile, threw a bare
/// [StateError], which is no refusal. The word that a device went comes
/// inside a wait, and nothing reads the picture back now: so the import
/// waits for the GPU to have made it — off this isolate, on the engine's
/// thread for waits ([GpuEngine.done]) — of the engine the first stroke
/// landed on, as the app's may be the next by then (the ⛔ of
/// `appGpuEngineIsGone`). ↩️Till 2026-11-16 it asked [GpuEngine.isGone]
/// after the read back, which was that wait.
Future<({Map<TileCoord, BitmapTile> tiles, int unread})> clipVectorTiles(
  List<Uint8List> bodies,
  ({int x, int y}) offset,
  ClipCelTarget target, {
  ClipStoredMask? mask,
}) async {
  var surface = BitmapSurface(
    canvasSize: target.wall.canvas,
    pasteboardReach: target.wall.reach,
    tileSize: target.tileSize,
  );
  GpuEngine? drawnOn;
  final unread = await onAWorkerAsking<BrushDabSequence, bool, int>((stroke) {
    drawnOn ??= appGpuEngine;
    surface = _withStroke(surface, stroke);
    return true;
  }, _strokesLaid(bodies, offset));
  final drawn = surface.tiles;
  final engine = drawnOn;
  if (drawn.isEmpty || engine == null) {
    return (tiles: const <TileCoord, BitmapTile>{}, unread: unread);
  }
  final tiles = await _throughTheLayer(drawn, target, mask);
  await engine.done();
  return (tiles: tiles, unread: unread);
}

/// Test seam: called as a drawn layer's picture is about to land through
/// its alpha and mask ([_throughTheLayer]) — where a device that goes is
/// one that went as the layer was drawn.
@visibleForTesting
void Function()? debugBeforeTheLayerLands;

/// [drawn] — a layer's strokes as the engine laid them — landed where they
/// lie through [target]'s alpha and [mask] ([GpuComposite.land]): a tile of
/// the cel's for each, inked and the engine's alone, with no wait for the
/// GPU; [drawn]'s tiles let go then ([EngineTileLedger.retire]), as
/// [_withStroke] lets go of what a stroke lay over.
///
/// The mask is read on a worker ([clipMaskPlaneOver]) — over what [drawn]
/// reaches of the canvas, where it shows what lies past its box.
///
/// ⚠️ONE ROAD, WHATEVER THE ALPHA AND THE MASK: a layer at its whole alpha
/// with no mask lands as any other does — laid once more, at whole.
Future<Map<TileCoord, BitmapTile>> _throughTheLayer(
  Map<TileCoord, BitmapTile> drawn,
  ClipCelTarget target,
  ClipStoredMask? mask,
) async {
  final ledger = EngineTileLedger.instance;
  final plane = mask == null
      ? null
      : await onAWorker(_planeOf(mask, _reachOf(drawn.keys, target)));
  debugBeforeTheLayerLands?.call();
  if (plane != null && plane.bytes.isEmpty) {
    // A box of no pixel that hides what lies past it: nothing shows.
    drawn.values.forEach(ledger.retire);
    return const {};
  }
  final composite = appGpuComposite;
  final under = plane == null
      ? null
      : GpuMask(
          composite,
          plane.bytes,
          x: plane.left,
          y: plane.top,
          width: plane.width,
          height: plane.height,
        );
  final coords = drawn.keys.toList();
  try {
    final landed = ledger.held((hold) {
      final picture = hold.gridOf(BrushFrameKey.noCel, drawn);
      return ledger.land(
        [for (final at in coords) (column: at.x, row: at.y, under: null)],
        by: (pool, cel, asked) => composite.land(
          pool,
          cel,
          picture,
          asked,
          opacity: (target.alpha * 65535).round(),
          mode: GpuBlend.normal,
          mask: under,
        ),
      );
    });
    drawn.values.forEach(ledger.retire);
    return {
      for (final (at, coord) in coords.indexed) coord: landed[at].tile!,
    };
  } finally {
    under?.free();
  }
}

/// The canvas pixels [tiles] — of [target]'s grid — reach inside its wall:
/// [left, top, right, bottom).
({int left, int top, int right, int bottom}) _reachOf(
  Iterable<TileCoord> tiles,
  ClipCelTarget target,
) {
  final side = target.tileSize;
  final wall = target.wall;
  final xs = [for (final tile in tiles) tile.x];
  final ys = [for (final tile in tiles) tile.y];
  return (
    left: math.max(wall.left, xs.reduce(math.min) * side),
    top: math.max(wall.top, ys.reduce(math.min) * side),
    right: math.min(wall.rightExclusive, (xs.reduce(math.max) + 1) * side),
    bottom: math.min(wall.bottomExclusive, (ys.reduce(math.max) + 1) * side),
  );
}

/// The worker's half of [_throughTheLayer]: [mask] read as the engine lays
/// a picture under it, over [within]. ⚠️Made HERE for the reason
/// [_strokesLaid] is.
ClipMaskPlane? Function() _planeOf(
  ClipStoredMask mask,
  ({int left, int top, int right, int bottom}) within,
) => () => clipMaskPlaneOver(mask, within);

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
/// a layer is drawn leaves nothing for the picture's tiles to read as —
/// which is why such a layer is refused whole ([clipVectorTiles]).
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
