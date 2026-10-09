import 'package:flutter/material.dart';

import '../shortcuts/editor_action_registry.dart' show EditorActionIds;
import '../text/app_strings.dart';
import '../widgets/app_icon_button.dart';

/// The camera view switch's press — and its key's (I-40).
void toggleCameraView(ValueNotifier<bool> enabled) {
  enabled.value = !enabled.value;
}

/// The CAMERA VIEW toggle that sits beside a command bar's transport
/// (R27 #1, unified across panels by R28 #1).
///
/// Camera view is a VIEW MODE, not a property of the timeline: the same
/// button therefore belongs on every panel that carries a transport. Both
/// entrances drive the one notifier the workspace owns, so the state can
/// never disagree between panels.
///
/// [keyValue] distinguishes the mounts for finders; everything else about
/// the button — icon, sizing, lit color, tooltip wording — lives here so a
/// restyle lands on every panel at once.
class CameraViewToggleButton extends StatelessWidget {
  const CameraViewToggleButton({
    super.key,
    required this.enabled,
    required this.keyValue,
  });

  /// Null hosts skip the button entirely (a panel without camera context).
  final ValueNotifier<bool>? enabled;
  final String keyValue;

  @override
  Widget build(BuildContext context) {
    final notifier = enabled;
    if (notifier == null) {
      return const SizedBox.shrink();
    }
    return ValueListenableBuilder<bool>(
      valueListenable: notifier,
      // R26 #42: the app's standard icon button — its accent IS the
      // on-state, so no hand-mixed color lives here.
      builder: (context, isOn, _) => AppIconButton(
        keyValue: keyValue,
        // ↩️「Camera view (on)」 and its twin stood here in English in
        // every language until I-40's round on the bar found them (10-09).
        tooltip: isOn
            ? AppText.strings.cameraViewOn
            : AppText.strings.cameraViewOff,
        shortcuts: const [EditorActionIds.cameraViewToggle],
        isSelected: isOn,
        onPressed: () => toggleCameraView(notifier),
        icon: const Icon(Icons.videocam_outlined),
      ),
    );
  }
}
