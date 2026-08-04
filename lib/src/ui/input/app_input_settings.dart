import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart' show PointerDeviceKind;

/// Pointer-input policy (UI-R22 #6, default flipped in UI-R22F #1).
///
/// What a TOUCH contact means on the timeline grids:
///
/// - [touchTimelineScroll] ON (the DEFAULT) — the timeline's edit
///   gestures (range select/move, comma grips, run handles, block
///   moves) release touch entirely, so a finger pan reaches the scroll
///   viewports uncontested: touch is the timeline's SCROLL device. The
///   pen (stylus) edits either way.
/// - OFF — touch EDITS exactly like the pen (the R17-⑥ contract: some
///   Windows/tablet drivers report styluses as touch, so touch keeps
///   full editing power — select, move, drag grips). The safety net for
///   pens that misreport as touch.
///
/// NOTE for tests: `test/flutter_test_config.dart` pins the corpus to
/// OFF (the touch-as-pen contract `tester.drag` was written under);
/// scroll-behavior suites opt into ON explicitly.
class AppInputSettings {
  const AppInputSettings({
    this.touchTimelineScroll = true,
    this.tabletService = TabletService.standard,
    this.pressureCurveGamma = 1.0,
    this.canvasRightClick = const CanvasPointerMapping(
      action: CanvasPointerAction.eyedropper,
    ),
    this.canvasWheelClick = const CanvasPointerMapping(
      action: CanvasPointerAction.pan,
    ),
    this.touchDragOneFinger = CanvasTouchDragAction.flip,
    this.touchDragTwoFingers = CanvasTouchDragAction.navigate,
    this.touchDragThreeFingers = CanvasTouchDragAction.brushSize,
    this.extraFingerModifier = true,
    this.flipHaptics = true,
    this.navigationRotationEnabled = true,
    this.navigationModifierRotationLock = false,
    this.rotationSnapDegrees = 15,
    this.zoomSnapPercents = defaultZoomSnapPercents,
    this.brushSizeSnaps = defaultBrushSizeSnaps,
  });

  /// The finger-count drag slots (PEN-7b), all user-assignable. PEN-12
  /// #4 retired the separate control/draw MODE: drawing is simply the
  /// ONE-FINGER slot's [CanvasTouchDragAction.draw] (the old mode setting
  /// overlapped it — "손으로 그린다는 게 1핑거 드래그잖아"). Touch-only
  /// form factors force the one-finger slot to draw at the policy level
  /// ([AppInput.touchDragActionFor]).
  final CanvasTouchDragAction touchDragOneFinger;
  final CanvasTouchDragAction touchDragTwoFingers;
  final CanvasTouchDragAction touchDragThreeFingers;

  /// The +1-finger modifier globally (PEN-7b): ON by default; OFF for
  /// users who dislike late fingers changing a locked gesture at all.
  final bool extraFingerModifier;

  /// The flip's per-drawing haptic tick. Devices without a motor ignore
  /// the call on their own (HapticFeedback is an optional platform
  /// channel), so this is a preference rather than a capability gate.
  final bool flipHaptics;

  /// Navigate-action composition: rotation entirely off = two fingers
  /// pan+zoom only (the canvas rotate buttons/shortcut stay separate).
  final bool navigationRotationEnabled;

  /// What the modifier does to ROTATION during navigate: snap to
  /// [rotationSnapDegrees] multiples (default) or LOCK at the angle the
  /// modifier landed on (pure pan+snap-zoom).
  final bool navigationModifierRotationLock;

  /// Snap tables (PEN-7b) — every list user-editable.
  final double rotationSnapDegrees;
  final List<double> zoomSnapPercents;
  final List<double> brushSizeSnaps;

  /// PEN-15: 10/25 joined so a sub-50% view has nearby snaps (the
  /// modifier constraint glues the CURRENT zoom to the nearest entry —
  /// with 50 as the floor, engaging at 30% read as "reset to 50%").
  static const List<double> defaultZoomSnapPercents = [
    10,
    25,
    50,
    75,
    100,
    125,
    150,
    200,
    300,
    400,
  ];

  /// PEN-15: the doubling ladder continues past 64 (brushes go to 2000).
  static const List<double> defaultBrushSizeSnaps = [
    2,
    4,
    8,
    16,
    32,
    64,
    128,
    256,
    512,
  ];

