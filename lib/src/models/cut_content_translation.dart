import 'dart:math' as math;

import 'camera_pose.dart';
import 'canvas_point.dart';
import 'canvas_size.dart';
import 'cut.dart';
import 'cut_camera.dart';
import 'drawing_guide.dart';
import 'layer.dart';
import 'layer_effect.dart';
import 'property_track.dart';
import 'transform_track.dart';

/// D5 (R7): carries a cut's CANVAS-COORDINATE model data through a canvas
/// resize — the model half of "the picture moves, so everything pinned to
/// it moves too". The raster half is the store's; this file owns camera
/// keyframes, guides, layer transform poses, where a reference row lays its
/// file and its effects' points, stands and pixel values.
///
/// A resize carries a point of the old canvas to `scale ∘ point + offset` on
/// the new ([ResizeWalk]). At scale 1 — 원본 크기, what every resize was —
/// it is a crop/extend: the content moves and nothing changes size (R19).
/// 🗣️I-180 (유저 2026-11-19 · 20): a resize may FIT the picture to the new
/// canvas as an import fits a file (비율 유지 · 비율 무시), and then
/// 「그림이나 내부 값이나 키나 싹 다 변경」 — places by the scale, and a
/// number that sizes something by the one size factor ([_sizeOf]).
/// 「내용물 변경안하는걸 옵션으로 … 지금이랑 같은 법」: 원본 크기 is today's
/// resize, every value here at scale 1.
///
/// Two offsets, because the render math has two kinds of pinning:
///
///  * [ResizeWalk.dx]/[ResizeWalk.dy] — the CONTENT's (where the pixels
///    went; at scale 1 rounded to the raster's whole-pixel blit so model and
///    picture stay in lockstep). Camera centres, guides and EXPLICIT
///    transform anchors/positions go by this.
///  * [ResizeWalk.centreDx]/[ResizeWalk.centreDy] — the CANVAS CENTRE's: a
///    NULL transform anchor re-reads as the canvas centre at draw time, so
///    a null-anchored pose renders as `q + position − centre`, and keeping
///    it pinned to its picture takes the position to `centre' + scale ∘
///    (position − centre)` — at scale 1 `position += Δcentre`, NOT the
///    content offset (the two agree only where the content's centre lands
///    on the canvas's: the centre resize anchor, and every fit). Exact at
///    zoom 1 / rotation 0 for every resize anchor, and exact at any zoom for
///    the centre anchor; a null-anchored pose that is BOTH scaled-or-rotated
///    AND resized off-centre has no key-level compensation (the correction
///    is frame-dependent) — and a turned pose under a scale that differs
///    across and down (비율 무시) would need a shear no pose holds. Those
///    corners are named here rather than silently wrong.
typedef ResizeWalk = ({
  double sx,
  double sy,
  double dx,
  double dy,
  double centreDx,
  double centreDy,
});

/// A resize that moves the content by ([dx], [dy]) and the canvas centre by
/// ([centreDx], [centreDy]) at [sx] × [sy] — 1 × 1, a crop/extend.
ResizeWalk resizeWalk({
  required double dx,
  required double dy,
  required double centreDx,
  required double centreDy,
  double sx = 1,
  double sy = 1,
}) => (
  sx: sx,
  sy: sy,
  dx: dx,
  dy: dy,
  centreDx: centreDx,
  centreDy: centreDy,
);

/// Whether [walk] leaves every point where it is.
bool _stays(ResizeWalk walk) =>
    walk.sx == 1 && walk.sy == 1 && walk.dx == 0 && walk.dy == 0;

/// The ONE number a resize sizes a number by — a camera's zoom, a pixel
/// value, a cel number's letters: the scale where it is the same across and
/// down, and where it is not, the two's geometric mean.
///
/// 🗣️I-180-Q2 a (유저 2026-11-20): 「두 배율의 기하평균」 for a pixel value,
/// and I-180-Q4 a 「기하평균의 역수 — Q2 와 같은 법」 for the camera's zoom;
/// I-180-Q3's memo 「크기라는건 배율 말한거였음. 가로세로길이 하나만 어긋나게
/// 바뀌는게아니라」 — a size is one scale, never stretched across alone.
double _sizeOf(ResizeWalk walk) => math.sqrt(walk.sx * walk.sy);

