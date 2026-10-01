import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/widgets.dart';

import '../../models/app_input_settings.dart';

/// A detector whose DEVICE SET follows the one-finger mode builds through
/// this, which builds it again whenever the input settings move the set.
///
/// A recognizer is handed its devices when its detector builds, and a
/// finger's meaning is a setting: the timeline's edit pans take a finger
/// while the one-finger slot draws and leave it to the scroll otherwise
/// ([AppInput.timelineEditPanDevices] — UI-R22 #6, 결정 10), and a tool's
/// own handles on the canvas take one only while it draws
/// ([AppInput.toolPointerDevices] — TS9).
///
/// ↩️The edit pans used to ride the app root's rebuild on every input
/// change, and that reached them only because it made the theme animate:
/// the whole app rebuilt for a few frames on any input toggle
/// (auto-frame-toggle-hitch, 2026-09-29). The canvas handles rode nothing
/// at all — they took their set in the recognizer's CONSTRUCTOR, which no
/// rebuild runs again, so a mode change reached them only when they were
/// mounted anew (finger-mode-reaches-canvas-handles). Listening here
/// rebuilds the detectors and nothing under them — [builder] hands each
/// one the child it already had.
class FingerModeDevices extends StatelessWidget {
  /// The timeline's edit pans ([AppInput.timelineEditPanDevices]).
  const FingerModeDevices.timelineEditPan({super.key, required this.builder})
    : _devices = _timelineEditPan;

  /// A tool's own handles on the canvas ([AppInput.toolPointerDevices]).
  const FingerModeDevices.tool({super.key, required this.builder})
    : _devices = _tool;

  /// Builds the detector with the set as it stands; null is every device
  /// (the tool set while one finger draws).
  final Widget Function(BuildContext context, Set<PointerDeviceKind>? devices)
  builder;

  final Set<PointerDeviceKind>? Function() _devices;

  static Set<PointerDeviceKind> _timelineEditPan() =>
      AppInput.timelineEditPanDevices;

  static Set<PointerDeviceKind>? _tool() => AppInput.toolPointerDevices;

  @override
  Widget build(BuildContext context) =>
      ValueListenableBuilder<AppInputSettings>(
        valueListenable: AppInput.settings,
        builder: (context, _, _) => builder(context, _devices()),
      );
}