  /// The PREVIOUS default lists (PEN-15): stored settings that still
  /// match one of these upgrade to the current default on load — only a
  /// user-customized list persists as-is.
  static const List<List<double>> legacyZoomSnapDefaults = [
    [50, 75, 100, 125, 150, 200, 300, 400],
  ];
  static const List<List<double>> legacyBrushSizeSnapDefaults = [
    [2, 4, 8, 16, 32, 64],
  ];

  /// The TEST-CORPUS baseline (see test/flutter_test_config.dart): the
  /// corpus was written under touch-as-pen — timeline touch EDITS and
  /// canvas touch DRAWS. Product defaults differ (scroll/control); the
  /// suites asserting those opt in explicitly. Every test that mutates
  /// [AppInput.settings] must tearDown-reset to THIS, never to
  /// `AppInputSettings()`.
  static const AppInputSettings testCorpusBaseline = AppInputSettings(
    touchTimelineScroll: false,
    touchDragOneFinger: CanvasTouchDragAction.draw,
  );

  /// The canvas mapping for the RIGHT-CLICK bit (PEN-7a): pen side/
  /// barrel button, S-Pen button, mouse right button — one row for all.
  final CanvasPointerMapping canvasRightClick;

  /// The canvas mapping for the WHEEL/MIDDLE bit: pen upper button,
  /// mouse wheel click.
  final CanvasPointerMapping canvasWheelClick;

  final bool touchTimelineScroll;

  /// The pen pressure RESPONSE curve (PEN-3, cross-platform): output =
  /// input^gamma. 1.0 = linear (the default, byte-identical to before);
  /// below 1 = SOFTER feel (a light touch already reads strong), above
  /// 1 = HARDER (full pressure takes a firm press). Applied wherever
  /// normalized pressure enters the brush pipeline — OS pointer and
  /// Wintab sidecar alike.
  final double pressureCurveGamma;

  /// Which tablet backend feeds pen data (PEN-2, the CSP-style dual
  /// service — Windows only; other platforms ignore it):
  /// - [TabletService.standard] (the DEFAULT): the OS pointer pipeline
  ///   exactly as today.
  /// - [TabletService.wintab]: the Wintab sidecar additionally streams
  ///   the DRIVER's pressure/tilt and overrides brush pressure — the
  ///   escape hatch for drivers whose OS path misreports the pen.
  final TabletService tabletService;

  AppInputSettings copyWith({
    bool? touchTimelineScroll,
    TabletService? tabletService,
    double? pressureCurveGamma,
    CanvasPointerMapping? canvasRightClick,
    CanvasPointerMapping? canvasWheelClick,
    CanvasTouchDragAction? touchDragOneFinger,
    CanvasTouchDragAction? touchDragTwoFingers,
    CanvasTouchDragAction? touchDragThreeFingers,
    bool? extraFingerModifier,
    bool? flipHaptics,
    bool? navigationRotationEnabled,
    bool? navigationModifierRotationLock,
    double? rotationSnapDegrees,
    List<double>? zoomSnapPercents,
    List<double>? brushSizeSnaps,
  }) => AppInputSettings(
    touchTimelineScroll: touchTimelineScroll ?? this.touchTimelineScroll,
    tabletService: tabletService ?? this.tabletService,
    pressureCurveGamma: pressureCurveGamma ?? this.pressureCurveGamma,
    canvasRightClick: canvasRightClick ?? this.canvasRightClick,
    canvasWheelClick: canvasWheelClick ?? this.canvasWheelClick,
    touchDragOneFinger: touchDragOneFinger ?? this.touchDragOneFinger,
    touchDragTwoFingers: touchDragTwoFingers ?? this.touchDragTwoFingers,
    touchDragThreeFingers: touchDragThreeFingers ?? this.touchDragThreeFingers,
    extraFingerModifier: extraFingerModifier ?? this.extraFingerModifier,
    flipHaptics: flipHaptics ?? this.flipHaptics,
    navigationRotationEnabled:
        navigationRotationEnabled ?? this.navigationRotationEnabled,
    navigationModifierRotationLock:
        navigationModifierRotationLock ?? this.navigationModifierRotationLock,
    rotationSnapDegrees: rotationSnapDegrees ?? this.rotationSnapDegrees,
    zoomSnapPercents: zoomSnapPercents ?? this.zoomSnapPercents,
    brushSizeSnaps: brushSizeSnaps ?? this.brushSizeSnaps,
  );