CanvasPoint _carried(CanvasPoint point, ResizeWalk walk) => CanvasPoint(
  x: walk.sx * point.x + walk.dx,
  y: walk.sy * point.y + walk.dy,
);

/// [track] with each key's value [map]ped — every other part of the key
/// as it was.
PropertyTrack<T> _mappedKeys<T>(PropertyTrack<T> track, T Function(T) map) =>
    PropertyTrack(
      keys: {
        for (final entry in track.keys.entries)
          entry.key: entry.value.copyWith(value: map(entry.value.value)),
      },
    );

/// [path]'s handles — canvas pixels out of their key — at [walk]'s scale:
/// a path through keys carried by a scale is the path carried by it.
KeyPath _scaledPath(KeyPath path, ResizeWalk walk) => switch (path) {
  _ when walk.sx == 1 && walk.sy == 1 => path,
  SplitPath(:final ahead, :final behind) => SplitPath(
    ahead: CanvasPoint(x: walk.sx * ahead.x, y: walk.sy * ahead.y),
    behind: CanvasPoint(x: walk.sx * behind.x, y: walk.sy * behind.y),
  ),
  JoinedPath(:final degrees, :final ahead, :final behind) => JoinedPath(
    degrees: _scaledDegrees(degrees, walk),
    ahead: ahead * _reachAlong(degrees, walk),
    behind: behind * _reachAlong(degrees, walk),
  ),
  _ => path,
};

/// How far one canvas pixel [degrees] from the x axis reaches at [walk]'s
/// scale.
double _reachAlong(double degrees, ResizeWalk walk) {
  final radians = degrees * math.pi / 180;
  final across = walk.sx * math.cos(radians);
  final down = walk.sy * math.sin(radians);
  return math.sqrt(across * across + down * down);
}

/// A way on the canvas, [degrees] from its x axis, as [walk]'s scale turns
/// it. ⚠️A quarter turn stays one exactly: `cos(90°)` is 6e-17, not 0, and
/// an axis-aligned way is axis-aligned at any scale.
double _scaledDegrees(double degrees, ResizeWalk walk) {
  if (walk.sx == walk.sy || degrees / 90 == (degrees / 90).roundToDouble()) {
    return degrees;
  }
  final radians = degrees * math.pi / 180;
  return math.atan2(walk.sy * math.sin(radians), walk.sx * math.cos(radians)) *
      180 /
      math.pi;
}

PropertyTrack<CanvasPoint> _carriedPointTrack(
  PropertyTrack<CanvasPoint> track,
  ResizeWalk walk,
) {
  if (track.isEmpty || _stays(walk)) {
    return track;
  }
  return PropertyTrack(
    keys: {
      for (final entry in track.keys.entries)
        entry.key: entry.value.copyWith(
          value: _carried(entry.value.value, walk),
          path: _scaledPath(entry.value.path, walk),
        ),
    },
  );
}

/// A POSITION lane carried by [walk]'s content map. EMPTY, it reads
/// [centre] — the canvas centre of the size it stood on, which [walk]
/// carries to the new centre; where that is not where the content map puts
/// it, it is keyed first where it stood, or its pose walks off its picture.
///
/// 🗣️F-362 (유저 2026-10-20): 「캔버스 크기 바꾸면 카메라도 이동해버림.
/// 소재는 기존 위치에 존재하는게 규칙 … 키를 찍어서라도 이동시켜두도록」 —
/// After Effects' Composition Settings anchor 「layers to a corner or edge
/// of the composition as it is resized」, the camera among them. ⛔No
/// tolerance: a centre resize by an odd size rounds the content half a
/// pixel off the centre, and the pose stays on the content there too.
PropertyTrack<CanvasPoint> _carriedPositionLane(
  PropertyTrack<CanvasPoint> lane, {
  required CanvasPoint centre,
  required ResizeWalk walk,
}) {
  final stood =
      lane.isEmpty && (walk.dx != walk.centreDx || walk.dy != walk.centreDy)
      ? pathLaneKeyed(lane, 0, centre)
      : lane;
  return _carriedPointTrack(stood, walk);
}

