// A REFERENCE STANDS WHERE ITS REFERENCE FX SAYS (I-68). 🗣️유저 2026-10-04:
// 「처음에 용지 세팅하고나서 오른쪽으로 캔버스 크기 늘리고나서, 용지
// 스위칭하려고 배치하면 캔버스 중앙에 배치되는데 … 구조적,근본적인 해결」;
// 10-10: 「담는값은 변형도구랑 같은거 공유 … 해상도가 달라도 같은크기로
// 겹치지않게 … 배치된 값, 원본값 유지」 · 캔버스 크기 변경 「가」(기준점대로).
//
// The pose a placement starts a file's picture at is the reference's own:
// the canvas growing afterwards moves it with the drawings, and a file
// swapped in stands at it over ITS pixels. The file itself is laid 1:1 on
// the cels — a PDF's page at its own size — and the canvas stands it where
// the fx does (F-374-Q1 · Q5: 「놓을때 100%인걸 놓기만 하면 됨」); a movie,
// decoded as it is shown, is laid there too. Rasterizing keeps the move as
// the row's own keys (Q3); where its transform cannot carry them the cels
// take the picture where the row shows it (Q7 「①은 스위치를 켜고 키로,
// ②③만 굽는다」). ↩️The file was laid at the fit, and again where the fx
// stood still — a GIF's frames and a PDF's pages too (10-10 「가」).
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/attached_layer_mount.dart';
import 'package:anicel/src/models/attached_placement.dart';
import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_resize_anchor.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/media_asset.dart';
import 'package:anicel/src/models/movie_cel.dart';
import 'package:anicel/src/models/property_track.dart';
import 'package:anicel/src/models/reference_swap.dart';
import 'package:anicel/src/models/tile_coord.dart';
import 'package:anicel/src/models/timeline_coverage.dart';
import 'package:anicel/src/models/transform_track.dart';
import 'package:anicel/src/services/bitmap_surface_geometry.dart';
import 'package:anicel/src/services/cut_frame_composite_plan.dart';
import 'package:anicel/src/services/import/media_import_planner.dart';
import 'package:anicel/src/services/import/raster_cel_import.dart';
import 'package:anicel/src/services/layer_pose_matrix.dart'
    show picturePlacement;
import 'package:anicel/src/services/media/video_decode_worker.dart';
import 'package:anicel/src/services/pdf/pdf_render_service.dart';
import 'package:anicel/src/services/reference_move_carried.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/import/import_file_settings.dart';
import 'package:anicel/src/ui/timeline/reference_lane_policy.dart';
import 'package:anicel/src/ui/timeline/timeline_lane_provider.dart';

import '../../helpers/cel_text_fixture.dart' show pixelOf;
import '../../helpers/fake_pdf_document.dart';
import '../../helpers/fake_video_backend.dart';
import '../../helpers/placed_sound_conform.dart';
import '../../helpers/solid_png_fixture.dart';
import '../../helpers/temp_dir.dart';
import '../../helpers/three_frame_gif.dart';

/// Cel [index] of [row] as the store holds it baked.
BitmapSurface? celOf(EditorSessionManager s, Layer row, int index) =>
    s.renderCaches.brushFrameStore.bakedSurfaceOrNull(
      s.brushFrameKeyForCut(s.requireActiveCut, row.id, row.frames[index].id),
    );

/// The colour [surface] holds at canvas pixel ([x], [y]), as straight RGBA.
List<int>? colourAt(BitmapSurface? surface, int x, int y) {
  if (surface == null) {
    return null;
  }
  final size = surface.tileSize;
  return pixelOf(
    surface,
    TileCoord.fromPixel(pixelX: x, pixelY: y, tileSize: size),
    x % size,
    y % size,
  );
}

/// A redraw the file did not give: it lacks [picture], counted from 0.
Matcher lacks(int picture) => isA<ReferenceLacksPicture>().having(
  (answer) => answer.picture,
  'picture',
  picture,
);

/// [colour] as the straight RGBA a surface reads back.
List<int> rgbaOf(ui.Color colour) {
  final argb = colour.toARGB32();
  return [(argb >> 16) & 0xFF, (argb >> 8) & 0xFF, argb & 0xFF, argb >>> 24];
}

/// The warmer the session woke, stopped — or it waits on past the test.
Future<void> stopTheWarmer(WidgetTester tester, EditorSessionManager s) async {
  s.playbackRig.prerenderScheduler.cancel();
  await tester.pump();
}

