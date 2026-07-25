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
