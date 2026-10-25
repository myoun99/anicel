import 'canvas_point.dart';
import 'canvas_size.dart';
import 'media_asset.dart' show normalizedMediaPath;
import 'transform_track.dart';

/// A layer's link to an EXTERNAL media source (§6-z23, the two-axis
/// model): the layer KIND says what the row is (image vs animation), and
/// THIS field alone says whether its pixels come from a library asset.
/// Null = a normal drawn layer.
///
/// The predicate the import design settled on — "cannot draw with the
/// brush + can rasterize" — IS `mediaReference != null`, on any kind:
/// an image layer referencing a still, an animation layer referencing a
/// sequence/GIF/video/PDF. RASTERIZING never changes the kind — it bakes
/// pixels into the cels and nulls this field, nothing else.
///
/// [assetPath] is the media pool's key (the absolute file path — the same
/// identity [AudioClip.filePath] uses; relinks rewrite it in the same
/// walk). [frameOffset] is how many source frames are skipped before the
/// layer's first frame — the time mapping for sequence/video sources,
/// [AudioClip.offsetFrames]'s exact analogue; stills ignore it.
///
/// [pose] is WHERE the file's picture stands on the canvas — the row's
/// REFERENCE FX (I-68). 🗣️유저 2026-10-04: 「처음에 용지 세팅하고나서 오른쪽으로
/// 캔버스 크기 늘리고나서, 용지 스위칭하려고 배치하면 캔버스 중앙에
/// 배치되는데 … 구조적,근본적인 해결」 — a paper swapped in after the canvas
/// had grown was fitted to the NEW canvas, because where the old one stood
/// was written nowhere. 10-09: 「fx로서 se의 네임태그마냥 참조fx라고
/// 전용fx만들어서 거기서 오프셋 관리」. I-68-Q1: 「레이어의 fx버튼 꺼도 그 자리
/// 유지되고 출력시에도 fx 적용 해제되있어도 유지됨」 — so it is not an effect
/// the switches bypass: the picture is laid at it when its pixels are made.
/// 🗣️I-65-Q6 (유저 2026-10-25): 「참조 fx 도 끈다(정말 날 것)」 — an output's
/// 끔 lays the picture where its pixels are laid ([laid], `layerAsOutput`);
/// 기본만 켬 keeps it. ↩️The output half of I-68-Q1 kept it whatever.
/// 10-10 (chat): 「담는값은 변형도구랑 같은거 공유 … 변형으로 크기 줄였으면
/// 같은값만큼 다른용지도 줄어들게 … 해상도가 달라도 같은크기로 겹치지않게 …
/// 배치된 값, 원본값 유지」 — a transform's values (the picture's centre on
/// the canvas, a scale per axis, a turn about that centre) over the
/// picture's OWN pixels, so another file takes the same values on ITS
/// pixels and a paper of another resolution stands at another size. The fit
/// a placement is made with only says where it STARTS (`fitPose`); nothing
/// fits it again.
///
/// [pictureSize] is the size of the picture the row shows, in its own
/// pixels — what [pose] stands on (원본값), and what a box around it is
/// drawn from.
///
/// [fx] is the reference fx's KEYS — position, scale and turn keyed the
/// way a transform's are, over the same values. ↩️It held none: 「키 없는
/// 값 하나」 (I-68 상담 ③ 「가」, 2026-10-10). 🗣️유저 2026-10-17 (F-374):
/// 「참조fx도 똑같이 fx로서 법 통일. 지금 움직여도 키 안생긴다거나 그런 각종
/// fx관련 싹 통일」. Unkeyed, a lane stands at [pose] — the value no edit
/// moves, as a transform's unkeyed lane stands at its identity — and keyed,
/// it stands where its keys say at each frame ([poseAt]). A sheet's photo
/// has no frames, so it never keys one.
///
/// [laid] is where the file's pixels are LAID on the row's cels — the
/// canvas moves them from there to [poseAt]. The file is laid 1:1 when the
/// row is placed (`placedReference`) and where it was when the row takes
/// another file, never because its fx moved: 🗣️F-374-Q1 (유저 2026-10-17,
/// 「트랜스폼처럼 화면에서 옮긴다」) 「굳이 다시 그릴필요도없고 그래봣자 더
/// 선명해지지도않음」. ↩️Where the fx stood
/// the picture still, the file was laid there again — into [laid], not
/// [pose], or deleting the keys would have left the reference where they had
/// been, while a transform's go back to its identity.
class MediaReference {
  MediaReference({
    required String assetPath,
    this.frameOffset = 0,
    required this.pose,
    required this.pictureSize,
    TransformTrack? fx,
    TransformPose? laid,
  }) : assetPath = normalizedMediaPath(assetPath),
       fx = fx ?? TransformTrack.empty(),
       _laid = laid == pose ? null : laid;

