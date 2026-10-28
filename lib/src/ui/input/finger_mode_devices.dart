import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/widgets.dart';

import '../../models/app_input_settings.dart';

/// A detector whose DEVICE SET follows the one-finger mode builds through
/// this, which builds it again whenever the input settings move the set.
///
/// A recognizer is handed its devices when its detector builds, and a
/// finger's meaning is a setting: a tool's own handles on the canvas take
/// one only while it draws ([AppInput.toolPointerDevices] — TS9).
///
/// ↩️The canvas handles took their set in the recognizer's CONSTRUCTOR,
/// which no rebuild runs again, so a mode change reached them only when
/// they were mounted anew (finger-mode-reaches-canvas-handles). Listening
/// here rebuilds the detectors and nothing under them — [builder] hands
/// each one the child it already had.
///
/// ★It listens ITSELF. ↩️It built a `ValueListenableBuilder` that did the
/// listening — two elements where one does, paid on every panel reopen
/// (card frame-panels-build-in-one-frame, 2026-10-25).
///
/// ↩️The timeline's edit pans built through it too, with their own set
/// ([AppInput.timelineEditPanDevices] — 결정 10). Their box hears the mode
/// and re-dresses its own recogniser now (`TimelineEditPan`), and the rail's
/// column sweep, the last of them, takes every device — a finger that lands
/// on a column's button is the button's (F-475).
class FingerModeDevices extends StatefulWidget {
  /// A tool's own handles on the canvas ([AppInput.toolPointerDevices]).
  const FingerModeDevices.tool({super.key, required this.builder});

  /// Builds the detector with the set as it stands; null is every device
  /// (the tool set while one finger draws).
  final Widget Function(BuildContext context, Set<PointerDeviceKind>? devices)
  builder;

  @override
  State<FingerModeDevices> createState() => _FingerModeDevicesState();
}

class _FingerModeDevicesState extends State<FingerModeDevices> {
  @override
  void initState() {
    super.initState();
    AppInput.settings.addListener(_moved);
  }

  @override
  void dispose() {
    AppInput.settings.removeListener(_moved);
    super.dispose();
  }

  void _moved() => setState(() {});

  @override
  Widget build(BuildContext context) =>
      widget.builder(context, AppInput.toolPointerDevices);
}
