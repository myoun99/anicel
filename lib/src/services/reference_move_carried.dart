import '../models/canvas_point.dart';
import '../models/canvas_size.dart';
import '../models/cut.dart';
import '../models/layer.dart';
import '../models/media_reference.dart';
import '../models/movie_cel.dart' show isMovieReference;
import '../models/property_track.dart';
import '../models/transform_track.dart';
import 'cut_frame_composite_plan.dart'
    show
        layerIdentityPose,
        referenceMoveAt,
        resolveLayerAnchorPointAt,
        resolveLayerPoseAt;
import 'import/camera_track.dart' show transformTrackOfFramePoses;
import 'layer_pose_matrix.dart'
    show LayerPlacement, LayerPoseSample, placementOf;

/// One use of a reference row's cels — a member of its 겸용 link group, or
/// the row alone — with the cut it stands in.
typedef ReferenceUse = ({Cut cut, Layer layer});

/// How RASTERIZE keeps where a reference row shows its file as it lets the
/// reference go — ⛔ONE answer for every door that rasterizes (F-374-Q7,
/// 유저 2026-10-17: 「①은 스위치를 켜고 키로, ②③만 굽는다」), asked of every
/// one of [uses] together:
///
/// * a use's move becomes its own transform
///   ([transformCarryingReferenceMove]) — F-374-Q3's keys, its switch on;
/// * where a transform cannot carry it, the cels take the picture where
///   the use shows it ([ReferenceUseLetGo]'s `asShown`);
/// * and where the cels cannot either, every use waits, the reference it
///   is, and the row says why ([ReferenceMoveWaits] — F-374-Q11, 유저
///   2026-10-17: 「막고 경고」).
///
/// 🗣️F-374-Q10 (유저 2026-10-17: 「같은 셀을 보는 쓰임을 전부 같이」 —
/// 「겸용컷이니까 다른컷이 바뀌는거는 인지하고있는게 사용자 기준」): the uses
/// of one cel let go of it TOGETHER. Their switch is one — the row's HEAD
/// (유저 2026-08-06) — so where it comes on, the keys each use kept while it
/// was off give way. A still's cel is ONE picture
/// (`SwapLayerReferenceCommand`): baked in place, every use shows it moved,
/// so its uses take their moves as keys all or none, and the cel takes the
/// picture only where every use shows it at one place (Q10's cost: 「쓰임마다
/// 참조 fx 가 다르면 한 셀에 담을 수 없어, 그때는 막힙니다」). A movie's cels
/// are made a position apiece, so each of its uses takes its own way.
///
/// [othersKeepKeys]: a row that wears their head but shows none of their
/// cels — a track's conte row (`headMirrorRows`) — keeps transform keys of
/// its own, which the switch coming on would show. Q10 answered for the
/// uses alone, so those keys never give way: the uses bake instead, or
/// wait.
ReferenceLetGo referenceLetGo({
  required List<ReferenceUse> uses,
  required bool othersKeepKeys,
}) {
  final carries = [
    for (final use in uses)
      transformCarryingReferenceMove(
        cut: use.cut,
        layer: use.layer,
        nameIsFree: (_, _) => true,
      ),
  ];
  final turnsOn = [
    for (final (use, carry) in carries.indexed)
      carry is ReferenceCarried &&
          carry.enabled &&
          !uses[use].layer.transformEnabled,
  ];
  final uncarried = carries.whereType<ReferenceUncarried>().firstOrNull;
  final movie = uses.any((use) => isMovieReference(use.layer));
  final showsOthers = othersKeepKeys && turnsOn.contains(true);
  final keyed = [
    for (final carry in carries)
      !showsOthers &&
          carry is ReferenceCarried &&
          (movie || uncarried == null),
  ];
  if (!movie && !keyed.contains(true)) {
    final why = _whyTheCelWaits(
      uses,
      keysWait: uncarried?.why ?? ReferenceWait.othersKeepKeys,
    );
    if (why != null) {
      return ReferenceMoveWaits(why);
    }
  }
  final on = [
    for (final (use, key) in keyed.indexed) key && turnsOn[use],
  ].contains(true);
  return ReferenceMoveCarried(
    _usesLetGo(uses, carries, keyed: keyed, on: on),
    switchOn: on,
  );
}

