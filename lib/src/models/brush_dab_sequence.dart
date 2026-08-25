import '../core/collection_equality.dart';
import 'brush_dab.dart';

class BrushDabSequence {
  BrushDabSequence([Iterable<BrushDab> dabs = const [], this.opacity = 1.0])
    : _dabs = List<BrushDab>.unmodifiable(dabs);

  /// 🚨★F-12 — the stroke's CEILING (유저 2026-08-24: 「불투명도 낮추면
  /// 스트로크동안 dab이 겹친다고 해도 해당 불투명도 이상으로 안 진해지지
  /// 않나?」).
  ///
  /// FLOW is what one dab lays and lives on the dab; OPACITY is how dark the
  /// accumulated stroke may get, and it cannot live there — dabs pile up
  /// source-over, so a per-dab factor converges on 1 however small it is.
  ///
  /// ⚠️A dab's own `opacity` is what remains PER DAB: the pressure curve and
  /// the jitter, which are variation rather than a ceiling. The tool's
  /// setting moved here. A single-stamp verb (the fill) keeps its opacity on
  /// its dab, because one stamp accumulates with nothing.
  final double opacity;

  final List<BrushDab> _dabs;

  List<BrushDab> get dabs => List<BrushDab>.unmodifiable(_dabs);

  int get length => _dabs.length;

  bool get isEmpty => _dabs.isEmpty;

  bool get isNotEmpty => _dabs.isNotEmpty;

  BrushDab? get firstOrNull => _dabs.isEmpty ? null : _dabs.first;

  BrushDab? get lastOrNull => _dabs.isEmpty ? null : _dabs.last;

  BrushDabSequence add(BrushDab dab) =>
      BrushDabSequence([..._dabs, dab], opacity);

  BrushDabSequence addAll(Iterable<BrushDab> dabs) =>
      BrushDabSequence([..._dabs, ...dabs], opacity);

  Map<String, dynamic> toJson() => {
    'dabs': _dabs.map((dab) => dab.toJson()).toList(),
    // Written only when it is not the default, so a full-strength stroke
    // serialises byte-for-byte as it always did.
    if (opacity != 1.0) 'opacity': opacity,
  };

  factory BrushDabSequence.fromJson(Map<String, dynamic> json) {
    return BrushDabSequence(
      (json['dabs'] as List? ?? const []).map(
        (dabJson) => BrushDab.fromJson(dabJson as Map<String, dynamic>),
      ),
      (json['opacity'] as num?)?.toDouble() ?? 1.0,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BrushDabSequence &&
          other.opacity == opacity &&
          listEquals(other._dabs, _dabs);

  @override
  int get hashCode => Object.hash(Object.hashAll(_dabs), opacity);

  @override
  String toString() =>
      'BrushDabSequence(length: $length, opacity: $opacity, dabs: $_dabs)';
}
