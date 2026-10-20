/// How a brush corrects the line it is drawn with — Clip Studio's 補正
/// category, a brush's own as everything under it is (유저 2026-10-20,
/// F-418-Q6: 「클튜는 브러시마다 보정값 독립적이니까 … 클튜랑 통일해서
/// 브러시별로 독립적으로 두자」).
///
/// 🗣️All of it, in Clip Studio's order (F-418-Q5 「선 다듬기 전부」, and
/// against the brush rule of the same day — 「클튜/포토샵에서
/// 공통적인것만 필수로 재현」 — 「다만 보정은 중요하니까 다 만들자」):
/// 角をとがらせる · 手ブレ補正 · 速度による手ブレ補正 └ 補正タイプ ·
/// 後補正 └ 速度による調整 · 表示倍率による調整 · ベジェ曲線.
///
/// ⚠️Fewer settings than Clip Studio shows, by the same day's 「로직같은건
/// 최대한 클튜 통일하되 너무 심하게 옵션 만들지 않는다」: where Clip Studio
/// has a switch and a value under it, ours is the value with nothing at the
/// bottom of its scale — as [stabilization]'s 0 already is (F-418-Q6). A
/// switch that is off cannot keep a value that does nothing.
/// ↩️Not the 手ブレ補正 since 유저 2026-10-20 「손떨림보정 수치를 클튜랑
/// 맞추고싶어서」: its scale is Clip Studio's, and nothing is a switch over
/// it ([steadies]). The 後補正 is still the value alone.
///
/// ↩️The stabilizer was the tool state's, shared by every brush and kept
/// out of presets as a hand-feel setting (P7, 2026-07-11, mine), and it
/// was stored nowhere: every launch put it back to 0.
class BrushCorrection {
  const BrushCorrection({
    this.sharpenCorners = false,
    this.steadies = true,
    this.stabilization = defaultStabilization,
    this.steadyingBySpeed = BrushSteadyingBySpeed.off,
    this.postStrength = 0,
    this.postBySpeed = true,
    this.postByViewScale = true,
    this.postBezier = false,
  });

  /// 角をとがらせる — 「角のある線を描いた時に角を立てます」.
  final bool sharpenCorners;

  /// 손떨림 보정 적용 — whether the line is steadied at all. Off, the
  /// [stabilization] and the [steadyingBySpeed] under it are kept and do
  /// nothing.
  ///
  /// 🗣️유저 2026-10-20: 「손떨림보정 수치를 클튜랑 맞추고싶어서. 0을 그냥
  /// 클튜 0으로 하고, 진짜 끄고싶을때를 위해 손떨림보정 적용 토글버튼
  /// 넣자. 적용해제면 손떨림보정쪽 다른 버튼 규칙처럼 비활성화」 — Clip
  /// Studio has no setting that steadies nothing, so ours is a switch over
  /// its scale.
  final bool steadies;

  /// 손떨림 보정, Clip Studio's 0..100 as it is: its 0 still steadies a
  /// little ([lagAtClipStudioZero]).
  ///
  /// ↩️🗣️유저 2026-10-20 (F-418-Q6): 「클튜는 0이라도 보정이 있는모양인데,
  /// 없는 상태를 만들고싶으니까 클립의 0을 우리의 1정도? 2나 3? 그정도로
  /// 알아서 하고, 0을 진짜 없는상태로」 — Clip Studio has no setting that
  /// steadies nothing, so ours had one below its scale: 1..100 were Clip
  /// Studio's 0..100 and 0 was nothing at all. The same day's 「수치를
  /// 클튜랑 맞추고싶어서」 put the nothing on a switch instead ([steadies]).
  final double stabilization;

  /// 速度による手ブレ補正 and its 補正タイプ, as one.
  final BrushSteadyingBySpeed steadyingBySpeed;