/// Each of [uses] as it lets go ([referenceLetGo]): the track [carries]
/// gives a use that takes its move as keys ([keyed]), the row's own to one
/// that does not — none where the switch comes on ([on]) over keys it kept
/// while off.
///
/// The uses are one naming space (`transformTrackHoldingName`): a name a
/// key the fx named takes on one of them is free only where no other holds
/// it once they have let go — two that carry it would join keys the fx
/// never named, and neither keeps it.
List<ReferenceUseLetGo> _usesLetGo(
  List<ReferenceUse> uses,
  List<ReferenceCarry> carries, {
  required List<bool> keyed,
  required bool on,
}) {
  TransformTrack tracked(int use, ReferenceCarry carry) => switch (carry) {
    ReferenceCarried(:final track, enabled: true) when keyed[use] => track,
    _ when on && !uses[use].layer.transformEnabled => TransformTrack.empty(),
    _ => uses[use].layer.transformTrack,
  };
  final tracks = [
    for (final (use, carry) in carries.indexed) tracked(use, carry),
  ];
  bool heldElsewhere(int use, TransformPropertyId property, String name) => [
    for (final (other, track) in tracks.indexed)
      if (other != use) track,
  ].any((track) => transformLaneUsesName(track, property, name));
  return [
    for (final (index, use) in uses.indexed)
      (
        use: use,
        track: tracked(
          index,
          transformCarryingReferenceMove(
            cut: use.cut,
            layer: use.layer,
            nameIsFree: (property, name) =>
                !heldElsewhere(index, property, name),
          ),
        ),
        asShown: !keyed[index],
      ),
  ];
}

/// Why a still's one cel cannot take the picture where [uses] show it —
/// null where it can: each shows it at ONE place, the move its fx makes at
/// every frame ([referenceMoveAt]), and all of them at the same one. Where
/// an fx MOVES the picture there is no place to take, and the row waits for
/// [keysWait], what kept the keys from carrying it (F-374-Q9 · Q11): an
/// image row holds one cel (D22), and a still that moves has no cels to
/// take its frames.
ReferenceWait? _whyTheCelWaits(
  List<ReferenceUse> uses, {
  required ReferenceWait keysWait,
}) {
  final moves = <LayerPlacement?>{};
  for (final use in uses) {
    final fx = use.layer.mediaReference?.fx;
    if (fx != null && fx.lanes.any((lane) => lane.keys.length > 1)) {
      return keysWait;
    }
    moves.add(referenceMoveAt(use.layer, 0));
  }
  return moves.length > 1 ? ReferenceWait.usesApart : null;
}

/// What [referenceLetGo] answers.
sealed class ReferenceLetGo {
  const ReferenceLetGo();
}

/// Every use lets go of the reference, each the way [uses] says, and where
/// [switchOn] the switch they share comes on with them.
final class ReferenceMoveCarried extends ReferenceLetGo {
  const ReferenceMoveCarried(this.uses, {required this.switchOn});

  final List<ReferenceUseLetGo> uses;
  final bool switchOn;

  /// Whether a cel takes a picture where a use shows it — the rasterize
  /// that bakes.
  bool get bakes => uses.any((use) => use.asShown);
}

/// How one use lets go ([ReferenceMoveCarried]): the transform [track] it
/// is left with, and whether its cels take the picture where it shows it
/// ([asShown] — F-374-Q7 ②③: 「멈춘 참조는 한 장 (보이는 크기 그대로),
/// 움직이는 참조는 움직이는 프레임마다 한 장」) or where the file is laid,
/// the move its track's now.
typedef ReferenceUseLetGo = ({
  ReferenceUse use,
  TransformTrack track,
  bool asShown,
});

/// Neither yet: every use stays the reference it is, and [why] is what the
/// row's warning says.
final class ReferenceMoveWaits extends ReferenceLetGo {
  const ReferenceMoveWaits(this.why);

  final ReferenceWait why;
}

