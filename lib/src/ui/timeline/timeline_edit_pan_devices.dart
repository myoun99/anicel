import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/widgets.dart';

import '../../models/app_input_settings.dart';

/// The timeline's EDIT PANS take their devices at BUILD time — a
/// recognizer is handed its set when its detector builds — so each one
/// builds through this, which builds it again whenever the input settings
/// move the set ([AppInput.timelineEditPanDevices]: a finger edits while
/// the one-finger slot draws and scrolls otherwise — UI-R22 #6, 결정 10).
///
/// ↩️They used to ride the app root's rebuild on every input change, and
/// that reached them only because it made the theme animate: the whole app
/// rebuilt for a few frames on any input toggle (auto-frame-toggle-hitch,
/// 2026-09-29). Listening here rebuilds the detectors and nothing under
/// them — [builder] hands each one the child it already had.
class TimelineEditPanDevices extends StatelessWidget {
  const TimelineEditPanDevices({super.key, required this.builder});

  final Widget Function(BuildContext context, Set<PointerDeviceKind> devices)
  builder;

  @override
  Widget build(BuildContext context) =>
      ValueListenableBuilder<AppInputSettings>(
        valueListenable: AppInput.settings,
        builder: (context, _, _) =>
            builder(context, AppInput.timelineEditPanDevices),
      );
}
