import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart'
    show Builder, MaterialApp, Scaffold, Text, TextButton, ValueKey;
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/attached_layer_resolve.dart'
    show attachedMirrorCelId;
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/project_background.dart';
import 'package:anicel/src/services/diagnostics/memory_black_box.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/menu/project_open_door.dart';
import 'package:anicel/src/ui/open_projects.dart';
import 'package:anicel/src/ui/session/clip_import_door.dart';

import '../../helpers/opened_session.dart';
import '../../helpers/temp_dir.dart';
import '../../helpers/wait_window.dart';
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

  /// A `ResizableImageInfo` that doubles a picture across.
  Uint8List doubledAcross() {
    final data = ByteData(184)
      ..setFloat64(40, 2)
      ..setFloat64(48, 1);
    return data.buffer.asUint8List();
  }

  /// A file: BG under an animation folder A whose cel 「1」 is a folder of
  /// two layers and whose cel 「2」 is one — on two timelines, the first
  /// keying 1 then 2, the second 2 alone; a shooting frame 200 × 100.
  ///
  /// [troubled] puts three more layers on top that cannot all be drawn: a
  /// grey one, a dropped picture its transform doubles, and one whose
  /// blocks the file does not hold.
  ///
  /// [strokes] puts a vector layer 「lines」 on top instead, moved to (30, 40)
  /// and beside its strokes a render whose blocks the file does not hold, as
  /// the one sample with vectors keeps. Its strokes ([_Strokes.held]): one 0
  /// … 40 across at its row 10, six across, and one record of a kind not
  /// drawn.
  ///
  /// [papered] puts a paper 0x204060 under BG.
  ///
  /// [masked] gives BG a mask that is on, standing 5 across from BG's
  /// top-left: it hides all it covers, and past its edges shows all — its
  /// blocks held, or not in the file.
  String writeClip({
    bool troubled = false,
    _Strokes? strokes,
    bool papered = false,
    _Masked? masked,
  }) {
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
      externalId(5): square(0, 2, (9, 9, 9)),
      externalId(6): blockRecordsBytes({0: null}),
      externalId(20): [
        ...vectorStrokeBytes([(0, 10, 1), (40, 10, 1)], radius: 3),
        ...vectorStrokeBytes([(0, 0, 1)], flags: 2),
      ],
      externalId(30): blockRecordsBytes({0: Uint8List(256 * 256)}),
      // Timeline one, A: 「1」 at tick 0, 「2」 at tick 12 (frame 6 — two
      // ticks a frame at 30 fps), to tick 24 (frame 12). BG throughout.
      externalId(10): trackDataBytes(
        cmtDocumentBytes(
          clipTrackSpec([
            clipNodeSpec(
              time: [0, 24],
              motion: [0, 24],
              keys: [0, 12],
              cels: ['1', '2'],
            ),
          ]),
        ),
      ),
      externalId(11): trackDataBytes(
        cmtDocumentBytes(
          clipTrackSpec([clipNodeSpec(time: [0, 24], motion: [0, 24])]),
        ),
      ),
      // Timeline two, A: 「2」 alone over its six frames.
      externalId(12): trackDataBytes(
        cmtDocumentBytes(
          clipTrackSpec([
            clipNodeSpec(
              time: [0, 12],
              motion: [0, 12],
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
      // The layer chained on top of A, if any.
      final onTopOfA = troubled
          ? 8
          : strokes != null
          ? 11
          : 0;
      // id, name, type, folder, composite, uuid, x, y, child, next,
      // render, animation.
      // The root's bottom layer.
      final bottom = papered ? 12 : 2;
      for (final row in <List<Object?>>[
        [1, '', 256, 1, 0, '', 0, 0, bottom, 0, 0, 0],
        if (papered) [12, 'paper', 1584, 0, 0, '', 0, 0, 0, 2, 0, 0],
        [2, 'BG', 1, 0, 0, uuidBg, 120, 50, 0, 3, 100, 0],
        [3, 'A', 0, 1, 2, uuidA, 0, 0, 4, onTopOfA, 0, 1],
        [4, '1', 0, 1, 0, '', 0, 0, 5, 7, 0, 0],
        [5, 'under', 1, 0, 0, '', 0, 0, 0, 6, 101, 0],
        [6, 'top', 1, 0, 0, '', 0, 0, 0, 0, 102, 0],
        [7, '2', 1, 0, 0, '', 20, 30, 0, 0, 103, 0],
        if (troubled) ...[
          [8, 'grey', 1, 0, 0, '', 0, 0, 0, 9, 105, 0],
          [10, 'lost', 1, 0, 0, '', 0, 0, 0, 0, 106, 0],
        ],
        if (strokes != null) [11, 'lines', 1, 0, 0, '', 30, 40, 0, 0, 107, 0],
      ]) {
        layer.execute(row);
      }
      layer.close();
      if (papered) {
        db.execute(
          'UPDATE Layer SET DrawColorMainRed = ?, DrawColorMainGreen = ?, '
          'DrawColorMainBlue = ? WHERE MainId = 12',
          [0x20202020, 0x40404040, 0x60606060],
        );
      }
      if (masked != null) {
        db
          ..execute('ALTER TABLE Layer ADD COLUMN LayerLayerMaskMipmap INTEGER')
          ..execute('ALTER TABLE Layer ADD COLUMN LayerMaskOffsetX INTEGER')
          ..execute(
            'UPDATE Layer SET LayerVisibility = 3, LayerLayerMaskMipmap = 108, '
            'LayerMaskOffsetX = 5 WHERE MainId = 2',
          )
          ..execute('''
            INSERT INTO Mipmap(MainId, BaseMipmapInfo) VALUES (108, 208);
            INSERT INTO MipmapInfo(MainId, ThisScale, Offscreen, NextIndex)
              VALUES (208, 100, 308, 0);
          ''')
          ..execute(
            'INSERT INTO Offscreen(MainId, Attribute, BlockData) '
            'VALUES (308, ?, ?)',
            [
              offscreenAttributeBytes(
                width: 64,
                height: 64,
                columns: 1,
                rows: 1,
                colourChannels: 0,
                fill: 1,
              ),
              externalId(masked == _Masked.held ? 30 : 96),
            ],
          );
      }
      if (strokes != null) {
        db.execute('''
          INSERT INTO Mipmap(MainId, BaseMipmapInfo) VALUES (107, 207);
          INSERT INTO MipmapInfo(MainId, ThisScale, Offscreen, NextIndex)
            VALUES (207, 100, 307, 0);
        ''');
        db.execute(
          'INSERT INTO Offscreen(MainId, Attribute, BlockData) '
          'VALUES (307, ?, ?)',
          [attribute, externalId(98)],
        );
        if (strokes == _Strokes.none) {
          // A vector layer by its render type alone: no stroke at all.
          db.execute(
            'UPDATE Layer SET DrawToRenderOffscreenType = 10 '
            'WHERE MainId = 11',
          );
        } else {
          db.execute(
            'INSERT INTO VectorObjectList(MainId, CanvasId, LayerId, '
            'VectorData) VALUES (1, 1, 11, ?)',
            [
              Uint8List.fromList(
                externalId(strokes == _Strokes.lost ? 97 : 20).codeUnits,
              ),
            ],
          );
        }
      }
      if (troubled) {
        db
          ..execute(
            'INSERT INTO Layer(MainId, LayerName, LayerType, LayerFolder, '
            'LayerVisibility, LayerOpacity, LayerComposite, LayerOffsetX, '
            'LayerOffsetY, LayerNextIndex, ResizableOriginalMipmap, '
            'ResizableImageInfo, DrawToRenderOffscreenType) '
            "VALUES (9, 'scan', 0, 0, 1, 256, 0, 0, 0, 10, 104, ?, 20)",
            [doubledAcross()],
          )
          ..execute('''
            INSERT INTO Mipmap(MainId, BaseMipmapInfo) VALUES
              (104, 204), (105, 205), (106, 206);
            INSERT INTO MipmapInfo(MainId, ThisScale, Offscreen, NextIndex)
              VALUES (204, 100, 304, 0), (205, 100, 305, 0),
              (206, 100, 306, 0);
          ''');
        final offscreens = db.prepare(
          'INSERT INTO Offscreen(MainId, Attribute, BlockData) '
          'VALUES (?, ?, ?)',
        );
        offscreens
          ..execute([304, attribute, externalId(5)])
          ..execute([
            305,
            offscreenAttributeBytes(
              width: 64,
              height: 64,
              columns: 1,
              rows: 1,
              colourChannels: 0,
            ),
            externalId(6),
          ])
          // Blocks the file does not hold.
          ..execute([306, attribute, externalId(99)])
          ..close();
      }
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
          (40, 41, 'one', 30.0, 0, 12, 50),
          (41, 0, 'two', 30.0, 0, 6, 52);
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
    final read = await readClipProject(clipPath: writeClip());
    expect(read, isNotNull, reason: 'the file reads');
    final session = EditorSessionManager(initialProject: read!.project);
    addTearDown(session.dispose);
    final progress = <double>[];
    final warnings = await session.clipDoor.bake(
      read,
      onProgress: progress.add,
    );

    expect(
      [for (final warning in warnings) warning.key],
      ['clipCelLayers'],
      reason: '🚨every picture DECODED — a seek that lands anywhere else '
          'arrives as a warning, not a throw',
    );
    expect(progress, [0.25, 0.5, 0.75, 1.0], reason: 'four pictures');
    expect(
      session.projectFile.hasUnsavedChanges,
      isTrue,
      reason: 'a conversion is unsaved — nothing on disk holds it',
    );
    expect(session.projectFile.path, isNull);
    final project = session.repository.requireProject();
    expect(project.name, 'scene');
    expect(project.fps, 30);
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
    final a1 = row(one, 'A-1');
    final bg = row(one, 'BG');

    expect(inked(session, one, base.id, cel1), 6 * 6, reason: 'top');
    expect(inked(session, one, base.id, cel2), 8 * 8, reason: 'cel 2');
    expect(
      inked(session, one, a1.id, attachedMirrorCelId(a1.id, cel1)),
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

  testWidgets('🚨the open window\'s Cancel stops the bake after the picture in '
      'hand, and no tab opens — card clip-import-hangs-on-three-samples: it '
      'went grey and the window stood until the import ended', (tester) async {
    final path = writeClip();
    MemoryBlackBox.reset();
    final projects = OpenProjects(
      first: createDefaultProject(),
      openSession: (project) => EditorSessionManager(initialProject: project),
      letGo: (session) => session.dispose(),
    );
    addTearDown(projects.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => ProjectOpenDoor(projects).open(context, (
                path: path,
                folderBookmark: null,
                placed: false,
              )),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    final told = watchTheBar(tester);

    await tester.tap(find.text('open'));
    await tester.pump();
    // A local file has no wait to stop, so the first to hear it is the bake.
    await tester.tap(find.byKey(const ValueKey<String>('app-progress-cancel')));
    await pumpPastTheWaitWindow(tester);

    expect(told, [0.25], reason: 'one picture of four, then the stop');
    expect(
      projects.sessions,
      hasLength(1),
      reason: 'the session the bake filled was in no tab, and was dropped',
    );
    expect(
      find.byKey(const ValueKey<String>('clip-import-warnings-notice')),
      findsNothing,
      reason: 'a stop says nothing',
    );
    expect(
      MemoryBlackBox.unfinishedEntry(),
      isNull,
      reason: 'a stop is not a kill',
    );

    for (final session in projects.sessions) {
      session.playbackRig.prerenderScheduler.cancel();
    }
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

    // BG stands at (120, 50): its 10 × 10 square of ink, 120 … 129 across,
    // reaches over the first tile's edge at 128 into the second column, and
    // stays in the first row.
    final bg = cut.layers.singleWhere((layer) => layer.name == 'BG');
    final bgSurface = session.renderCaches.brushFrameStore.bakedSurfaceOrNull(
      session.brushFrameKeyForCut(cut, bg.id, bg.frames.single.id),
    )!;
    expect(
      {for (final coord in bgSurface.tiles.keys) (coord.x, coord.y)},
      {(0, 0), (1, 0)},
    );

    // Cel 「2」 stands at (20, 30): its 8 × 8 square covers 20 … 27, 30 … 37,
    // inside the first tile.
    final tile = surface.tiles.values.single;
    int alphaAt(int x, int y) => tile.pixels[(y * 128 + x) * 4 + 3];
    expect(alphaAt(20, 30), 255);
    expect(alphaAt(27, 37), 255);
    expect(alphaAt(19, 30), 0);
    expect(alphaAt(28, 38), 0);
  });

  test('what cannot be drawn is said by name — a grey layer, a picture its '
      'transform doubles, blocks the file does not hold', () async {
    final opened = await openedClip(writeClip(troubled: true));
    final session = opened!.session;
    addTearDown(session.dispose);

    expect(
      [
        for (final warning in opened.warnings)
          (warning.key, warning.values['name'] ?? warning.values['file']),
      ],
      unorderedEquals([
        ('clipCelLayers', 'A'),
        ('clipNotColour', 'grey'),
        ('clipTransform', 'scan'),
        ('celUnreadable', 'lost'),
      ]),
    );
    final cut = session.repository.requireProject().tracks.single.cuts.first;
    final scan = cut.layers.singleWhere((layer) => layer.name == 'scan');
    expect(
      inked(session, cut, scan.id, scan.frames.single.id),
      2 * 2,
      reason: 'the doubled picture still lands, at its move',
    );
  });

  test('🎯a layer\'s mask that is on is baked into its picture where the '
      'mask stands — and nothing said (보드 the-clip-import-leaves-masks-and-'
      'locks-unsaid)', () async {
    final opened = await openedClip(writeClip(masked: _Masked.held));
    final session = opened!.session;
    addTearDown(session.dispose);

    expect([for (final warning in opened.warnings) warning.key], [
      'clipCelLayers',
    ]);
    final cut = session.repository.requireProject().tracks.single.cuts.first;
    final bg = cut.layers.singleWhere((layer) => layer.name == 'BG');
    expect(
      inked(session, cut, bg.id, bg.frames.single.id),
      5 * 10,
      reason: 'its square 120 … 129 across, the mask over 125 … — five '
          'columns left of it',
    );
  });

  test('a mask whose blocks the file does not hold is said, and the picture '
      'comes in whole', () async {
    final opened = await openedClip(writeClip(masked: _Masked.lost));
    final session = opened!.session;
    addTearDown(session.dispose);

    expect(
      [
        for (final warning in opened.warnings)
          (warning.key, warning.values['name']),
      ],
      unorderedEquals([
        ('clipCelLayers', 'A'),
        ('layerMaskNotApplied', 'BG'),
      ]),
    );
    final cut = session.repository.requireProject().tracks.single.cuts.first;
    final bg = cut.layers.singleWhere((layer) => layer.name == 'BG');
    expect(inked(session, cut, bg.id, bg.frames.single.id), 10 * 10);
  });

  test('F-370: the paper under every row opens as the project\'s '
      'paper', () async {
    final opened = await openedClip(writeClip(papered: true));
    final session = opened!.session;
    addTearDown(session.dispose);

    expect(
      session.repository.requireProject().background,
      const ProjectBackground.color(0xFF204060),
    );
  });

  test('F-370-Q2: a file with no paper opens with none — its sheet open, '
      'as CLIP STUDIO shows it', () async {
    final opened = await openedClip(writeClip());
    final session = opened!.session;
    addTearDown(session.dispose);

    final paper = session.repository.requireProject().background;
    expect(paper.none, isTrue);
    expect(paper.paintedArgb, 0x00000000, reason: 'nothing paints for it');
  });

  test('🎯a vector layer is drawn from its strokes, where its offset puts '
      'them — the render it keeps without blocks is not refused for it '
      '(6-1 item 8: 「벡터 레이어는 래스터로 그려 넣는다」)', () async {
    final opened = await openedClip(writeClip(strokes: _Strokes.held));
    final session = opened!.session;
    addTearDown(session.dispose);

    expect(
      [
        for (final warning in opened.warnings)
          (warning.key, warning.values['name'] ?? warning.values['file']),
      ],
      unorderedEquals([
        ('clipCelLayers', 'A'),
        ('clipVector', 'lines'),
        ('clipVectorUnread', 'lines'),
      ]),
      reason: 'drawn with a round pen is said, and the record it does not '
          'draw; 「could not be read」 is not',
    );
    final cut = session.repository.requireProject().tracks.single.cuts.first;
    final lines = cut.layers.singleWhere((layer) => layer.name == 'lines');
    final surface = session.renderCaches.brushFrameStore.bakedSurfaceOrNull(
      session.brushFrameKeyForCut(cut, lines.id, lines.frames.single.id),
    )!;
    final tile = surface.tiles.values.single;
    int alphaAt(int x, int y) => tile.pixels[(y * 128 + x) * 4 + 3];
    // Stored 0 … 40 across at row 10, moved by (30, 40): 30 … 70 at row 50.
    expect(alphaAt(50, 49), closeTo(255, 1));
    expect(alphaAt(50, 45), 0, reason: 'six across, not more');
    expect(alphaAt(20, 9), 0, reason: 'not where it is stored');
  });

  test('strokes the file does not hold are said by name, and the layer '
      'stays, empty', () async {
    final opened = await openedClip(writeClip(strokes: _Strokes.lost));
    final session = opened!.session;
    addTearDown(session.dispose);

    expect(
      [
        for (final warning in opened.warnings)
          (warning.key, warning.values['name'] ?? warning.values['file']),
      ],
      unorderedEquals([
        ('clipCelLayers', 'A'),
        ('clipVector', 'lines'),
        ('celUnreadable', 'lines'),
      ]),
    );
    final cut = session.repository.requireProject().tracks.single.cuts.first;
    final lines = cut.layers.singleWhere((layer) => layer.name == 'lines');
    expect(inked(session, cut, lines.id, lines.frames.single.id), 0);
  });

  test('a vector layer with no stroke is an empty picture — not one 「that '
      'could not be read」 for the render it keeps without blocks', () async {
    final opened = await openedClip(writeClip(strokes: _Strokes.none));
    final session = opened!.session;
    addTearDown(session.dispose);

    expect(
      [
        for (final warning in opened.warnings)
          (warning.key, warning.values['name'] ?? warning.values['file']),
      ],
      unorderedEquals([('clipCelLayers', 'A'), ('clipVector', 'lines')]),
    );
    final cut = session.repository.requireProject().tracks.single.cuts.first;
    final lines = cut.layers.singleWhere((layer) => layer.name == 'lines');
    expect(inked(session, cut, lines.id, lines.frames.single.id), 0);
  });

  test('🎯a sound the file holds comes in CARRIED — on the track\'s SE row, '
      'its bytes the project\'s, the copy taken out gone, nothing to undo '
      '(유저 10-09: 「소리도 가져오게 못하나? 단일파일안에있을거아냐」)', () async {
    const uuidVoice = '99990000-aaaa-bbbb-cccc-ddddeeeeffff';
    const object = 'aaaa1111-2222-3333-4444-555566667777';
    const bank = 'bbbb1111-2222-3333-4444-555566667777';
    final mp3 = [0x49, 0x44, 0x33, 4, 0, 0, 0, 0, 0, 0, 1, 2, 3];
    final database = clipDatabaseBytes(temp, (db) {
      db
        ..execute(clipSchema)
        ..execute('ALTER TABLE Layer ADD COLUMN AudioLayer INTEGER')
        ..execute('ALTER TABLE Layer ADD COLUMN FirstLayerObject INTEGER')
        ..execute(
          'CREATE TABLE LayerObject(_PW_ID INTEGER PRIMARY KEY, '
          'MainId INTEGER, LayerId INTEGER, ObjectUuid TEXT, '
          'BankItemUuid TEXT, ObjectName TEXT, ObjectNext INTEGER)',
        )
        ..execute(
          'CREATE TABLE CanvasItem(_PW_ID INTEGER PRIMARY KEY, '
          'MainId INTEGER, ItemUuid TEXT, ItemType TEXT, '
          'ItemFileExtension TEXT, ItemBinaryMainIndex INTEGER)',
        )
        ..execute(
          'CREATE TABLE CanvasItemBinary(_PW_ID INTEGER PRIMARY KEY, '
          'MainId INTEGER, ItemBinaryData TEXT)',
        )
        ..execute(
          'INSERT INTO Canvas(MainId, CanvasWidth, CanvasHeight, '
          'CanvasRootFolder) VALUES (1, 64, 32, 1)',
        )
        ..execute(
          'INSERT INTO Layer(MainId, LayerName, LayerType, LayerFolder, '
          "LayerFirstChildIndex) VALUES (1, '', 256, 1, 2)",
        )
        ..execute(
          'INSERT INTO Layer(MainId, LayerName, LayerType, LayerFolder, '
          'LayerVisibility, LayerUuid, AudioLayer, FirstLayerObject) '
          "VALUES (2, 'voice', 8720, 0, 1, '$uuidVoice', 1, 10)",
        )
        ..execute(
          'INSERT INTO LayerObject(MainId, LayerId, ObjectUuid, '
          'BankItemUuid, ObjectName, ObjectNext) '
          "VALUES (10, 2, '$object', '$bank', 'take.mp3', 0)",
        )
        ..execute(
          'INSERT INTO CanvasItem(MainId, ItemUuid, ItemType, '
          'ItemFileExtension, ItemBinaryMainIndex) '
          "VALUES (20, '$bank', 'Audio', 'mp3', 30)",
        )
        ..execute(
          'INSERT INTO CanvasItemBinary(MainId, ItemBinaryData) '
          "VALUES (30, '${externalId(5)}')",
        )
        ..execute('''
          INSERT INTO AnimationCutBank(MainId, FirstTimeLine, CurrentIndex)
            VALUES (1, 40, 0);
          INSERT INTO TimeLine(MainId, NextTimeLine, TimeLineName, FrameRate,
            StartFrame, EndFrame, FirstTrack) VALUES
            (40, 0, 'one', 24.0, 0, 48, 50);
        ''');
      final track = db.prepare(
        'INSERT INTO Track(MainId, TrackNextIndex, TrackKind, '
        'LayerUuidWithTrack, TrackActionMixer2) VALUES (?, ?, ?, ?, ?)',
      );
      track
        ..execute([50, 0, 4001, clipUuidBytes(uuidVoice), externalId(6)])
        ..close();
    });
    final path = '${temp.path}${Platform.pathSeparator}voiced.clip';
    File(path).writeAsBytesSync(
      clipFileBytes(
        database: database,
        externals: {
          externalId(5): mp3,
          // The sound from the clip's head, its own speed, at its level.
          externalId(6): trackDataBytes(
            cmtDocumentBytes(
              clipTrackSpec([
                CmtSpec(
                  'ActionNodeClip',
                  'null',
                  children: [
                    ...clipNodeSpec(time: [0, 120], motion: [0, 120]).children,
                    const CmtSpec(
                      'AnimInfo',
                      'null',
                      children: [
                        CmtSpec(
                          'Param',
                          'Int32',
                          value: 3,
                          attributes: {'Name': 'AudioPlayer', 'Tag': object},
                        ),
                        CmtSpec(
                          'Param',
                          'Double',
                          value: 100,
                          attributes: {'Name': 'AudioVolume'},
                        ),
                      ],
                    ),
                  ],
                ),
              ]),
            ),
          ),
        },
      ),
    );

    final opened = await openedClip(path);
    final session = opened!.session;
    addTearDown(session.dispose);

    final project = session.repository.requireProject();
    // A track keeps two SE rows at least; the sound's is the one it plays on.
    final row = project.tracks.single.seLayers.singleWhere(
      (layer) => layer.audioClips.isNotEmpty,
    );
    final clip = row.audioClips.single;
    expect(clip.filePath, endsWith('/take.mp3'), reason: 'called as it was');
    expect((clip.offsetFrames, clip.gain), (0, 1.0));
    final asset = session.mediaPool.mediaAssets.singleWhere(
      (asset) => asset.path == clip.filePath,
    );
    expect(asset.carriedAs, isNotNull, reason: 'carried, as a recording is');
    expect(session.projectFile.projectHoldsMediaBytes(clip.filePath), isTrue);
    expect(
      File(clip.filePath).existsSync(),
      isFalse,
      reason: 'the copy taken out goes once the project holds its bytes',
    );
    expect(session.historyManager.canUndo, isFalse, reason: 'not an edit');
    expect(
      [for (final warning in opened.warnings) warning.key],
      isNot(contains('clipSound')),
    );
  });

  test('🎯a 2D camera folder\'s move is its folder\'s transform — its keys '
      'where the pan needs them — and the cut\'s camera the frame it shoots, '
      'still (유저 10-13: 「카메라폴더는 그냥 폴더에 트랜스폼 움직이는걸로 … '
      '이름은 카메라폴더 이름 그대로」)', () async {
    const uuidCamera = '22223333-4444-5555-6666-777788889999';
    // At rest on the shooting frame: the frame's own size, its centre
    // (100, 50) placed on the frame's centre (320, 180).
    final rest = ByteData(184)
      ..setFloat64(40, 1)
      ..setFloat64(48, 1)
      ..setFloat64(64, 320)
      ..setFloat64(72, 180)
      ..setFloat64(80, 100)
      ..setFloat64(88, 50);
    final database = clipDatabaseBytes(temp, (db) {
      db
        ..execute(clipSchema)
        ..execute(
          'ALTER TABLE Layer ADD COLUMN Camera2DResizableImageInfo BLOB',
        )
        ..execute(
          'INSERT INTO Canvas(MainId, CanvasWidth, CanvasHeight, '
          'CanvasRootFolder, CropFrameInnerWidth, CropFrameInnerHeight, '
          'CropFrameCropOffsetX, CropFrameCropOffsetY, '
          'CropFrameInnerOffsetX, CropFrameInnerOffsetY) '
          'VALUES (1, 640, 360, 1, 200, 100, 0, 0, 0, 0)',
        )
        ..execute(
          'INSERT INTO Layer(MainId, LayerName, LayerType, LayerFolder, '
          "LayerFirstChildIndex) VALUES (1, '', 256, 1, 2)",
        )
        ..execute('''
          INSERT INTO AnimationCutBank(MainId, FirstTimeLine, CurrentIndex)
            VALUES (1, 40, 0);
          INSERT INTO TimeLine(MainId, NextTimeLine, TimeLineName, FrameRate,
            StartFrame, EndFrame, FirstTrack) VALUES
            (40, 0, 'one', 24.0, 0, 12, 50);
        ''');
      db.prepare(
          'INSERT INTO Layer(MainId, LayerName, LayerType, LayerFolder, '
          'LayerVisibility, LayerUuid, LayerFirstChildIndex, '
          'Camera2DResizableImageInfo) VALUES (?, ?, ?, ?, ?, ?, ?, ?)',
        )
        ..execute([
          2,
          'camera',
          512,
          1,
          1,
          uuidCamera,
          0,
          rest.buffer.asUint8List(),
        ])
        ..close();
      db.prepare(
          'INSERT INTO Track(MainId, TrackNextIndex, TrackKind, '
          'LayerUuidWithTrack, TrackActionMixer2) VALUES (?, ?, ?, ?, ?)',
        )
        ..execute([50, 0, 2005, clipUuidBytes(uuidCamera), externalId(6)])
        ..close();
    });
    final path = '${temp.path}${Platform.pathSeparator}panned.clip';
    File(path).writeAsBytesSync(
      clipFileBytes(
        database: database,
        externals: {
          // Ticks at 60 a second on 24 fps: the clip is frames 0 … 12, and
          // tick 27.5 frame 11. Across from x 100 to 210; the rest held.
          externalId(6): trackDataBytes(
            cmtDocumentBytes(
              clipTrackSpec([
                const CmtSpec(
                  'ActionNodeClip',
                  'null',
                  children: [
                    CmtSpec(
                      'TimeClip',
                      'null',
                      children: [
                        CmtSpec('Start', 'Double', value: 0),
                        CmtSpec('End', 'Double', value: 30),
                        CmtSpec('Rate', 'Double', value: 60),
                      ],
                    ),
                    CmtSpec(
                      'MotionClip',
                      'null',
                      children: [
                        CmtSpec('Start', 'Double', value: 0),
                        CmtSpec('End', 'Double', value: 30),
                      ],
                    ),
                    CmtSpec(
                      'AnimInfo',
                      'null',
                      children: [
                        CmtSpec(
                          'FCurve',
                          'null',
                          attributes: {'Type': 'ImagePosition', 'Axis': 'X'},
                          children: [
                            CmtSpec('Frame', 'Double[]', value: [0, 27.5]),
                            CmtSpec('Value', 'Double[]', value: [100, 210]),
                          ],
                        ),
                      ],
                    ),
                  ],
                ),
              ]),
            ),
          ),
        },
      ),
    );

    final opened = await openedClip(path);
    final session = opened!.session;
    addTearDown(session.dispose);

    final project = session.repository.requireProject();
    expect(
      (project.cameraSize.width, project.cameraSize.height),
      (200, 100),
      reason: 'the frame it shoots is the project\'s camera',
    );
    final cut = project.tracks.single.cuts.single;
    expect(
      [
        for (final MapEntry(key: frame, value: pose)
            in cut.camera.keyframes.entries)
          (frame, pose.center),
      ],
      [(0, CanvasPoint(x: 320, y: 180))],
      reason: 'CLIP STUDIO\'s own camera does not move',
    );
    final folder = cut.layers.singleWhere((layer) => layer.name == 'camera');
    expect(folder.kind, LayerKind.folder);
    final transform = folder.transformTrack;
    expect(
      {
        for (final MapEntry(key: frame, value: key)
            in transform.anchorPoint.keys.entries)
          frame: key.value,
      },
      {0: CanvasPoint(x: 100, y: 180), 11: CanvasPoint(x: 210, y: 180)},
      reason: 'a pan: its ends, on the point the camera stands at',
    );
    expect(
      transform.position.keys.values.single.value,
      CanvasPoint(x: 320, y: 180),
      reason: 'the frame\'s point its pivot is',
    );
  });

  test('a file that is not a CLIP STUDIO file is not one', () async {
    final path = '${temp.path}${Platform.pathSeparator}not.clip';
    File(path).writeAsStringSync('nothing in particular');

    expect(await openedClip(path), isNull);
  });
}

/// What the vector layer of [writeClip] holds: its strokes, strokes the file
/// does not hold, or none at all.
enum _Strokes { held, lost, none }

/// Whether the file of [writeClip] holds the blocks of BG's mask.
enum _Masked { held, lost }
