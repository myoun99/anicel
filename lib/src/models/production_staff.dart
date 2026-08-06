/// One production role's assignee: the name a paper form prints, and the
/// 도장 it can stamp instead of a signature.
///
/// Project-level, like the rest of the production info — a cut envelope,
/// a timesheet and a conte page all print the same person for the same
/// role, so the fact belongs to the work rather than to a sheet.
class ProductionStaff {
  const ProductionStaff({this.name = '', this.stampAssetPath});

  static const ProductionStaff empty = ProductionStaff();

  /// The printed name (原画 담당자, 演出 …).
  final String name;

  /// A [MediaAsset] path of kind `image` — the approval stamp. A
  /// transparent PNG stamps cleanly over a form; null simply leaves the
  /// box for a hand-drawn mark.
  final String? stampAssetPath;

  bool get isEmpty => name.isEmpty && stampAssetPath == null;

  ProductionStaff copyWith({String? name, String? Function()? stampAssetPath}) {
    return ProductionStaff(
      name: name ?? this.name,
      // A closure so a stamp can be CLEARED (the plain-nullable convention
      // cannot say that).
      stampAssetPath: stampAssetPath == null
          ? this.stampAssetPath
          : stampAssetPath(),
    );
  }

  Map<String, dynamic> toJson() => {
    if (name.isNotEmpty) 'name': name,
    if (stampAssetPath != null) 'stamp': stampAssetPath,
  };

  factory ProductionStaff.fromJson(Map<String, dynamic> json) {
    return ProductionStaff(
      name: json['name'] as String? ?? '',
      stampAssetPath: json['stamp'] as String?,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ProductionStaff &&
          other.name == name &&
          other.stampAssetPath == stampAssetPath;

  @override
  int get hashCode => Object.hash(name, stampAssetPath);

  @override
  String toString() => 'ProductionStaff($name, stamp: $stampAssetPath)';
}

/// The role keys the bundled form presets bind to (`{staff.genga.name}`).
///
/// Deliberately NOT an enum: the process list differs per production — the
/// WIT envelope wants 原画·動画·色指定·スキャン·トレス・ペイント, the
/// ゴールデンタイム one wants 原画·動画·ペイント·特殊 — so a studio's own
/// form may bind keys that ship with nothing. These are the defaults a
/// preset can rely on, not the closed set.
abstract final class ProductionRole {
  /// 原画 — key animation.
  static const String genga = 'genga';

  /// 動画 — inbetweens.
  static const String douga = 'douga';

  /// 色指定 — colour designation.
  static const String colorDesign = 'colorDesign';

  /// スキャン — scanning.
  static const String scan = 'scan';

  /// トレス・ペイント — trace and paint.
  static const String tracePaint = 'tracePaint';

  /// ペイント — paint alone (forms that split it from trace).
  static const String paint = 'paint';

  /// 特殊効果 — special effects.
  static const String specialEffects = 'specialEffects';

  /// 撮影 — photography/compositing.
  static const String photography = 'photography';

  /// 演出 — episode director (an approval box).
  static const String director = 'director';

  /// 監督 — series director.
  static const String chiefDirector = 'chiefDirector';

  /// 作画監督 — animation director.
  static const String animationDirector = 'animationDirector';

  /// 総作画監督 — chief animation director.
  static const String chiefAnimationDirector = 'chiefAnimationDirector';

  /// 動画チェック — inbetween check.
  static const String inbetweenCheck = 'inbetweenCheck';

  /// 色検査 — colour check.
  static const String colorCheck = 'colorCheck';
}
