import '../core/collection_equality.dart';

/// One onion-skin peg: how strongly the drawing at that distance ghosts.
///
/// Opacity 0 IS the off switch — there is no separate enable flag, so a peg
/// can never be "on" and invisible at the same time.
class OnionPeg {
  const OnionPeg({required this.opacity});

  /// 0 = this peg ghosts nothing.
  final double opacity;

  bool get shows => opacity > 0;

  OnionPeg copyWith({double? opacity}) =>
      OnionPeg(opacity: opacity ?? this.opacity);

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is OnionPeg && other.opacity == opacity;

  @override
  int get hashCode => opacity.hashCode;
}

/// How onion frames color: side tints (Colors — the default) or the
/// artwork's own colors (Images), opacity only.
enum OnionSkinMode { colors, images }

/// What one peg step counts.
enum OnionSkinStep {
  /// Peg k = the k-th unique DRAWING before/after the current one: a held
  /// block is one drawing and linked repeats collapse. This is the
  /// animator's "previous drawing", and it degenerates to plain frames
  /// when nothing is held.
  blocks,

  /// Peg k = literally k frames before/after. Inside a hold that resolves
  /// to the drawing already on screen, which ghosts nothing at all.
  frames,
}

/// The editor's onion-skin state (session view state, not project data):
/// [maxPegs] pegs per side, each with its own opacity, the side tints, the
/// Colors/Images mode and what a peg step counts.
///
/// UI-R17 #5: there is NO master enable — onion application is PER LAYER
/// (TVPaint style: the session's onion layer-id set), these settings only
/// shape HOW the ghosts render.
class OnionSkinSettings {
  const OnionSkinSettings({
    this.beforePegs = defaultBeforePegs,
    this.afterPegs = defaultAfterPegs,
    this.tintBefore = 0xFFE53935,
    this.tintAfter = 0xFF43A047,
    this.mode = OnionSkinMode.colors,
    this.step = OnionSkinStep.blocks,
  });

  static const int maxPegs = 8;

  static const OnionPeg _off = OnionPeg(opacity: 0);

  /// Every slot exists from the start (the panel shows all of them at
  /// once): one drawing each way, the rest silent.
  static const List<OnionPeg> defaultBeforePegs = [
    OnionPeg(opacity: 0.4),
    _off,
    _off,
    _off,
    _off,
    _off,
    _off,
    _off,
  ];
  static const List<OnionPeg> defaultAfterPegs = [
    OnionPeg(opacity: 0.3),
    _off,
    _off,
    _off,
    _off,
    _off,
    _off,
    _off,
  ];

  /// Peg k = the (k+1)-th drawing (or frame, per [step]) before/after.
  final List<OnionPeg> beforePegs;
  final List<OnionPeg> afterPegs;

  /// Side tint colors (ARGB) for [OnionSkinMode.colors].
  final int tintBefore;
  final int tintAfter;

  final OnionSkinMode mode;
  final OnionSkinStep step;


  /// 🚨★★★**F-150 — 어니언 값은 유저 설정이다.** 유저 2026-09-16: 「어니언
  /// 패널에서 세팅한 값이 **세션으로서 저장안됨. 세션이라기보다 유저설정?**」.
  /// It is: a light-table shape is how the animator works, not what the
  /// project holds — so it rides with the app, beside the accents and the
  /// input settings ([AppOnionSkinSettingsStore]).
  ///
  /// ⛔The pegs are written as PLAIN OPACITIES, not objects: [OnionPeg] is
  /// one number and 「opacity 0 IS the off switch」 is the class's own law, so
  /// a `{"opacity": …}` wrapper would be a second spelling of nothing.
  /// ⚠️A file whose list is short or long is read to [maxPegs] all the same —
  /// the panel shows every slot at once, so a settings file from a build
  /// with a different count must not leave it with fewer boxes than rows.
  Map<String, dynamic> toJson() => {
    'beforePegs': [for (final peg in beforePegs) peg.opacity],
    'afterPegs': [for (final peg in afterPegs) peg.opacity],
    'tintBefore': tintBefore,
    'tintAfter': tintAfter,
    'mode': mode.name,
    'step': step.name,
  };

  static OnionSkinSettings fromJson(Map<String, dynamic> json) {
    const fallback = OnionSkinSettings();
    return OnionSkinSettings(
      beforePegs: _pegsFrom(json['beforePegs'], fallback.beforePegs),
      afterPegs: _pegsFrom(json['afterPegs'], fallback.afterPegs),
      tintBefore: json['tintBefore'] is int
          ? json['tintBefore'] as int
          : fallback.tintBefore,
      tintAfter: json['tintAfter'] is int
          ? json['tintAfter'] as int
          : fallback.tintAfter,
      mode: _enumFrom(OnionSkinMode.values, json['mode'], fallback.mode),
      step: _enumFrom(OnionSkinStep.values, json['step'], fallback.step),
    );
  }

  /// [maxPegs] pegs, whatever the file holds: missing ones take the
  /// default's, extra ones are dropped.
  static List<OnionPeg> _pegsFrom(Object? raw, List<OnionPeg> fallback) {
    if (raw is! List) {
      return fallback;
    }
    return [
      for (var i = 0; i < maxPegs; i += 1)
        if (i < raw.length && raw[i] is num)
          OnionPeg(opacity: (raw[i] as num).toDouble().clamp(0.0, 1.0))
        else
          fallback[i],
    ];
  }

  static T _enumFrom<T extends Enum>(List<T> values, Object? raw, T fallback) {
    for (final value in values) {
      if (value.name == raw) {
        return value;
      }
    }
    return fallback;
  }
  OnionSkinSettings copyWith({
    List<OnionPeg>? beforePegs,
    List<OnionPeg>? afterPegs,
    int? tintBefore,
    int? tintAfter,
    OnionSkinMode? mode,
    OnionSkinStep? step,
  }) {
    return OnionSkinSettings(
      beforePegs: beforePegs ?? this.beforePegs,
      afterPegs: afterPegs ?? this.afterPegs,
      tintBefore: tintBefore ?? this.tintBefore,
      tintAfter: tintAfter ?? this.tintAfter,
      mode: mode ?? this.mode,
      step: step ?? this.step,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is OnionSkinSettings &&
          listEquals(other.beforePegs, beforePegs) &&
          listEquals(other.afterPegs, afterPegs) &&
          other.tintBefore == tintBefore &&
          other.tintAfter == tintAfter &&
          other.mode == mode &&
          other.step == step;

  @override
  int get hashCode => Object.hash(
    Object.hashAll(beforePegs),
    Object.hashAll(afterPegs),
    tintBefore,
    tintAfter,
    mode,
    step,
  );
}
