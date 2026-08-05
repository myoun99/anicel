import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show HapticFeedback;
import 'package:flutter/widgets.dart' show Offset;

import '../input/app_input_settings.dart';
import 'flip_hud_model.dart';

/// Which axis the flip locked to.
enum FlipHudAxis {
  /// Left/right — the frame axis of the row being stood on.
  frame,

  /// Up/down — the row stack.
  row,
}

/// The flip HUD's own state: whether it shows, on which axis, at which
/// anchor, and the snapshot it draws. Shell-owned (the
/// `CanvasSelectionCommands` idiom) rather than held in the gesture
/// layer's State — a live-drag verb parked in a host State is how a
/// release silently fails to land.
///
/// ★ THE contract: this controller never owns the cursor. It is told when
/// a gesture starts, when a step has LANDED, and when the gesture ends;
/// everything it shows comes from a snapshot the session hands over. Step
/// a slot index here and the HUD becomes a second movement rule that
/// drifts the day the navigation rules change.
class FlipHudController extends ChangeNotifier {
  FlipHudController({
    VoidCallback? hapticTick,
    bool Function()? hapticsEnabled,
    DateTime Function()? clock,
  }) : _hapticTick = hapticTick ?? HapticFeedback.selectionClick,
       _hapticsEnabled =
           hapticsEnabled ?? (() => AppInput.settings.value.flipHaptics),
       // The coalesce window is wall-clock, not a timer — a sweep is fast
       // in real time whatever the frame rate is doing. Injectable so a
       // test can step it exactly instead of sleeping.
       _clock = clock ?? DateTime.now;

  /// The picture lingers this long after the fingers lift — long enough to
  /// read what you landed on without it feeling stuck.
  static const Duration holdAfterRelease = Duration(milliseconds: 350);

  /// Consecutive ticks closer than this are dropped rather than queued. A
  /// fast sweep crosses blocks faster than a motor can answer, and a
  /// backlog keeps buzzing after the hand has stopped.
  static const Duration hapticCoalesce = Duration(milliseconds: 50);

  /// The fade-out that follows the hold.
  static const Duration fadeOut = Duration(milliseconds: 180);

  final VoidCallback _hapticTick;
  final bool Function() _hapticsEnabled;
  final DateTime Function() _clock;

  FlipHudSnapshot Function(FlipHudAxis axis)? _snapshotOf;

  bool _visible = false;
  FlipHudAxis? _axis;
  FlipHudAxis? _displayAxis;
  bool _frameStep = false;
  Offset? _anchor;
  FlipHudSnapshot _snapshot = FlipHudSnapshot.empty;

  String? _lastContentKey;
  DateTime? _lastTickAt;
  Timer? _hideTimer;
  Timer? _clearTimer;

  (int, int)? _lastPosition;
  DateTime? _lastLandedAt;
  Duration? _lastStepInterval;

  /// How long the last step took to arrive, measured landing to landing.
  ///
  /// The strip's slide reads this to size itself: an implicit animation
  /// RESTARTS at full duration whenever its target moves, so a sweep that
  /// steps faster than the slide lasts leaves the strip permanently
  /// behind the hand — and the selection rides the strip, so the picture
  /// visibly disagrees with the cell it says you are on. Sizing each leg
  /// to the interval that preceded it makes the strip arrive exactly as
  /// the next step lands. Null before the second landing of a gesture.
  Duration? get lastStepInterval => _lastStepInterval;

  /// Whether the HUD is at full opacity. It stays mounted through the
  /// fade that follows — [displayAxis] is what says "still on screen".
  bool get visible => _visible;

  /// The LIVE axis: null the moment the fingers lift.
  FlipHudAxis? get axis => _axis;

  /// The axis to DRAW, kept through the release hold so the outgoing
  /// frames do not snap to the other shape on their way out.
  FlipHudAxis? get displayAxis => _displayAxis;

  /// True while the +1-finger modifier is turning the frame axis into
  /// single-frame steps — the HUD's other mode, not a finer version of
  /// the same one.
  bool get frameStep => _frameStep;