/// Why a rasterize leaves a reference row the reference it is
/// ([ReferenceMoveWaits]) — what its warning says, and how to get past it
/// (F-374-Q11 「막고 경고」: 「회전을 90° 단위로 · 배율을 고르게 · 어태치를
/// 풀면 그대로 「한 장 + 트랜스폼」으로 굽힙니다」) — the stable key the
/// string tables answer, and the English the UI falls back to (I-4, the
/// contract every reason a model gives keeps since F-124).
enum ReferenceWait {
  /// An attach row stands where its base's transform puts it: it has no
  /// transform of its own to key.
  attached(
    "An attached layer stands where its base's Transform puts it, so a "
    'moving Reference cannot become its own keys. Detach it to rasterize.',
  ),

  /// The file is laid on the cels other than 1:1 and upright — as a row
  /// placed before F-374-Q1 lays it.
  laidAsFitted(
    'This file was laid at a fitted size by an earlier version, so a '
    'moving Reference cannot become keys. Place the file again to '
    'rasterize.',
  ),

  /// The row is scaled unevenly under a picture turned other than by a
  /// quarter: a shear, which no pose of its own makes.
  sheared(
    'A turn other than by 90° under a Scale stretched on one axis is a '
    'shape no Transform draws. Even out the Scale, or turn by 90°, to '
    'rasterize.',
  ),

  /// The switch coming on would show keys a row wearing the head with it
  /// keeps ([referenceLetGo]'s `othersKeepKeys`).
  othersKeepKeys(
    'Another layer that shares this Transform switch keeps keys of its '
    'own while it is off, and switching it on would show them. Switch '
    'the Transform on first to rasterize.',
  ),

  /// The uses show the picture at different places, and the cel they share
  /// holds it at one.
  usesApart(
    "The linked layers show this cel's picture in different places, and "
    'one cel holds it in one. Match their Reference to rasterize.',
  );

  const ReferenceWait(this.label);

  /// The English wording, and the fallback for a language that has not
  /// tabled this reason (`ReferenceWaitWords.labelFor`).
  final String label;
}

/// What [transformCarryingReferenceMove] answers.
sealed class ReferenceCarry {
  const ReferenceCarry();
}

/// The move carried: the row's transform [track], its switch [enabled].
final class ReferenceCarried extends ReferenceCarry {
  const ReferenceCarried(this.track, {required this.enabled});

  final TransformTrack track;
  final bool enabled;
}

/// The row's transform cannot carry the move, and [why] — an attach row, a
/// file not laid 1:1, a shear.
final class ReferenceUncarried extends ReferenceCarry {
  const ReferenceUncarried(this.why);

  final ReferenceWait why;
}

