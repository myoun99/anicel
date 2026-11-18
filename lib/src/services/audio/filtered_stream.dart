import 'dart:math' as math;
import 'dart:typed_data';

import '../../native/qa_audio_filter.dart';
import 'sound_filters.dart';
import 'conform_pcm_stream.dart';

/// A span too long to hold, baked through its row's filters a window at a
/// time (board audio-fx-grows-like-the-pros ③): the filters' memory at
/// every [spacing]-th sample of the span, made by one pass over it, so a
/// window baked on from the checkpoint before it holds the samples the
/// whole span baked at once holds there — playback's windows and an
/// export's blocks alike ([readStreamedWindow]).
///
/// ↩️It was to be baked to disk, kept as a conform is: but a conform's file
/// holds int16, and a filter that raises a sound past full scale would
/// have been clipped there — a long sound playing other samples than a
/// short one under the same filters — and a long span would have been
/// held on disk once more.
final class FilterCheckpoints {
  const FilterCheckpoints({required this.spacing, required this.memories});

  /// Samples of the span between two checkpoints.
  final int spacing;

  /// The memory at the span's sample `k * spacing`, for each k the span
  /// reaches — the first all at rest.
  final List<Float64List> memories;
}

/// How far apart a span's checkpoints stand at [rate]: a quarter second —
/// the most a window's bake reads before the window begins — or farther
/// where the filters remember much ([memory] doubles over [channels]), so
/// the checkpoints weigh no more than a quarter of the sound between them:
/// a double is two floats' bytes, so one every 8 × [memory] ÷ [channels]
/// samples.
///
/// 🔬A noise removal remembers each channel's model and frames — about
/// 5,000 doubles a channel (native/audio_mix denoiser.rs): a checkpoint a
/// quarter second would weigh three times the sound, about 190 MB for ten
/// minutes in stereo; this way 0.83 s apart at 48 kHz. An equalizer's and a
/// compressor's stay a quarter second.
int filterCheckpointSpacing({
  required int rate,
  required int channels,
  required int memory,
}) => math.max(
  math.max(1, rate ~/ 4),
  channels <= 0 ? 0 : 8 * memory ~/ channels,
);

/// [span]'s checkpoints, read off [reader] — the conform its samples are
/// cut from — a stretch at a time. Null where the conform does not read
/// whole or the engine refuses it.
FilterCheckpoints? filterCheckpointsOf(
  ConformPcmStreamReader reader,
  FilteredSpan span,
) {
  final stretches = FilterStretches(
    channels: reader.channels,
    rate: reader.sampleRate,
    stages: span.stages,
  );
  final spacing = filterCheckpointSpacing(
    rate: reader.sampleRate,
    channels: reader.channels,
    memory: stretches.kept.length,
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
  return FilterCheckpoints(spacing: spacing, memories: memories);
}

/// A streamed span's filters as a window is read through them: the span and
/// its checkpoints.
typedef FilteredStream = ({
  FilteredSpan span,
  FilterCheckpoints checkpoints,
});

/// One streamed window: [count] samples per channel from [start] of
/// [reader]'s conform, through [filtered] where its span has filters
/// — what a run's upload reads for a clip on a worker, and an export for a
/// block ([readStreamedWindow]).
typedef StreamWindowRead = ({
  ConformPcmStreamReader reader,
  int start,
  int count,
  FilteredStream? filtered,
});

/// [read]'s window — through its filters where it has them, baked on from
/// the checkpoint before it with the samples before it dropped; as the
/// conform holds it where not ([ConformPcmStreamReader.readWindow]) — into
/// the list [place] makes when it makes one. Clamped into the conform, and
/// into the span where there is one; empty where it does not read whole.
///
/// 🚨THE ONE READ A STREAMED SOURCE'S WINDOWS TAKE — playback's, on its
/// worker, and an export's blocks — so the two cannot play a long span
/// through its filters two ways.
({int startSample, Float32List samples}) readStreamedWindow(
  StreamWindowRead read, {
  Float32List? Function(int floats)? place,
}) {
  final filtered = read.filtered;
  return filtered == null
      ? read.reader.readWindow(read.start, read.count, place: place)
      : _readFilteredWindow(read, filtered, place);
}

({int startSample, Float32List samples}) _readFilteredWindow(
  StreamWindowRead read,
  FilteredStream filtered,
  Float32List? Function(int floats)? place,
) {
  final reader = read.reader;
  final (:span, :checkpoints) = filtered;
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
  final stretches = FilterStretches(
    channels: channels,
    rate: reader.sampleRate,
    stages: span.stages,
    from: (first: from - span.start, memory: checkpoints.memories[k]),
  );
  // What comes out late ([FilterStretches.latency]) is read on past the
  // window — in silence past the span, as its whole bake is ([filterAudio]).
  final late = stretches.latency;
  final count = start - from + held + late;
  final reach = math.min(from + count, spanEnd) - from;
  final stretch = reader.readWindow(from, reach).samples;
  if (stretch.length != reach * channels) {
    return empty;
  }
  final baked = stretches.next(
    reach == count
        ? stretch
        : (Float32List(count * channels)..setAll(0, stretch)),
  );
  if (baked.length != count * channels) {
    return empty;
  }
  final floats = held * channels;
  final into = place?.call(floats) ?? Float32List(floats);
  final at = (start - from + late) * channels;
  into.setAll(0, Float32List.sublistView(baked, at, at + floats));
  return (startSample: start, samples: into);
}