  /// In the pool's one spelling ([normalizedMediaPath]).
  final String assetPath;
  final int frameOffset;
  final TransformPose pose;
  final CanvasSize pictureSize;
  final TransformTrack fx;

  /// Null while the pixels are laid at [pose] — so a [copyWith] that moves
  /// [pose] alone (a sheet photo dragged) moves them with it.
  final TransformPose? _laid;
  TransformPose get laid => _laid ?? pose;

  /// Where the reference fx stands the file's picture at [frameIndex].
  TransformPose poseAt(int frameIndex) => poseAtTime(frameIndex.toDouble());

  /// [poseAt] between frames too — a header graph's curve (I-89 ③).
  TransformPose poseAtTime(double time) =>
      fx.resolveAtTime(time: time, orElse: () => pose);

  MediaReference copyWith({
    String? assetPath,
    int? frameOffset,
    TransformPose? pose,
    CanvasSize? pictureSize,
    TransformTrack? fx,
    TransformPose? laid,
  }) => MediaReference(
    assetPath: assetPath ?? this.assetPath,
    frameOffset: frameOffset ?? this.frameOffset,
    pose: pose ?? this.pose,
    pictureSize: pictureSize ?? this.pictureSize,
    fx: fx ?? this.fx,
    laid: laid ?? _laid,
  );

  Map<String, dynamic> toJson() => {
    'path': assetPath,
    if (frameOffset != 0) 'offset': frameOffset,
    'pose': _poseToJson(pose),
    'size': pictureSize.toJson(),
    if (fx.isNotEmpty) 'fx': fx.toJson(),
    if (_laid case final laid?) 'laid': _poseToJson(laid),
  };

  factory MediaReference.fromJson(Map<String, dynamic> json) {
    final fx = json['fx'] as Map<String, dynamic>?;
    final laid = json['laid'] as Map<String, dynamic>?;
    return MediaReference(
      assetPath: json['path'] as String,
      frameOffset: (json['offset'] as int?) ?? 0,
      pose: _poseFromJson(json['pose'] as Map<String, dynamic>),
      pictureSize: CanvasSize.fromJson(json['size'] as Map<String, dynamic>),
      fx: fx == null ? null : TransformTrack.fromJson(fx),
      laid: laid == null ? null : _poseFromJson(laid),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is MediaReference &&
      other.assetPath == assetPath &&
      other.frameOffset == frameOffset &&
      other.pose == pose &&
      other.pictureSize == pictureSize &&
      other.fx == fx &&
      other.laid == laid;

  @override
  int get hashCode =>
      Object.hash(assetPath, frameOffset, pose, pictureSize, fx, laid);

  @override
  String toString() =>
      'MediaReference($assetPath, offset: $frameOffset, pose: $pose, '
      'size: ${pictureSize.width}x${pictureSize.height}, fx: $fx, '
      'laid: $laid)';
}

Map<String, dynamic> _poseToJson(TransformPose pose) => {
  'center': pose.center.toJson(),
  'scale': pose.scale.toJson(),
  if (pose.rotationDegrees != 0) 'rotation': pose.rotationDegrees,
};

TransformPose _poseFromJson(Map<String, dynamic> json) {
  final scale = CanvasPoint.fromJson(json['scale'] as Map<String, dynamic>);
  return TransformPose(
    center: CanvasPoint.fromJson(json['center'] as Map<String, dynamic>),
    scaleX: scale.x,
    scaleY: scale.y,
    rotationDegrees: (json['rotation'] as num?)?.toDouble() ?? 0,
  );
}