/// [layer]'s own transform with its REFERENCE FX's move carried into it —
/// what RASTERIZE leaves the row at as it lets the reference go (§6-f): the
/// cels stand at every frame where the fx stood the file, by the row's own
/// keys now.
///
/// 🗣️F-374-Q3 (유저 2026-10-17, 「움직임을 그 행의 트랜스폼 키로 옮긴다
/// (추천)」): the pictures stay as the cels hold them — laid where the file
/// was laid, 1:1 since Q1 — and the fx's keys become the row's. The row
/// turns and scales them about where the file was laid, the picture's own
/// centre on its cels, as the fx turned the picture about its centre: that
/// place is the row's Anchor Point (none while it is the canvas's centre,
/// the lane's own default).
///
/// While none of the row's own lanes is keyed twice, the fx's keys are
/// carried AS THEY ARE — their frames, sides, paths and roving — each value
/// through the row's own pose, so the picture moves exactly as it did,
/// between keys too: but for a curved way under a row scaled unevenly,
/// which the walk by distance (I-89 ④) paces a little otherwise once the
/// scale has stretched it. A lane of the fx with no key carries its unkeyed
/// value as ONE key where the row starts — the way [transformTrackOfFramePoses]
/// keys a lane that never moves — none at the lane's identity, and a lane
/// the fx leaves as the row had it stays the row's ([_StillLanes]). Once
/// the row's own lanes move as well, the two moves are one only frame by
/// frame: the pose on every frame from the first key to the last is keyed
/// by [transformTrackOfFramePoses] — the keys of both on their frames, a
/// lane neither keys left as above, and a key more wherever a way between
/// them would stray from the picture by more than a pixel (유저 10-13 「1px
/// 까지 허용」).
///
/// A carried key keeps its NAME where [nameIsFree] says the row's naming
/// space holds no such name: the fx named its keys on itself alone, and the
/// row's lanes name across its 겸용 link group, where a name another use
/// holds would join keys the fx never named — and move them. The keys made
/// frame by frame carry none: their values are no longer the fx's.
///
/// The switch comes ON with the move (F-374-Q7 ①, 유저 2026-10-17: 「①은
/// 스위치를 켜고 키로」): a row whose transform is switched off shows none of
/// its own — the fx has no switch (I-68-Q1) — so the move is carried over
/// none, and the keys the row kept while it showed nothing give way. A row
/// with no move to carry keeps its transform and its switch as they are.
///
/// [ReferenceUncarried] when the row's transform cannot carry the move
/// (F-374-Q7 ②③ — the cels take it), and why: an attach row stands where
/// its base's transform puts it, and a row scaled unevenly under a picture
/// turned other than by a quarter would have to SHEAR it, which no pose
/// does.
ReferenceCarry transformCarryingReferenceMove({
  required Cut cut,
  required Layer layer,
  required bool Function(TransformPropertyId property, String name)
  nameIsFree,
}) {
  final reference = layer.mediaReference;
  if (reference == null ||
      (reference.fx.isEmpty && reference.pose == reference.laid)) {
    return ReferenceCarried(
      layer.transformTrack,
      enabled: layer.transformEnabled,
    );
  }
  final laid = reference.laid;
  if (isAttachedLayer(layer)) {
    return const ReferenceUncarried(ReferenceWait.attached);
  }
  // A file is laid 1:1 and upright since F-374-Q1 (`placedReference`): the
  // carry reads the fx's pose as the row's over the cel's own pixels, and a
  // lay that is not would need that lay undone first.
  if (laid != TransformPose(center: laid.center)) {
    return const ReferenceUncarried(ReferenceWait.laidAsFitted);
  }
  final shown = layer.transformEnabled
      ? layer
      : layer.copyWith(transformTrack: TransformTrack.empty());
  final canvas = cut.canvasSize;
  final row = shown.transformTrack;
  final own = [row.anchorPoint, row.position, row.scale, row.rotation];
  final track = own.every((lane) => lane.keys.length < 2)
      ? _keysCarried(shown, reference, canvas, nameIsFree)
      : _framesCarried(shown, reference, canvas, own);
  return track == null
      ? const ReferenceUncarried(ReferenceWait.sheared)
      : ReferenceCarried(track, enabled: true);
}

/// The fx's keys through the row's one pose ([transformCarryingReferenceMove]).
TransformTrack? _keysCarried(
  Layer layer,
  MediaReference reference,
  CanvasSize canvas,
  bool Function(TransformPropertyId property, String name) nameIsFree,
) {
  final carry = _KeysCarry(layer, reference, canvas, nameIsFree);
  // An uneven row scale carries only a picture the fx never turns other
  // than by a quarter.
  final turns = reference.fx.rotation.keys.length;
  if (!carry.carrier.carries(carry.turn) ||
      (!carry.carrier.even && turns > 1)) {
    return null;
  }
  return TransformTrack.properties(
    anchorPoint: carry.still.anchorPoint(reference.laid.center),
    position: carry.position,
    scale: carry.scale,
    rotation: carry.rotation,
    opacity: layer.transformTrack.opacity,
  );
}

/// Each of a row's lanes as the fx's keys carry them through its one pose.
class _KeysCarry {
  _KeysCarry(Layer layer, this.reference, CanvasSize canvas, this.nameIsFree)
    : carrier = _Carrier(_ownAt(layer, canvas, 0), canvas),
      still = _StillLanes(layer, canvas);

  final MediaReference reference;
  final bool Function(TransformPropertyId property, String name) nameIsFree;
  final _Carrier carrier;
  final _StillLanes still;

  TransformTrack get _fx => reference.fx;
  TransformPose get _pose => reference.pose;

  /// The one turn of an fx keyed at most once there.
  double get turn => _fx.rotation.isEmpty
      ? _pose.rotationDegrees
      : _fx.rotation.keys.values.first.value;

