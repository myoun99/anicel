import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/audio_clip.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/export_format_selection.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_frame_rate.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/services/audio/audio_conform_pipeline.dart';
import 'package:anicel/src/services/audio/audio_peaks_extractor.dart';
import 'package:anicel/src/services/editing/default_cut_helpers.dart';
import 'package:anicel/src/services/persistence/app_export_settings.dart';
import 'package:anicel/src/ui/audio/audio_conform_store.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/export/export_dialog.dart';
import 'package:anicel/src/ui/export/export_format_availability.dart';
import 'package:anicel/src/ui/export/png_sequence_export_service.dart'
    show ExportWriteSummary;
import 'package:anicel/src/ui/export/video_export_service.dart';

import '../../helpers/export_preview_probe.dart';
import '../../helpers/temp_dir.dart';

/// A film run that writes nothing: it asks for the sound before its mix, as
/// a writer that puts a frame there does with its first picture, and keeps
/// what it is handed.
class _AFilmThatAsksForItsPast extends VideoExportService {
  static const lead = 1024;

  bool hadMix = false;
  Int16List? past;

  @override
  Future<ExportWriteSummary> exportVideo({
    required int count,
    required Future<ui.Image?> Function(int index) renderImage,
    required String outputFilePath,
    required ProjectFrameRate frameRate,
    String? audioMixPath,
    SoundBefore? soundBefore,
    ExportVideoContainer container = ExportVideoContainer.mp4,
    ExportVideoCodec codec = ExportVideoCodec.h264,
    bool alpha = false,
    int bitrateBps = 0,
    ExportGifSettings gif = const ExportGifSettings(),
    void Function(int completed, int total)? onProgress,
    bool Function()? isCancelled,
  }) async {
    hadMix = audioMixPath != null;
    past = await soundBefore!(lead);
    return (written: count, processed: count);
  }
}

/// 🗣️유저 2026-11-10 (board an-mp4-reopened-loses-its-first-9-ms-of-sound-
/// Q2): 「내보낼 때 소리 앞에 1,024 샘플(무음, 범위 앞에 소리가 있으면 그
/// 소리)을 넣고」.
///
/// The window hands the film's writer the sound just before the film's
/// first frame — off the mixer the film's own sound comes from, of the
/// frames the TIMELINE holds before it: the cut before the one going out is
/// the film's past as much as the cut's own earlier frames are.
void main() {
  late Directory temp;

  setUp(() {
    AppExport.settings.value = AppExportSettings();
    temp = Directory.systemTemp.createTempSync('anicel-film-led');
  });

  tearDown(() {
    AppExport.settings.value = AppExportSettings();
    deleteTempQuietly(temp);
  });

  // Two frames at 24 fps, in the conform's 48 kHz.
  const cutSamples = 4000;

  /// A stereo sound of a cut's length whose every sample says where it
  /// lies: frame n holds n + 1 on the left and its negative on the right,
  /// in 16-bit steps.
  Float32List ramp() {
    final samples = Float32List(cutSamples * 2);
    for (var index = 0; index < cutSamples; index += 1) {
      samples[index * 2] = (index + 1) / 32768;
      samples[index * 2 + 1] = -(index + 1) / 32768;
    }
    return samples;
  }

  /// A cut of two frames that plays [sound] over both.
  Cut cutPlaying(String id, {required String sound}) => Cut(
    id: CutId(id),
    name: id.toUpperCase(),
    duration: 2,
    canvasSize: const CanvasSize(width: 8, height: 8),
    layers: [
      Layer(
        id: LayerId('$id-a'),
        name: 'A',
        frames: [
          Frame(id: FrameId('$id-a1'), duration: 1, strokes: const []),
        ],
      ),
      Layer(
        id: LayerId('$id-se'),
        name: 'S1',
        kind: LayerKind.se,
        frames: [
          Frame(id: FrameId('$id-se1'), duration: 1, strokes: const []),
        ],
        timeline: {0: TimelineExposure.drawing(FrameId('$id-se1'), length: 2)},
        audioClips: [AudioClip(filePath: sound, frameId: FrameId('$id-se1'))],
      ),
      createCameraLayer(cutId: CutId(id)),
    ],
  );

  /// Cut A plays the ramp, cut B after it a steady level of its own — a
  /// sound no sample of which is the ramp's.
  EditorSessionManager session() {
    final level = Float32List(cutSamples * 2);
    level.fillRange(0, level.length, 0.25);
    final sounds = {'before.wav': ramp(), 'own.wav': level};
    return EditorSessionManager(
      audioConformStore: AudioConformStore(
        resolveConformPath: (_) => null,
        runner: (request) async {
          final samples = sounds.entries
              .singleWhere((sound) => request.sourcePath.endsWith(sound.key))
              .value;
          return ConformResult(
            outcome: ConformOutcome.built,
            peaks: AudioPeaks(bucketsPerSecond: 100, peaks: Float32List(9)),
            samples: samples,
            channels: 2,
            sampleRate: request.projectSampleRate,
            frames: samples.length ~/ 2,
            speedNumerator: request.speedNumerator,
            speedDenominator: request.speedDenominator,
          );
        },
        log: (_) {},
      ),
      initialProject: Project(
        id: const ProjectId('project'),
        name: 'Project',
        cameraSize: const CanvasSize(width: 32, height: 18),
        tracks: [
          Track(
            id: const TrackId('track'),
            name: 'Track',
            cuts: [
              cutPlaying('a', sound: 'before.wav'),
              cutPlaying('b', sound: 'own.wav'),
            ],
          ),
        ],
        createdAt: DateTime.utc(2026),
      ),
    );
  }

  /// The film of the cut [stoodOn], as the window writes it by default —
  /// what its writer was handed.
  Future<_AFilmThatAsksForItsPast> filmOf(
    WidgetTester tester,
    String stoodOn,
  ) async {
    final run = _AFilmThatAsksForItsPast();
    final s = session();
    addTearDown(s.dispose);
    s.selectCut(CutId(stoodOn));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ExportDialog(
            session: s,
            exportDirectoryPicker: () async => temp.path,
            videoExportService: run,
            formatAvailability: ExportFormatAvailability.permissive(),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.settleExportPreview();
    final state = tester.state<ExportDialogState>(find.byType(ExportDialog));
    await tester.runAsync(state.export);
    await tester.pump();
    s.playbackRig.prerenderScheduler.cancel();
    return run;
  }

  /// The sound frame [pcm] holds at [index], both channels.
  List<int> frameAt(Int16List pcm, int index) => [
    pcm[index * 2],
    pcm[index * 2 + 1],
  ];

  testWidgets('🚨the film of a cut is handed the END of the cut before it — '
      'the samples that sounded just before its first', (tester) async {
    final run = await filmOf(tester, 'b');

    expect(run.hadMix, isTrue, reason: 'LIVENESS: the film has a sound');
    final past = run.past!;
    expect(past, hasLength(_AFilmThatAsksForItsPast.lead * 2));
    // Cut A's last 1,024 samples, each where it lay against cut B's first.
    expect(frameAt(past, 0), [cutSamples - 1023, -(cutSamples - 1023)]);
    expect(frameAt(past, 1023), [cutSamples, -cutSamples]);
  });

  testWidgets('nothing sounded before the track\'s first cut — its film is '
      'handed none, and its writer\'s silence stays', (tester) async {
    final run = await filmOf(tester, 'a');

    expect(run.hadMix, isTrue, reason: 'LIVENESS: the film has a sound');
    expect(run.past, isNull);
  });
}
