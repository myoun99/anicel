import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:anicel/src/models/frame.dart' show InbetweenMark;
import 'package:anicel/src/services/import/clip_container.dart';
import 'package:anicel/src/services/import/clip_document.dart';
import 'package:anicel/src/services/import/clip_track_clip.dart';

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
          LabelNextIndex) VALUES (70, 6, 1, 71), (71, 20, 2, 72),
          (72, 30, 3, 0);
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
    expect(
      first.tracks[key]!.breakdownMarks,
      {6: InbetweenMark.one, 20: InbetweenMark.two},
      reason:
          '🗣️I-130-csp-import-Q1: LabelType 1 is the ○, 2 the ● — the '
          'third kind is no in-between',
    );
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
    expect(document.warnings, [
      '1 timeline label(s) of LabelType 3, which no in-between mark is, '
          'left out',
    ]);
  });

  test('a text layer is 800 — or 0 with its text\'s columns filled, as four '
      'in two samples were (10-09)', () {
    final database = databaseBytes((db) {
      db
        ..execute(clipSchema)
        ..execute('ALTER TABLE Layer ADD COLUMN TextLayerType INTEGER')
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
          "LayerNextIndex, TextLayerType) VALUES (2, 'words', 0, 0, 3, 1)",
        )
        ..execute(
          'INSERT INTO Layer(MainId, LayerName, LayerType, LayerFolder) '
          "VALUES (3, 'plain', 1, 0)",
        );
    });

    final document = readClipDocument(
      write(database, const {}),
      scratch: folder,
    );

    expect(
      [for (final layer in document.root.children) (layer.name, layer.kind)],
      [('words', ClipLayerKind.lettering), ('plain', ClipLayerKind.raster)],
    );
    expect(
      document.resolution,
      72,
      reason: 'a point a pixel where the file names no resolution',
    );
  });

  group('F-370-Q3: a text layer\'s texts', () {
    /// A file whose layer 2 is a text layer: [texts] its string and
    /// attributes, then its arrays'; layer 3 a raster beside it. Offscreen
    /// 300 is its declared render's, 301 its thumbnail, 302 · 303 name it
    /// alone and 304 names layer 3.
    String writeTexts(
      List<(String, Uint8List)> texts, {
      List<Uint8List>? settings,
    }) {
      final strings = [for (final (text, _) in texts) utf8.encode(text)];
      final attributes = settings ?? [for (final (_, set) in texts) set];
      final attribute = offscreenAttributeBytes(
        width: 8,
        height: 8,
        columns: 1,
        rows: 1,
      );
      final database = databaseBytes((db) {
        db.execute(clipSchema);
        for (final column in [
          'Layer ADD COLUMN TextLayerType INTEGER',
          'Layer ADD COLUMN TextLayerString BLOB',
          'Layer ADD COLUMN TextLayerAttributes BLOB',
          'Layer ADD COLUMN TextLayerStringArray BLOB',
          'Layer ADD COLUMN TextLayerAttributesArray BLOB',
          'Offscreen ADD COLUMN LayerId INTEGER',
          'Canvas ADD COLUMN CanvasResolution REAL',
        ]) {
          db.execute('ALTER TABLE $column');
        }
        db
          ..execute(
            'CREATE TABLE LayerThumbnail(_PW_ID INTEGER PRIMARY KEY, '
            'MainId INTEGER, ThumbnailOffscreen INTEGER)',
          )
          ..execute(
            'INSERT INTO Canvas(MainId, CanvasWidth, CanvasHeight, '
            'CanvasRootFolder, CanvasResolution) VALUES (1, 64, 32, 1, 350)',
          )
          ..execute(
            'INSERT INTO Layer(MainId, LayerName, LayerType, LayerFolder, '
            "LayerFirstChildIndex) VALUES (1, '', 256, 1, 2)",
          )
          ..execute(
            'INSERT INTO Layer(MainId, LayerName, LayerType, LayerFolder, '
            'LayerNextIndex, LayerRenderMipmap, TextLayerType, '
            'TextLayerString, TextLayerAttributes, TextLayerStringArray, '
            'TextLayerAttributesArray) '
            "VALUES (2, 'words', 800, 0, 3, 100, 2, ?, ?, ?, ?)",
            [
              strings.first,
              attributes.first,
              clipTextArrayBytes(strings.sublist(1)),
              clipTextArrayBytes(attributes.sublist(1)),
            ],
          )
          ..execute(
            'INSERT INTO Layer(MainId, LayerName, LayerType, LayerFolder) '
            "VALUES (3, 'plain', 1, 0)",
          )
          ..execute('''
            INSERT INTO Mipmap(MainId, BaseMipmapInfo) VALUES (100, 200);
            INSERT INTO MipmapInfo(MainId, ThisScale, Offscreen, NextIndex)
              VALUES (200, 100, 300, 0);
            INSERT INTO LayerThumbnail(MainId, ThumbnailOffscreen)
              VALUES (1, 301);
          ''');
        final offscreen = db.prepare(
          'INSERT INTO Offscreen(MainId, LayerId, Attribute, BlockData) '
          'VALUES (?, ?, ?, ?)',
        );
        for (final (id, layer) in [
          (303, 2),
          (300, 2),
          (304, 3),
          (302, 2),
          (301, 2),
        ]) {
          offscreen.execute([id, layer, attribute, externalId(id)]);
        }
        offscreen.close();
      });
      return write(database, const {});
    }

    test('🎯its string and attributes, then each of their arrays\' — its '
        'pictures the offscreens that name it ALONE, in their order — and '
        'the canvas\'s resolution the file\'s', () {
      final one = Uint8List.fromList([1, 0, 0, 0, 0, 0, 0, 0]);
      final two = Uint8List.fromList([2, 0, 0, 0, 0, 0, 0, 0]);
      final three = Uint8List.fromList([3, 0, 0, 0, 0, 0, 0, 0]);
      final document = readClipDocument(
        writeTexts([('one', one), ('二', two), ('three', three)]),
        scratch: folder,
      );

      final words = document.root.children.first;
      expect(words.kind, ClipLayerKind.lettering);
      expect([for (final text in words.texts) text.text], [
        'one',
        '二',
        'three',
      ]);
      expect([for (final text in words.texts) text.attributes], [
        one,
        two,
        three,
      ]);
      expect(
        [for (final picture in words.textPictures) picture.blocksId],
        [externalId(302), externalId(303)],
        reason: 'not its render\'s (300), its thumbnail (301), or another '
            'layer\'s (304)',
      );
      expect(document.root.children.last.texts, isEmpty);
      expect(document.resolution, 350);
      expect(document.warnings, isEmpty);
    });

    test('texts and settings that do not pair are said, and the pairs '
        'kept', () {
      final set = Uint8List.fromList([9, 0, 0, 0, 0, 0, 0, 0]);
      final document = readClipDocument(
        writeTexts([('a', set), ('b', set)], settings: [set]),
        scratch: folder,
      );

      final words = document.root.children.first;
      expect([for (final text in words.texts) text.text], ['a']);
      expect(document.warnings, [
        'text layer 2 holds 2 texts and 1 settings for them',
      ]);
    });
  });

  test('F-370: a layer\'s colour is its DrawColorMain… — each channel by its '
      'top byte — and a layer the file names none for has none', () {
    final database = databaseBytes((db) {
      db
        ..execute(clipSchema)
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
          'LayerNextIndex, DrawColorMainRed, DrawColorMainGreen, '
          "DrawColorMainBlue) VALUES (2, 'paper', 1584, 0, 3, ?, ?, ?)",
          // The bytes under the top one are not the colour's.
          [0x20202020, 0x40FFFFFF, 0x60000000],
        )
        ..execute(
          'INSERT INTO Layer(MainId, LayerName, LayerType, LayerFolder) '
          "VALUES (3, 'plain', 1, 0)",
        );
    });

    final document = readClipDocument(
      write(database, const {}),
      scratch: folder,
    );

    expect(
      [for (final layer in document.root.children) layer.mainColour],
      [0xFF204060, null],
    );
  });

  test('a layer\'s effects are on where its LayerEffectInfo turns one on or '
      'its layer colour is — a paper\'s colour is none — and LayerClip '
      'clips it', () {
    final database = databaseBytes((db) {
      db
        ..execute(clipSchema)
        ..execute('ALTER TABLE Layer ADD COLUMN LayerEffectInfo BLOB')
        ..execute('ALTER TABLE Layer ADD COLUMN DrawColorEnable INTEGER')
        ..execute('ALTER TABLE Layer ADD COLUMN LayerClip INTEGER')
        ..execute(
          'INSERT INTO Canvas(MainId, CanvasWidth, CanvasHeight, '
          'CanvasRootFolder) VALUES (1, 64, 32, 1)',
        )
        ..execute(
          'INSERT INTO Layer(MainId, LayerName, LayerType, LayerFolder, '
          "LayerFirstChildIndex) VALUES (1, '', 256, 1, 2)",
        );
      final layer = db.prepare(
        'INSERT INTO Layer(MainId, LayerName, LayerType, LayerFolder, '
        'LayerNextIndex, LayerEffectInfo, DrawColorEnable, LayerClip, '
        'DrawColorMainRed, DrawColorMainGreen, DrawColorMainBlue) '
        'VALUES (?, ?, ?, 0, ?, ?, ?, ?, ?, ?, ?)',
      );
      const red = [0xFFFFFFFF, 0, 0];
      layer
        ..execute([2, 'paper', 1584, 3, null, 1, null, ...red])
        ..execute([3, 'tinted', 1, 4, null, 1, null, ...red])
        // A colour once set and switched off again: the file keeps it.
        ..execute([4, 'untinted', 1, 5, null, null, null, ...red])
        ..execute([
          5, 'bordered', 1, 6,
          layerEffectInfoBytes(on: {'EffectEdge'}), null, null,
          null, null, null,
        ])
        ..execute([
          6, 'switched off', 1, 7, layerEffectInfoBytes(), null, null,
          null, null, null,
        ])
        ..execute([7, 'clipped', 1, 0, null, null, 1, null, null, null])
        ..close();
    });

    final document = readClipDocument(
      write(database, const {}),
      scratch: folder,
    );

    expect(
      [
        for (final layer in document.root.children)
          (layer.name, layer.effectsOn, layer.clipped),
      ],
      [
        ('paper', false, false),
        ('tinted', true, false),
        ('untinted', false, false),
        ('bordered', true, false),
        ('switched off', false, false),
        ('clipped', false, true),
      ],
    );
  });

  test('🎯a layer\'s mask is the one CLIP STUDIO applies — a '
      'LayerLayerMaskMipmap with LayerVisibility\'s bit 2 on, standing at '
      'LayerOffset + LayerMaskOffset + LayerMaskOffscrOffset (MoArt\'s '
      'reading); one switched off is none — and LayerLock locks it', () {
    final attribute = offscreenAttributeBytes(
      width: 4,
      height: 4,
      columns: 1,
      rows: 1,
      colourChannels: 0,
    );
    final database = databaseBytes((db) {
      db.execute(clipSchema);
      for (final column in [
        'LayerLayerMaskMipmap',
        'LayerMaskOffsetX',
        'LayerMaskOffsetY',
        'LayerMaskOffscrOffsetX',
        'LayerMaskOffscrOffsetY',
        'LayerLock',
      ]) {
        db.execute('ALTER TABLE Layer ADD COLUMN $column INTEGER');
      }
      db
        ..execute(
          'INSERT INTO Canvas(MainId, CanvasWidth, CanvasHeight, '
          'CanvasRootFolder) VALUES (1, 64, 32, 1)',
        )
        ..execute(
          'INSERT INTO Layer(MainId, LayerName, LayerType, LayerFolder, '
          "LayerFirstChildIndex) VALUES (1, '', 256, 1, 2)",
        );
      final layer = db.prepare(
        'INSERT INTO Layer(MainId, LayerName, LayerType, LayerFolder, '
        'LayerNextIndex, LayerVisibility, LayerOffsetX, LayerOffsetY, '
        'LayerLayerMaskMipmap, LayerMaskOffsetX, LayerMaskOffsetY, '
        'LayerMaskOffscrOffsetX, LayerMaskOffscrOffsetY, LayerLock) '
        'VALUES (?, ?, 1, 0, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
      );
      layer
        ..execute([2, 'masked', 3, 3, 10, 20, 100, 1, 2, 300, 400, 0])
        ..execute([3, 'mask off', 4, 1, 10, 20, 100, 1, 2, 300, 400, 0])
        ..execute([4, 'not held', 5, 2, 0, 0, 101, 0, 0, 0, 0, 0])
        ..execute([5, 'locked', 6, 1, 0, 0, 0, 0, 0, 0, 0, 16])
        ..execute([6, 'bare', 0, 3, 0, 0, 0, 0, 0, 0, 0, 0])
        ..close();
      db.execute('''
        INSERT INTO Mipmap(MainId, BaseMipmapInfo) VALUES (100, 200);
        INSERT INTO MipmapInfo(MainId, ThisScale, Offscreen, NextIndex)
          VALUES (200, 100, 300, 0);
      ''');
      db.prepare(
          'INSERT INTO Offscreen(MainId, Attribute, BlockData) '
          'VALUES (?, ?, ?)',
        )
        ..execute([300, attribute, externalId(1)])
        ..close();
    });

    final document = readClipDocument(
      write(database, const {}),
      scratch: folder,
    );
    final [masked, off, notHeld, _, bare] = document.root.children;

    expect((masked.mask?.left, masked.mask?.top), (311, 422));
    expect(masked.mask?.source?.attribute, attribute);
    expect(masked.mask?.source?.blocksId, externalId(1));
    expect(off.mask, isNull, reason: 'CLIP STUDIO does not apply it either');
    expect(notHeld.mask, isNotNull, reason: 'on, and said when it comes in');
    expect(notHeld.mask?.source, isNull);
    expect(bare.mask, isNull, reason: 'bit 2 with no mask names none');
    expect([for (final layer in document.root.children) layer.locked], [
      false,
      false,
      false,
      true,
      false,
    ]);
  });

  test('🎯a sound layer holds its sound — the chunk its file is in, its name '
      'and extension — and its track\'s clip says what plays from which '
      'second on which frame (memory `csp-clip-format-notes` §3)', () {
    const uuidVoice = '99990000-aaaa-bbbb-cccc-ddddeeeeffff';
    const object = 'AAAA1111-2222-3333-4444-555566667777';
    const bank = 'bbbb1111-2222-3333-4444-555566667777';
    final soundTrack = trackDataBytes(
      cmtDocumentBytes(
        clipTrackSpec([
          const CmtSpec(
            'ActionNodeClip',
            'null',
            children: [
              // Ticks at 60 a second: the clip is seconds 1 … 5, frames
              // 24 … 120 at 24 fps.
              CmtSpec(
                'TimeClip',
                'null',
                children: [
                  CmtSpec('Start', 'Double', value: 60),
                  CmtSpec('End', 'Double', value: 300),
                  CmtSpec('Rate', 'Double', value: 60),
                ],
              ),
              CmtSpec(
                'MotionClip',
                'null',
                children: [
                  CmtSpec('Start', 'Double', value: 60),
                  CmtSpec('End', 'Double', value: 300),
                ],
              ),
              CmtSpec(
                'AnimInfo',
                'null',
                children: [
                  CmtSpec(
                    'Param',
                    'Int32',
                    value: 7,
                    attributes: {'Name': 'AudioPlayer', 'Tag': object},
                  ),
                  CmtSpec(
                    'Param',
                    'Double',
                    value: 80,
                    attributes: {'Name': 'AudioVolume'},
                  ),
                  // Half a second in on the clip's first frame, two seconds
                  // over two seconds — its own speed.
                  CmtSpec(
                    'FCurve',
                    'null',
                    attributes: {'Type': 'PlayTime'},
                    children: [
                      CmtSpec('Frame', 'Double[]', value: [60, 180]),
                      CmtSpec('Value', 'Double[]', value: [0.5, 2.5]),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ]),
      ),
    );
    final database = databaseBytes((db) {
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
        ..execute(
          'INSERT INTO AnimationCutBank(MainId, FirstTimeLine, CurrentIndex) '
          'VALUES (1, 40, 0)',
        )
        ..execute(
          'INSERT INTO TimeLine(MainId, NextTimeLine, TimeLineName, '
          'FrameRate, StartFrame, EndFrame, FirstTrack) '
          "VALUES (40, 0, 'cut', 24.0, 0, 120, 50)",
        );
      final track = db.prepare(
        'INSERT INTO Track(MainId, TrackNextIndex, TrackKind, '
        'LayerUuidWithTrack, TrackActionMixer, TrackActionMixer2, '
        'TrackLabelFirstIndex) VALUES (?, ?, ?, ?, ?, ?, ?)',
      );
      track
        ..execute([50, 0, 4001, clipUuidBytes(uuidVoice), '', externalId(6), 0])
        ..close();
    });

    final document = readClipDocument(
      write(database, {
        externalId(5): [0x49, 0x44, 0x33, 4, 0, 0],
        externalId(6): soundTrack,
      }),
      scratch: folder,
    );

    final voice = document.root.children.single;
    expect(voice.kind, ClipLayerKind.sound);
    expect(voice.sounds, [
      (
        objectUuid: 'aaaa1111222233334444555566667777',
        binaryId: externalId(5),
        name: 'take.mp3',
        extension: 'mp3',
      ),
    ]);
    final track = document.timelines.single.tracks[uuidVoice.replaceAll(
      '-',
      '',
    )]!;
    expect(track.sounds, [
      (
        span: (start: 24, end: 120),
        player: 'aaaa1111222233334444555566667777',
        frame: 24,
        startSeconds: 0.5,
        speed: 1.0,
        volume: 0.8,
        volumeVaries: false,
      ),
    ]);
  });

  test('🎯every chain the file keeps is walked one way: a row it names that '
      'is not there is said, a chain that comes back on itself stops, and a '
      'layer two chains name is walked once — the second time said', () {
    final database = databaseBytes((db) {
      db
        ..execute(clipSchema)
        ..execute(
          'INSERT INTO Canvas(MainId, CanvasWidth, CanvasHeight, '
          'CanvasRootFolder) VALUES (1, 64, 32, 1)',
        )
        ..execute(
          'INSERT INTO AnimationCutBank(MainId, FirstTimeLine, CurrentIndex) '
          'VALUES (1, 40, 0)',
        )
        // Timeline 40, then 41, which is not there.
        ..execute(
          'INSERT INTO TimeLine(MainId, NextTimeLine, TimeLineName, '
          'FrameRate, StartFrame, EndFrame, FirstTrack) '
          "VALUES (40, 41, 'one', 24.0, 0, 12, 0)",
        );
      db.prepare(
          'INSERT INTO Layer(MainId, LayerName, LayerType, LayerFolder, '
          'LayerFirstChildIndex, LayerNextIndex) VALUES (?, ?, ?, ?, ?, ?)',
        )
        // The root's children: A, B, then A again.
        ..execute([1, '', 256, 1, 2, 0])
        ..execute([2, 'A', 0, 1, 4, 3])
        ..execute([3, 'B', 0, 1, 4, 2])
        // Both folders' first child is C, whose next is 9 — not there.
        ..execute([4, 'C', 1, 0, 0, 9])
        ..close();
    });

    final document = readClipDocument(write(database, {}), scratch: folder);

    expect(
      [
        for (final layer in document.root.children)
          [layer.name, for (final child in layer.children) child.name],
      ],
      [
        ['A', 'C'],
        ['B'],
      ],
      reason: 'the root\'s chain stops where it comes back to A',
    );
    expect([for (final timeline in document.timelines) timeline.name], [
      'one',
    ]);
    expect(document.warnings, [
      'a layer chain names layer 9, which is not there',
      'a layer chain names layer 4 a second time',
      'a layer chain names layer 9, which is not there',
      'the timeline chain names timeline 41, which is not there',
    ]);
  });

  const uuidCamera = '22223333-4444-5555-6666-777788889999';

  /// A file of one 2D camera folder — resting at 1.5 times the frame, its
  /// pivot (100, 50) placed at (300, 200) — and a track whose one clip
  /// moves it by [anim], from the timeline's tick [from] to its 120th: a
  /// camera's track, unless [trackKind] says otherwise.
  ClipDocument cameraDocument(
    List<CmtSpec> anim, {
    double from = 0,
    int trackKind = 2005,
  }) {
    final rest = ByteData(184)
      ..setFloat64(40, 1.5)
      ..setFloat64(48, 1.5)
      ..setFloat64(56, 0)
      ..setFloat64(64, 300)
      ..setFloat64(72, 200)
      ..setFloat64(80, 100)
      ..setFloat64(88, 50);
    final cameraTrack = trackDataBytes(
      cmtDocumentBytes(
        clipTrackSpec([
          CmtSpec(
            'ActionNodeClip',
            'null',
            children: [
              // Ticks at 60 a second: from 0, the clip is frames 0 … 48 at
              // 24 fps, and tick 60 frame 24.
              CmtSpec(
                'TimeClip',
                'null',
                children: [
                  CmtSpec('Start', 'Double', value: from),
                  const CmtSpec('End', 'Double', value: 120),
                  const CmtSpec('Rate', 'Double', value: 60),
                ],
              ),
              CmtSpec(
                'MotionClip',
                'null',
                children: [
                  const CmtSpec('Start', 'Double', value: 0),
                  CmtSpec('End', 'Double', value: 120 - from),
                ],
              ),
              CmtSpec('AnimInfo', 'null', children: anim),
            ],
          ),
        ]),
      ),
    );
    final database = databaseBytes((db) {
      db
        ..execute(clipSchema)
        ..execute(
          'ALTER TABLE Layer ADD COLUMN Camera2DResizableImageInfo BLOB',
        )
        ..execute(
          'INSERT INTO Canvas(MainId, CanvasWidth, CanvasHeight, '
          'CanvasRootFolder) VALUES (1, 640, 360, 1)',
        )
        ..execute(
          'INSERT INTO Layer(MainId, LayerName, LayerType, LayerFolder, '
          "LayerFirstChildIndex) VALUES (1, '', 256, 1, 2)",
        )
        ..execute(
          'INSERT INTO AnimationCutBank(MainId, FirstTimeLine, CurrentIndex) '
          'VALUES (1, 40, 0)',
        )
        ..execute(
          'INSERT INTO TimeLine(MainId, NextTimeLine, TimeLineName, '
          'FrameRate, StartFrame, EndFrame, FirstTrack) '
          "VALUES (40, 0, 'cut', 24.0, 0, 48, 50)",
        );
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
          'LayerUuidWithTrack, TrackActionMixer, TrackActionMixer2, '
          'TrackLabelFirstIndex) VALUES (?, ?, ?, ?, ?, ?, ?)',
        )
        ..execute([
          50,
          0,
          trackKind,
          clipUuidBytes(uuidCamera),
          '',
          externalId(6),
          0,
        ])
        ..close();
    });
    return readClipDocument(
      write(database, {externalId(6): cameraTrack}),
      scratch: folder,
    );
  }

  ClipMove moveOf(ClipDocument document) => document
      .timelines
      .single
      .tracks[uuidCamera.replaceAll('-', '')]!
      .moves
      .single;
  List<(double, double)> keys(ClipCurve curve) => [
    for (final key in curve.keys) (key.frame, key.value),
  ];
  String ways(ClipCurve curve) => [
    for (final way in curve.ways)
      switch (way) {
        ClipHold() => 'held',
        ClipStraight() => 'straight',
        ClipCubic(:final leaving, :final arriving) => 'cubic $leaving '
            '$arriving',
      },
  ].join(', ');

  test('🎯a 2D camera folder holds where it rests, and its track\'s clip how '
      'it moves: a curve per value, a Param for a value with none, keys on '
      'the frames the ticks land on (memory `csp-clip-format-notes` §3, '
      'the shape of s6)', () {
    final document = cameraDocument(const [
      CmtSpec(
        'Param',
        'Double2',
        value: [100, 50],
        attributes: {'Name': 'ImageCenter'},
      ),
      // A graph pulled on its first two keys: their slopes in value per
      // tick, 0.4 frames a tick; the last key CLIP STUDIO's own.
      CmtSpec(
        'FCurve',
        'null',
        attributes: {'Type': 'ImagePosition', 'Axis': 'X'},
        children: [
          CmtSpec('Frame', 'Double[]', value: [0, 30, 60]),
          CmtSpec('Value', 'Double[]', value: [300, 330, 360]),
          CmtSpec('LeftSlope', 'Double[]', value: [9, 0.5, 0.25]),
          CmtSpec('RightSlope', 'Double[]', value: [2, 7, 3]),
          CmtSpec(
            'Interp',
            'String[]',
            value: ['Hermite', 'Hermite', 'Default'],
          ),
        ],
      ),
      CmtSpec(
        'FCurve',
        'null',
        attributes: {'Type': 'ImagePosition', 'Axis': 'Y'},
        children: [
          // Frames 0 · 7 · 17 · 29 · 40: a rise at 4.7, 2 and 2.6 a frame,
          // then a fall.
          CmtSpec('Frame', 'Double[]', value: [0, 17.5, 42.5, 72.5, 100]),
          CmtSpec('Value', 'Double[]', value: [401, 434, 454, 485, 470]),
        ],
      ),
      CmtSpec(
        'Param',
        'Double',
        value: 150,
        attributes: {'Name': 'ImageScale'},
      ),
      // Into a held key flat, a key with no handles (test4), held from it,
      // and the third names a curve the reader does not know.
      CmtSpec(
        'FCurve',
        'null',
        attributes: {'Type': 'ImageRotation'},
        children: [
          CmtSpec('Frame', 'Double[]', value: [0, 30, 60, 90]),
          CmtSpec('Value', 'Double[]', value: [0, 12, 24, 36]),
          CmtSpec(
            'Interp',
            'String[]',
            value: ['Default', 'Constant', 'Bezier', 'Default'],
          ),
        ],
      ),
    ]);

    final camera = document.root.children.single;
    expect(camera.isFolder, isTrue, reason: 'a folder all the same');
    expect(camera.camera, (
      scaleX: 1.5,
      scaleY: 1.5,
      degrees: 0.0,
      x: 300.0,
      y: 200.0,
      pivotX: 100.0,
      pivotY: 50.0,
    ));
    final move = moveOf(document);
    expect(move.span, (start: 0, end: 48));
    expect(keys(move.x), [(0.0, 300.0), (12.0, 330.0), (24.0, 360.0)]);
    expect(
      ways(move.x),
      'cubic 5.0 1.25, cubic 17.5 0.0',
      reason:
          'a pulled key\'s right slope leaving and left arriving, per '
          'frame; CLIP STUDIO\'s own at the last key, still',
    );
    expect(keys(move.y), [
      (0.0, 401.0),
      (7.0, 434.0),
      (17.0, 454.0),
      (29.0, 485.0),
      (40.0, 470.0),
    ]);
    expect(
      ways(move.y),
      'cubic 0.0 2.0, cubic 2.0 2.0, cubic 2.0 0.0, cubic 0.0 0.0',
      reason:
          'CLIP STUDIO\'s own way: still at the ends and where it turns '
          'back, and between, the gentler of the two ways\' slopes',
    );
    expect(
      [keys(move.scaleX), keys(move.scaleY)],
      [
        [(0.0, 1.5)],
        [(0.0, 1.5)],
      ],
      reason: 'its Param — a camera\'s one scale, on both axes',
    );
    expect(keys(move.pivotX), [(0.0, 100.0)], reason: 'its pair');
    expect(keys(move.pivotY), [(0.0, 50.0)]);
    expect(keys(move.degrees), [
      (0.0, 0.0),
      (12.0, 12.0),
      (24.0, 24.0),
      (36.0, 36.0),
    ]);
    expect(ways(move.degrees), 'cubic 0.0 0.0, held, straight');
    expect(move.degrees.unread, isTrue, reason: 'a curve it does not know');
    expect(move.x.unread || move.y.unread, isFalse);
  });

  test('a pulled zoom keeps its slopes in percent a tick — moved, as its '
      'values are, to times the frame a frame', () {
    final move = moveOf(
      cameraDocument(const [
        CmtSpec(
          'FCurve',
          'null',
          attributes: {'Type': 'ImageScale'},
          children: [
            CmtSpec('Frame', 'Double[]', value: [0, 30]),
            CmtSpec('Value', 'Double[]', value: [100, 150]),
            CmtSpec('LeftSlope', 'Double[]', value: [0, 4]),
            CmtSpec('RightSlope', 'Double[]', value: [8, 0]),
            CmtSpec('Interp', 'String[]', value: ['Hermite', 'Hermite']),
          ],
        ),
      ]),
    );

    for (final scale in [move.scaleX, move.scaleY]) {
      expect(keys(scale), [(0.0, 1.0), (12.0, 1.5)]);
      expect(ways(scale), 'cubic 0.2 0.1');
    }
  });

  test('a value no curve keys is its Param, keyed where the clip starts — '
      'as is one whose curve keys nothing', () {
    final move = moveOf(
      cameraDocument(const [
        CmtSpec(
          'Param',
          'Double2',
          value: [100, 50],
          attributes: {'Name': 'ImageCenter'},
        ),
        CmtSpec(
          'FCurve',
          'null',
          attributes: {'Type': 'ImageCenter', 'Axis': 'X'},
          children: [
            CmtSpec('Frame', 'Double[]', value: <double>[]),
            CmtSpec('Value', 'Double[]', value: <double>[]),
          ],
        ),
      ], from: 30),
    );

    expect(move.span, (start: 12, end: 48));
    expect(keys(move.pivotX), [(12.0, 100.0)]);
    expect(keys(move.pivotY), [(12.0, 50.0)]);
    expect(
      [move.pivotX.unread, move.pivotY.unread, move.x.unread],
      [false, false, false],
      reason: 'a held value, and one the clip says nothing of, are read',
    );
  });

  test('a curve a file keeps oddly still reads: a pulled key with no slopes '
      'kept runs straight, and is said; two keys on one tick bend '
      'nothing', () {
    final move = moveOf(
      cameraDocument(const [
        CmtSpec(
          'FCurve',
          'null',
          attributes: {'Type': 'ImagePosition', 'Axis': 'X'},
          children: [
            CmtSpec('Frame', 'Double[]', value: [0, 30]),
            CmtSpec('Value', 'Double[]', value: [300, 330]),
            CmtSpec('Interp', 'String[]', value: ['Hermite', 'Hermite']),
          ],
        ),
        CmtSpec(
          'FCurve',
          'null',
          attributes: {'Type': 'ImagePosition', 'Axis': 'Y'},
          children: [
            CmtSpec('Frame', 'Double[]', value: [0, 30, 30, 60]),
            CmtSpec('Value', 'Double[]', value: [400, 410, 410, 420]),
          ],
        ),
      ]),
    );

    expect(ways(move.x), 'straight');
    expect(move.x.unread, isTrue);
    expect(ways(move.y), 'cubic 0.0 0.0, cubic 0.0 0.0, cubic 0.0 0.0');
  });

  test('🎯「등속」 is `Linear`: from a Linear key the way runs straight, and '
      'is read (the user\'s zoom-and-turn sample — both keys Linear, its '
      'zoom and turn on a straight ramp); into one, a way arrives flat — a '
      'key with no handles (test4)', () {
    final move = moveOf(
      cameraDocument(const [
        CmtSpec(
          'FCurve',
          'null',
          attributes: {'Type': 'ImageScale'},
          children: [
            CmtSpec('Frame', 'Double[]', value: [0, 58]),
            CmtSpec('Value', 'Double[]', value: [100, 150]),
            CmtSpec('LeftSlope', 'Double[]', value: [0, 0]),
            CmtSpec('RightSlope', 'Double[]', value: [0, 0]),
            CmtSpec('Interp', 'String[]', value: ['Linear', 'Linear']),
          ],
        ),
        CmtSpec(
          'FCurve',
          'null',
          attributes: {'Type': 'ImageRotation'},
          children: [
            CmtSpec('Frame', 'Double[]', value: [0, 30, 60, 90]),
            CmtSpec('Value', 'Double[]', value: [0, 12, 36, 48]),
            CmtSpec(
              'Interp',
              'String[]',
              value: ['Default', 'Linear', 'Default', 'Default'],
            ),
          ],
        ),
      ]),
    );

    expect(ways(move.scaleX), 'straight');
    expect(ways(move.degrees), 'cubic 0.0 0.0, straight, cubic 1.0 0.0');
    expect(move.scaleX.unread || move.degrees.unread, isFalse);
  });

  test('🎯test4 (10-14): keys 야와라카 · 등속 · 홀드 · 야와라카 — each kind '
      'is the way that leaves its key, and the way into the 등속 key '
      'arrives flat, as CLIP STUDIO\'s frames came (0.04px; the key\'s own '
      'slope there played 0.75px off)', () {
    final move = moveOf(
      cameraDocument(const [
        CmtSpec(
          'FCurve',
          'null',
          attributes: {'Type': 'ImagePosition', 'Axis': 'Y'},
          children: [
            CmtSpec('Frame', 'Double[]', value: [0, 18, 38, 58]),
            CmtSpec('Value', 'Double[]', value: [307, 312, 349, 357]),
            CmtSpec('LeftSlope', 'Double[]', value: [0, 0, 0, 0]),
            CmtSpec('RightSlope', 'Double[]', value: [0, 0, 0, 0]),
            CmtSpec(
              'Interp',
              'String[]',
              value: ['Default', 'Linear', 'Constant', 'Default'],
            ),
          ],
        ),
      ]),
    );

    expect(ways(move.y), 'cubic 0.0 0.0, straight, held');
    expect(move.y.unread, isFalse);
  });

  test('🎯any layer\'s track keys its placement the same way — a cel '
      'folder\'s scale by axis, `ImageAspectScale` (test4), read over an '
      '`ImageScale` — and a clip that keys none of it moves nothing', () {
    final move = moveOf(
      cameraDocument(trackKind: 2000, const [
        CmtSpec(
          'Param',
          'Double2',
          value: [100, 50],
          attributes: {'Name': 'ImageAspectScale'},
        ),
        CmtSpec(
          'FCurve',
          'null',
          attributes: {'Type': 'ImageAspectScale', 'Axis': 'Y'},
          children: [
            CmtSpec('Frame', 'Double[]', value: [0, 30]),
            CmtSpec('Value', 'Double[]', value: [50, 200]),
            CmtSpec('Interp', 'String[]', value: ['Linear', 'Default']),
          ],
        ),
        CmtSpec(
          'Param',
          'Double',
          value: 300,
          attributes: {'Name': 'ImageScale'},
        ),
      ]),
    );

    expect(keys(move.scaleX), [(0.0, 1.0)], reason: 'its pair\'s X');
    expect(keys(move.scaleY), [(0.0, 0.5), (12.0, 2.0)]);
    expect(ways(move.scaleY), 'straight');

    final shownOnly = cameraDocument(trackKind: 2000, const [
      CmtSpec(
        'Param',
        'Int32',
        value: 0,
        attributes: {'Name': 'ImageCelName', 'Tag': '1'},
      ),
    ]);
    expect(
      shownOnly.timelines.single.tracks[uuidCamera.replaceAll('-', '')]!.moves,
      isEmpty,
    );
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

  test('the copy of the database it read from is made in the room it is '
      'handed, and gone from it afterwards', () {
    final room = Directory('${folder.path}/room');
    expect(
      () => readClipDocument(fixture(), scratch: room),
      throwsA(isA<FileSystemException>()),
      reason: 'a room that is not there is no room — the copy went there',
    );
    room.createSync();
    readClipDocument(fixture(), scratch: room);
    expect(room.listSync(), isEmpty);
  });

  // 🗣️I-130-csp-import-Q1 (유저 2026-10-27): 「새로 만든것임. 기밀아니고」 —
  // a sample made for this, not one from work, so it is kept as a fixture.
  test('🎯the sample the user made for the marks: its ○ on frame 3 and its ● '
      'on frame 5 — the first two labels it made, as asked — and five more, '
      'each the mark its kind is', () {
    final document = readClipDocument(
      'test/fixtures/clip_inbetween_marks.clip',
      scratch: folder,
    );
    final folderTrack = document.timelines.single.tracks.values.singleWhere(
      (track) => track.kind == 2000,
    );
    expect(folderTrack.breakdownMarks, {
      3: InbetweenMark.one,
      5: InbetweenMark.two,
      8: InbetweenMark.two,
      9: InbetweenMark.one,
      10: InbetweenMark.one,
      11: InbetweenMark.two,
      12: InbetweenMark.one,
    });
    expect(document.warnings, isEmpty);
  });
}
