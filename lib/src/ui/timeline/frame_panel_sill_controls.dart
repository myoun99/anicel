import 'package:flutter/material.dart';

import '../camera/camera_view_toggle_button.dart';
import '../editor_session_manager.dart';
import '../playback/canvas_playback_controller.dart';
import '../playback/playback_transport_controls.dart';
import 'project_settings_pill.dart';

/// What a frame panel puts on the 문턱: its playback transport, the camera
/// view toggle, and the settings pill — right-aligned, ahead of the region's
/// own collapse button.
///
/// ★They live on the SILL rather than in the command bar for one reason
/// (유저 확정, 2026-08-10): the sill's right edge does not move. Its tabs
/// grow from the left, so adding a panel to the workspace shifts the tabs
/// and nothing else — whereas a left-aligned transport in the command bar
/// slid sideways every time the bar above it changed shape. 「존재할 거면
/// 늘 그 자리에.」
///
/// ★And the ZOOM and the x-sheet toggle deliberately did NOT come with them:
/// those reach into the panel's own contents, so they stay on the panel's
/// own row. What is on the sill is what means the same thing whichever
/// panel is open.
///
/// Mounted by the WORKSPACE through [EditorPanelTab.sillTrailing], not by
/// the tab host — only the active tab's is built, which is what lets one
/// sill carry two panels' transports without either of them knowing.
class FramePanelSillControls extends StatelessWidget {
  const FramePanelSillControls({
    super.key,
    required this.session,
    required this.scope,
    required this.cameraViewKeyValue,
    this.cameraViewEnabled,
    this.playbackStartFrame,
    this.onSkipToStart,
  });

  final EditorSessionManager session;

  /// Which playlist this panel's transport drives: the timeline plays the
  /// active cut, the storyboard the whole track.
  final PlaybackScope scope;

  /// R28 #1: camera view is a VIEW MODE, so every panel with a transport
  /// carries the toggle beside it — both entrances drive the one notifier.
  final ValueNotifier<bool>? cameraViewEnabled;
  final String cameraViewKeyValue;

  final int Function()? playbackStartFrame;
  final VoidCallback? onSkipToStart;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        PlaybackTransportControls(
          controller: session.playback,
          scope: scope,
          playbackStartFrame: playbackStartFrame,
          onSkipToStart: onSkipToStart,
          resolveMeterPeaks: () => session.audioDeviceTransport.meterPeaks,
          isVoiceRecording: session.isVoiceRecording,
          onToggleVoiceRecording: () =>
              toggleVoiceRecordingWithFeedback(context, session),
          voiceRecordClipLit: session.voiceRecordClipLit,
          resolveStrings: () => session.uiStrings,
        ),
        CameraViewToggleButton(
          enabled: cameraViewEnabled,
          keyValue: cameraViewKeyValue,
        ),
        const SizedBox(width: 6),
        ProjectSettingsPill(session: session),
        const SizedBox(width: 4),
      ],
    );
  }
}