  Map<String, dynamic> toJson() => {
    'touchTimelineScroll': touchTimelineScroll,
    'tabletService': tabletService.name,
    'pressureCurveGamma': pressureCurveGamma,
    'canvasRightClick': canvasRightClick.toJson(),
    'canvasWheelClick': canvasWheelClick.toJson(),
    'touchDragOneFinger': touchDragOneFinger.name,
    'touchDragTwoFingers': touchDragTwoFingers.name,
    'touchDragThreeFingers': touchDragThreeFingers.name,
    'extraFingerModifier': extraFingerModifier,
    'flipHaptics': flipHaptics,
    'navigationRotationEnabled': navigationRotationEnabled,
    'navigationModifierRotationLock': navigationModifierRotationLock,
    'rotationSnapDegrees': rotationSnapDegrees,
    'zoomSnapPercents': zoomSnapPercents,
    'brushSizeSnaps': brushSizeSnaps,
  };

  static List<double> _doubleList(Object? json, List<double> fallback) {
    if (json is! List) {
      return fallback;
    }
    final values = <double>[
      for (final entry in json)
        if (entry is num) entry.toDouble(),
    ];
    return values.isEmpty ? fallback : values;
  }

  /// PEN-15: a stored list that still matches a PREVIOUS default swaps to
  /// the current default — expanded defaults reach existing settings
  /// files while genuinely customized lists persist untouched.
  static List<double> _upgradedList(
    List<double> stored, {
    required List<List<double>> legacyDefaults,
    required List<double> current,
  }) {
    for (final legacy in legacyDefaults) {
      if (listEquals(stored, legacy)) {
        return current;
      }
    }
    return stored;
  }

  static AppInputSettings fromJson(
    Map<String, dynamic> json,
  ) => AppInputSettings(
    touchTimelineScroll: json['touchTimelineScroll'] as bool? ?? true,
    tabletService:
        TabletService.values.asNameMap()[json['tabletService']] ??
        TabletService.standard,
    pressureCurveGamma: (json['pressureCurveGamma'] as num?)?.toDouble() ?? 1.0,
    canvasRightClick: CanvasPointerMapping.fromJson(
      json['canvasRightClick'],
      fallback: const CanvasPointerMapping(
        action: CanvasPointerAction.eyedropper,
      ),
    ),
    canvasWheelClick: CanvasPointerMapping.fromJson(
      json['canvasWheelClick'],
      fallback: const CanvasPointerMapping(action: CanvasPointerAction.pan),
    ),
    touchDragOneFinger:
        CanvasTouchDragAction.values.asNameMap()[json['touchDragOneFinger']] ??
        CanvasTouchDragAction.flip,
    touchDragTwoFingers:
        CanvasTouchDragAction.values.asNameMap()[json['touchDragTwoFingers']] ??
        CanvasTouchDragAction.navigate,
    touchDragThreeFingers:
        CanvasTouchDragAction.values
            .asNameMap()[json['touchDragThreeFingers']] ??
        CanvasTouchDragAction.brushSize,
    extraFingerModifier: json['extraFingerModifier'] as bool? ?? true,
    flipHaptics: json['flipHaptics'] as bool? ?? true,
    navigationRotationEnabled:
        json['navigationRotationEnabled'] as bool? ?? true,
    navigationModifierRotationLock:
        json['navigationModifierRotationLock'] as bool? ?? false,
    rotationSnapDegrees:
        (json['rotationSnapDegrees'] as num?)?.toDouble() ?? 15,
    zoomSnapPercents: _upgradedList(
      _doubleList(json['zoomSnapPercents'], defaultZoomSnapPercents),
      legacyDefaults: legacyZoomSnapDefaults,
      current: defaultZoomSnapPercents,
    ),
    brushSizeSnaps: _upgradedList(
      _doubleList(json['brushSizeSnaps'], defaultBrushSizeSnaps),
      legacyDefaults: legacyBrushSizeSnapDefaults,
      current: defaultBrushSizeSnaps,
    ),
  );