/// A SIZE lane — a scale's — at [by] times what it stood at. EMPTY, it
/// stood at 1 and is keyed there first, as an empty position lane is
/// ([_carriedPositionLane]).
PropertyTrack<CanvasPoint> _sizedLane(
  PropertyTrack<CanvasPoint> lane,
  double by,
) {
  if (by == 1) {
    return lane;
  }
  final stood = lane.isEmpty
      ? PropertyTrack<CanvasPoint>(keys: {0: PropertyKey(uniformScale(1))})
      : lane;
  return _mappedKeys(
    stood,
    (scale) => CanvasPoint(x: scale.x * by, y: scale.y * by),
  );
}

/// Every camera keyframe centre goes with the content — THROUGH THE LANES,
/// never the pose facade: `CutCamera(keyframes:)` rebuilds all lanes from
/// resolved poses, which linearizes holds, erases key names and
/// synthesizes keys at the union frames (adversarial review). The position
/// lane and an explicit anchor lane go by [walk]; the zoom by the size
/// factor's inverse, so the film shows what it showed of the picture
/// (🗣️I-180-Q3 a · Q4 a); rotation and opacity pass through. An UNKEYED
/// position reads [defaultCameraPoseFor] on [from] ([_carriedPositionLane]),
/// an unkeyed zoom 1 ([_sizedLane]).
CutCamera carryCutCamera(
  CutCamera camera,
  ResizeWalk walk, {
  required CanvasSize from,
}) {
  final track = camera.track;
  final position = _carriedPositionLane(
    track.position,
    centre: defaultCameraPoseFor(from).center,
    walk: walk,
  );
  final anchorPoint = _carriedPointTrack(track.anchorPoint, walk);
  final scale = _sizedLane(track.scale, 1 / _sizeOf(walk));
  if (identical(position, track.position) &&
      identical(anchorPoint, track.anchorPoint) &&
      identical(scale, track.scale)) {
    return camera;
  }
  return CutCamera.fromTrack(
    track.copyWith(position: position, anchorPoint: anchorPoint, scale: scale),
  );
}

GuideAxis _carriedAxis(GuideAxis axis, ResizeWalk walk) => axis.copyWith(
  origin: _carried(axis.origin, walk),
  angleDegrees: _scaledDegrees(axis.angleDegrees, walk),
);

GuideLine _carriedLine(GuideLine line, ResizeWalk walk) =>
    line.copyWith(a: _carried(line.a, walk), b: _carried(line.b, walk));

VanishingPoint _carriedVanishingPoint(
  VanishingPoint point,
  ResizeWalk walk,
) => switch (point) {
  VanishingPointAt(:final point) => VanishingPointAt(_carried(point, walk)),
  // A direction is a vector, not a place — it does not move; a scale that
  // differs across and down turns it.
  VanishingPointTowards(:final dx, :final dy) =>
    walk.sx == walk.sy ? point : _scaledWay(dx, dy, walk),
  VanishingPointFromLines(:final first, :final second) =>
    VanishingPointFromLines(
      _carriedLine(first, walk),
      _carriedLine(second, walk),
    ),
};

/// The way ([dx], [dy]) runs on the canvas, as [walk]'s scale turns it —
/// one long, as a direction is written.
VanishingPointTowards _scaledWay(double dx, double dy, ResizeWalk walk) {
  final across = walk.sx * dx;
  final down = walk.sy * dy;
  final length = math.sqrt(across * across + down * down);
  return VanishingPointTowards(dx: across / length, dy: down / length);
}

GuideShape _carriedShape(GuideShape shape, ResizeWalk walk) =>
    switch (shape) {
      SymmetryShape() => shape.copyWith(
        axis: _carriedAxis(shape.axis, walk),
      ),
      PerspectiveShape() => shape.copyWith(
        eyeLevel: _carriedAxis(shape.eyeLevel, walk),
        vanishingPoints: [
          for (final point in shape.vanishingPoints)
            _carriedVanishingPoint(
              point,
              walk,
            ).drawing(point.lineDensity),
        ],
      ),
    };

