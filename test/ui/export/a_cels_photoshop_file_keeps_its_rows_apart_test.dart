import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/bitmap_tile.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/export_format_selection.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_blend_mode.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/tile_coord.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/services/editing/default_cut_helpers.dart';
import 'package:anicel/src/services/photoshop/psd_reader.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/export/export_cel_group_plan.dart';
import 'package:anicel/src/ui/export/export_frame_renderer.dart';
import 'package:anicel/src/ui/export/export_plan.dart';
import 'package:anicel/src/ui/export/still_image_encoders.dart';
import 'package:anicel/src/ui/text/app_strings.dart';

import '../../helpers/no_guides_laid.dart';

/// A cel written as a Photoshop document keeps apart the rows its picture
/// lays into one (I-117 — 🗣️유저 2026-10-21: 「셀은 출력될 셀 등 소재 하나당
/// 해당 어태치레이어 구조 그대로 지켜서 출력」): every member, bottom-up, each
/// drawn as itself and carrying its strength and blend for the file to lay
/// it by — over the ground the picture stands on, where it has one.
void main() {
  const size = CanvasSize(width: 8, height: 8);
  const cutId = CutId('cut');
  final a1 = Frame(id: const FrameId('a1'), duration: 1, strokes: const []);
  final shade1 = Frame(
    id: const FrameId('s1'),
    duration: 1,
    strokes: const [],
  );
  const clear = ui.Color(0x00000000);
  const white = ui.Color(0xFFFFFFFF);
  const black = [0, 0, 0, 255];
  const blue = [10, 20, 220, 255];

  /// A cut of the cel 「A」 and a row riding it, 「A 影」 — multiplied over
  /// it at half strength.
  EditorSessionManager film() {
    final session = EditorSessionManager(
      initialProject: Project(
        id: const ProjectId('project'),
        name: 'Project',
        cameraSize: size,
        createdAt: DateTime.utc(2026),
        tracks: [
          Track(
            id: const TrackId('track'),
            name: 'Track',
            cuts: [
              Cut(
                id: cutId,
                name: 'CUT',
                duration: 1,
                canvasSize: size,
                layers: [
                  Layer(id: const LayerId('a'), name: 'A', frames: [a1]),
                  Layer(
                    id: const LayerId('shade'),
                    name: 'A 影',
                    frames: [shade1],
                    opacity: 0.5,
                    blendMode: LayerBlendMode.multiply,
                  ),
                  createCameraLayer(cutId: cutId),
                ],
              ),
            ],
          ),
        ],
      ),
    );
    addTearDown(session.dispose);
    return session;
  }

  /// A picture of the canvas's size holding [paint] alone: each (x, y) →
  /// its RGBA.
  Uint8List only(Map<(int, int), List<int>> paint) {
    final pixels = Uint8List(size.width * size.height * 4);
    for (final MapEntry(key: (x, y), value: rgba) in paint.entries) {
      pixels.setAll((y * size.width + x) * 4, rgba);
    }
    return pixels;
  }

  /// [session]'s drawings: [onA] on 「A」 and [onShade] on 「A 影」, each
  /// (x, y) → its RGBA.
  void paint(
    EditorSessionManager session, {
    required Map<(int, int), List<int>> onA,
    required Map<(int, int), List<int>> onShade,
  }) {
    final cut = session.requireActiveCut;
    void put(String row, FrameId cel, Map<(int, int), List<int>> paint) =>
        session.renderCaches.brushFrameStore.storeBakedSurface(
          session.brushFrameKeyForCut(cut, LayerId(row), cel),
          BitmapSurface(
            canvasSize: size,
            tileSize: 8,
            tiles: {
              TileCoord(x: 0, y: 0): BitmapTile(size: 8, pixels: only(paint)),
            },
          ),
        );
    put('a', a1.id, onA);
    put('shade', shade1.id, onShade);
  }

  /// A black dot at (1, 1) on 「A」 and a blue one at (2, 2) on 「A 影」.
  void draw(EditorSessionManager session) =>
      paint(session, onA: {(1, 1): black}, onShade: {(2, 2): blue});

  /// The cel 「A 1」 with 「A 影」 riding it.
  ExportCelGroupTask celOf(EditorSessionManager session) {
    final cut = session.requireActiveCut;
    final [a, shade, ...] = cut.layers;
    return ExportCelGroupTask(
      cut: cut,
      baseLayer: a,
      members: [a, shade],
      memberFrames: [a1, shade1],
      baseFrame: a1,
      celName: '1',
      fileName: 'A1.psd',
    );
  }

  /// [row]'s picture, straight RGBA.
  Future<Uint8List> pictureOf(ExportLayerRow row) async {
    final image = await row.draw();
    final bytes = await image.toByteData(
      format: ui.ImageByteFormat.rawStraightRgba,
    );
    image.dispose();
    return bytes!.buffer.asUint8List();
  }

  List<ExportLayerRow> rowsOf(EditorSessionManager session, ui.Color ground) =>
      ExportFrameRenderer(session: session, background: ground).celGroupRows(
        celOf(session),
        ExportSizeMode.canvas,
        guideColor: noGuidesLaid,
      );

  testWidgets('each member is a row of its own, bottom-up — its strength and '
      'blend the file\'s to lay it by, its picture drawn as itself: whole, '
      'in no blend, on nothing', (tester) async {
    await tester.runAsync(() async {
      final session = film();
      draw(session);
      final rows = rowsOf(session, clear);

      expect(
        [for (final row in rows) (row.name, row.opacity, row.blendMode)],
        [
          ('A', 1.0, LayerBlendMode.normal),
          ('A 影', 0.5, LayerBlendMode.multiply),
        ],
      );
      expect(await pictureOf(rows[0]), only({(1, 1): black}));
      expect(
        await pictureOf(rows[1]),
        only({(2, 2): blue}),
        reason: 'at full strength — the half is the file\'s to apply',
      );
    });
  });

  testWidgets('the cel\'s own picture lays them as the file does — each by '
      'its strength and blend (R26 #30)', (tester) async {
    await tester.runAsync(() async {
      final session = film();
      const gray = [128, 128, 128, 255];
      paint(session, onA: {(2, 2): gray}, onShade: {(2, 2): blue});
      final picture = (await ExportFrameRenderer(
        session: session,
        background: white,
      ).renderCelGroup(
        celOf(session),
        ExportSizeMode.canvas,
        guideColor: noGuidesLaid,
      ))!;
      final drawn = (await picture.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      ))!.buffer.asUint8List();
      picture.dispose();

      // The blue multiplied into the gray under it, laid over it at half.
      final at = (2 * size.width + 2) * 4;
      for (var c = 0; c < 3; c += 1) {
        expect(
          drawn[at + c],
          closeTo((gray[c] + gray[c] * blue[c] / 255) / 2, 2),
        );
      }
    });
  });

  testWidgets('the ground an RGB cel stands on is its bottom row, and no row '
      'stands on it; an RGBA cel has none', (tester) async {
    await tester.runAsync(() async {
      final session = film();
      draw(session);
      final onWhite = rowsOf(session, white);

      expect(
        [for (final row in onWhite) row.name],
        [AppText.strings.exBackground, 'A', 'A 影'],
      );
      expect(await pictureOf(onWhite.first), only({
        for (var y = 0; y < size.height; y += 1)
          for (var x = 0; x < size.width; x += 1) (x, y): [255, 255, 255, 255],
      }));
      expect(await pictureOf(onWhite[1]), only({(1, 1): black}));
      expect([for (final row in rowsOf(session, clear)) row.name], [
        'A',
        'A 影',
      ]);
    });
  });

  testWidgets('a cel with no artwork has no rows, as it has no picture',
      (tester) async {
    await tester.runAsync(() async {
      final session = film();
      final renderer = ExportFrameRenderer(session: session, background: white);
      final task = celOf(session);

      expect(
        await renderer.renderCelGroup(
          task,
          ExportSizeMode.canvas,
          guideColor: noGuidesLaid,
        ),
        isNull,
      );
      expect(
        renderer.celGroupRows(
          task,
          ExportSizeMode.canvas,
          guideColor: noGuidesLaid,
        ),
        isEmpty,
      );
    });
  });

  testWidgets('drawn after the cel\'s picture, its rows read no cel the '
      'picture did not', (tester) async {
    await tester.runAsync(() async {
      final session = film();
      draw(session);
      final renderer = ExportFrameRenderer(session: session, background: clear);
      final task = celOf(session);
      (await renderer.renderCelGroup(
        task,
        ExportSizeMode.canvas,
        guideColor: noGuidesLaid,
      ))!.dispose();
      final read = renderer.debugCelReads;

      for (final row in renderer.celGroupRows(
        task,
        ExportSizeMode.canvas,
        guideColor: noGuidesLaid,
      )) {
        (await row.draw()).dispose();
      }
      expect(renderer.debugCelReads, read);
    });
  });

  testWidgets('written, they are the document\'s rows over the cel\'s '
      'picture — names, strengths, blends and pixels as drawn, a colour as '
      'it is where its alpha is half', (tester) async {
    await tester.runAsync(() async {
      final session = film();
      const half = [200, 100, 50, 128];
      paint(
        session,
        onA: {(1, 1): black, (2, 1): half},
        onShade: {(2, 2): blue},
      );
      final renderer = ExportFrameRenderer(session: session, background: white);
      final task = celOf(session);
      final picture = (await renderer.renderCelGroup(
        task,
        ExportSizeMode.canvas,
        guideColor: noGuidesLaid,
      ))!;
      final drawn = (await picture.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      ))!.buffer.asUint8List();
      final bytes = await encodePsd(
        picture,
        const ExportFormatSelection(
          kind: ExportMediaKind.still,
          stillFormat: ExportStillFormat.psd,
          channels: ExportChannels.rgb,
        ),
        renderer.celGroupRows(
          task,
          ExportSizeMode.canvas,
          guideColor: noGuidesLaid,
        ),
      );
      picture.dispose();
      final read = readPsdDocument(Uint8List.fromList(bytes!));

      expect(
        [
          for (final layer in read.layers)
            (layer.name, layer.opacity, layer.blendKey),
        ],
        [
          (AppText.strings.exBackground, 255, 'norm'),
          ('A', 255, 'norm'),
          ('A 影', 128, 'mul '),
        ],
      );
      final line = read.layers[1];
      expect((line.left, line.top, line.right, line.bottom), (1, 1, 3, 2));
      final pixels = line.pixels!;
      expect(pixels.sublist(0, 4), black);
      for (var c = 0; c < 4; c += 1) {
        expect(
          pixels[4 + c],
          closeTo(half[c], 2),
          reason: 'its colour kept apart from its alpha, as a layer keeps it',
        );
      }
      expect(read.composite, drawn, reason: 'the cel\'s own picture, opaque');
    });
  });
}
