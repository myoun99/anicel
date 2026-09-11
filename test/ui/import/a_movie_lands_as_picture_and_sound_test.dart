// A MOVIE LANDS (미디어 배치 라운드 6): as cels when it bakes — one per movie
// frame on the SOUND's clock, a frame the clock shows twice held — or as ONE
// reference cel over its span when it does not; on a picture row's frames it
// always bakes; and its sound lands on the SE rows with it, same start, same
// span, one undo for the pair — or alone, on an SE row's cell.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/media_asset.dart';
import 'package:anicel/src/services/import/import_layer_spot.dart';
import 'package:anicel/src/services/media/video_decode_worker.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/import/import_file_settings.dart';

import '../../helpers/fake_video_backend.dart';
import '../../helpers/placed_sound_conform.dart';

void main() {
  late Directory tempDir;
  late String moviePath;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('anicel-movie-lands');
    moviePath = '${tempDir.path}${Platform.pathSeparator}take3.mov';
    await File(moviePath).writeAsBytes(const [0, 0, 0, 24]);
  });

  tearDown(() async {
    debugVideoDecodeBackend = null;
    try {
      await tempDir.delete(recursive: true);
    } on Object {
      // Windows keeps handles briefly; leftovers live in systemTemp.
    }
  });

  /// A session whose conform answers every file as a second of sound — the
  /// movie's soundtrack, without the isolate a widget test cannot run.
  EditorSessionManager session() {
    final s = EditorSessionManager(
      initialProject: createDefaultProject(),
      audioConformStore: soundConformStore(),
    );
    addTearDown(s.dispose);
    return s;
  }

  Layer movieRow(EditorSessionManager s) => s.requireActiveCut.layers
      .firstWhere((layer) => layer.name == 'take3.mov');

  Future<bool> place(
    WidgetTester tester,
    EditorSessionManager s, {
    bool rasterize = false,
    bool withSound = false,
    int inFrame = 0,
    int? outFrame,
    ImportLayerSpot? spot,
  }) async => (await tester.runAsync(
    () => s.importDoors.importVideoFile(
      path: moviePath,
      settings: ImportFileSettings(
        mode: ImportFileMode.reference,
        bake: rasterize,
        sound: withSound,
        inFrame: inFrame,
        outFrame: outFrame,
      ),
      spot: spot,
    ),
  ))!;

  testWidgets('baked: a cel per movie frame on the sound\'s clock — a 12 fps '
      'take in a 24 fps project holds each frame for two', (tester) async {
    final fake = FakeVideoBackend(frameCount: 12, fpsNumerator: 12);
    debugVideoDecodeBackend = fake;
    final s = session();

    expect(await place(tester, s, rasterize: true), isTrue);

    final layer = movieRow(s);
    expect(layer.mediaReference, isNull, reason: 'baked means drawn cels');
    expect(layer.frames, hasLength(12));
    expect([for (final exposure in layer.timeline.values) exposure.length], [
      for (var i = 0; i < 12; i += 1) 2,
    ]);
    expect(s.layerStack.celHasContentForLayer(layer, 0), isTrue);
    expect(fake.asked, [
      for (var i = 0; i < 12; i += 1) i,
    ], reason: 'each movie frame read once, in order');
    final asset = s.mediaPool.mediaAssets.single;
    expect((asset.kind, asset.frameCount), (MediaAssetKind.video, 12));
    await tester.pumpAndSettle();
  });

  testWidgets('kept as a reference: ONE cel over its span, pointing at the '
      'file from the IN point — with no pixels of its own', (
    tester,
  ) async {
    final fake = FakeVideoBackend(frameCount: 24);
    debugVideoDecodeBackend = fake;
    final s = session();

    expect(await place(tester, s, inFrame: 4, outFrame: 9), isTrue);

    final layer = movieRow(s);
    expect(layer.kind, LayerKind.animation);
    expect(layer.frames, hasLength(1));
    expect(layer.timeline.keys, [0]);
    expect(layer.timeline[0]!.length, 6, reason: 'IN 4 through OUT 9');
    expect(layer.mediaReference?.assetPath, normalizedMediaPath(moviePath));
    expect(layer.mediaReference?.frameOffset, 4);
    expect(
      s.brushSurfaceForLayerFrame(layer, layer.frames.single),
      isNull,
      reason:
          'a reference keeps no pixels — its pictures are decoded where '
          'they are shown',
    );
    expect(
      fake.asked.every((frame) => frame >= 4 && frame <= 9),
      isTrue,
      reason: 'whatever is shown or warmed lies inside IN 4 … OUT 9',
    );
    await tester.pumpAndSettle();
  });

  testWidgets('let go on a picture row\'s frames it always bakes, from the '
      'cell it was let go on — the row stays a drawing row', (tester) async {
    final fake = FakeVideoBackend(frameCount: 3);
    debugVideoDecodeBackend = fake;
    final s = session();
    final row = s.requireActiveCut.layers.firstWhere(
      (layer) => s.acceptsPlacedFrames(layer.id),
    );

    expect(
      await place(
        tester,
        s,
        spot: RowFramesSpot(layerId: row.id, frameIndex: 2),
      ),
      isTrue,
    );

    final after = s.requireActiveCut.layers.firstWhere((l) => l.id == row.id);
    expect(after.mediaReference, isNull);
    expect(after.timeline.keys, containsAll(<int>[2, 3, 4]));
    expect(fake.asked, [0, 1, 2]);
    await tester.pumpAndSettle();
  });

  testWidgets('its sound lands with it — same start, same span, the file\'s '
      'name as the dialogue — and ONE undo takes both', (tester) async {
    debugVideoDecodeBackend = FakeVideoBackend(frameCount: 24);
    final s = session();
    final start = s.activeCutGlobalStartFrame;
    final layersBefore = s.requireActiveCut.layers.length;

    expect(await place(tester, s, withSound: true, inFrame: 3), isTrue);

    expect(movieRow(s).timeline[0]!.length, 21);
    final se = s.activeTrack.seLayers.firstWhere(
      (layer) => layer.timeline[start] != null,
    );
    final block = se.timeline[start]!;
    expect(block.length, 21, reason: 'the picture\'s span');
    final frame = se.frameById(block.frameId!)!;
    expect((frame.name, frame.seName), ('take3.mov', 'SE'));
    final clip = se.audioClips.single;
    expect(clip.filePath, normalizedMediaPath(moviePath));
    expect(clip.offsetFrames, 3, reason: 'the sound starts at IN too');
    expect(
      s.mediaPool.mediaAssets,
      hasLength(1),
      reason: 'one entry for the pair',
    );

    s.undo();
    expect(s.requireActiveCut.layers, hasLength(layersBefore));
    expect(
      s.activeTrack.seLayers.every((layer) => layer.timeline[start] == null),
      isTrue,
    );
    await tester.pumpAndSettle();
  });

  testWidgets('let go on an SE row\'s cell a movie is its sound alone, and '
      'the pool keeps ONE entry — the movie, not a sound', (tester) async {
    final s = session();
    final seRow = s.activeTrack.seLayers.first;

    final ok = await tester.runAsync(
      () => s.importDoors.importSoundFile(
        path: moviePath,
        copyIntoProject: false,
        spot: SeCellSpot(layerId: seRow.id, frameIndex: 0),
      ),
    );

    expect(ok, isTrue);
    expect(s.mediaPool.mediaAssets.single.kind, MediaAssetKind.video);
    expect(
      s.requireActiveCut.layers.where((layer) => layer.name == 'take3.mov'),
      isEmpty,
      reason: 'an SE row holds sound only — no picture came with it',
    );
    await tester.pumpAndSettle();
  });
}