  /// 後補正, 0..100 (`BrushRevision`) — 0 takes nothing out. Once drawn,
  /// the line's wobble is taken out and it is laid again, the moment the
  /// pen lifts (F-418-Q7 「뗄 때 다듬은 선으로 바뀐다」).
  final double postStrength;

  /// 速度による調整: 「描画速度が速くなるほど補正が強くかかります」 —
  /// [postStrength] is what the quickest line gets.
  final bool postBySpeed;

  /// 表示倍率による調整: 「表示倍率が小さいほど補正は強くなり」 — the
  /// wobble is measured on the screen, not on the canvas.
  final bool postByViewScale;

  /// ベジェ曲線: 「補正された曲線は2次ベジェになります」; a spline when off.
  final bool postBezier;

  /// Clip Studio's 0 (유저 F-418-Q6: 「없으면 클튜 0인거랑 동일한 우리의
  /// 값으로 기본값으로」) — and [[F-258]]'s 「기본값 1.0」, which was that 0
  /// on the scale before Clip Studio's own.
  static const double defaultStabilization = 0;

  /// A brush that corrects nothing.
  static const BrushCorrection none = BrushCorrection(steadies: false);

  /// The highest [stabilization]: Clip Studio's 100.
  static const double maxStabilization = 100.0;

  /// The highest [postStrength]: Clip Studio's 100.
  static const double maxPostStrength = 100.0;

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

  /// Where 「ゆっくり描いたときに補正をかける」 stops having an effect —
  /// 「[手ブレ補正]の値が低いときのみ効果があります」, and Clip Studio's
  /// guide puts the line at 30.
  static const double _slowTypeReaches = 30;

  /// How far a wobble may stray, in pixels, for one step of
  /// [postStrength].
  ///
  /// ⚠️Mine, to be matched by hand against Clip Studio: nothing published
  /// says what its numbers measure.
  static const double _postPixelsPerStep = 0.25;

  /// How far behind the pen the line runs, in time, while the pen moves
  /// at [speed] (normalised, 0..1) — for a brush that [steadies].
  ///
  /// A time, not a distance: the line closes the same share of what is left
  /// in the same time at any zoom (↩️the rope it replaced was screen
  /// pixels).
  ///
  /// ⚠️How the speed bends it is mine, after Clip Studio's words: the slow
  /// type lifts a setting under 30 toward 30 as the pen slows, the quick
  /// type halves the setting at the quickest.
  Duration lagAt(double speed) {
    final set = stabilization.clamp(0.0, maxStabilization);
    final clipStudio = switch (steadyingBySpeed) {
      BrushSteadyingBySpeed.off => set,
      BrushSteadyingBySpeed.slow when set < _slowTypeReaches =>
        set + (_slowTypeReaches - set) * (1 - speed),
      BrushSteadyingBySpeed.slow => set,
      BrushSteadyingBySpeed.fast => set * (1 - speed / 2),
    };
    final from = lagAtClipStudioZero.inMicroseconds;
    final to = lagAtClipStudioHundred.inMicroseconds;
    return Duration(
      microseconds: (from + (to - from) * clipStudio / 100).round(),
    );
  }

  /// How far, in canvas pixels, a wobble of a line drawn at [zoom] and at
  /// [speed] (normalised, 0..1 — the line's own) may stray and still be
  /// taken out — or null when nothing is.
  double? postWithin({required double zoom, required double speed}) {
    var within = postStrength * _postPixelsPerStep;
    if (postByViewScale) {
      within /= zoom;
    }
    if (postBySpeed) {
      within *= speed;
    }
    return within > 0 ? within : null;
  }

