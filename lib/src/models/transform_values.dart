/// 🚨★★★**WHAT A TRANSFORM DOES TO A PIECE — EVERY VALUE THE USER SETS, AND
/// NO PLACE.**
///
/// After Effects' property set for one piece, each as the number a transform
/// box holds: Position is the MOVE ([tx], [ty]); Scale is a ratio per axis
/// ([sx], [sy]) whose SIGN is a mirror; Rotation is [rotationDegrees],
/// clockwise on the canvas; Anchor Point is a displacement from the piece's
/// own centre ([anchorX], [anchorY]). Aimed at a place they are a
/// `SelectionAffine`, and a layer's fx pose is the same four aimed at its
/// anchor (`selection_placement.dart`).
///
/// 🗣️유저 2026-10-01 (F-256): 「변형도구 일반변형, 가로에 대한 단독배율변경
/// 같은게 저장안됨. 가로세로 통합으로서 저장? 기록됨. 그러니 트랜스폼fx가
/// ae랑 같은 구조니 그거랑 데이터구조 통일할거 통일하면서 가로나 세로 비율?
/// 수정이 구조적으로 기록될수있는 구조이도록 개편」 — and 10-03 (F-265), of a
/// 좌우반전 that 재현 replayed as 좌우 + 상하: 「반전을 숫자로서 표현못하는게
/// 원인인거같으니 구조적으로 해결. 심플한 데이터로서 해결하도록」.
///
/// The box held both scales all along. What lost one was every DOOR that
/// carried the box's numbers somewhere else — the record 재현 replays, the
/// replay, the tool panel's digits and its write, the walk to another cel.
/// Each spelled its own list of doubles: a single `scale`, or no anchor. So
/// a mirror came back on both axes, a one-axis stretch came back on both or
/// on neither, and the cross went back to the middle.
///
/// ⛔**ONE OBJECT, CARRIED WHOLE.** A door that takes the box's values takes
/// THIS, never a list of its fields, so a value added here reaches every
/// door there is. `the_values_are_listed_whole_test` holds the lists this
/// class itself has to spell.
class TransformValues {
  const TransformValues({
    this.sx = 1,
    this.sy = 1,
    this.rotationDegrees = 0,
    this.tx = 0,
    this.ty = 0,
    this.anchorX = 0,
    this.anchorY = 0,
  });

  /// A box as it opens: nothing moved, scaled or turned, the cross in the
  /// middle.
  static const TransformValues identity = TransformValues();

  /// The scale along each of the piece's own axes, 1 being the size it has.
  ///
  /// ⚠️A NEGATIVE scale is that axis mirrored, and it is the whole of
  /// 좌우반전 / 상하반전 — a flip is a number here, not a flag beside one
  /// (F-265).
  final double sx;
  final double sy;

  final double rotationDegrees;

  /// THE USER'S MOVE, in canvas pixels.
  final double tx;
  final double ty;

  /// WHERE THE ROTATION HAPPENS, as a displacement from the piece's centre.
  ///
  /// ⚠️Two doubles rather than a point for the same reason [tx] and [ty]
  /// are: a displacement is not a place, and this one has to have a const
  /// default so that 「no anchor」 needs no null anywhere.
  ///
  /// 🗣️유저 2026-09-20: 「tvp도 클튜도 **앵커포인트 별도로 둘수있어. 기본값은
  /// 중심**인데, 그걸 유저가 드래그해서 움직이는방식 … **앵커포인트는 회전시
  /// 앵커를 기준으로 회전**해」 — while 확대/축소 is 「**항상 상자의 중심**」,
  /// which is the affine's pivot. Two centres, because they answer two
  /// questions.
  ///
  /// ⛔**A DISPLACEMENT, NOT A POINT, in absolute canvas units.** 유저 fixed
  /// both halves the same day: 「기본값 상자안의 자리에서 **얼마나 이동됬나**」
  /// and 「**편집값은 절대값이야. 그냥 고정이야.** 용지가 어떻든간에 **무조건
  /// 같은값**으로 편집이 이루어져야되」. Zero is the box centre, so the
  /// default needs no special case anywhere.
  final double anchorX;
  final double anchorY;

  /// ⚠️The ANCHOR is not part of this. Moving it alone changes no pixel —
  /// `SelectionAffine.appliedTx` shows why: with no rotation it costs
  /// nothing — so a box whose anchor moved and nothing else still has
  /// nothing to land.
  bool get isIdentity =>
      sx == 1 && sy == 1 && rotationDegrees == 0 && tx == 0 && ty == 0;

  /// Nothing but a move: the pixels travel without being resampled.
  ///
  /// 🚨★★★**THE CHEAP PATH IS A LAW, NOT AN OPTIMISATION.** A translation
  /// carries the lifted stamp byte-exactly by moving its centre, so a drag
  /// inside the box neither resamples nor re-decodes — it is as cheap as it
  /// was when the move lived outside the affine entirely, which is what
  /// 유저's 「**가볍게 구조적으로 설계**」 asks of this round. ⛔The anchor is
  /// not consulted: with no rotation it costs nothing
  /// (`SelectionAffine.appliedTx`).
  bool get isPureTranslation => sx == 1 && sy == 1 && rotationDegrees == 0;

  /// Every value, as one string — the half of a resample's cache key that
  /// is not the place (`SelectionAffine.cacheKey` has the reason it is
  /// spelled on the class).
  String get cacheKey => '$sx,$sy,$rotationDegrees,$tx,$ty,$anchorX,$anchorY';

  TransformValues copyWith({
    double? sx,
    double? sy,
    double? rotationDegrees,
    double? tx,
    double? ty,
    double? anchorX,
    double? anchorY,
  }) {
    return TransformValues(
      sx: sx ?? this.sx,
      sy: sy ?? this.sy,
      rotationDegrees: rotationDegrees ?? this.rotationDegrees,
      tx: tx ?? this.tx,
      ty: ty ?? this.ty,
      anchorX: anchorX ?? this.anchorX,
      anchorY: anchorY ?? this.anchorY,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TransformValues &&
          other.sx == sx &&
          other.sy == sy &&
          other.rotationDegrees == rotationDegrees &&
          other.tx == tx &&
          other.ty == ty &&
          other.anchorX == anchorX &&
          other.anchorY == anchorY;

  @override
  int get hashCode =>
      Object.hash(sx, sy, rotationDegrees, tx, ty, anchorX, anchorY);

  @override
  String toString() =>
      'TransformValues(sx: $sx, sy: $sy, rotationDegrees: $rotationDegrees, '
      'tx: $tx, ty: $ty, anchorX: $anchorX, anchorY: $anchorY)';
}