  /// Where the axis locked, in the gesture layer's local coordinates. The
  /// HUD pins here for the whole gesture: the finger travels a long way
  /// along the drag axis, and a HUD that follows it cannot be read.
  Offset? get anchor => _anchor;

  FlipHudSnapshot get snapshot => _snapshot;

  /// The session supplies the rows. Unbound the HUD simply never shows —
  /// the CanvasSelectionCommands idiom.
  ///
  /// The axis is passed in because it decides how much has to be built: a
  /// frame-axis window draws ONE row's blocks, so materialising every
  /// other row's runs would be work nobody looks at.
  void bind(FlipHudSnapshot Function(FlipHudAxis axis) snapshotOf) {
    _snapshotOf = snapshotOf;
  }

  void unbind() {
    _snapshotOf = null;
  }

  /// The axis has locked: show, and remember what we are standing on so
  /// the first real step can tell whether the picture changed. No tick —
  /// nothing has moved yet.
  void begin({
    required FlipHudAxis axis,
    required Offset anchor,
    required bool frameStep,
  }) {
    _hideTimer?.cancel();
    _hideTimer = null;
    _clearTimer?.cancel();
    _clearTimer = null;
    _axis = axis;
    _displayAxis = axis;
    _anchor = anchor;
    _frameStep = frameStep;
    _snapshot = _snapshotOf?.call(axis) ?? FlipHudSnapshot.empty;
    _lastContentKey = _snapshot.contentKey;
    _lastPosition = (_snapshot.frameIndex, _snapshot.rowIndex);
    _lastLandedAt = null;
    _lastStepInterval = null;
    _visible = !_snapshot.isEmpty;
    if (!_visible) {
      _displayAxis = null;
    }
    notifyListeners();
  }

  /// A step has LANDED (or the modifier changed). Re-reads the session and
  /// ticks if the picture under the cursor is a different one.
  void refresh({bool? frameStep}) {
    final live = _axis;
    if (live == null) {
      return;
    }
    if (frameStep != null) {
      _frameStep = frameStep;
    }
    _snapshot = _snapshotOf?.call(live) ?? FlipHudSnapshot.empty;
    _visible = !_snapshot.isEmpty;
    if (_visible) {
      _displayAxis = _axis;
    }
    // Only a LANDING re-times the slide. A modifier change re-renders
    // without moving the cursor, and letting that reset the interval
    // would size the next leg off a non-event.
    final position = (_snapshot.frameIndex, _snapshot.rowIndex);
    if (position != _lastPosition) {
      final now = _clock();
      final previous = _lastLandedAt;
      _lastStepInterval = previous == null ? null : now.difference(previous);
      _lastLandedAt = now;
      _lastPosition = position;
    }
    final key = _snapshot.contentKey;
    if (key != null && key != _lastContentKey) {
      _tick();
    }
    _lastContentKey = key;
    notifyListeners();
  }

  /// The gesture is over: hold the picture briefly, then fade out.
  void end() {
    if (_axis == null && _displayAxis == null) {
      return;
    }
    _axis = null;
    _lastContentKey = null;
    if (!_visible) {
      _displayAxis = null;
      _anchor = null;
      notifyListeners();
      return;
    }
    _hideTimer?.cancel();
    _hideTimer = Timer(holdAfterRelease, () {
      _hideTimer = null;
      _visible = false;
      notifyListeners();
      // Stay mounted for the fade, then let go of the anchor.
      _clearTimer?.cancel();
      _clearTimer = Timer(fadeOut, () {
        _clearTimer = null;
        _displayAxis = null;
        _anchor = null;
        notifyListeners();
      });
    });
    notifyListeners();
  }

  void _tick() {
    if (!_hapticsEnabled()) {
      return;
    }
    final now = _clock();
    final last = _lastTickAt;
    if (last != null && now.difference(last) < hapticCoalesce) {
      return;
    }
    _lastTickAt = now;
    // No platform branch on purpose: HapticFeedback rides
    // SystemChannels.platform, an OptionalMethodChannel, and the desktop
    // embedders answer NotImplemented — the call is a silent no-op there
    // rather than an error to guard against.
    _hapticTick();
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _hideTimer = null;
    _clearTimer?.cancel();
    _clearTimer = null;
    super.dispose();
  }
}
