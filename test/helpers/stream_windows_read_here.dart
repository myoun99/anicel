import 'package:anicel/src/services/audio/audio_mixer_reference.dart'
    show AudioMixSource;
import 'package:anicel/src/services/audio/equalized_stream.dart'
    show StreamWindowRead, readStreamedWindow;
import 'package:anicel/src/ui/playback/audio_playback_schedule.dart';

/// [read]'s window read on this isolate, as a worker reads it
/// (`readStreamWindowsInto`) — for a test that looks at what a plan reads.
AudioMixSource streamWindowReadHere(StreamWindowRead read) {
  final window = readStreamedWindow(read);
  return AudioMixSource(
    samples: window.samples,
    channels: read.reader.channels,
    sourceStart: window.startSample,
  );
}

/// [plan]'s upload, every window read on this isolate
/// ([streamWindowReadHere]).
WindowedUpload readHere(WindowedUploadPlan plan) => plan.withWindows([
  for (final read in plan.reads) streamWindowReadHere(read),
]);
