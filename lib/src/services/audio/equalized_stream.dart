import 'dart:math' as math;
import 'dart:typed_data';

import '../../native/qa_audio_equalizer.dart';
import 'audio_equalizer.dart';
import 'conform_pcm_stream.dart';

/// A span too long to hold, baked through its row's equalizer a window at a
/// time (board audio-fx-grows-like-the-pros ③): the filters' memory at
/// every [spacing]-th sample of the span, made by one pass over it, so a
/// window baked on from the checkpoint before it holds the samples the
/// whole span baked at once holds there — playback's windows and an
/// export's blocks alike ([readEqualizedWindow]).
///
/// ↩️It was to be baked to disk, kept as a conform is: but a conform's file
/// holds int16, and an equalizer that raises a sound past full scale would
/// have been clipped there — a long sound playing other samples than a
/// short one under the same equalizer — and a long span would have been
/// held on disk once more.
final class EqualizerCheckpoints {
  const EqualizerCheckpoints({required this.spacing, required this.memories});

  /// Samples of the span between two checkpoints.
  final int spacing;

  /// The memory at the span's sample `k * spacing`, for each k the span
  /// reaches — the first all at rest.
  final List<Float64List> memories;
}

/// How far apart a span's checkpoints stand at [rate]: a quarter second —
/// the most a window's bake reads before the window begins.
int equalizerCheckpointSpacing(int rate) => math.max(1, rate ~/ 4);

/// [span]'s checkpoints, read off [reader] — the conform its samples are
/// cut from — a stretch at a time. Null where the conform does not read
/// whole or the engine refuses it.
EqualizerCheckpoints? equalizerCheckpointsOf(
  ConformPcmStreamReader reader,
  EqualizedSpan span,
) {
  final spacing = equalizerCheckpointSpacing(reader.sampleRate);
  final stretches = EqualizerStretches(
    channels: reader.channels,
    rate: reader.sampleRate,
    stages: span.stages,
  );
  final memories = <Float64List>[];
  final end = math.min(span.start + span.length, reader.length);
  for (var at = span.start; at < end; at += spacing) {
    memories.add(stretches.kept);
    final count = math.min(spacing, end - at);
    final read = reader.readWindow(at, count).samples;
    if (read.length != count * reader.channels ||
        stretches.next(read).length != read.length) {
      return null;
    }
  }
  return EqualizerCheckpoints(spacing: spacing, memories: memories);
}

/// A streamed span's equalizer as a window is read through it: the span and
/// its checkpoints.
typedef EqualizedStream = ({
  EqualizedSpan span,
  EqualizerCheckpoints checkpoints,
});

/// One streamed window: [count] samples per channel from [start] of
/// [reader]'s conform, through [equalized] where its span has an equalizer
/// — what a run's upload reads for a clip on a worker, and an export for a
/// block ([readStreamedWindow]).
typedef StreamWindowRead = ({
  ConformPcmStreamReader reader,
  int start,
  int count,
  EqualizedStream? equalized,
});

/// [read]'s window — through its equalizer where it has one, baked on from
/// the checkpoint before it with the samples before it dropped; as the
/// conform holds it where not ([ConformPcmStreamReader.readWindow]) — into
/// the list [place] makes when it makes one. Clamped into the conform, and
/// into the span where there is one; empty where it does not read whole.
///
/// 🚨THE ONE READ A STREAMED SOURCE'S WINDOWS TAKE — playback's, on its
/// worker, and an export's blocks — so the two cannot play a long span
/// through its equalizer two ways.
({int startSample, Float32List samples}) readStreamedWindow(
  StreamWindowRead read, {
  Float32List? Function(int floats)? place,
}) {
  final equalized = read.equalized;
  return equalized == null
      ? read.reader.readWindow(read.start, read.count, place: place)
      : _readEqualizedWindow(read, equalized, place);
}

({int startSample, Float32List samples}) _readEqualizedWindow(
  StreamWindowRead read,
  EqualizedStream equalized,
  Float32List? Function(int floats)? place,
) {
  final reader = read.reader;
  final (:span, :checkpoints) = equalized;
  final spanEnd = math.min(span.start + span.length, reader.length);
  final start = read.start.clamp(span.start, spanEnd);
  final held = (read.start + read.count).clamp(start, spanEnd) - start;
  final empty = (startSample: start, samples: Float32List(0));
  if (held == 0 || checkpoints.memories.isEmpty) {
    return empty;
  }
  final k = math.min(
    (start - span.start) ~/ checkpoints.spacing,
    checkpoints.memories.length - 1,
  );
  final from = span.start + k * checkpoints.spacing;
  final channels = reader.channels;
  final stretch = reader.readWindow(from, start - from + held).samples;
  final baked = EqualizerStretches(
    channels: channels,
    rate: reader.sampleRate,
    stages: span.stages,
    from: (first: from - span.start, memory: checkpoints.memories[k]),
  ).next(stretch);
  if (baked.length != (start - from + held) * channels) {
    return empty;
  }
  final floats = held * channels;
  final into = place?.call(floats) ?? Float32List(floats);
  into.setAll(0, Float32List.sublistView(baked, (start - from) * channels));
  return (startSample: start, samples: into);
}