  @override
  bool operator ==(Object other) =>
      other is AppInputSettings &&
      other.touchTimelineScroll == touchTimelineScroll &&
      other.tabletService == tabletService &&
      other.pressureCurveGamma == pressureCurveGamma &&
      other.canvasRightClick == canvasRightClick &&
      other.canvasWheelClick == canvasWheelClick &&
      other.touchDragOneFinger == touchDragOneFinger &&
      other.touchDragTwoFingers == touchDragTwoFingers &&
      other.touchDragThreeFingers == touchDragThreeFingers &&
      other.extraFingerModifier == extraFingerModifier &&
      other.flipHaptics == flipHaptics &&
      other.navigationRotationEnabled == navigationRotationEnabled &&
      other.navigationModifierRotationLock == navigationModifierRotationLock &&
      other.rotationSnapDegrees == rotationSnapDegrees &&
      listEquals(other.zoomSnapPercents, zoomSnapPercents) &&
      listEquals(other.brushSizeSnaps, brushSizeSnaps);

  @override
  int get hashCode => Object.hash(
    touchTimelineScroll,
    tabletService,
    pressureCurveGamma,
    canvasRightClick,
    canvasWheelClick,
    touchDragOneFinger,
    touchDragTwoFingers,
    touchDragThreeFingers,
    extraFingerModifier,
    flipHaptics,
    navigationRotationEnabled,
    navigationModifierRotationLock,
    rotationSnapDegrees,
    Object.hashAll(zoomSnapPercents),
    Object.hashAll(brushSizeSnaps),
  );
}

/// The tablet backend choice (PEN-2). CSP's '사용할 태블릿 서비스'
/// analogue: standard = the OS pointer path ('Tablet PC'), wintab = the
/// driver-direct sidecar.
enum TabletService { standard, wintab }

/// What a STANDARD secondary input does on the CANVAS (PEN-7a) — the
/// app's one in-house mapping layer. Everywhere else follows the
/// driver/OS meaning of the input untouched; on canvas the user assigns
/// it. Pen side/barrel buttons, the S-Pen button and the mouse right
/// button all arrive as the SAME right-click bit, so one row governs
/// them all (and the wheel/upper-button bit gets its own row).
/// [undo]/[redo] are ONE-SHOT actions (PEN-11): they fire once at the
/// press — and on a hover BUTTON press for pens that report it — so the
/// pen can undo even while S-Pen hover palm-rejection blocks all touch.
enum CanvasPointerAction { eyedropper, eraser, pan, undo, redo, none }

/// What happens when the held mapping ends (PEN-7a): the hold
/// temporarily SWITCHES THE TOOL (the shared tool-switch path — cursor,
/// panels and per-tool settings all follow for free); release either
/// springs back to the original tool (the default) or keeps the
/// switched tool armed.
enum CanvasPointerRelease { returnToTool, keep }

/// One canvas mapping row: the action plus its release behavior.
class CanvasPointerMapping {
  const CanvasPointerMapping({
    required this.action,
    this.release = CanvasPointerRelease.returnToTool,
  });

  final CanvasPointerAction action;
  final CanvasPointerRelease release;

  CanvasPointerMapping copyWith({
    CanvasPointerAction? action,
    CanvasPointerRelease? release,
  }) => CanvasPointerMapping(
    action: action ?? this.action,
    release: release ?? this.release,
  );

  Map<String, dynamic> toJson() => {
    'action': action.name,
    'release': release.name,
  };

