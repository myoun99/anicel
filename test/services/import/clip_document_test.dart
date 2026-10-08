import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:anicel/src/services/import/clip_container.dart';
import 'package:anicel/src/services/import/clip_document.dart';

import '../../helpers/temp_dir.dart';
import 'clip_test_builder.dart';

/// The structure of a CLIP STUDIO PAINT file read out of its embedded
/// database (card `csp-clip-import-analysis`) — against a database written
/// here with the tables and columns the format notes name, some of them
/// left out the way the program leaves out the ones it does not use.
void main() {
  late Directory folder;
  setUp(() => folder = Directory.systemTemp.createTempSync('qa_clip_doc_'));
  tearDown(() => deleteTempQuietly(folder));

  Uint8List databaseBytes(void Function(Database db) build) =>
      clipDatabaseBytes(folder, build);

  String write(Uint8List database, Map<String, List<int>> externals) {
    final path = '${folder.path}/cut.clip';
    File(path).writeAsBytesSync(
      clipFileBytes(database: database, externals: externals),
    );
    return path;
  }

  const uuidA = '0f1e2d3c-4b5a-6978-8796-a5b4c3d2e1f0';
  const uuidBg = '11112222-3333-4444-5555-666677778888';

  /// [track]'s clips as nested lists — a record holding a list compares
  /// that list by identity, so the pieces are spelled out for `equals`.
  List<Object> shape(ClipTrack track) => [
    for (final piece in track.pieces) [piece.span, piece.cels],
  ];

  String fixture() {
    final attribute50 = offscreenAttributeBytes(
      width: 128,
      height: 128,
      columns: 1,
      rows: 1,
    );
    final attribute100 = offscreenAttributeBytes(
      width: 256,
      height: 256,
      columns: 1,
      rows: 1,
    );
    final externals = <String, List<int>>{
      externalId(1): blockRecordsBytes({0: null}),
      externalId(2): blockRecordsBytes({0: null}),
      // Timeline 1, A: keys 0 · 30 · 60 ticks = frames 0 · 12 · 24.
      externalId(10): trackDataBytes(
        cmtDocumentBytes(
          clipTrackSpec([
            clipNodeSpec(
              time: [0, 120],
              motion: [0, 120],
              keys: [0, 30, 60],
              cels: ['1', '2', '1'],
            ),
          ]),
        ),
      ),
      // The same track in single precision with other keys — the double
      // document is the one to read.
      externalId(11): trackDataBytes(
        cmtDocumentBytes(
          clipTrackSpec([
            clipNodeSpec(
              time: [0, 120],
              motion: [0, 120],
              keys: [0],
              cels: ['2'],
            ),
          ]),
          doubles: false,
        ),
      ),
      // Timeline 2, A: a clip moved to tick 25 — its motion starts at −25.
      externalId(12): trackDataBytes(
        cmtDocumentBytes(
          clipTrackSpec([
            // Its keys written out of order: a clip's cels come in order
            // of frame however the file lists them.
            clipNodeSpec(
              time: [25, 60],
              motion: [-25, 10],
              keys: [5, -25],
              cels: ['1', '2'],
            ),
          ]),
        ),
      ),
      // Timeline 2, BG: only the single-precision document, shown 0 … 24.
      externalId(13): trackDataBytes(
        cmtDocumentBytes(
          clipTrackSpec([clipNodeSpec(time: [0, 60], motion: [0, 60])]),
          doubles: false,
        ),
      ),
      // Timeline 3, A: a clip stretched to twice its motion — 60 ticks of
      // keys over 120 of timeline, so a key at tick 30 lands on frame 24 —
      // and, written FIRST, a second clip after a gap.
      externalId(14): trackDataBytes(
        cmtDocumentBytes(
          clipTrackSpec([
            clipNodeSpec(
              time: [150, 180],
              motion: [0, 30],
              keys: [0],
              cels: ['2'],
            ),
            clipNodeSpec(
              time: [0, 120],
              motion: [0, 60],
              keys: [0, 30],
              cels: ['1', '2'],
            ),
          ]),
        ),
      ),
    };
    final database = databaseBytes((db) {
      db.execute(clipSchema);
      db.execute(
        'INSERT INTO Canvas(MainId, CanvasWidth, CanvasHeight, '
        'CanvasRootFolder) VALUES (1, 1919.6, 1080.4, 1)',
      );
      final layer = db.prepare(
        'INSERT INTO Layer(MainId, LayerName, LayerType, LayerFolder, '
        'LayerVisibility, LayerOpacity, LayerComposite, LayerUuid, '
        'LayerOffsetX, LayerOffsetY, LayerRenderOffscrOffsetX, '
        'LayerRenderOffscrOffsetY, LayerFirstChildIndex, LayerNextIndex, '
        'LayerRenderMipmap, ResizableOriginalMipmap, ResizableImageInfo, '
        'DrawToRenderOffscreenType, AnimationFolder) '
        'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
      );
      void row(
        int id,
        String name, {
        int type = 1,
        int folder = 0,
        int visibility = 1,
        int opacity = 256,
        int composite = 0,
        String uuid = '',
        int x = 0,
        int y = 0,
        int renderX = 0,
        int renderY = 0,
        int firstChild = 0,
        int next = 0,
        int render = 0,
        int original = 0,
        int animation = 0,
      }) {
        // A dropped picture carries its transform and draws to its original.
        final placed = original != 0;
        final transform = placed ? Uint8List(184) : null;
        final drawTo = placed ? 20 : 0;
        layer.execute([
          id, name, type, folder, visibility, opacity, composite, uuid, x, y,
          renderX, renderY, firstChild, next, render, original, transform,
          drawTo, animation,
        ]);
      }
      // The root: paper · BG · A, bottom to top.
      row(1, '', type: 256, folder: 1, firstChild: 2);
      row(2, 'paper', type: 1584, next: 3);
      row(3, 'BG', uuid: uuidBg, x: 10, y: -4, renderX: 5, renderY: 20,
          render: 100, next: 4);
      row(4, 'A', type: 0, folder: 17, composite: 2, opacity: 230,
          uuid: uuidA, firstChild: 5, animation: 1);
      // A's cels: 「1」 a single layer, 「2」 a folder of two.
      row(5, '1', visibility: 0, next: 6);
      row(6, '2', type: 0, folder: 1, firstChild: 7, next: 9);
      row(7, 'lower', next: 8);
      row(8, 'upper');
      row(9, 'scan', type: 0, original: 101);
      layer.close();
      db.execute('''
        INSERT INTO Mipmap(MainId, BaseMipmapInfo)
          VALUES (100, 200), (101, 210);
        INSERT INTO MipmapInfo(MainId, ThisScale, Offscreen, NextIndex) VALUES
          (200, 50, 300, 201), (201, 100, 301, 0), (210, 100, 302, 0);
      ''');
      final offscreen = db.prepare(
        'INSERT INTO Offscreen(MainId, Attribute, BlockData) VALUES (?, ?, ?)',
      );
      offscreen
        ..execute([300, attribute50, externalId(9)])
        ..execute([301, attribute100, externalId(1)])
        ..execute([302, attribute100, externalId(2)])
        ..close();
      db.execute('''
        INSERT INTO AnimationCutBank(MainId, FirstTimeLine, CurrentIndex)
          VALUES (1, 40, 1);
        INSERT INTO TimeLine(MainId, NextTimeLine, TimeLineName, FrameRate,
          StartFrame, EndFrame, FirstTrack) VALUES
          (40, 41, 'cut 1', 24.0, 0, 48, 50),
          (41, 42, 'cut 2', 24.0, 0, 24, 52),
          (42, 0, 'cut 3', 24.0, 0, 48, 54);
        INSERT INTO TimeLineLabel(MainId, LabelFrame, LabelType,
          LabelNextIndex) VALUES (70, 6, 1, 71), (71, 20, 2, 0);
      ''');
      final track = db.prepare(
        'INSERT INTO Track(MainId, TrackNextIndex, TrackKind, '
        'LayerUuidWithTrack, TrackActionMixer, TrackActionMixer2, '
        'TrackLabelFirstIndex) VALUES (?, ?, ?, ?, ?, ?, ?)',
      );
      final a = clipUuidBytes(uuidA);
      final bg = clipUuidBytes(uuidBg);
      track
        ..execute([50, 0, 2000, a, externalId(11), externalId(10), 70])
        ..execute([52, 53, 2000, a, '', externalId(12), 0])
        ..execute([53, 0, 2001, bg, externalId(13), '', 0])
        ..execute([54, 0, 2000, a, '', externalId(14), 0])
        ..close();
    });
    return write(database, externals);
  }

  test('the canvas, and the layer tree bottom to top with what each is', () {
    final document = readClipDocument(fixture(), scratch: folder);
    final root = document.root;
    final a = root.children[2];

    expect((document.width, document.height), (1920, 1080));
    expect(document.frame, isNull, reason: 'no shooting frame: shot whole');
    expect(root.kind, ClipLayerKind.root);
    expect([for (final layer in root.children) layer.name], [
      'paper',
      'BG',
      'A',
    ]);
    expect(root.children[0].kind, ClipLayerKind.paper);
    expect(root.children[1].kind, ClipLayerKind.raster);
    expect(a.kind, ClipLayerKind.folder);
    expect(a.isAnimationFolder, isTrue);
    expect(a.isCollapsed, isTrue, reason: 'bit 16 of LayerFolder');
    expect((a.opacity, a.composite), (230, 2));
    expect(a.uuid, uuidA.replaceAll('-', ''));
    expect([for (final cel in a.children) cel.name], ['1', '2', 'scan']);
    expect(a.children[0].isShown, isFalse);
    expect(a.children[1].isFolder, isTrue);
    expect(a.children[1].isCollapsed, isFalse, reason: 'LayerFolder 1: open');
    expect(root.children[1].isShown, isTrue);
    expect(a.children[1].isAnimationFolder, isFalse);
    expect(
      [for (final layer in a.children[1].children) layer.name],
      ['lower', 'upper'],
    );
    expect(a.children[2].kind, ClipLayerKind.picture);
  });

  test('a picture stands where its two offsets add up to, read at 100%', () {
    final document = readClipDocument(fixture(), scratch: folder);
    final bg = document.root.children[1];
    final scan = document.root.children[2].children[2];

    expect((bg.left, bg.top), (15, 16));
    expect(
      (bg.offsetX, bg.offsetY),
      (10, -4),
      reason: 'the layer\'s own offset, apart — what a dropped picture is '
          'placed from',
    );
    expect(bg.render!.blocksId, externalId(1), reason: 'not the 50% level');
    expect(bg.render!.attribute, isNotEmpty);
    expect(scan.render, isNull);
    expect(scan.original!.blocksId, externalId(2));
    expect(scan.originalTransform, hasLength(184));
  });

  test('every timeline in its chain, each layer\'s track by its uuid', () {
    final document = readClipDocument(fixture(), scratch: folder);
    final [first, second, third] = document.timelines;
    final key = uuidA.replaceAll('-', '');
    expect(
      shape(third.tracks[key]!),
      [
        [
          (start: 0, end: 48),
          [(frame: 0, cel: '1'), (frame: 24, cel: '2')],
        ],
        [
          (start: 60, end: 72),
          [(frame: 60, cel: '2')],
        ],
      ],
      reason: 'a stretched clip spreads its keys by the stretch; each clip '
          'keeps its own keys, and the clips come in order of frame',
    );

    expect(document.currentTimeline, 1);
    expect((first.name, first.fps, first.start, first.end), (
      'cut 1',
      24.0,
      0,
      48,
    ));
    expect(first.tracks[key]!.kind, 2000);
    expect(
      shape(first.tracks[key]!),
      [
        [
          (start: 0, end: 48),
          [(frame: 0, cel: '1'), (frame: 12, cel: '2'), (frame: 24, cel: '1')],
        ],
      ],
      reason: 'the double document — the single one keys 「2」 alone',
    );
    expect(first.tracks[key]!.labels, [6], reason: 'a breakdown only');
    expect(second.name, 'cut 2');
    expect(
      shape(second.tracks[key]!),
      [
        [
          (start: 10, end: 24),
          [(frame: 10, cel: '2'), (frame: 22, cel: '1')],
        ],
      ],
      reason: 'a moved clip: its keys count from its motion\'s start',
    );
    final bg = second.tracks[uuidBg.replaceAll('-', '')]!;
    expect(bg.kind, 2001);
    expect(shape(bg), [
      [(start: 0, end: 24), isEmpty],
    ]);
    expect(document.warnings, isEmpty);
  });

  test('the shooting frame: its size, and its centre the canvas\'s moved by '
      'the crop\'s offset and the inner frame\'s', () {
    final database = databaseBytes((db) {
      db
        ..execute(clipSchema)
        ..execute(
          'INSERT INTO Canvas(MainId, CanvasWidth, CanvasHeight, '
          'CanvasRootFolder, CropFrameInnerWidth, CropFrameInnerHeight, '
          'CropFrameCropOffsetX, CropFrameCropOffsetY, '
          'CropFrameInnerOffsetX, CropFrameInnerOffsetY) '
          'VALUES (1, 1754, 2236, 1, 1500, 846, 10, -498, -4, 73)',
        )
        ..execute(
          'INSERT INTO Layer(MainId, LayerName, LayerType, LayerFolder) '
          "VALUES (1, '', 256, 1)",
        );
    });

    final document = readClipDocument(
      write(database, const {}),
      scratch: folder,
    );

    expect(document.frame, (
      width: 1500,
      height: 846,
      centerX: 877.0 + 10 - 4,
      centerY: 1118.0 - 498 + 73,
    ));
  });

  test('a file whose database holds no canvas is refused', () {
    final database = databaseBytes(
      (db) => db.execute('CREATE TABLE Unrelated(a INTEGER)'),
    );
    expect(
      () => readClipDocument(write(database, const {}), scratch: folder),
      throwsA(isA<ClipFormatException>()),
    );
  });

  test('the copy of the database it read from is gone afterwards', () {
    readClipDocument(fixture(), scratch: folder);
    expect(
      folder.listSync().where((entry) => entry.path.endsWith('.db')),
      isEmpty,
    );
  });
}