  PropertyTrack<CanvasPoint> get position => _fx.position.isEmpty
      ? still.position(carrier.centre(_pose.center))
      : _carried(
          _fx.position,
          TransformPropertyId.position,
          (key) => key.copyWith(
            value: carrier.centre(key.value),
            path: carrier.path(key.path),
          ),
        );

  PropertyTrack<CanvasPoint> get scale => _fx.scale.isEmpty
      ? still.scale(carrier.scaled(_pose.scale, turn))
      : _carried(
          _fx.scale,
          TransformPropertyId.scale,
          (key) => key.copyWith(value: carrier.scaled(key.value, turn)),
        );

  PropertyTrack<double> get rotation => _fx.rotation.isEmpty
      ? still.rotation(carrier.turned(_pose.rotationDegrees))
      : _carried(
          _fx.rotation,
          TransformPropertyId.rotation,
          (key) => key.copyWith(value: carrier.turned(key.value)),
        );

  /// [keys] carried one by one, each keeping its name where that is free.
  PropertyTrack<T> _carried<T>(
    PropertyTrack<T> keys,
    TransformPropertyId property,
    PropertyKey<T> Function(PropertyKey<T> key) carry,
  ) => PropertyTrack(
    keys: {
      for (final MapEntry(key: frame, value: key) in keys.keys.entries)
        frame: carry(key).copyWith(
          name: () => switch (key.name) {
            final name? when nameIsFree(property, name) => name,
            _ => null,
          },
        ),
    },
  );
}

/// What one of [layer]'s lanes is left as where it stands at ONE value
/// all along and neither move keys it — the row's own lane while it stands
/// there already, none at the lane's identity, else ONE key where the row
/// starts: the way [transformTrackOfFramePoses] keys a lane that never
/// moves. ⛔One law for a lane the keys carry and a lane the frames do.
class _StillLanes {
  _StillLanes(this.layer, CanvasSize canvas)
    : centre = layerIdentityPose(canvas).center,
      start = layer.timeline.isEmpty ? 0 : layer.timeline.firstKey()!;

  final Layer layer;

  /// The canvas's centre: an empty Position's and Anchor Point's value.
  final CanvasPoint centre;

  /// Where the row starts — the frame a lane that never moves is keyed on.
  final int start;

  TransformTrack get _row => layer.transformTrack;

  PropertyTrack<CanvasPoint> anchorPoint(CanvasPoint value) =>
      _held(_row.anchorPoint, value, centre, _keyed);

  PropertyTrack<CanvasPoint> position(CanvasPoint value) => _held(
    _row.position,
    value,
    centre,
    (value) => positionLaneKeyed(PropertyTrack.empty(), start, value),
  );

  PropertyTrack<CanvasPoint> scale(CanvasPoint value) =>
      _held(_row.scale, value, uniformScale(1), _keyed);

  PropertyTrack<double> rotation(double value) =>
      _held(_row.rotation, value, 0.0, _keyed);

  /// [fitted] — a lane fitted frame by frame on the frames [keyedOn] —
  /// left as [held] leaves it where neither move keys it and it came out
  /// ONE key, never moving.
  PropertyTrack<T> settled<T>(
    PropertyTrack<T> fitted,
    Iterable<int> keyedOn,
    PropertyTrack<T> Function(T value) held,
  ) => keyedOn.isEmpty && fitted.keys.length == 1
      ? held(fitted.keys.values.single.value)
      : fitted;

  PropertyTrack<T> _held<T>(
    PropertyTrack<T> own,
    T value,
    T identity,
    PropertyTrack<T> Function(T value) keyed,
  ) {
    final owned = own.keys.isEmpty ? identity : own.keys.values.single.value;
    return value == owned
        ? own
        : value == identity
        ? PropertyTrack<T>.empty()
        : keyed(value);
  }

  PropertyTrack<T> _keyed<T>(T value) =>
      PropertyTrack(keys: {start: PropertyKey(value)});
}