  static CanvasPointerMapping fromJson(
    Object? json, {
    required CanvasPointerMapping fallback,
  }) {
    if (json is! Map) {
      return fallback;
    }
    return CanvasPointerMapping(
      action:
          CanvasPointerAction.values.asNameMap()[json['action']] ??
          fallback.action,
      release:
          CanvasPointerRelease.values.asNameMap()[json['release']] ??
          fallback.release,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is CanvasPointerMapping &&
      other.action == action &&
      other.release == release;

  @override
  int get hashCode => Object.hash(action, release);
}

/// The drag action a finger-count slot performs on canvas (PEN-7b) —
/// every slot is user-assignable; the action owns its axes AND its
/// +1-finger modifier meaning, so reassignment carries both.
enum CanvasTouchDragAction {
  /// 파라파라: horizontal = previous/next DRAWING (the plain-arrow
  /// actions), vertical = layer up/down. Modifier = one-frame steps.
  flip,

  /// Pan+zoom+rotate (one finger degrades to pan-only naturally).
  /// Modifier = constrain: zoom snaps to the list; rotation snaps or
  /// locks per [AppInputSettings.navigationModifierRotationLock].
  navigate,

  /// Vertical = brush size (horizontal deliberately unmapped). Modifier
  /// = snap to the size list.
  brushSize,

  /// ONE-FINGER slot only (PEN-12 #4): the finger draws like the pen —
  /// the old control/draw mode setting collapsed into this. No modifier:
  /// a COMMITTED stroke ignores extra fingers entirely (palm/habit must
  /// never vanish a live line); two fingers landing together before the
  /// stroke commits still navigate.
  draw,

  none,
}

/// The LIVE input policy (the accent-settings pattern): the app root
/// rebuilds off the notifier; the session restores/persists it.
abstract final class AppInput {
  static final ValueNotifier<AppInputSettings> settings =
      ValueNotifier<AppInputSettings>(const AppInputSettings());

  static bool get touchTimelineScroll => settings.value.touchTimelineScroll;

  /// Test hook: forces the touch-only form-factor answer.
  static bool? debugTouchOnlyFormFactorOverride;

  /// iPhone-class devices (iOS, phone-sized) have NO pen — touch must
  /// draw there regardless of the stored preference (PEN-7b capability
  /// rule: 아이폰=그리기 강제).
  static bool get touchOnlyFormFactor {
    final override = debugTouchOnlyFormFactorOverride;
    if (override != null) {
      return override;
    }
    if (defaultTargetPlatform != TargetPlatform.iOS) {
      return false;
    }
    final view = PlatformDispatcher.instance.implicitView;
    if (view == null) {
      return false;
    }
    final shortestSide = view.physicalSize.shortestSide / view.devicePixelRatio;
    return shortestSide < 600;
  }

  /// The drag action assigned to a finger-count slot (3+ fingers share
  /// the three-finger slot). Touch-only form factors force the
  /// one-finger slot to DRAW (PEN-7b capability rule: 아이폰=그리기
  /// 강제 — no pen exists there).
  static CanvasTouchDragAction touchDragActionFor(int fingerCount) {
    final value = settings.value;
    if (fingerCount <= 1) {
      return touchOnlyFormFactor
          ? CanvasTouchDragAction.draw
          : value.touchDragOneFinger;
    }
    if (fingerCount == 2) {
      return value.touchDragTwoFingers;
    }
    return value.touchDragThreeFingers;
  }

  /// Whether a single finger DRAWS on canvas (PEN-12 #4 — the retired
  /// control/draw mode's replacement question).
  static bool get touchDraws =>
      touchDragActionFor(1) == CanvasTouchDragAction.draw;

  /// Nearest-value snapping against a user-editable list (PEN-7b) —
  /// shared by the navigate constraints and the brush-size drag.
  static double snapToList(double value, List<double> snaps) {
    if (snaps.isEmpty) {
      return value;
    }
    var best = snaps.first;
    for (final candidate in snaps) {
      if ((candidate - value).abs() < (best - value).abs()) {
        best = candidate;
      }
    }
    return best;
  }

  /// The pen pressure response curve (PEN-3): output = input^gamma.
  /// Gamma 1 short-circuits so the default path costs nothing.
  static double applyPressureCurve(double pressure) {
    final gamma = settings.value.pressureCurveGamma;
    if (gamma == 1.0) {
      return pressure;
    }
    return math.pow(pressure.clamp(0.0, 1.0), gamma).toDouble();
  }

  /// The device set every timeline EDIT pan uses (range select/move,
  /// comma grips, run handles, block moves): touch joins exactly while
  /// the timeline scroll does NOT own it.
  static Set<PointerDeviceKind> get timelineEditPanDevices => {
    PointerDeviceKind.mouse,
    PointerDeviceKind.stylus,
    PointerDeviceKind.invertedStylus,
    PointerDeviceKind.unknown,
    if (!touchTimelineScroll) PointerDeviceKind.touch,
  };

  /// Whether a CELL press of [kind] may SEEK the playhead (UI-R23
  /// feedback #2): with touch-scroll ON a finger on the grid is pure
  /// scroll — its press-down must not move the frame index (the first
  /// scroll touch kept re-seeking). Pen/mouse always seek; with the
  /// toggle OFF touch seeks like a pen (the R17-⑥ contract).
  static bool timelineCellPressSeeks(PointerDeviceKind kind) =>
      kind != PointerDeviceKind.touch || !touchTimelineScroll;
}
