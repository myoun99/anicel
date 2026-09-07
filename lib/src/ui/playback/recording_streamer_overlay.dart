import 'package:flutter/material.dart';

import '../editor_session_manager.dart';

/// The ADR streamer (REC1-E): a vertical line sweeping the picture that
/// reaches the right edge exactly at the punch-in — the eye's half of
/// the "삐-삐-삐-(대사)" cue, over the playback view only during the
/// approach. Shrinks to nothing outside it, so it can stay permanently
/// mounted in the canvas stack (the sibling-count rule).
class RecordingStreamerOverlay extends StatelessWidget {
  const RecordingStreamerOverlay({super.key, required this.session});

  final EditorSessionManager session;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: session.isVoiceRecording,
      builder: (context, recording, _) {
        if (!recording) {
          return const SizedBox.shrink();
        }
        return ValueListenableBuilder<int?>(
          valueListenable: session.playbackRig.playback.globalFrameIndexListenable,
          builder: (context, frame, _) {
            final window = session.voiceRecordStreamerWindow;
            if (frame == null || window == null) {
              return const SizedBox.shrink();
            }
            final span = window.punchFrame - window.startFrame;
            if (span <= 0 ||
                frame < window.startFrame ||
                frame >= window.punchFrame) {
              return const SizedBox.shrink();
            }
            return IgnorePointer(
              child: CustomPaint(
                key: const ValueKey<String>('recording-streamer'),
                size: Size.infinite,
                painter: _StreamerPainter(
                  (frame - window.startFrame) / span,
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class _StreamerPainter extends CustomPainter {
  const _StreamerPainter(this.progress);

  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final x = size.width * progress;
    // The classic film scribe: one bright line, ~90% opaque (user pick),
    // in the cue-sheet amber the beeps' settings row also shows.
    canvas.drawRect(
      Rect.fromLTWH(x - 1.5, 0, 3, size.height),
      Paint()..color = const Color(0xE6FAC775),
    );
  }

  @override
  bool shouldRepaint(covariant _StreamerPainter oldDelegate) =>
      oldDelegate.progress != progress;
}