/// Every guide's canvas-coordinate geometry goes with the content — the
/// resize command's own doc names guides as the reason 겸용 siblings
/// resize together ("an axis stored in canvas coordinates means two
/// different places when the canvases disagree"), yet the old command
/// never moved them.
CutGuides carryCutGuides(CutGuides guides, ResizeWalk walk) {
  if (guides.isEmpty || _stays(walk)) {
    return guides;
  }
  return guides.copyWith(
    guides: [
      for (final guide in guides.guides)
        guide.copyWith(shape: _carriedShape(guide.shape, walk)),
    ],
  );
}

/// [effect]'s pixel values ([EffectParameterUnit.pixels] — a blur's radius)
/// at [by] times what they were, their keys with them.
Map<String, EffectParameter> _sizedPixelValues(LayerEffect effect, double by) {
  bool inPixels(String id) =>
      effect.specOf(id)?.unit == EffectParameterUnit.pixels;
  if (by == 1 || !effect.parameters.keys.any(inPixels)) {
    return effect.parameters;
  }
  return {
    for (final MapEntry(key: id, value: parameter)
        in effect.parameters.entries)
      id: inPixels(id)
          ? EffectParameter(
              value: parameter.value * by,
              track: _mappedKeys(parameter.track, (value) => value * by),
            )
          : parameter,
  };
}

/// An effect's canvas-coordinate keys carried by [walk] with the picture it
/// filters: its points ([LayerEffect.points] — a radial blur's centre) and
/// where a kind that draws its own picture stands it ([LayerEffect.stand]
/// — a cel number's letters), and its pixel values and the size it stands
/// its picture at by the size factor ([_sizeOf]). Points and stands are the
/// row's paper's, read before its pose as its cels' pixels are, so the
/// content map carries them. Unkeyed, they read the paper's middle
/// ([effectPointOnPaper], [effectStandPose]), a row at rest's on [from] —
/// and are keyed where they stood first, as a position lane is
/// ([_carriedPositionLane]). A kind that draws no picture of its own stands
/// none ([LayerEffect]'s constructor).
///
/// ↩️The resize moved none of these: a radial blur's centre and a cel
/// number's letters stayed on the old canvas's coordinates as the picture
/// moved off them (card a-canvas-resize-leaves-effect-points-behind).
LayerEffect _carriedEffect(
  LayerEffect effect, {
  required CanvasSize from,
  required ResizeWalk walk,
}) {
  final centre = layerIdentityPose(from).center;
  final size = _sizeOf(walk);
  TransformTrack placed(TransformTrack keys, {required bool sized}) {
    final position = _carriedPositionLane(
      keys.position,
      centre: centre,
      walk: walk,
    );
    final scale = sized ? _sizedLane(keys.scale, size) : keys.scale;
    return identical(position, keys.position) && identical(scale, keys.scale)
        ? keys
        : keys.copyWith(position: position, scale: scale);
  }

  final points = {
    for (final entry in effect.points.entries)
      entry.key: placed(entry.value, sized: false),
  };
  final stand = effect.kind.drawsItsOwnPicture
      ? placed(effect.stand, sized: true)
      : effect.stand;
  final parameters = _sizedPixelValues(effect, size);
  if (identical(stand, effect.stand) &&
      identical(parameters, effect.parameters) &&
      points.entries.every(
        (entry) => identical(entry.value, effect.points[entry.key]),
      )) {
    return effect;
  }
  return effect.copyWith(
    points: points,
    stand: stand,
    parameters: parameters,
  );
}

/// [pose] — a picture's on the canvas — carried by [walk]: its centre by
/// the content map, its size by the scale on each axis, as the picture is.
TransformPose _carriedPose(TransformPose pose, ResizeWalk walk) =>
    pose.copyWith(
      center: _carried(pose.center, walk),
      scaleX: pose.scaleX * walk.sx,
      scaleY: pose.scaleY * walk.sy,
    );

