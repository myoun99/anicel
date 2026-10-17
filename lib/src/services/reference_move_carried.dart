import '../models/canvas_point.dart';
import '../models/canvas_size.dart';
import '../models/cut.dart';
import '../models/layer.dart';
import '../models/media_reference.dart';
import '../models/movie_cel.dart' show isMovieReference;
import '../models/property_track.dart';
import '../models/transform_track.dart';
import 'cut_frame_composite_plan.dart'
    show layerIdentityPose, resolveLayerAnchorPointAt, resolveLayerPoseAt;
import 'import/camera_track.dart' show transformTrackOfFramePoses;
import 'layer_pose_matrix.dart'
    show LayerPlacement, LayerPoseSample, placementOf;

/// How RASTERIZE keeps where [layer] shows its file as it lets the reference
/// go — ⛔ONE answer for every door that rasterizes (F-374-Q7, 유저
/// 2026-10-17: 「①은 스위치를 켜고 키로, ②③만 굽는다」):
///
/// * the move becomes the row's own transform
///   ([transformCarryingReferenceMove]) — F-374-Q3's keys, its switch on;
/// * where that transform cannot carry it, the cels take the picture where
///   the row shows it ([ReferenceMoveBaked]);
/// * and the rows F-374-Q9 · Q10 ask about wait, left the references they
///   are ([ReferenceMoveWaits]).
///
/// [others] is what the rows beside it hold ([OthersHold]).
ReferenceLetGo referenceLetGo({
  required Cut cut,
  required Layer layer,
  required OthersHold others,
  required bool Function(TransformPropertyId property, String name)
  nameIsFree,
}) {
  final carried = transformCarryingReferenceMove(
    cut: cut,
    layer: layer,
    nameIsFree: nameIsFree,
  );
  // ⏳F-374-Q10: the switch is the row's HEAD, one for every row that wears
  // it (유저 2026-08-06) — on, it shows the keys the others kept while it
  // was off, keys Q7 ① never weighed.
  final switchShowsOthers =
      carried != null &&
      carried.enabled &&
      !layer.transformEnabled &&
      others.keys;
  final keyed = switchShowsOthers ? null : carried;
  final movie = isMovieReference(layer);
  // ⏳F-374-Q10: a cel the link group shares is ONE picture
  // (`SwapLayerReferenceCommand`) — baked in place, every other use would
  // show it moved, and moved again by its own fx; and a movie's one cel
  // gives way to cels of its frames, which sweeps every other use's
  // exposures of it away (`UpdateLayerTimelineCommand`).
  if (others.cels && (movie || keyed == null)) {
    return const ReferenceMoveWaits();
  }
  if (keyed != null) {
    return ReferenceMoveKeyed(keyed.track, enabled: keyed.enabled);
  }
  // ⏳F-374-Q9: a cel baked in place holds the picture at ONE place, and an
  // image row holds one cel (D22) — a still that moves has no cels to take
  // its frames. A movie's are made a position apiece.
  final fx = layer.mediaReference!.fx;
  return movie || fx.lanes.every((l) => l.keys.length < 2)
      ? const ReferenceMoveBaked()
      : const ReferenceMoveWaits();
}

/// What the rows beside a reference row hold that its rasterize must not
/// disturb ([referenceLetGo]): [keys] — another row wearing its head, its
/// transform switch with it (`headMirrorRows`), keeps transform keys of its
/// own, which the switch coming on would show; [cels] — another use of its
/// link group shows its cels.
typedef OthersHold = ({bool keys, bool cels});

/// What [referenceLetGo] answers.
sealed class ReferenceLetGo {
  const ReferenceLetGo();
}

/// The move carried into the row's own transform: [track], with its switch
/// [enabled].
final class ReferenceMoveKeyed extends ReferenceLetGo {
  const ReferenceMoveKeyed(this.track, {required this.enabled});

  final TransformTrack track;
  final bool enabled;
}

/// The cels take the picture where the row shows it, and the row's
/// transform and switch stay as they are (F-374-Q7 ②③: 「멈춘 참조는 한 장
/// (보이는 크기 그대로), 움직이는 참조는 움직이는 프레임마다 한 장」).
final class ReferenceMoveBaked extends ReferenceLetGo {
  const ReferenceMoveBaked();
}

/// Neither yet: the row stays the reference it is.
final class ReferenceMoveWaits extends ReferenceLetGo {
  const ReferenceMoveWaits();
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
/// Null when the row's transform cannot carry the move (F-374-Q7 ②③ — the
/// cels take it): an attach row stands where its base's transform puts it,
/// and a row scaled unevenly under a picture turned other than by a quarter
/// would have to SHEAR it, which no pose does.
({TransformTrack track, bool enabled})? transformCarryingReferenceMove({
  required Cut cut,
  required Layer layer,
  required bool Function(TransformPropertyId property, String name)
  nameIsFree,
}) {
  final reference = layer.mediaReference;
  if (reference == null ||
      (reference.fx.isEmpty && reference.pose == reference.laid)) {
    return (track: layer.transformTrack, enabled: layer.transformEnabled);
  }
  final laid = reference.laid;
  // A file is laid 1:1 and upright since F-374-Q1 (`placedReference`): the
  // carry reads the fx's pose as the row's over the cel's own pixels, and a
  // lay that is not would need that lay undone first.
  if (isAttachedLayer(layer) || laid != TransformPose(center: laid.center)) {
    return null;
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
  return track == null ? null : (track: track, enabled: true);
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
