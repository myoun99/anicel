import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/attached_layer_resolve.dart'
    show attachedMirrorCelId;
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/session/clip_import_door.dart';

import '../../helpers/opened_session.dart';
import '../../helpers/temp_dir.dart';
import '../../services/import/clip_test_builder.dart';

/// A CLIP STUDIO file opens AS A PROJECT (card `csp-clip-import-analysis`)
/// — read, planned, born as a session, and every picture baked into it.
///
/// The file is built here, database and blocks, the way the format notes
/// lay it out: the samples are work files and stay out of the repository.
/// The CLIP STUDIO door itself — named so `tool/mutation_run.dart` has a
/// suite to run for it.
ClipImportDoor clipDoorOf(EditorSessionManager session) => session.clipDoor;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory temp;
  setUp(() => temp = Directory.systemTemp.createTempSync('qa_clip_session_'));
  tearDown(() => deleteTempQuietly(temp));

  const uuidA = '0f1e2d3c-4b5a-6978-8796-a5b4c3d2e1f0';
  const uuidBg = '11112222-3333-4444-5555-666677778888';

  /// A picture 64 × 64 whose square [from] … [to] (both ways) is [colour],
  /// opaque; the rest is clear.
  Uint8List square(int from, int to, (int, int, int) colour) =>
      blockRecordsBytes({
        0: colourBlock((x, y) {
          final inside = x >= from && x < to && y >= from && y < to;
          return inside ? (colour.$1, colour.$2, colour.$3, 255) : (0, 0, 0, 0);
        }),
      });

  /// A file: BG under an animation folder A whose cel 「1」 is a folder of
  /// two layers and whose cel 「2」 is one — on two timelines, the first
  /// keying 1 then 2, the second 2 alone; a shooting frame 200 × 100.
  String writeClip() {
    final attribute = offscreenAttributeBytes(
      width: 64,
      height: 64,
      columns: 1,
      rows: 1,
    );
    final externals = <String, List<int>>{
      externalId(1): square(0, 10, (200, 0, 0)),
      externalId(2): square(0, 4, (0, 0, 200)),
      externalId(3): square(0, 6, (0, 200, 0)),
      externalId(4): square(0, 8, (200, 200, 200)),
      // Timeline one, A: 「1」 at tick 0, 「2」 at tick 15 (frame 6), to
      // tick 30 (frame 12). BG throughout.
      externalId(10): trackDataBytes(
        cmtDocumentBytes(
          clipTrackSpec([
            clipNodeSpec(
              time: [0, 30],
              motion: [0, 30],
              keys: [0, 15],
              cels: ['1', '2'],
            ),
          ]),
        ),
      ),
      externalId(11): trackDataBytes(
        cmtDocumentBytes(
          clipTrackSpec([clipNodeSpec(time: [0, 30], motion: [0, 30])]),
        ),
      ),
      // Timeline two, A: 「2」 alone over its six frames.
      externalId(12): trackDataBytes(
        cmtDocumentBytes(
          clipTrackSpec([
            clipNodeSpec(
              time: [0, 15],
              motion: [0, 15],
              keys: [0],
              cels: ['2'],
            ),
          ]),
        ),
      ),
    };
    final database = clipDatabaseBytes(temp, (db) {
      db
        ..execute(clipSchema)
        ..execute(
          'INSERT INTO Canvas(MainId, CanvasWidth, CanvasHeight, '
          'CanvasRootFolder, CropFrameInnerWidth, CropFrameInnerHeight, '
          'CropFrameCropOffsetX, CropFrameCropOffsetY, '
          'CropFrameInnerOffsetX, CropFrameInnerOffsetY) '
          'VALUES (1, 300, 200, 1, 200, 100, 10, -5, 0, 0)',
        );
      final layer = db.prepare(
        'INSERT INTO Layer(MainId, LayerName, LayerType, LayerFolder, '
        'LayerVisibility, LayerOpacity, LayerComposite, LayerUuid, '
        'LayerOffsetX, LayerOffsetY, LayerFirstChildIndex, LayerNextIndex, '
        'LayerRenderMipmap, AnimationFolder) '
        'VALUES (?, ?, ?, ?, 1, 256, ?, ?, ?, ?, ?, ?, ?, ?)',
      );
      // id, name, type, folder, composite, uuid, x, y, child, next,
      // render, animation.
      for (final row in <List<Object?>>[
        [1, '', 256, 1, 0, '', 0, 0, 2, 0, 0, 0],
        [2, 'BG', 1, 0, 0, uuidBg, 100, 50, 0, 3, 100, 0],
        [3, 'A', 0, 1, 2, uuidA, 0, 0, 4, 0, 0, 1],
        [4, '1', 0, 1, 0, '', 0, 0, 5, 7, 0, 0],
        [5, 'under', 1, 0, 0, '', 0, 0, 0, 6, 101, 0],
        [6, 'top', 1, 0, 0, '', 0, 0, 0, 0, 102, 0],
        [7, '2', 1, 0, 0, '', 20, 30, 0, 0, 103, 0],
      ]) {
        layer.execute(row);
      }
      layer.close();
      db.execute('''
        INSERT INTO Mipmap(MainId, BaseMipmapInfo) VALUES
          (100, 200), (101, 201), (102, 202), (103, 203);
        INSERT INTO MipmapInfo(MainId, ThisScale, Offscreen, NextIndex) VALUES
          (200, 100, 300, 0), (201, 100, 301, 0), (202, 100, 302, 0),
          (203, 100, 303, 0);
        INSERT INTO AnimationCutBank(MainId, FirstTimeLine, CurrentIndex)
          VALUES (1, 40, 0);
        INSERT INTO TimeLine(MainId, NextTimeLine, TimeLineName, FrameRate,
          StartFrame, EndFrame, FirstTrack) VALUES
          (40, 41, 'one', 24.0, 0, 12, 50),
          (41, 0, 'two', 24.0, 0, 6, 52);
      ''');
      final offscreen = db.prepare(
        'INSERT INTO Offscreen(MainId, Attribute, BlockData) VALUES (?, ?, ?)',
      );
      for (var i = 0; i < 4; i += 1) {
        offscreen.execute([300 + i, attribute, externalId(1 + i)]);
      }
      offscreen.close();
      final track = db.prepare(
        'INSERT INTO Track(MainId, TrackNextIndex, TrackKind, '
        'LayerUuidWithTrack, TrackActionMixer2) VALUES (?, ?, ?, ?, ?)',
      );
      final a = clipUuidBytes(uuidA);
      final bg = clipUuidBytes(uuidBg);
      track
        ..execute([50, 51, 2000, a, externalId(10)])
        ..execute([51, 0, 2001, bg, externalId(11)])
        ..execute([52, 0, 2000, a, externalId(12)])
        ..close();
    });
    final path = '${temp.path}${Platform.pathSeparator}scene.clip';
    File(path).writeAsBytesSync(
      clipFileBytes(database: database, externals: externals),
    );
    return path;
  }

  /// How many pixels of [layerId]'s cel [frameId] in [cut] carry ink — 0
  /// when nothing was baked there.
  int inked(
    EditorSessionManager session,
    Cut cut,
    LayerId layerId,
    FrameId frameId,
  ) {
    final surface = session.renderCaches.brushFrameStore.bakedSurfaceOrNull(
      session.brushFrameKeyForCut(cut, layerId, frameId),
    );
    if (surface == null) {
      return 0;
    }
    var count = 0;
    for (final tile in surface.tiles.values) {
      final bytes = tile.pixels;
      for (var p = 3; p < bytes.length; p += 4) {
        if (bytes[p] != 0) {
          count += 1;
        }
      }
    }
    return count;
  }

  test('🎯a .clip opens AS the project: every timeline a 겸용 cut, its rate, '
      'its shooting frame the camera, and every picture baked', () async {
    final opened = await openedClip(writeClip());
    expect(opened, isNotNull, reason: 'the file reads');
    final session = opened!.session;
    addTearDown(session.dispose);

    expect(
      [for (final warning in opened.warnings) warning.key],
      ['clipCelLayers'],
      reason: '🚨every picture DECODED — a seek that lands anywhere else '
          'arrives as a warning, not a throw',
    );
    final project = session.repository.requireProject();
    expect(project.name, 'scene');
    expect(project.fps, 24);
    expect(
      (project.cameraSize.width, project.cameraSize.height),
      (200, 100),
      reason: 'the shooting frame is the project\'s frame',
    );
    expect(session.canUndo, isFalse, reason: 'an open is not an edit');
    final [one, two] = project.tracks.single.cuts;
    expect((one.name, one.duration, two.name, two.duration), (
      'one',
      12,
      'two',
      6,
    ));
    for (final cut in [one, two]) {
      final pose = cut.camera.keyframeAt(0)!;
      expect(
        (pose.center.x, pose.center.y, pose.zoom),
        (150.0 + 10, 100.0 - 5, 1.0),
        reason: 'every cut\'s camera stands on the frame\'s centre',
      );
    }

    Layer row(Cut cut, String name, {LayerKind? kind}) =>
        cut.layers.singleWhere(
          (layer) => layer.name == name && (kind == null || layer.kind == kind),
        );
    final base = row(one, 'A', kind: LayerKind.animation);
    final cel1 = base.frames.firstWhere((cel) => cel.name == '1').id;
    final cel2 = base.frames.firstWhere((cel) => cel.name == '2').id;
    final a2 = row(one, 'A-2');
    final bg = row(one, 'BG');

    expect(inked(session, one, base.id, cel1), 6 * 6, reason: 'top');
    expect(inked(session, one, base.id, cel2), 8 * 8, reason: 'cel 2');
    expect(
      inked(session, one, a2.id, attachedMirrorCelId(a2.id, cel1)),
      4 * 4,
      reason: 'the layer under the top one, on the attach row',
    );
    expect(inked(session, one, bg.id, bg.frames.single.id), 10 * 10);
    expect(
      inked(session, two, row(two, 'A', kind: LayerKind.animation).id, cel2),
      8 * 8,
      reason: 'the second cut shows the same cel — one bank, linked',
    );
  });

  test('a picture lands where it stands on the canvas', () async {
    final opened = await openedClip(writeClip());
    final session = opened!.session;
    addTearDown(session.dispose);
    final cut = session.repository.requireProject().tracks.single.cuts.first;
    final base = cut.layers.singleWhere(
      (layer) => layer.name == 'A' && layer.kind == LayerKind.animation,
    );
    final cel2 = base.frames.firstWhere((cel) => cel.name == '2').id;
    final surface = session.renderCaches.brushFrameStore.bakedSurfaceOrNull(
      session.brushFrameKeyForCut(cut, base.id, cel2),
    )!;

    // Cel 「2」 stands at (20, 30): its 8 × 8 square covers 20 … 27, 30 … 37,
    // inside the first tile.
    final tile = surface.tiles.values.single;
    int alphaAt(int x, int y) => tile.pixels[(y * 128 + x) * 4 + 3];
    expect(alphaAt(20, 30), 255);
    expect(alphaAt(27, 37), 255);
    expect(alphaAt(19, 30), 0);
    expect(alphaAt(28, 38), 0);
  });

  test('a file that is not a CLIP STUDIO file is not one', () async {
    final path = '${temp.path}${Platform.pathSeparator}not.clip';
    File(path).writeAsStringSync('nothing in particular');

    expect(await openedClip(path), isNull);
  });
}
