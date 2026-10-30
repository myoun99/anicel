import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/models/audio_clip.dart';
import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/bitmap_tile.dart';
import 'package:anicel/src/models/camera_instruction.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/export_spec.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/layer_mark.dart';
import 'package:anicel/src/models/layer_process.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/tile_coord.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/services/audio/audio_conform_pipeline.dart';
import 'package:anicel/src/services/editing/default_cut_helpers.dart';
import 'package:anicel/src/services/persistence/app_export_settings.dart';
import 'package:anicel/src/ui/audio/audio_conform_store.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/export/export_dialog.dart';
import 'package:anicel/src/ui/export/export_format_availability.dart';

import '../../helpers/files_written_under.dart';
import '../../helpers/project_scratch_folder.dart';
import '../../helpers/written_wav.dart';

/// The AE Script tab's run, down to the files on disk: the cels the Cels
/// list picks, written as the tab writes them, and the script beside them
/// (ae-script-export). The script's comps are pinned where they are laid
/// (`ae_script_plan_test.dart`) and how they are said to After Effects
/// where they are written (`ae_script_test.dart`).
///
/// 🗣️ae-script-export-Q1 (유저 2026-10-15): 「ae 스크립트? 탭을 새로 만들어서
/// 거기서 셀부분 선택하는 동작은 셀 탭 그대로 사용하되, 용지 적용은
/// 필요없으니 그런부분 없앤다던가?」.
void main() {
  setUp(() => AppExport.settings.value = AppExportSettings());
  tearDown(() => AppExport.settings.value = AppExportSettings());

  const size = CanvasSize(width: 8, height: 8);
  const cutId = CutId('cut');
  const black = (0, 0, 0, 255);
  const key = LayerMark(process: LayerProcess.key);

  Frame frame(String id, String name) =>
      Frame(id: FrameId(id), duration: 1, strokes: const [], name: name);

  /// A (two cels) · B (one) · a paper row · a direction row.
  EditorSessionManager film({
    List<Layer> seLayers = const [],
    AudioConformStore? sounds,
  }) => EditorSessionManager(
    audioConformStore: sounds,
    initialProject: Project(
      id: const ProjectId('project'),
      name: 'Project',
      cameraSize: const CanvasSize(width: 32, height: 18),
      createdAt: DateTime.utc(2026),
      tracks: [
        Track(
          id: const TrackId('track'),
          name: 'Track',
          seLayers: seLayers,
          cuts: [
            Cut(
              id: cutId,
              name: 'CUT1',
              duration: 2,
              canvasSize: size,
              layers: [
                Layer(
                  id: const LayerId('paper'),
                  name: 'Paper',
                  frames: [frame('p1', '1')],
                  mark: const LayerMark(process: LayerProcess.paper),
                ),
                Layer(
                  id: const LayerId('a'),
                  name: 'A',
                  frames: [frame('a1', '1'), frame('a2', '2')],
                  mark: key,
                ),
                Layer(
                  id: const LayerId('b'),
                  name: 'B',
                  frames: [frame('b1', '1')],
                  mark: key,
                ),
                Layer(
                  id: const LayerId('inst'),
                  name: 'Camera',
                  frames: const [],
                  kind: LayerKind.instruction,
                  instructions: {
                    0: const InstructionEvent(
                      instructionId: 'pan',
                      length: 2,
                      text: 'PAN',
                    ),
                  },
                ),
                createCameraLayer(cutId: cutId),
              ],
            ),
          ],
        ),
      ],
    ),
  );

  /// One pixel of [colour] at ([x], [y]) on an empty canvas.
  BitmapSurface dot((int, int, int, int) colour, int x, int y) {
    final pixels = Uint8List(8 * 8 * 4);
    final i = (y * 8 + x) * 4;
    pixels[i] = colour.$1;
    pixels[i + 1] = colour.$2;
    pixels[i + 2] = colour.$3;
    pixels[i + 3] = colour.$4;
    return BitmapSurface(
      canvasSize: size,
      tileSize: 8,
      tiles: {TileCoord(x: 0, y: 0): BitmapTile(size: 8, pixels: pixels)},
    );
  }

  /// A black dot at (1, 1) on every cel, the paper's at (5, 5).
  void draw(EditorSessionManager session) {
    final cut = session.cutById(cutId)!;
    final store = session.renderCaches.brushFrameStore;
    void put(String row, String cel, BitmapSurface pixels) =>
        store.storeBakedSurface(
          session.brushFrameKeyForCut(cut, LayerId(row), FrameId(cel)),
          pixels,
        );
    put('a', 'a1', dot(black, 1, 1));
    put('a', 'a2', dot(black, 1, 1));
    put('b', 'b1', dot(black, 1, 1));
    put('paper', 'p1', dot(black, 5, 5));
  }

  Future<ExportDialogState> pumpAeScript(
    WidgetTester tester,
    EditorSessionManager session,
    Directory into,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1400, 660));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    addTearDown(() => tester.pumpWidget(const SizedBox.shrink()));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ExportDialog(
            session: session,
            exportDirectoryPicker: () async => into.path,
            formatAvailability: ExportFormatAvailability.permissive(),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.tap(
      find.byKey(const ValueKey<String>('export-tab-aeScript')),
    );
    await tester.pump();
    return tester.state<ExportDialogState>(find.byType(ExportDialog));
  }

  /// The alpha of the written [png] at ([x], [y]).
  Future<int> alphaOf(File png, int x, int y) async {
    final codec = await ui.instantiateImageCodec(png.readAsBytesSync());
    final image = (await codec.getNextFrame()).image;
    final bytes = (await image.toByteData(
      format: ui.ImageByteFormat.rawRgba,
    ))!;
    image.dispose();
    return bytes.getUint8((y * 8 + x) * 4 + 3);
  }

  testWidgets('🎯the run writes the picked cels and the script that lays '
      'them out, named after the cut', (tester) async {
    final temp = Directory.systemTemp.createTempSync('qa-ae-script');
    deleteAfterSessionEnds(temp);
    final session = film();
    addTearDown(session.dispose);
    draw(session);

    final state = await pumpAeScript(tester, session, temp);
    await tester.runAsync(state.export);
    await tester.pump();

    expect(filesWrittenUnder(temp), [
      'A1.png',
      'A2.png',
      'B1.png',
      'CUT1.jsx',
    ]);
    final script = File('${temp.path}/CUT1.jsx').readAsStringSync();
    for (final cel in ['A1.png', 'A2.png', 'B1.png']) {
      expect(script, contains('footage("$cel")'));
    }
    expect(script, contains('comp("CUT1 canvas", 8, 8, 2, bin)'));
    expect(script, contains('comp("CUT1", 32, 18, 2, bin)'));
    session.playbackRig.prerenderScheduler.cancel();
  });

  testWidgets('a cel is the drawing alone — no paper under it, its ground '
      'open', (tester) async {
    final temp = Directory.systemTemp.createTempSync('qa-ae-script-paper');
    deleteAfterSessionEnds(temp);
    final session = film();
    addTearDown(session.dispose);
    draw(session);
    // The Cels tab lays its paper; the AE Script tab does not ask.
    expect(const CelsExportSpec().applyPaper, isTrue);

    final state = await pumpAeScript(tester, session, temp);
    await tester.runAsync(state.export);
    await tester.pump();

    final cel = File('${temp.path}/A1.png');
    final (dotAlpha, paperAlpha, groundAlpha) = await tester.runAsync(
      () async => (
        await alphaOf(cel, 1, 1),
        await alphaOf(cel, 5, 5),
        await alphaOf(cel, 3, 3),
      ),
    ) ?? (0, 0, 0);
    expect(dotAlpha, 255);
    expect(paperAlpha, 0, reason: 'the paper was laid into the cel');
    expect(groundAlpha, 0);
    session.playbackRig.prerenderScheduler.cancel();
  });

  testWidgets('the tab offers the Cels list\'s picking without what a '
      'delivery cel adds', (tester) async {
    final temp = Directory.systemTemp.createTempSync('qa-ae-script-rules');
    deleteAfterSessionEnds(temp);
    final session = film();
    addTearDown(session.dispose);

    await pumpAeScript(tester, session, temp);

    Finder byKey(String key) => find.byKey(ValueKey<String>(key));
    expect(byKey('export-cels-kind-cel'), findsOneWidget);
    expect(byKey('export-cels-kind-art'), findsOneWidget);
    expect(byKey('export-cels-kind-conte'), findsOneWidget);
    for (final absent in [
      'export-cels-kind-direction',
      'export-cels-kind-timesheet',
      'export-cels-kind-envelope',
      'export-cels-apply-paper',
      'export-cels-cam',
    ]) {
      expect(byKey(absent), findsNothing, reason: absent);
    }
    session.playbackRig.prerenderScheduler.cancel();
  });

  testWidgets('its picking is its own: a kind turned off here leaves the '
      'Cels tab\'s', (tester) async {
    final temp = Directory.systemTemp.createTempSync('qa-ae-script-own');
    deleteAfterSessionEnds(temp);
    final session = film();
    addTearDown(session.dispose);

    final state = await pumpAeScript(tester, session, temp);
    await tester.tap(
      find.byKey(const ValueKey<String>('export-cels-kind-art')),
    );
    await tester.pump();

    expect(
      state.debugSpecs.aeScript.cels.kinds,
      {ExportCelKind.cel},
    );
    expect(
      state.debugSpecs.cels.kinds,
      const CelsExportSpec().kinds,
      reason: 'the AE Script tab wrote the Cels tab\'s picking',
    );
    session.playbackRig.prerenderScheduler.cancel();
  });

  testWidgets('🎯a cut that sounds is heard in AE as the app plays it: its '
      'mix a WAV by the cut\'s name, as long as its comps, laid in its '
      'camera comp', (tester) async {
    final temp = Directory.systemTemp.createTempSync('qa-ae-script-sound');
    deleteAfterSessionEnds(temp);
    // ae-script-export-Q4 「넣는다 — 앱이 놓은 그대로 WAV 로」: a sound on the
    // track from the cut's second frame, its PCM a steady half.
    final store = AudioConformStore(
      resolveConformPath: (_) => null,
      runner: (request) async => ConformResult(
        outcome: ConformOutcome.built,
        samples: Float32List(request.projectSampleRate)..fillRange(
          0,
          request.projectSampleRate,
          0.5,
        ),
        channels: 1,
        sampleRate: request.projectSampleRate,
        frames: request.projectSampleRate,
      ),
      log: (_) {},
    );
    final session = film(
      sounds: store,
      seLayers: [
        Layer(
          id: const LayerId('se'),
          name: 'S1',
          kind: LayerKind.se,
          frames: [frame('se1', '1')],
          timeline: {
            1: const TimelineExposure.drawing(FrameId('se1'), length: 1),
          },
          audioClips: [
            AudioClip(filePath: 'voice.wav', frameId: const FrameId('se1')),
          ],
        ),
      ],
    );
    addTearDown(session.dispose);
    draw(session);

    final state = await pumpAeScript(tester, session, temp);
    await tester.runAsync(state.export);
    await tester.pump();

    expect(filesWrittenUnder(temp), contains('CUT1.wav'));
    final wav = readWrittenWav(
      File('${temp.path}/CUT1.wav').readAsBytesSync(),
    );
    // Two frames at 24 — the comps' length — at the store's rate.
    final perFrame = wav.sampleRate ~/ 24;
    expect(wav.length, perFrame * 2);
    double at(int sample) => wav.samples[sample * wav.channels];
    expect(at(perFrame ~/ 2), 0, reason: 'nothing sounds on frame 0');
    expect(at(perFrame + perFrame ~/ 2), isNot(0), reason: 'frame 1 sounds');
    final script = File('${temp.path}/CUT1.jsx').readAsStringSync();
    expect(script, contains('footage("CUT1.wav")'));
    session.playbackRig.prerenderScheduler.cancel();
  });
}
