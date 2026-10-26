import 'package:flutter/material.dart';

import '../../models/working_panel.dart';
import '../camera/camera_view_toggle_button.dart';
import '../editor_session_manager.dart';
import '../playback/canvas_playback_controller.dart';
import '../playback/playback_transport_controls.dart';
import '../storyboard_playhead_mapping.dart'
    show seekStoryboardPlayheadToTrackStart;

/// What a frame panel's transport drives: its playlist, where a play
/// starts, and where 「처음으로」 goes while the transport is not running
/// there.
typedef PanelTransport = ({
  PlaybackScope scope,
  int Function() startFrame,
  VoidCallback skipToStart,
});

/// [panel]'s transport — ONE answer for its bar's buttons and their keys
/// (F-261: a key presses the button on the panel being worked in, the panel
/// the flip already follows).
PanelTransport panelTransportFor(
  WorkingPanel panel,
  EditorSessionManager session,
) => switch (panel) {
  WorkingPanel.timeline => (
    scope: PlaybackScope.activeCut,
    startFrame: () => session.currentFrameIndex,
    skipToStart: () => session.selectFrameIndex(0),
  ),
  WorkingPanel.storyboard => (
    scope: PlaybackScope.allCuts,
    startFrame: () => session.playheadCursors.trackFrameNow() ?? 0,
    skipToStart: () => seekStoryboardPlayheadToTrackStart(session),
  ),
};

/// A frame panel's transport, at the head of its command bar
/// ([TimelineCommandBar.transport]): its playback buttons and the camera
/// view toggle — what [panel]'s transport drives is [panelTransportFor]'s
/// answer.
/// ↩️A ⚙ of the project's settings stood beside them too, until they went
/// to the top strip's ⚙ beside the work's (답 playback-quality-home-Q1
/// 「프로젝트 설정으로 같이」).
///
/// ↩️They stood on the region's 문턱 from 2026-08-10 to F-111 (유저
/// 2026-10-08, F-111-Q1 「버튼행 맨 왼쪽에 고정 — 알약 칸 밖」). The sill's
/// right edge does not move — its tabs grow from the left — whereas a
/// transport leading the command bar's scrolling row slid sideways every
/// time the row changed shape: 「존재할 거면 늘 그 자리에」. Pinned at the
/// bar's head, outside its scroller, it keeps that.
///
/// ★And the ZOOM and the x-sheet toggle are not part of it: those reach into
/// the panel's own contents and stand at the bar's other end, in the view
/// cluster. What is here means the same thing whichever panel is open.
class FramePanelTransport extends StatelessWidget {
  const FramePanelTransport({
    super.key,
    required this.session,
    required this.panel,
  });

  final EditorSessionManager session;

  /// Whose transport this is: the timeline plays the active cut, the
  /// storyboard the whole track.
  final WorkingPanel panel;

  /// R28 #1: camera view is a VIEW MODE, so every panel with a transport
  /// carries the toggle beside it — both entrances press the one switch,
  /// the project's camera row's eye ([EditorSessionManager.cameraViewMode]).
  String get _cameraViewKeyValue => switch (panel) {
    WorkingPanel.timeline => 'timeline-camera-view-button',
    WorkingPanel.storyboard => 'storyboard-camera-view-button',
  };

  @override
  Widget build(BuildContext context) {
    final transport = panelTransportFor(panel, session);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        PlaybackTransportControls(
          controller: session.playbackRig.playback,
          scope: transport.scope,
          playbackStartFrame: transport.startFrame,
          onSkipToStart: transport.skipToStart,
          resolveMeterPeaks: () =>
              session.playbackRig.audioDeviceTransport.meterPeaks,
          isVoiceRecording: session.voiceRecording.isVoiceRecording,
          onToggleVoiceRecording: () =>
              toggleVoiceRecordingWithFeedback(context, session),
          voiceRecordClipLit: session.voiceRecording.voiceRecordClipLit,
          resolveStrings: () => session.uiStrings,
          playsWithout: session.playbackRig.audioDeviceTransport.playsWithout,
        ),
        CameraViewToggleButton(
          view: session.cameraViewMode,
          keyValue: _cameraViewKeyValue,
        ),
      ],
    );
  }
}
