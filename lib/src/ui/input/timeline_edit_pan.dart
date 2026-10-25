import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart' show PipelineOwner;
import 'package:flutter/widgets.dart';

import '../../models/app_input_settings.dart' show AppInput;
import 'eager_pan_gesture_recognizer.dart';
import 'recognizer_box.dart';

/// The eager pan that owns a timeline edit drag from its first pixel — a
/// range drag on the cells and the lanes, a header graph's box (I-3 ⑤), a
/// rail row's move or select — as one render object.
///
/// ONE recogniser set-up for all of them (the audit's clone scan,
/// 2026-09-03): pressed DOWN is where the drag starts
/// ([DragStartBehavior.down]), the device gesture settings are the
/// context's, and the devices follow the one-finger mode
/// ([AppInput.timelineEditPanDevices] — UI-R22 #6, 결정 10): pen and mouse
/// edit, a finger scrolls the timeline until one finger is the drawing hand.
/// The box hears that setting itself and hands the recogniser the new set;
/// nothing is built again.
///
/// Translucent: the taps under it (select the layer, the eye, the sliders)
/// keep firing — only the pan joins the arena.
///
/// ★ONE BOX ([RecognizerBox]). ↩️It was `FingerModeDevices` around a
/// [RawGestureDetector] — four elements under every row's cells and every
/// row's drag, paid on every panel reopen — and the row drag wrote the same
/// set-up by hand a second time (card frame-panels-build-in-one-frame,
/// 2026-10-25).
class TimelineEditPan extends RecognizerBox<EagerPanGestureRecognizer> {
  const TimelineEditPan({
    super.key,
    required this.debugOwner,
    this.firstStepAt,
    this.draggedAStep,
    required this.onStart,
    required this.onUpdate,
    required this.onEnd,
    required this.onCancel,
    super.child,
  });

  /// Who the recogniser is made for, as its `debugOwner`.
  final Object debugOwner;

  /// [EagerPanGestureRecognizer.firstStepAt].
  final bool Function(Offset down, Offset now)? firstStepAt;

  /// [EagerPanGestureRecognizer.draggedAStep].
  final bool Function()? draggedAStep;

  final GestureDragStartCallback onStart;
  final GestureDragUpdateCallback onUpdate;
  final VoidCallback onEnd;
  final VoidCallback onCancel;

  @override
  HitTestBehavior get behavior => HitTestBehavior.translucent;

  @override
  EagerPanGestureRecognizer makeRecognizer() =>
      EagerPanGestureRecognizer(debugOwner: debugOwner);

  @override
  void configure(EagerPanGestureRecognizer recognizer) {
    recognizer
      ..firstStepAt = firstStepAt
      ..draggedAStep = draggedAStep
      ..dragStartBehavior = DragStartBehavior.down
      ..onStart = onStart
      ..onUpdate = onUpdate
      ..onEnd = ((_) => onEnd())
      ..onCancel = onCancel;
  }

  @override
  RenderTimelineEditPan createRenderObject(BuildContext context) =>
      RenderTimelineEditPan(
        gestureSettings: MediaQuery.maybeGestureSettingsOf(context),
      )..wear(this);

  @override
  void updateRenderObject(
    BuildContext context,
    covariant RenderTimelineEditPan renderObject,
  ) {
    // PEN-11: a detector injects none of these, so the box hands them over.
    renderObject.gestureSettings = MediaQuery.maybeGestureSettingsOf(context);
    super.updateRenderObject(context, renderObject);
  }
}

/// [TimelineEditPan]'s render object: hands its recogniser the devices the
/// one-finger mode leaves an edit pan, again whenever that mode moves.
class RenderTimelineEditPan
    extends RenderRecognizerBox<EagerPanGestureRecognizer> {
  RenderTimelineEditPan({required this.gestureSettings});

  /// The context's device gesture settings, handed to the recogniser.
  DeviceGestureSettings? gestureSettings;

  @override
  void wear(RecognizerBox<EagerPanGestureRecognizer> box) {
    super.wear(box);
    _dress();
  }

  /// The devices and the device settings, onto the recogniser held now.
  void _dress() {
    recognizer
      ?..supportedDevices = AppInput.timelineEditPanDevices
      ..gestureSettings = gestureSettings;
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    AppInput.settings.addListener(_dress);
    _dress();
  }

  @override
  void detach() {
    AppInput.settings.removeListener(_dress);
    super.detach();
  }
}
