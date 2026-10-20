/// How a brush corrects the line it is drawn with — Clip Studio's 補正
/// category, a brush's own as everything under it is (유저 2026-10-20,
/// F-418-Q6: 「클튜는 브러시마다 보정값 독립적이니까 … 클튜랑 통일해서
/// 브러시별로 독립적으로 두자」).
///
/// ↩️The stabilizer was the tool state's, shared by every brush and kept
/// out of presets as a hand-feel setting (P7, 2026-07-11, mine), and it
/// was stored nowhere: every launch put it back to 0.
class BrushCorrection {
  const BrushCorrection({this.stabilization = defaultStabilization});

  /// 손떨림 보정 — 0 steadies nothing; 1..100 are Clip Studio's 0..100,
  /// spread evenly ([fromClipStudio]).
  ///
  /// 🗣️유저 2026-10-20 (F-418-Q6): 「클튜는 0이라도 보정이 있는모양인데,
  /// 없는 상태를 만들고싶으니까 클립의 0을 우리의 1정도? 2나 3? 그정도로
  /// 알아서 하고, 0을 진짜 없는상태로」 — Clip Studio has no setting that
  /// steadies nothing, so ours has one below its scale.
  final double stabilization;

  /// Clip Studio's 0 (유저 F-418-Q6: 「없으면 클튜 0인거랑 동일한 우리의
  /// 값으로 기본값으로」) — and [[F-258]]'s 「기본값 1.0」.
  static const double defaultStabilization = 1.0;

  /// A brush that corrects nothing.
  static const BrushCorrection none = BrushCorrection(stabilization: 0);

  /// The highest [stabilization]: Clip Studio's 100.
  static const double maxStabilization = 100.0;

  /// How far behind the pen the line runs at Clip Studio's 0 — the little
  /// it steadies there.
  ///
  /// ⚠️Mine, to be matched by hand against Clip Studio: no source says what
  /// its 0 does beyond 「little to no visible correction」.
  static const Duration lagAtClipStudioZero = Duration(milliseconds: 4);

  /// How far behind the pen the line runs at Clip Studio's 100: 0.165 s,
  /// measured by replaying one recorded stroke into Clip Studio
  /// (canvas-cluster.com, 2020 — the one figure anyone has published).
  static const Duration lagAtClipStudioHundred = Duration(milliseconds: 165);

  /// Clip Studio's 手ブレ補正 (`FlickerReduction`, 0..100) on our scale.
  static double fromClipStudio(num flickerReduction) =>
      1.0 + flickerReduction.clamp(0, 100).toDouble() * 0.99;

  /// How far behind the pen the line runs, in time — or null when this
  /// brush steadies nothing.
  ///
  /// A time, not a distance: the line closes the same share of what is left
  /// in the same time at any zoom (↩️the rope it replaced was screen
  /// pixels).
  Duration? get lag {
    if (stabilization <= 0) {
      return null;
    }
    final clipStudio = ((stabilization - 1.0) / 0.99).clamp(0.0, 100.0);
    final from = lagAtClipStudioZero.inMicroseconds;
    final to = lagAtClipStudioHundred.inMicroseconds;
    return Duration(
      microseconds: (from + (to - from) * clipStudio / 100).round(),
    );
  }

  BrushCorrection copyWith({double? stabilization}) =>
      BrushCorrection(stabilization: stabilization ?? this.stabilization);

  Map<String, Object?> toJson() => {'stabilization': stabilization};

  /// Reads what [toJson] wrote; a part that is absent keeps its default.
  static BrushCorrection fromJson(Object? json) {
    if (json is! Map) {
      return const BrushCorrection();
    }
    return BrushCorrection(
      stabilization:
          (json['stabilization'] as num?)?.toDouble() ?? defaultStabilization,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BrushCorrection && other.stabilization == stabilization;

  @override
  int get hashCode => stabilization.hashCode;

  @override
  String toString() => 'BrushCorrection(stabilization: $stabilization)';
}