/// Where [surface]'s ink lies on the canvas, or null when it holds none.
ui.Rect? inkOf(BitmapSurface? surface) {
  if (surface == null) {
    return null;
  }
  final box = bitmapSurfaceContentBounds(surface);
  return box == null
      ? null
      : ui.Rect.fromLTRB(
          box.left.toDouble(),
          box.top.toDouble(),
          box.rightExclusive.toDouble(),
          box.bottomExclusive.toDouble(),
        );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// A row's own transform at half its height: under a picture its fx turns
  /// other than by a quarter, a shear no pose of the row's makes.
  final squashed = TransformTrack.empty().copyWith(
    scale: PropertyTrack<CanvasPoint>().withKey(0, CanvasPoint(x: 1, y: 0.5)),
  );

  group('a fit is where a pose STARTS', () {
    const picture = CanvasSize(width: 200, height: 100);
    const canvas = CanvasSize(width: 400, height: 400);

    ui.Rect laid(MediaFitMode fit) {
      final placement = picturePlacement(
        fitPose(picture: picture, canvas: canvas, fit: fit),
        picture,
      );
      final topLeft = placement.apply(CanvasPoint(x: 0, y: 0));
      final bottomRight = placement.apply(CanvasPoint(x: 200, y: 100));
      return ui.Rect.fromLTRB(
        topLeft.x,
        topLeft.y,
        bottomRight.x,
        bottomRight.y,
      );
    }

    test('contain letterboxes, stretch fills, none is 1:1 — each centred',
        () {
      expect(
        laid(MediaFitMode.contain),
        const ui.Rect.fromLTRB(0, 100, 400, 300),
      );
      expect(
        laid(MediaFitMode.stretch),
        const ui.Rect.fromLTRB(0, 0, 400, 400),
      );
      expect(
        laid(MediaFitMode.none),
        const ui.Rect.fromLTRB(100, 150, 300, 250),
      );
    });

    test('1:1 stands a picture an odd number of pixels off the canvas\'s '
        'size on whole pixels — copied, never resampled half a pixel over',
        () {
      const odd = CanvasSize(width: 101, height: 61);

      expect(
        picturePlacement(
          fitPose(picture: odd, canvas: canvas, fit: MediaFitMode.none),
          odd,
        ).apply(CanvasPoint(x: 0, y: 0)),
        CanvasPoint(x: 150, y: 170),
      );
    });

    test('a picture with no pixels stands 1:1 — it has no size to fit', () {
      expect(
        fitPose(
          picture: const CanvasSize(width: 0, height: 10),
          canvas: canvas,
          fit: MediaFitMode.stretch,
        ),
        TransformPose(center: CanvasPoint(x: 200, y: 200)),
      );
    });
  });

  group('a paper', () {
    late Directory tempDir;
    late String red;
    late String blue;
    late String blueTwice;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('anicel-i68-paper');
    });

    tearDown(() => deleteTempQuietly(tempDir));

    /// A session with a red [width]×[height] paper placed 1:1 as a
    /// reference on the default 2340×1654 canvas — its middle at
    /// (1170, 827).
    Future<(EditorSessionManager, Layer)> placed(
      WidgetTester tester, {
      int width = 100,
      int height = 60,
    }) async {
      final s = EditorSessionManager(initialProject: createDefaultProject());
      addTearDown(s.dispose);
      s.playbackRig.prerenderScheduler.beginInputHold();
      await tester.runAsync(() async {
        red = await writeSolidPng(
          tempDir,
          'red.png',
          width: width,
          height: height,
          rgba: 0xFF0000FF,
        );
        blue = await writeSolidPng(
          tempDir,
          'blue.png',
          width: 100,
          height: 60,
          rgba: 0x0000FFFF,
        );
        blueTwice = await writeSolidPng(
          tempDir,
          'blue2x.png',
          width: 200,
          height: 120,
          rgba: 0x0000FFFF,
        );
        expect(
          await s.importDoors.importImageFile(
            path: red,
            destination: ImportDestination.activeCutLayer,
            copyIntoProject: false,
            fit: MediaFitMode.none,
          ),
          isTrue,
        );
      });
      final row = s.requireActiveCut.layers.firstWhere(
        (layer) => layer.mediaReference != null,
      );
      return (s, row);
    }

    ui.Rect? shown(EditorSessionManager s, Layer row) {
      final cut = s.requireActiveCut;
      return inkOf(
        s.renderCaches.brushFrameStore.bakedSurfaceOrNull(
          s.brushFrameKeyForCut(cut, row.id, row.frames.single.id),
        ),
      );
    }

    Layer rowOf(EditorSessionManager s, Layer row) => s.layerById(row.id)!;

    testWidgets('🎯the canvas grows to the right, and a paper swapped in '
        'afterwards stands where the first one stood — not in the middle of '
        'the canvas it grew to', (tester) async {
      final (s, row) = await placed(tester);
      expect(shown(s, row), const ui.Rect.fromLTRB(1120, 797, 1220, 857));

      s.cutVerbs.resizeActiveCutCanvas(
        const CanvasSize(width: 2940, height: 1654),
        anchor: CanvasResizeAnchor.centerLeft,
      );
      expect(
        rowOf(s, row).mediaReference!.pose.center,
        CanvasPoint(x: 1170, y: 827),
        reason: 'pinned left: the paper did not move',
      );

      expect(
        await tester.runAsync(
          () => s.importDoors.swapReference(layerId: row.id, path: blue),
        ),
        isA<ReferenceLaid>(),
      );
      expect(
        shown(s, row),
        const ui.Rect.fromLTRB(1120, 797, 1220, 857),
        reason: 'where red stood — the canvas\'s new middle is x 1470',
      );
    });

    testWidgets('grown to the LEFT, the paper moves with the drawings — and '
        'the one swapped in afterwards stands where it moved to',
        (tester) async {
      final (s, row) = await placed(tester);

      s.cutVerbs.resizeActiveCutCanvas(
        const CanvasSize(width: 2940, height: 1654),
        anchor: CanvasResizeAnchor.centerRight,
      );
      expect(shown(s, row), const ui.Rect.fromLTRB(1720, 797, 1820, 857));
      expect(
        rowOf(s, row).mediaReference!.pose.center,
        CanvasPoint(x: 1770, y: 827),
        reason: 'the content offset (600), not the canvas middle\'s (300)',
      );

      await tester.runAsync(
        () => s.importDoors.swapReference(layerId: row.id, path: blue),
      );
      expect(shown(s, row), const ui.Rect.fromLTRB(1720, 797, 1820, 857));
    });

    testWidgets('a paper of another resolution stands at ITS size — the same '
        'pose over its own pixels, not fitted to the old one\'s rect',
        (tester) async {
      final (s, row) = await placed(tester);

      await tester.runAsync(
        () => s.importDoors.swapReference(layerId: row.id, path: blueTwice),
      );

      expect(shown(s, row), const ui.Rect.fromLTRB(1070, 767, 1270, 887));
      expect(
        rowOf(s, row).mediaReference!.pictureSize,
        const CanvasSize(width: 200, height: 120),
        reason: 'the size the row shows is the new file\'s',
      );
    });

    testWidgets('rasterizing keeps the paper where its reference fx stood '
        'it — the move the row\'s own Position key now (F-374-Q3) — and '
        'ONE undo gives the reference back', (tester) async {
      final (s, row) = await placed(tester);
      s.laneVerbs.setLaneValueAt(
        row.id,
        referencePositionLaneId,
        0,
        '1200, 827',
        frameIsGlobal: false,
        description: 'Edit Position',
        scaleLinked: false,
      );

      s.editingCanvas.rasterizeLayerReferences([row.id]);

      final baked = rowOf(s, row);
      expect(baked.mediaReference, isNull);
      expect(
        shown(s, baked),
        const ui.Rect.fromLTRB(1120, 797, 1220, 857),
        reason: 'the cel as the file was laid on it',
      );
      expect(
        baked.transformTrack.position.keys.map(
          (frame, key) => MapEntry(frame, key.value),
        ),
        {0: CanvasPoint(x: 1200, y: 827)},
      );
      expect(
        layerPlacementAt(
          cut: s.requireActiveCut,
          layer: baked,
          frameIndex: 0,
        )!.apply(CanvasPoint(x: 1120, y: 797)),
        CanvasPoint(x: 1150, y: 797),
      );

      s.undo();
      expect(rowOf(s, row).mediaReference, isNotNull);
      expect(rowOf(s, row).transformTrack.isEmpty, isTrue);
      await tester.pump(const Duration(minutes: 1));
      await stopTheWarmer(tester, s);
    });

    /// [row]'s own transform written as [track], its reference fx as [fx].
    void posed(
      EditorSessionManager s,
      Layer row, {
      TransformTrack? track,
      TransformTrack? fx,
    }) {
      final coordinator = s.cutCommandCoordinator;
      if (track != null) {
        coordinator.updateLayerTransformTrack(
          cutId: s.requireActiveCut.id,
          layerId: row.id,
          transformTrack: track,
        );
      }
      if (fx != null) {
        coordinator.updateLayerReferenceFx(layerId: row.id, fx: fx);
      }
    }

    ReferenceLetGo wayOf(EditorSessionManager s, Layer row) => s
        .cutCommandCoordinator
        .referenceLetGoOf(cutId: s.requireActiveCut.id, layerId: row.id);

    /// A way whose cels take the picture where the uses show it.
    final bakes = isA<ReferenceMoveCarried>().having(
      (way) => way.bakes,
      'bakes',
      isTrue,
    );

    final turnedOnce = TransformTrack.empty().copyWith(
      rotation: PropertyTrack<double>().withKey(0, 30),
    );
    final halved = TransformTrack.empty().copyWith(
      scale: PropertyTrack<CanvasPoint>().withKey(
        0,
        CanvasPoint(x: 0.5, y: 0.5),
      ),
    );

    /// [row] attached above the cut's drawing: an attach row, which stands
    /// where its base's transform puts it.
    void attachToTheDrawing(EditorSessionManager s, Layer row) {
      final base = s.requireActiveCut.layers.firstWhere(
        (layer) => layer.kind == LayerKind.animation,
      );
      s.cutCommandCoordinator.setLayerAttachment(
        cutId: s.requireActiveCut.id,
        attach: LayerAttachDrop(
          mounts: [
            (
              layerId: row.id,
              baseId: base.id,
              placement: AttachedPlacement.above,
            ),
          ],
        ),
      );
    }

    testWidgets('a key the fx named keeps its name on the row — the row\'s '
        'own key of that name is one the move replaces', (tester) async {
      final (s, row) = await placed(tester);
      PropertyTrack<CanvasPoint> up(double x) => PropertyTrack(
        keys: {0: PropertyKey(CanvasPoint(x: x, y: 827), name: 'up')},
      );
      posed(
        s,
        row,
        track: TransformTrack.empty().copyWith(position: up(1170)),
        fx: TransformTrack.empty().copyWith(position: up(1200)),
      );

      s.editingCanvas.rasterizeLayerReferences([row.id]);

      final baked = rowOf(s, row);
      expect(baked.mediaReference, isNull);
      expect(baked.transformTrack.position.keys[0]!.name, 'up');
      await tester.pump(const Duration(minutes: 1));
      await stopTheWarmer(tester, s);
    });

    testWidgets('🎯① a row whose transform is switched off: rasterizing '
        'turns it on and the move is its keys — the keys it kept while it '
        'showed nothing are gone, and ONE undo gives all of it back '
        '(F-374-Q7)', (tester) async {
      final (s, row) = await placed(tester);
      posed(
        s,
        row,
        track: TransformTrack.empty().copyWith(
          rotation: PropertyTrack<double>().withKey(0, 45),
        ),
      );
      s.effectsAndFx.setLayerTransformFx(row.id, enabled: false);
      posed(
        s,
        row,
        fx: TransformTrack.empty().copyWith(
          position: PropertyTrack<CanvasPoint>().withKey(
            0,
            CanvasPoint(x: 1200, y: 827),
          ),
        ),
      );

      s.editingCanvas.rasterizeLayerReferences([row.id]);

      final baked = rowOf(s, row);
      expect(baked.mediaReference, isNull);
      expect(baked.transformEnabled, isTrue);
      expect(
        baked.transformTrack.position.keys.map(
          (frame, key) => MapEntry(frame, key.value),
        ),
        {0: CanvasPoint(x: 1200, y: 827)},
      );
      expect(baked.transformTrack.rotation.isEmpty, isTrue);
      expect(shown(s, baked), const ui.Rect.fromLTRB(1120, 797, 1220, 857));

      s.undo();
      final back = rowOf(s, row);
      expect(back.mediaReference, isNotNull);
      expect(back.transformEnabled, isFalse);
      expect(back.transformTrack.rotation.keys.keys, [0]);
      await tester.pump(const Duration(minutes: 1));
      await stopTheWarmer(tester, s);
    });

    testWidgets('🎯③ a row scaled unevenly under a paper turned 30° would '
        'shear it: the cel takes the picture where the row shows it, IN '
        'PLACE, the row\'s transform as it was — and ONE undo gives the '
        'picture and the reference back (F-374-Q7)', (tester) async {
      final (s, row) = await placed(tester);
      posed(s, row, track: squashed, fx: turnedOnce);
      expect(wayOf(s, row), bakes);
      final cel = rowOf(s, row).frames.single.id;

      expect(
        await tester.runAsync(
          () => s.importDoors.bakeReferenceAsSeen(
            cutId: s.requireActiveCut.id,
            layerId: row.id,
          ),
        ),
        isTrue,
      );

      final baked = rowOf(s, row);
      expect(baked.mediaReference, isNull);
      expect(baked.frames.single.id, cel, reason: 'the same cel, in place');
      expect(baked.transformTrack, squashed);
      // 100×60 turned 30° about (1170, 827): 116.6 × 102 across.
      final ink = shown(s, baked)!;
      expect(ink.left, closeTo(1111.7, 1.5));
      expect(ink.top, closeTo(776, 1.5));
      expect(ink.right, closeTo(1228.3, 1.5));
      expect(ink.bottom, closeTo(878, 1.5));
      final surface = celOf(s, baked, 0);
      expect(colourAt(surface, 1170, 827), [255, 0, 0, 255]);
      expect(
        (colourAt(surface, 1121, 798) ?? const [0, 0, 0, 0])[3],
        0,
        reason: 'where the corner was laid, nothing now',
      );

      s.undo();
      expect(rowOf(s, row).mediaReference, isNotNull);
      expect(shown(s, row), const ui.Rect.fromLTRB(1120, 797, 1220, 857));
      await tester.pump(const Duration(minutes: 1));
      await stopTheWarmer(tester, s);
    });

    testWidgets('a row changed while its cels are drawn is left as it is now '
        '— the bake takes nothing', (tester) async {
      final (s, row) = await placed(tester);
      posed(s, row, track: squashed, fx: turnedOnce);
      final turnedTwice = TransformTrack.empty().copyWith(
        rotation: PropertyTrack<double>().withKey(0, 60),
      );

      final baked = await tester.runAsync(() {
        final bake = s.importDoors.bakeReferenceAsSeen(
          cutId: s.requireActiveCut.id,
          layerId: row.id,
        );
        // Lands while the cels are being drawn.
        posed(s, row, fx: turnedTwice);
        return bake;
      });

      expect(baked, isFalse);
      final now = rowOf(s, row);
      expect(now.mediaReference!.fx, turnedTwice);
      expect(shown(s, now), const ui.Rect.fromLTRB(1120, 797, 1220, 857));
      await tester.pump(const Duration(minutes: 1));
      await stopTheWarmer(tester, s);
    });

    testWidgets('② an attach row stands where its base puts it: its cel '
        'takes the picture where it shows, half its size', (tester) async {
      final (s, row) = await placed(tester);
      attachToTheDrawing(s, row);
      posed(s, row, fx: halved);
      expect(wayOf(s, row), bakes);

      await tester.runAsync(
        () => s.importDoors.bakeReferenceAsSeen(
          cutId: s.requireActiveCut.id,
          layerId: row.id,
        ),
      );

      final baked = rowOf(s, row);
      expect(baked.mediaReference, isNull);
      expect(isAttachedLayer(baked), isTrue);
      expect(
        inkOf(celOf(s, baked, 0)),
        const ui.Rect.fromLTRB(1145, 812, 1195, 842),
      );
      await tester.pump(const Duration(minutes: 1));
      await stopTheWarmer(tester, s);
    });

    testWidgets('a paper bigger than the canvas bakes where it shows — the '
        'part the pasteboard holds as well', (tester) async {
      final (s, row) = await placed(tester, width: 2400, height: 1700);
      expect(
        shown(s, row)!.topLeft,
        const ui.Offset(-30, -23),
        reason: 'the premise: laid 1:1, its overflow on the pasteboard',
      );
      attachToTheDrawing(s, row);
      posed(s, row, fx: halved);

      await tester.runAsync(
        () => s.importDoors.bakeReferenceAsSeen(
          cutId: s.requireActiveCut.id,
          layerId: row.id,
        ),
      );

      final baked = rowOf(s, row);
      expect(baked.mediaReference, isNull);
      expect(shown(s, baked), const ui.Rect.fromLTRB(570, 402, 1770, 1252));
      await tester.pump(const Duration(minutes: 1));
      await stopTheWarmer(tester, s);
    });

    testWidgets('a still that MOVES on a row whose transform cannot carry '
        'it waits — no rasterize leaves it anything but the reference it '
        'is (F-374-Q9)', (tester) async {
      final (s, row) = await placed(tester);
      posed(
        s,
        row,
        track: squashed,
        fx: TransformTrack.empty().copyWith(
          rotation: PropertyTrack<double>().withKey(0, 30).withKey(12, 60),
        ),
      );
      final before = rowOf(s, row);
      expect(wayOf(s, row), isA<ReferenceMoveWaits>());

      s.editingCanvas.rasterizeLayerReferences([row.id]);
      expect(
        await tester.runAsync(
          () => s.importDoors.bakeReferenceAsSeen(
            cutId: s.requireActiveCut.id,
            layerId: row.id,
          ),
        ),
        isFalse,
      );

      expect(rowOf(s, row), before);
      expect(shown(s, row), const ui.Rect.fromLTRB(1120, 797, 1220, 857));
      await tester.pump(const Duration(minutes: 1));
      await stopTheWarmer(tester, s);
    });

    testWidgets('🎯a 겸용 copy: rasterizing one use rasterizes every use of '
        'its cel — each keeps the picture where it showed it, the switch '
        'they share comes on and the keys the copy kept while it was off '
        'give way — and ONE undo gives both back (F-374-Q10)', (tester) async {
      final (s, row) = await placed(tester);
      final copy = s.cutCommandCoordinator.linkDuplicateLayer(
        cutId: s.requireActiveCut.id,
        layerId: row.id,
        insertionIndex: 0,
      );
      s.effectsAndFx.setLayerTransformFx(row.id, enabled: false);
      expect(
        s.layerById(copy)!.transformEnabled,
        isFalse,
        reason: 'the premise: one switch for both',
      );
      posed(
        s,
        row,
        fx: TransformTrack.empty().copyWith(
          position: PropertyTrack<CanvasPoint>().withKey(
            0,
            CanvasPoint(x: 1200, y: 827),
          ),
        ),
      );
      posed(
        s,
        s.layerById(copy)!,
        track: TransformTrack.empty().copyWith(
          rotation: PropertyTrack<double>().withKey(0, 45),
        ),
      );
      final before = [rowOf(s, row), s.layerById(copy)!];

      s.editingCanvas.rasterizeLayerReferences([row.id]);

      final baked = rowOf(s, row);
      final bakedCopy = s.layerById(copy)!;
      expect([baked.mediaReference, bakedCopy.mediaReference], [null, null]);
      expect([baked.transformEnabled, bakedCopy.transformEnabled], [
        true,
        true,
      ]);
      expect(
        baked.transformTrack.position.keys.map(
          (frame, key) => MapEntry(frame, key.value),
        ),
        {0: CanvasPoint(x: 1200, y: 827)},
      );
      expect(
        bakedCopy.transformTrack.isEmpty,
        isTrue,
        reason: 'the copy showed the picture where it is laid',
      );
      expect(
        shown(s, bakedCopy),
        const ui.Rect.fromLTRB(1120, 797, 1220, 857),
        reason: 'the one cel, as the file was laid on it',
      );

      s.undo();
      expect([rowOf(s, row), s.layerById(copy)!], before);
      await tester.pump(const Duration(minutes: 1));
      await stopTheWarmer(tester, s);
    });

    testWidgets('🎯a 겸용 copy its transform cannot carry the move of: the '
        'one cel takes the picture where both uses show it, and both let '
        'go — where they show it apart, both wait (F-374-Q10: 「쓰임마다 참조 '
        'fx 가 다르면 한 셀에 담을 수 없어, 그때는 막힙니다」)', (tester) async {
      final (s, row) = await placed(tester);
      final copy = s.cutCommandCoordinator.linkDuplicateLayer(
        cutId: s.requireActiveCut.id,
        layerId: row.id,
        insertionIndex: 0,
      );
      posed(s, s.layerById(copy)!, track: squashed, fx: turnedOnce);
      expect(
        wayOf(s, row),
        isA<ReferenceMoveWaits>().having(
          (way) => way.why,
          'why',
          ReferenceWait.usesApart,
        ),
        reason: 'the row shows the picture where it is laid',
      );

      posed(s, row, fx: turnedOnce);
      expect(wayOf(s, row), bakes);
      expect(
        await tester.runAsync(
          () => s.importDoors.bakeReferenceAsSeen(
            cutId: s.requireActiveCut.id,
            layerId: row.id,
          ),
        ),
        isTrue,
      );

      final bakedCopy = s.layerById(copy)!;
      expect([rowOf(s, row).mediaReference, bakedCopy.mediaReference], [
        null,
        null,
      ]);
      expect(bakedCopy.transformTrack, squashed);
      // 100×60 turned 30° about (1170, 827): 116.6 × 102 across.
      final ink = shown(s, bakedCopy)!;
      expect(ink.left, closeTo(1111.7, 1.5));
      expect(ink.bottom, closeTo(878, 1.5));

      s.undo();
      expect(rowOf(s, row).mediaReference, isNotNull);
      expect(s.layerById(copy)!.mediaReference, isNotNull);
      await tester.pump(const Duration(minutes: 1));
      await stopTheWarmer(tester, s);
    });
  });

  group('a movie', () {
    late Directory tempDir;
    late String moviePath;
    late String otherPath;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('anicel-i68-movie');
      moviePath = '${tempDir.path}${Platform.pathSeparator}take3.mov';
      otherPath = '${tempDir.path}${Platform.pathSeparator}take4.mov';
      await File(moviePath).writeAsBytes(const [0, 0, 0, 24]);
      await File(otherPath).writeAsBytes(const [0, 0, 0, 24]);
    });

    tearDown(() async {
      debugVideoDecodeBackend = null;
      deleteTempQuietly(tempDir);
    });

    /// A 64×36 take of [fps] placed 1:1 as a reference on the default
    /// canvas, the warmer held so what is decoded is the test's asking.
    Future<(EditorSessionManager, Layer, FakeVideoBackend)> placed(
      WidgetTester tester, {
      int fps = 24,
    }) async {
      final fake = FakeVideoBackend(frameCount: 24, fpsNumerator: fps);
      debugVideoDecodeBackend = fake;
      final s = EditorSessionManager(
        initialProject: createDefaultProject(),
        audioConformStore: soundConformStore(),
      );
      addTearDown(s.dispose);
      s.playbackRig.prerenderScheduler.beginInputHold();
      await tester.runAsync(
        () => s.importDoors.importVideoFile(
          path: moviePath,
          settings: const ImportFileSettings(
            mode: ImportFileMode.reference,
            movieParts: MovieParts.picture,
            fit: MediaFitMode.none,
          ),
        ),
      );
      return (s, s.requireActiveCut.layers.firstWhere(isMovieReference), fake);
    }

    Future<ui.Rect?> shownAt(
      WidgetTester tester,
      EditorSessionManager s,
      Layer row,
    ) async {
      await tester.runAsync(
        () => s.movieCels
            .hydrate(s.requireActiveCut, 0)
            .timeout(const Duration(seconds: 30)),
      );
      final layer = s.layerById(row.id)!;
      return inkOf(
        s.renderCaches.brushSurfaceForLayerFrame(
          layer,
          resolveExposedFrameAt(layer, 0)!,
        ),
      );
    }

    testWidgets('🎯the canvas grows, and the movie stays among the drawings '
        '— it is not fitted to the middle of the new canvas at the next '
        'decode', (tester) async {
      final (s, row, _) = await placed(tester);
      expect(
        await shownAt(tester, s, row),
        const ui.Rect.fromLTRB(1138, 809, 1202, 845),
      );

      // On the real clock: the session asks for the frame it shows as the
      // edit lands, and a decode begun on the test's clock never ends.
      await tester.runAsync(() async {
        s.cutVerbs.resizeActiveCutCanvas(
          const CanvasSize(width: 2940, height: 1654),
          anchor: CanvasResizeAnchor.centerLeft,
        );
      });

      expect(
        await shownAt(tester, s, row),
        const ui.Rect.fromLTRB(1138, 809, 1202, 845),
      );
      await tester.pumpAndSettle();
    });

    testWidgets('a canvas that keeps its size but moves the picture moves '
        'the movie too — decoded again where it stands now', (tester) async {
      final (s, row, _) = await placed(tester);
      await shownAt(tester, s, row);

      await tester.runAsync(() async {
        s.cutVerbs.placeActiveCutCanvas(
          const CanvasSize(width: 2340, height: 1654),
          contentOffset: (dx: 100, dy: -50),
        );
      });

      expect(
        await shownAt(tester, s, row),
        const ui.Rect.fromLTRB(1238, 759, 1302, 795),
      );
      await tester.pumpAndSettle();
    });

    /// [row]'s reference fx keyed where [position] is typed into its
    /// Position lane — on the real clock, as a canvas edit is above.
    Future<void> typed(
      WidgetTester tester,
      EditorSessionManager s,
      Layer row,
      String position,
    ) => tester.runAsync(
      () async => s.laneVerbs.setLaneValueAt(
        row.id,
        referencePositionLaneId,
        0,
        position,
        frameIsGlobal: false,
        description: 'Edit Position',
        scaleLinked: false,
      ),
    );

    Future<bool?> rasterized(
      WidgetTester tester,
      EditorSessionManager s,
      Layer row,
    ) => tester.runAsync(
      () => s.importDoors.rasterizeMovieReference(
        cutId: s.requireActiveCut.id,
        layerId: row.id,
      ),
    );

    /// [row] squashed on its own and turned a quarter by its fx over frames
    /// 0 to 12 of the cut — a move its transform cannot carry.
    void squashedAndTurning(EditorSessionManager s, Layer row) =>
        s.cutCommandCoordinator
          ..updateLayerTransformTrack(
            cutId: s.requireActiveCut.id,
            layerId: row.id,
            transformTrack: squashed,
          )
          ..updateLayerReferenceFx(
            layerId: row.id,
            fx: TransformTrack.empty().copyWith(
              rotation: PropertyTrack<double>().withKey(0, 0).withKey(12, 90),
            ),
          );

    /// Where [row]'s cel at [frame] of the cut holds ink.
    ui.Rect? inkAt(EditorSessionManager s, Layer row, int frame) => inkOf(
      s.renderCaches.brushSurfaceForLayerFrame(
        row,
        resolveExposedFrameAt(row, frame)!,
      ),
    );

    /// Turned a quarter about where the 64×36 take is laid.
    const turnedAQuarter = ui.Rect.fromLTRB(1152, 795, 1188, 859);

    testWidgets('its reference fx standing somewhere else decodes nothing '
        'again — the frame stays where the movie is laid, and the canvas '
        'moves it there (F-374-Q1)', (tester) async {
      final (s, row, fake) = await placed(tester);
      await shownAt(tester, s, row);
      final asked = fake.asked.length;

      await typed(tester, s, row, '200, 100');

      expect(
        await shownAt(tester, s, row),
        const ui.Rect.fromLTRB(1138, 809, 1202, 845),
      );
      expect(fake.asked.length, asked, reason: '「굳이 다시 그릴필요도없고」');
      // Where the installed picture was laid — what the editing canvas
      // moves it from.
      final layer = s.layerById(row.id)!;
      expect(
        s.movieCels.laidAt(
          s.brushFrameKeyForCut(
            s.requireActiveCut,
            row.id,
            resolveExposedFrameAt(layer, 0)!.id,
          ),
        ),
        TransformPose(center: CanvasPoint(x: 1170, y: 827)),
      );
      expect(
        layerPlacementAt(
          cut: s.requireActiveCut,
          layer: layer,
          frameIndex: 0,
        )!.apply(CanvasPoint(x: 1138, y: 809)),
        CanvasPoint(x: 168, y: 82),
      );
      await tester.pumpAndSettle();
    });

    testWidgets('a movie swapped in is the one decoded — the cel keeps its '
        'key, and a picture of the other movie is not what it shows',
        (tester) async {
      final (s, row, fake) = await placed(tester);
      await shownAt(tester, s, row);

      expect(
        await tester.runAsync(
          () => s.importDoors.swapReference(layerId: row.id, path: otherPath),
        ),
        isA<ReferenceLaid>(),
      );
      final asked = fake.asked.length;
      await shownAt(tester, s, row);

      expect(
        fake.openedAt.map((opened) => opened.path),
        contains(normalizedMediaPath(otherPath)),
      );
      expect(
        fake.asked.length,
        greaterThan(asked),
        reason: 'the frame is decoded from the movie the row shows now',
      );
      await tester.pumpAndSettle();
    });

    testWidgets('rasterizing bakes the frames where the movie is laid, and '
        'its reference fx\'s move becomes the row\'s own keys — the picture '
        'where it stood (F-374-Q3), one undo for both', (tester) async {
      final (s, row, _) = await placed(tester);
      await typed(tester, s, row, '200, 100');

      await rasterized(tester, s, row);

      final baked = s.layerById(row.id)!;
      expect(baked.mediaReference, isNull);
      expect(inkAt(s, baked, 0), const ui.Rect.fromLTRB(1138, 809, 1202, 845));
      expect(
        baked.transformTrack.position.keys.map(
          (frame, key) => MapEntry(frame, key.value),
        ),
        {0: CanvasPoint(x: 200, y: 100)},
      );
      expect(
        layerPlacementAt(
          cut: s.requireActiveCut,
          layer: baked,
          frameIndex: 0,
        )!.apply(CanvasPoint(x: 1138, y: 809)),
        CanvasPoint(x: 168, y: 82),
      );

      s.undo();
      expect(s.layerById(row.id)!.mediaReference, isNotNull);
      expect(s.layerById(row.id)!.transformTrack.isEmpty, isTrue);
      await tester.pump(const Duration(minutes: 1));
      await stopTheWarmer(tester, s);
    });

    testWidgets('🎯③ a movie its row\'s transform cannot carry the move of '
        'bakes each frame where its reference fx stands it there — a cel '
        'apiece as it turns, the row\'s transform as it was (F-374-Q7 · '
        '「움직이는 참조는 움직이는 프레임마다 한 장」)', (tester) async {
      final (s, row, _) = await placed(tester);
      squashedAndTurning(s, row);
      expect(
        await tester.runAsync(
          () => s.importDoors.bakeReferenceAsSeen(
            cutId: s.requireActiveCut.id,
            layerId: row.id,
          ),
        ),
        isFalse,
        reason: 'a movie\'s frames are decoded, not its one cel moved',
      );

      expect(await rasterized(tester, s, row), isTrue);

      final baked = s.layerById(row.id)!;
      expect(baked.mediaReference, isNull);
      expect(baked.transformTrack, squashed);
      expect(inkAt(s, baked, 0), const ui.Rect.fromLTRB(1138, 809, 1202, 845));
      expect(inkAt(s, baked, 12), turnedAQuarter);
      await tester.pump(const Duration(minutes: 1));
      await stopTheWarmer(tester, s);
    });

    testWidgets('a movie trimmed at its head, slower than the cut: each '
        'position stands where the fx stands it on ITS frame of the cut — a '
        'cel wherever the movie or the move changes, the block where it '
        'was', (tester) async {
      final (s, row, _) = await placed(tester, fps: 8);
      s.activeCutControllers.timelineController.shiftExposureEdge(
        layerId: row.id,
        blockStartIndex: 0,
        edge: TimelineBlockEdge.start,
        delta: 6,
      );
      squashedAndTurning(s, row);

      expect(await rasterized(tester, s, row), isTrue);

      final baked = s.layerById(row.id)!;
      expect(baked.timeline.firstKey(), 6, reason: 'where the trim left it');
      FrameId celAt(int frame) => resolveExposedFrameAt(baked, frame)!.id;
      expect(
        celAt(7),
        isNot(celAt(6)),
        reason: 'one picture of the movie, turned on',
      );
      expect(
        celAt(13),
        celAt(12),
        reason: 'neither the movie nor the move changes',
      );
      expect(inkAt(s, baked, 12), turnedAQuarter);
      await tester.pump(const Duration(minutes: 1));
      await stopTheWarmer(tester, s);
    });

    testWidgets('🎯a movie whose cel another use shows is rasterized with it '
        '— both expose ONE bank of cels, a cel for each picture of the movie '
        'they show, and one undo gives both back (F-374-Q10)', (
      tester,
    ) async {
      final (s, row, _) = await placed(tester);
      final copy = s.cutCommandCoordinator.linkDuplicateLayer(
        cutId: s.requireActiveCut.id,
        layerId: row.id,
        insertionIndex: 0,
      );
      final before = [s.layerById(row.id)!, s.layerById(copy)!];

      expect(await rasterized(tester, s, row), isTrue);

      final baked = s.layerById(row.id)!;
      final bakedCopy = s.layerById(copy)!;
      expect([baked.mediaReference, bakedCopy.mediaReference], [null, null]);
      expect(bakedCopy.frames, baked.frames);
      expect(
        baked.frames,
        hasLength(drawingBlocks(before.first.timeline).single.length),
        reason: 'a cel a position, as the row alone takes — not one more',
      );
      expect(
        bakedCopy.timeline,
        baked.timeline,
        reason: 'the same pictures, the same cels',
      );

      s.undo();
      expect([s.layerById(row.id)!, s.layerById(copy)!], before);
      await tester.pump(const Duration(minutes: 1));
      await stopTheWarmer(tester, s);
    });

    testWidgets('a movie\'s uses each take their own way: the copy its '
        'transform cannot carry shows its frames where its fx turns them, '
        'in cels of its own — and a picture both show is one cel '
        '(F-374-Q10)', (tester) async {
      final (s, row, _) = await placed(tester);
      final copy = s.cutCommandCoordinator.linkDuplicateLayer(
        cutId: s.requireActiveCut.id,
        layerId: row.id,
        insertionIndex: 0,
      );
      squashedAndTurning(s, s.layerById(copy)!);

      expect(await rasterized(tester, s, row), isTrue);

      final baked = s.layerById(row.id)!;
      final bakedCopy = s.layerById(copy)!;
      FrameId celAt(Layer layer, int frame) =>
          resolveExposedFrameAt(layer, frame)!.id;
      expect(bakedCopy.frames, baked.frames, reason: 'one bank');
      expect(
        celAt(bakedCopy, 0),
        celAt(baked, 0),
        reason: 'not turned yet: the picture the row shows there',
      );
      expect(celAt(bakedCopy, 12), isNot(celAt(baked, 12)));
      expect(inkAt(s, bakedCopy, 12), turnedAQuarter);
      expect(inkAt(s, baked, 12), const ui.Rect.fromLTRB(1138, 809, 1202, 845));
      expect(bakedCopy.transformTrack, squashed);
      await tester.pump(const Duration(minutes: 1));
      await stopTheWarmer(tester, s);
    });

    testWidgets('a movie row changed while its file is opened is left as it '
        'is now — nothing is rasterized', (tester) async {
      final (s, row, _) = await placed(tester);
      final moved = TransformTrack.empty().copyWith(
        position: PropertyTrack<CanvasPoint>().withKey(
          0,
          CanvasPoint(x: 200, y: 100),
        ),
      );

      final answer = await tester.runAsync(() {
        final rasterize = s.importDoors.rasterizeMovieReference(
          cutId: s.requireActiveCut.id,
          layerId: row.id,
        );
        // Lands while the movie is being opened.
        s.cutCommandCoordinator.updateLayerReferenceFx(
          layerId: row.id,
          fx: moved,
        );
        return rasterize;
      });

      expect(answer, isFalse);
      final now = s.layerById(row.id)!;
      expect(now.mediaReference!.fx, moved);
      expect(now.frames, row.frames);
      await tester.pump(const Duration(minutes: 1));
      await stopTheWarmer(tester, s);
    });
  });

  group('a PDF\'s pages', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('anicel-i68-pdf');
    });

    tearDown(() {
      PdfRenderService.debugResetForTests();
      deleteTempQuietly(tempDir);
    });

    /// [pdf]'s pages from [inFrame] to [outFrame] placed as a reference on
    /// a 200×100 canvas, contained: a 100×50 first page stands at twice its
    /// size, every page laid 1:1 in the canvas's middle.
    Future<(EditorSessionManager, Layer)> placed(
      WidgetTester tester,
      FakePdfDocument pdf, {
      int inFrame = 0,
      int? outFrame,
    }) async {
      PdfRenderService.debugOpenerOverride = (_) async => pdf;
      final s = EditorSessionManager(initialProject: createDefaultProject());
      addTearDown(s.dispose);
      s.playbackRig.prerenderScheduler.beginInputHold();
      await tester.runAsync(() async {
        s.cutVerbs.resizeActiveCutCanvas(
          const CanvasSize(width: 200, height: 100),
        );
        final path = '${tempDir.path}${Platform.pathSeparator}conte.pdf';
        await File(path).writeAsBytes(const [0x25, 0x50, 0x44, 0x46]);
        expect(
          await s.importDoors.importPdfFile(
            path: path,
            destination: ImportDestination.activeCutLayer,
            copyIntoProject: false,
            inFrame: inFrame,
            outFrame: outFrame,
          ),
          isTrue,
        );
      });
      final row = s.requireActiveCut.layers.firstWhere(
        (layer) => layer.mediaReference != null,
      );
      return (s, row);
    }

    testWidgets('🎯every page of a reference stands at ITS pose over the '
        'page\'s own size — a bigger page stands bigger, not fitted again — '
        'each laid 1:1, rendered once at its own size (F-374-Q5)',
        (tester) async {
      final pdf = FakePdfDocument(
        pageSizes: const [ui.Size(100, 50), ui.Size(200, 100)],
      );
      final (s, row) = await placed(tester, pdf);

      expect(
        row.mediaReference!.pose,
        TransformPose.uniform(center: CanvasPoint(x: 100, y: 50), zoom: 2),
      );
      expect(
        row.mediaReference!.pictureSize,
        const CanvasSize(width: 100, height: 50),
      );
      expect(inkOf(celOf(s, row, 0)), const ui.Rect.fromLTRB(50, 25, 150, 75));
      expect(inkOf(celOf(s, row, 1)), const ui.Rect.fromLTRB(0, 0, 200, 100));
      expect(
        [for (final (_, width, height) in pdf.renderRequests) (width, height)],
        [(100, 50), (200, 100)],
        reason: 'the vector source rasters once, at the page\'s own size',
      );
      final placement = layerPlacementAt(
        cut: s.requireActiveCut,
        layer: s.layerById(row.id)!,
        frameIndex: 1,
      )!;
      expect(
        [
          placement.apply(CanvasPoint(x: 0, y: 0)),
          placement.apply(CanvasPoint(x: 200, y: 100)),
        ],
        [CanvasPoint(x: -100, y: -50), CanvasPoint(x: 300, y: 150)],
        reason: 'the reference\'s pose over a 200×100 page — twice its own '
            'size, not fitted to the canvas again',
      );
      await stopTheWarmer(tester, s);
    });

    testWidgets('🎯placing renders EACH page from its own page of the file — '
        'counted from the span\'s IN, not from the row\'s first cel — each '
        'at its own size, and lets each render go once laid', (tester) async {
      final pdf = FakePdfDocument(
        pageSizes: const [ui.Size(100, 50), ui.Size(100, 50), ui.Size(60, 30)],
      );
      final (s, row) = await placed(tester, pdf, inFrame: 1);

      expect([for (final frame in row.frames) frame.filePicture], [1, 2]);
      expect(
        pdf.renderRequests,
        [(1, 100, 50), (2, 60, 30)],
        reason: 'each page once, at its own size',
      );
      for (final (index, ink) in [
        (0, const ui.Rect.fromLTRB(50, 25, 150, 75)),
        (1, const ui.Rect.fromLTRB(70, 35, 130, 65)),
      ]) {
        final cel = celOf(s, row, index);
        expect(inkOf(cel), ink);
        expect(
          colourAt(cel, 100, 50),
          rgbaOf(FakePdfDocument.pageColor(index + 1)),
          reason: 'cel $index is page ${index + 1}',
        );
      }
      expect(
        row.mediaReference!.pictureSize,
        const CanvasSize(width: 100, height: 50),
        reason: 'the size the row says is its first cel\'s page',
      );
      expect(
        pdf.renders.where((image) => !image.debugDisposed),
        isEmpty,
        reason: 'a page rendered for the placing is let go of once laid',
      );
      await stopTheWarmer(tester, s);
    });

    testWidgets('one page kept from the middle is a still that says WHICH '
        'page it is — and that page is the one laid', (tester) async {
      final pdf = FakePdfDocument(
        pageSizes: const [ui.Size(100, 50), ui.Size(100, 50), ui.Size(100, 50)],
      );
      final (s, row) = await placed(tester, pdf, inFrame: 2, outFrame: 2);

      expect(row.frames.single.filePicture, 2);
      expect(pdf.renderRequests, [(2, 100, 50)]);
      expect(
        colourAt(celOf(s, row, 0), 100, 50),
        rgbaOf(FakePdfDocument.pageColor(2)),
      );
      await stopTheWarmer(tester, s);
    });
  });

  // I-68 「가」 (유저 2026-10-10): each cel of a GIF says which picture of the
  // file it is — the picture a one-frame still takes of a file swapped in.
  // ↩️Its frames were laid again by it where the fx stood still, until
  // F-374-Q1.
  group('a GIF\'s frames', () {
    late Directory tempDir;
    const white = [255, 255, 255, 255];
    const black = [0, 0, 0, 255];

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('anicel-i68-gif');
    });

    tearDown(() => deleteTempQuietly(tempDir));

    /// The black · white · black GIF from its second frame to [outFrame],
    /// contained as a reference on a 100×100 canvas: to its end, two cels
    /// — white, then black — each its 1×1 picture laid 1:1 at pixel
    /// (50, 50), the pose filling the canvas with it.
    Future<(EditorSessionManager, Layer)> placed(
      WidgetTester tester, {
      int? outFrame,
    }) async {
      final s = EditorSessionManager(initialProject: createDefaultProject());
      addTearDown(s.dispose);
      s.playbackRig.prerenderScheduler.beginInputHold();
      await tester.runAsync(() async {
        s.cutVerbs.resizeActiveCutCanvas(
          const CanvasSize(width: 100, height: 100),
        );
        expect(
          await s.importDoors.importImageFile(
            path: await writeThreeFrameGif(tempDir, 'walk.gif'),
            destination: ImportDestination.activeCutLayer,
            copyIntoProject: false,
            inFrame: 1,
            outFrame: outFrame,
          ),
          isTrue,
        );
      });
      final row = s.requireActiveCut.layers.firstWhere(
        (layer) => layer.mediaReference != null,
      );
      return (s, row);
    }

    testWidgets('🎯each cel says which picture of the FILE it is — from the '
        'span\'s IN — so the row has the reference fx', (tester) async {
      final (s, row) = await placed(tester);

      expect([for (final frame in row.frames) frame.filePicture], [1, 2]);
      for (final (index, colour) in [(0, white), (1, black)]) {
        final cel = celOf(s, row, index);
        expect(inkOf(cel), const ui.Rect.fromLTRB(50, 50, 51, 51));
        expect(colourAt(cel, 50, 50), colour, reason: 'cel $index');
      }
      expect(
        timelineLanesForLayer(
          layer: row,
          session: s,
          expandedGroupKeys: const {},
        ).first.laneId,
        referenceGroupLaneId,
      );
      await stopTheWarmer(tester, s);
    });

    testWidgets('one frame kept is a still that says WHICH frame it is — '
        'the white one', (tester) async {
      final (s, row) = await placed(tester, outFrame: 1);

      expect(row.frames.single.filePicture, 1);
      final cel = celOf(s, row, 0);
      expect(inkOf(cel), const ui.Rect.fromLTRB(50, 50, 51, 51));
      expect(colourAt(cel, 50, 50), white);
      await stopTheWarmer(tester, s);
    });

    // ⓐ (유저 2026-10-10 「추천대로가자」): a swap keeps the picture's number
    // — the file is all that changes (as laying the file again did, until
    // F-374-Q1).
    testWidgets('🎯a still that is one frame takes the SAME frame of a file '
        'swapped in — another GIF\'s 2nd, not its 1st — and a file with no '
        'such frame is not taken: the answer names the one it lacks',
        (tester) async {
      final (s, row) = await placed(tester, outFrame: 1);
      final files = (await tester.runAsync(
        () async => (
          // red · blue · red
          gif: await writeThreeFrameGif(
            tempDir,
            'other.gif',
            colours: const [0xFF0000, 0x0000FF],
          ),
          png: await writeSolidPng(
            tempDir,
            'bg.png',
            width: 1,
            height: 1,
            rgba: 0x00FF00FF,
          ),
        ),
      ))!;

      expect(
        await tester.runAsync(
          () => s.importDoors.swapReference(layerId: row.id, path: files.png),
        ),
        lacks(1),
      );
      expect(s.layerById(row.id), row, reason: 'nothing changed');

      expect(
        await tester.runAsync(
          () => s.importDoors.swapReference(layerId: row.id, path: files.gif),
        ),
        isA<ReferenceLaid>(),
      );
      expect(
        colourAt(celOf(s, row, 0), 50, 50),
        [0, 0, 255, 255],
        reason: 'its 2nd frame, blue — not its 1st, red',
      );
      await tester.pump(const Duration(minutes: 1));
      await stopTheWarmer(tester, s);
    });

    testWidgets('rasterizing lets go of which picture each cel was, with the '
        'file — its undo gives both back, its redo takes them again',
        (tester) async {
      final (s, row) = await placed(tester);
      List<int?> pictures() => [
        for (final frame in s.layerById(row.id)!.frames) frame.filePicture,
      ];

      s.editingCanvas.rasterizeLayerReferences([row.id]);
      expect(s.layerById(row.id)!.mediaReference, isNull);
      expect(pictures(), [null, null]);

      s.undo();
      expect(s.layerById(row.id)!.mediaReference, isNotNull);
      expect(pictures(), [1, 2]);
      expect(referenceRedrawFor(s.layerById(row.id)!), ReferenceSwap.pictures);

      s.redo();
      expect(pictures(), [null, null]);
      await tester.pump(const Duration(minutes: 1));
      await stopTheWarmer(tester, s);
    });
  });
}
