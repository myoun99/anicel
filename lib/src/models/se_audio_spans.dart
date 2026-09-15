import 'audio_clip.dart';
import 'layer.dart';
import 'timeline_coverage.dart';

/// One audible window of an SE layer: a timeline block whose frame carries
/// a linked sound. The BLOCK is the instance — the sound starts where the
/// block starts and never plays past its end (the audible tail also clamps
/// to the file's own length, which only the peaks pipeline knows).
class SeAudioSpan {
  const SeAudioSpan({
    required this.clip,
    required this.clipIndex,
    required this.startFrame,
    required this.lengthFrames,
    this.leadInFrames = 0,
  });

  final AudioClip clip;

  /// Index into [Layer.audioClips] (the removal hook's handle).
  final int clipIndex;

  /// Cut-local start of the carrying block.
  final int startFrame;

  /// The carrying block's length — the hard playback/display window.
  final int lengthFrames;

  /// How much of the sound already played before [startFrame]: a block a
  /// cut shows spilling in from an earlier cut starts there with its sound
  /// that far along (F-113). Zero for every block that starts where it is
  /// shown.
  final int leadInFrames;

  int get endFrameExclusive => startFrame + lengthFrames;

  /// Frames into the FILE the span's first frame sounds — the clip's own
  /// offset trim plus [leadInFrames]. What a waveform is drawn from.
  int get leadingFrames => clip.offsetFrames + leadInFrames;
}

/// Every audible window of [layer], in block order. A frame exposed by
/// several blocks (linked/held reuse — footsteps) yields one span per
/// block; clips whose frame has no block are inert (deleted blocks fall
/// silent, and return when the frame is exposed again — frame-link
/// semantics, same as drawings).
///
/// [leadInAtStart] is how far into its sound a block starting at frame 0
/// already is: a track-SE row's cut-local clone restarts a block that spills
/// in from an earlier cut there (`TrackSeWindow.spillInLeadFrames`).
List<SeAudioSpan> seAudioSpans(Layer layer, {int leadInAtStart = 0}) {
  if (layer.audioClips.isEmpty) {
    return const [];
  }
  final spans = <SeAudioSpan>[];
  for (final block in drawingBlocks(layer.timeline)) {
    for (var index = 0; index < layer.audioClips.length; index += 1) {
      final clip = layer.audioClips[index];
      if (clip.frameId == block.frameId) {
        spans.add(
          SeAudioSpan(
            clip: clip,
            clipIndex: index,
            startFrame: block.startIndex,
            lengthFrames: block.endIndexExclusive - block.startIndex,
            leadInFrames: block.startIndex == 0 ? leadInAtStart : 0,
          ),
        );
      }
    }
  }
  return spans;
}