/// A layer's canvas-coordinate model data goes with its picture:
///
///  * EXPLICIT anchor keys and their position keys go by the content map —
///    the pose subtracts the anchor, so carrying both keeps the render
///    identical at every zoom.
///  * A NULL anchor re-reads as the canvas centre, so the position keys go
///    by the centre's instead (see the file doc).
///  * An UNKEYED position under an explicit anchor reads
///    [layerIdentityPose] on [from] ([_carriedPositionLane]).
///  * Its own scale and turn stay: its cels are laid anew at the resize's
///    scale, and a row's scale is of them.
///  * The file a REFERENCE row shows stands where its reference fx puts its
///    centre on the canvas (I-68), and that goes by the content map like a
///    camera's centre: the picture keeps its place among the drawings, and
///    a file swapped in or laid again afterwards stands there too (유저
///    2026-10-10 「캔버스 크기 변경 … 가」 — 기준점대로). Its file is no
///    cel laid anew: its pose's size, and its fx's, go by the scale.
///  * Its effects' points, stands and pixel values go with its cels' pixels
///    ([_carriedEffect]).
///
/// 🪦A bullet before the reference's moved a TEXT cel's canvas-coordinate
/// anchor with its picture. The TEXT row went with F-154 and its payload
/// with the save format's floor (`anicelOldestReadFormatVersion`): nothing
/// holds one.
Layer carryLayerForResize(
  Layer layer, {
  required CanvasSize from,
  required ResizeWalk walk,
}) {
  final track = layer.transformTrack;
  final hasExplicitAnchor = track.anchorPoint.isNotEmpty;
  final positionWalk = hasExplicitAnchor
      ? walk
      : resizeWalk(
          sx: walk.sx,
          sy: walk.sy,
          dx: walk.centreDx,
          dy: walk.centreDy,
          centreDx: walk.centreDx,
          centreDy: walk.centreDy,
        );
  final reference = layer.mediaReference;
  final effects = [
    for (final effect in layer.effects)
      _carriedEffect(effect, from: from, walk: walk),
  ];
  final effectsMoved = !effects.indexed.every(
    (each) => identical(each.$2, layer.effects[each.$1]),
  );
  if (track.position.isEmpty &&
      track.anchorPoint.isEmpty &&
      reference == null &&
      !effectsMoved) {
    return layer;
  }
  return layer.copyWith(
    effects: effectsMoved ? effects : null,
    transformTrack: track.copyWith(
      position: _carriedPositionLane(
        track.position,
        centre: layerIdentityPose(from).center,
        walk: positionWalk,
      ),
      anchorPoint: _carriedPointTrack(track.anchorPoint, walk),
    ),
    // Its keys and where its file is laid stand on the same canvas (F-374),
    // so they go with it — the cel's pixels go with the drawings.
    mediaReference: reference?.copyWith(
      pose: _carriedPose(reference.pose, walk),
      fx: reference.fx.copyWith(
        position: _carriedPointTrack(reference.fx.position, walk),
        scale: walk.sx == 1 && walk.sy == 1
            ? reference.fx.scale
            : _mappedKeys(
                reference.fx.scale,
                (scale) =>
                    CanvasPoint(x: scale.x * walk.sx, y: scale.y * walk.sy),
              ),
      ),
      laid: _carriedPose(reference.laid, walk),
    ),
  );
}

/// The whole cut's model follow for a resize: camera, guides and every
/// layer's canvas coordinates, in one immutable copy. The canvas size
/// itself is the caller's write (it differs per call site).
Cut carryCutContentModel(Cut cut, ResizeWalk walk) {
  if (_stays(walk) && walk.centreDx == 0 && walk.centreDy == 0) {
    return cut;
  }
  return cut.copyWith(
    camera: carryCutCamera(cut.camera, walk, from: cut.canvasSize),
    guides: carryCutGuides(cut.guides, walk),
    layers: [
      for (final layer in cut.layers)
        carryLayerForResize(layer, from: cut.canvasSize, walk: walk),
    ],
  );
}