/// The two moves frame by frame ([transformCarryingReferenceMove]).
TransformTrack? _framesCarried(
  Layer layer,
  MediaReference reference,
  CanvasSize canvas,
  List<PropertyTrack<Object?>> own,
) {
  final fx = reference.fx;
  Set<int> keyed(Iterable<PropertyTrack<Object?>> lanes) => {
    for (final lane in lanes) ...lane.keys.keys,
  };
  final frames = keyed([...own, ...fx.lanes]).toList()..sort();
  final byFrame = <int, LayerPoseSample>{};
  for (var frame = frames.first; frame <= frames.last; frame += 1) {
    final carrier = _Carrier(_ownAt(layer, canvas, frame), canvas);
    final pose = carrier.pose(reference.poseAt(frame));
    if (pose == null) {
      return null;
    }
    // The anchor is where the file was laid on every frame — a lane of its
    // own, left as a still one is.
    byFrame[frame] = (pose: pose, anchorPoint: null);
  }
  final row = layer.transformTrack;
  final keyedOn = (
    anchorPoint: const <int>{},
    // The picture's centre goes where the row's whole pose puts the fx's:
    // every lane of the row moves it.
    position: keyed([...own, fx.position]),
    scale: keyed([row.scale, fx.scale]),
    rotation: keyed([row.rotation, fx.rotation]),
  );
  final fitted = transformTrackOfFramePoses(byFrame, keyedOn: keyedOn);
  final still = _StillLanes(layer, canvas);
  return TransformTrack.properties(
    anchorPoint: still.anchorPoint(reference.laid.center),
    position: fitted.position,
    scale: still.settled(fitted.scale, keyedOn.scale, still.scale),
    rotation: still.settled(fitted.rotation, keyedOn.rotation, still.rotation),
    opacity: row.opacity,
  );
}

/// [layer]'s own pose and anchor at [frame] — its identity while its lanes
/// are empty.
LayerPoseSample _ownAt(Layer layer, CanvasSize canvas, int frame) => (
  pose:
      resolveLayerPoseAt(layer: layer, canvasSize: canvas, frameIndex: frame) ??
      layerIdentityPose(canvas),
  anchorPoint: resolveLayerAnchorPointAt(layer: layer, frameIndex: frame),
);

/// The row's own pose at one frame, as it carries where the fx stands the
/// picture: the fx's centre goes where the row's placement puts it, the
/// fx's turn after the row's, and the fx's two scales — over the cel's own
/// pixels, the file laid 1:1 — under the row's, whose two axes a quarter
/// turn of the picture swaps. ⛔One law for a key carried and a frame
/// carried: the composite's own order, the row's pose over the fx's move
/// (`placementUnderFolders`' `within`).
class _Carrier {
  _Carrier(LayerPoseSample own, CanvasSize canvas)
    : placement = placementOf(own, canvas),
      turn = own.pose.rotationDegrees,
      scale = own.pose.scale;

  final LayerPlacement placement;
  final double turn;
  final CanvasPoint scale;

  bool get even => scale.x == scale.y;

  /// Whether a picture the fx turns by [shown] stands under the row's
  /// scale without a shear: an even scale carries any turn, an uneven one
  /// a quarter's.
  bool carries(double shown) => even || shown % 90 == 0;

  CanvasPoint centre(CanvasPoint shown) => placement.apply(shown);

  KeyPath path(KeyPath shown) => switch (shown) {
    HandledPath(:final tangent) => HandledPath(
      CanvasPoint(
        x: placement.a * tangent.x + placement.c * tangent.y,
        y: placement.b * tangent.x + placement.d * tangent.y,
      ),
    ),
    _ => shown,
  };

  double turned(double shown) => turn + shown;

  CanvasPoint scaled(CanvasPoint shown, double shownTurn) {
    final swapped = !even && (shownTurn / 90).round().isOdd;
    return CanvasPoint(
      x: (swapped ? scale.y : scale.x) * shown.x,
      y: (swapped ? scale.x : scale.y) * shown.y,
    );
  }

  /// The row's pose that stands the picture where [shown] does, or null
  /// when it would shear.
  TransformPose? pose(TransformPose shown) {
    if (!carries(shown.rotationDegrees)) {
      return null;
    }
    final scales = scaled(shown.scale, shown.rotationDegrees);
    return TransformPose(
      center: centre(shown.center),
      scaleX: scales.x,
      scaleY: scales.y,
      rotationDegrees: turned(shown.rotationDegrees),
    );
  }
}