  BrushCorrection copyWith({
    bool? sharpenCorners,
    bool? steadies,
    double? stabilization,
    BrushSteadyingBySpeed? steadyingBySpeed,
    double? postStrength,
    bool? postBySpeed,
    bool? postByViewScale,
    bool? postBezier,
  }) => BrushCorrection(
    sharpenCorners: sharpenCorners ?? this.sharpenCorners,
    steadies: steadies ?? this.steadies,
    stabilization: stabilization ?? this.stabilization,
    steadyingBySpeed: steadyingBySpeed ?? this.steadyingBySpeed,
    postStrength: postStrength ?? this.postStrength,
    postBySpeed: postBySpeed ?? this.postBySpeed,
    postByViewScale: postByViewScale ?? this.postByViewScale,
    postBezier: postBezier ?? this.postBezier,
  );

  Map<String, Object?> toJson() => {
    'sharpenCorners': sharpenCorners,
    'steadies': steadies,
    'stabilization': stabilization,
    'steadyingBySpeed': steadyingBySpeed.name,
    'postStrength': postStrength,
    'postBySpeed': postBySpeed,
    'postByViewScale': postByViewScale,
    'postBezier': postBezier,
  };

  /// Reads what [toJson] wrote; a part that is absent keeps its default.
  static BrushCorrection fromJson(Object? json) {
    const fallback = BrushCorrection();
    if (json is! Map) {
      return fallback;
    }
    bool flag(String key, bool otherwise) =>
        json[key] is bool ? json[key] as bool : otherwise;
    double number(String key, double otherwise) =>
        (json[key] as num?)?.toDouble() ?? otherwise;
    return BrushCorrection(
      sharpenCorners: flag('sharpenCorners', fallback.sharpenCorners),
      steadies: flag('steadies', fallback.steadies),
      stabilization: number('stabilization', fallback.stabilization),
      steadyingBySpeed: BrushSteadyingBySpeed.values.firstWhere(
        (type) => type.name == json['steadyingBySpeed'],
        orElse: () => fallback.steadyingBySpeed,
      ),
      postStrength: number('postStrength', fallback.postStrength),
      postBySpeed: flag('postBySpeed', fallback.postBySpeed),
      postByViewScale: flag('postByViewScale', fallback.postByViewScale),
      postBezier: flag('postBezier', fallback.postBezier),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BrushCorrection &&
          other.sharpenCorners == sharpenCorners &&
          other.steadies == steadies &&
          other.stabilization == stabilization &&
          other.steadyingBySpeed == steadyingBySpeed &&
          other.postStrength == postStrength &&
          other.postBySpeed == postBySpeed &&
          other.postByViewScale == postByViewScale &&
          other.postBezier == postBezier;

  @override
  int get hashCode => Object.hash(
    sharpenCorners,
    steadies,
    stabilization,
    steadyingBySpeed,
    postStrength,
    postBySpeed,
    postByViewScale,
    postBezier,
  );

  @override
  String toString() =>
      'BrushCorrection(sharpenCorners: $sharpenCorners, '
      'steadies: $steadies, '
      'stabilization: $stabilization, '
      'steadyingBySpeed: ${steadyingBySpeed.name}, '
      'postStrength: $postStrength, postBySpeed: $postBySpeed, '
      'postByViewScale: $postByViewScale, postBezier: $postBezier)';
}

/// 速度による手ブレ補正 and its 補正タイプ.
enum BrushSteadyingBySpeed {
  /// The speed changes nothing.
  off,

  /// ゆっくり描いたときに補正をかける — `FlickerReductionBySpeedType` 1
  /// (F-418-Q8: 「1 = 천천히 그릴 때 보정」, the user's G펜 shows it).
  slow,

  /// すばやく描いたときに弱く補正 — 2, the one after it in Clip Studio's
  /// list (no file of the user's carries it).
  fast;

  /// What a .sut's `FlickerReductionBySpeed` and
  /// `FlickerReductionBySpeedType` say together.
  static BrushSteadyingBySpeed fromClipStudio({
    required num? bySpeed,
    required num? type,
  }) => (bySpeed ?? 0) == 0
      ? off
      : switch (type) {
          2 => fast,
          _ => slow,
        };
}
