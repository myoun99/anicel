import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/bitmap_tile.dart';
import 'package:anicel/src/models/tile_coord.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/text/canvas_letter_faces.dart';
import 'package:anicel/src/ui/text/cel_text_bake.dart';

import '../../helpers/opened_session.dart';
import '../../helpers/temp_dir.dart';
import '../../services/import/clip_test_builder.dart';

/// 🎯F-370-Q3 (유저 2026-10-17: 「이제 들인다(앱의 글자로)」): a CLIP STUDIO
/// text layer opens as a row whose cel holds the app's own texts — each
/// shown as CLIP STUDIO drew it, from the picture the file keeps of it,
/// until it is edited.
///
/// The file is built here, the way the format notes lay it out (memory
/// `csp-clip-format-notes` 6-1 §13): the samples are work files and stay
/// out of the repository.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory temp;
  setUp(() => temp = Directory.systemTemp.createTempSync('qa_clip_text_'));
  tearDown(() {
    debugCelTextBaker = null;
    deleteTempQuietly(temp);
  });

  /// A file whose one layer, 「words」 at (5, 6), is a text layer of two
  /// texts: 「Hi」, whose box (10, 20) … (40, 50) CLIP STUDIO drew a
  /// picture of — a 31 × 31 picture inked at its top-left 4 × 4 — and
  /// 「yo」, which the file holds no picture of.
  String writeClip() {
    final database = clipDatabaseBytes(temp, (db) {
      db.execute(clipSchema);
      for (final column in [
        'Layer ADD COLUMN TextLayerType INTEGER',
        'Layer ADD COLUMN TextLayerString BLOB',
        'Layer ADD COLUMN TextLayerAttributes BLOB',
        'Layer ADD COLUMN TextLayerStringArray BLOB',
        'Layer ADD COLUMN TextLayerAttributesArray BLOB',
        'Offscreen ADD COLUMN LayerId INTEGER',
      ]) {
        db.execute('ALTER TABLE $column');
      }
      db
        ..execute(
          'INSERT INTO Canvas(MainId, CanvasWidth, CanvasHeight, '
          'CanvasRootFolder) VALUES (1, 300, 200, 1)',
        )
        ..execute(
          'INSERT INTO Layer(MainId, LayerName, LayerType, LayerFolder, '
          "LayerFirstChildIndex) VALUES (1, '', 256, 1, 2)",
        )
        ..execute(
          'INSERT INTO Layer(MainId, LayerName, LayerType, LayerFolder, '
          'LayerVisibility, LayerOpacity, LayerOffsetX, LayerOffsetY, '
          'TextLayerType, TextLayerString, TextLayerAttributes, '
          'TextLayerStringArray, TextLayerAttributesArray) '
          "VALUES (2, 'words', 800, 0, 1, 256, 5, 6, 2, ?, ?, ?, ?)",
          [
            utf8.encode('Hi'),
            clipTextAttributesBytes(
              box: (x0: 10, y0: 20, x1: 40, y1: 50),
              colour: (200, 0, 0),
            ),
            clipTextArrayBytes([utf8.encode('yo')]),
            clipTextArrayBytes([
              clipTextAttributesBytes(box: (x0: 60, y0: 20, x1: 80, y1: 40)),
            ]),
          ],
        )
        ..execute(
          'INSERT INTO Offscreen(MainId, LayerId, Attribute, BlockData) '
          'VALUES (400, 2, ?, ?)',
          [
            offscreenAttributeBytes(width: 31, height: 31, columns: 1, rows: 1),
            externalId(1),
          ],
        );
    });
    final path = '${temp.path}${Platform.pathSeparator}scene.clip';
    File(path).writeAsBytesSync(
      clipFileBytes(
        database: database,
        externals: {
          externalId(1): blockRecordsBytes({
            0: colourBlock(
              (x, y) => x < 4 && y < 4 ? (200, 0, 0, 255) : (0, 0, 0, 0),
            ),
          }),
        },
      ),
    );
    return path;
  }

  /// A plate no picture of the file makes: what the stand-in engine sets.
  Map<TileCoord, BitmapTile> markerPlate() => {
    TileCoord(x: 1, y: 1): BitmapTile(
      size: defaultCelTileSize,
      pixels: Uint8List(defaultCelTileSize * defaultCelTileSize * 4)
        ..[3] = 255,
    ),
  };

  test('🎯its texts are the cel\'s — the one CLIP STUDIO drew shown as it '
      'drew it, where it stands; the one it did not set by this app, and '
      'said', () async {
    final set = <String>[];
    final marker = markerPlate();
    debugCelTextBaker =
        (layout, {required pasteboard, required tileSize, previous = const {}}) {
          set.add(layout.content.text);
          return Future.value(marker);
        };
    final opened = await openedClip(writeClip());
    final session = opened!.session;
    addTearDown(session.dispose);

    expect(
      [
        for (final warning in opened.warnings)
          (warning.key, warning.values['name']),
      ],
      [('clipTextSetHere', 'words')],
    );
    expect(set, ['yo'], reason: 'only the text the file drew no picture of');
    final cut = session.repository.requireProject().tracks.single.cuts.single;
    final row = cut.layers.singleWhere((layer) => layer.name == 'words');
    final surface = session.renderCaches.brushFrameStore.bakedSurfaceOrNull(
      session.brushFrameKeyForCut(cut, row.id, row.frames.single.id),
    )!;
    final [hi, yo] = surface.texts;
    expect((hi.id, hi.content.text), (1, 'Hi'));
    expect(hi.content.spans.single.style.color, 0xFFC80000);
    expect(hi.content.anchor.x, 15);
    expect(
      hi.content.anchor.y,
      closeTo(26 - (1.2 - 1) * 12 / 2, 1e-9),
      reason: 'the line\'s top, half its leading over the box',
    );
    // The picture lies at the box's top-left on the canvas, (15, 26): its
    // 4 × 4 of ink covers 15 … 18 across and 26 … 29 down.
    final tile = hi.plate[TileCoord(x: 0, y: 0)]!;
    int alphaAt(int x, int y) =>
        tile.pixels[(y * defaultCelTileSize + x) * 4 + 3];
    expect(alphaAt(15, 26), 255);
    expect(alphaAt(18, 29), 255);
    expect(alphaAt(14, 26), 0);
    expect(alphaAt(19, 30), 0);
    expect(hi.plate.keys, [TileCoord(x: 0, y: 0)]);
    expect((yo.id, yo.content.text), (2, 'yo'));
    expect(yo.plate, marker, reason: 'the plate this app set');
    expect(
      surface.tiles,
      isEmpty,
      reason: 'the cel draws nothing but its texts',
    );
  });

  test('a text this app sets is set once the face it is in — held by the '
      'device and still being read — has reached the engine, as the text '
      'tool waits for it', () async {
    final faces = CanvasLetterFaces(
      // A held face is read when it is first asked for — here by the
      // import, as it comes to the text — and is on its way from then
      // until the reading's turn comes round.
      files: (_) async => [Uint8List(4)],
      register: (_, {required engineFamily}) async {},
    )..setHeld({'Face': 'face-files'});
    final before = CanvasLetterFaces.current;
    CanvasLetterFaces.current = faces;
    addTearDown(() {
      CanvasLetterFaces.current = before;
      faces.dispose();
    });
    final arrived = <bool>[];
    debugCelTextBaker =
        (layout, {required pasteboard, required tileSize, previous = const {}}) {
          arrived.add(!faces.isOnItsWay('Face'));
          return Future.value(markerPlate());
        };
    final opened = await openedClip(writeClip());
    addTearDown(opened!.session.dispose);

    expect(arrived, [true], reason: 'set in its face, not in a stand-in');
  });

  test('the import says a text layer is done only once its texts are in '
      'its cel — the one it sets among them', () async {
    debugCelTextBaker =
        (layout, {required pasteboard, required tileSize, previous = const {}}) =>
            // A turn of the event loop: the engine's bake is not done at
            // once.
            Future(markerPlate);
    late EditorSessionManager session;
    int? textsInTheCel() {
      final cut = session.repository.requireProject().tracks.single.cuts.single;
      final row = cut.layers.singleWhere((layer) => layer.name == 'words');
      return session.renderCaches.brushFrameStore
          .bakedSurfaceOrNull(
            session.brushFrameKeyForCut(cut, row.id, row.frames.single.id),
          )
          ?.texts
          .length;
    }

    final atProgress = <int?>[];
    final opened = await openedClip(
      writeClip(),
      make: (project) =>
          session = EditorSessionManager(initialProject: project),
      onProgress: (_) => atProgress.add(textsInTheCel()),
    );
    addTearDown(opened!.session.dispose);

    expect(atProgress, [2], reason: 'both texts, as the layer is said done');
  });
}
