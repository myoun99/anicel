import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/bitmap_tile.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/export_format_selection.dart';
import 'package:anicel/src/models/export_spec.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/import/import_warning.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_blend_mode.dart';
import 'package:anicel/src/models/layer_effect.dart';
import 'package:anicel/src/models/layer_folder.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_section_defaults.dart';
import 'package:anicel/src/models/media_asset.dart' show MediaFitMode;
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/tile_coord.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/models/transform_track.dart';
import 'package:anicel/src/services/editing/default_cut_helpers.dart';
import 'package:anicel/src/services/import/media_import_planner.dart'
    show ImportIdMint;
import 'package:anicel/src/services/import/psd_layer_plan.dart';
import 'package:anicel/src/services/persistence/app_export_settings.dart';
import 'package:anicel/src/services/photoshop/psd_reader.dart';
import 'package:anicel/src/ui/canvas/layer_blend_shader.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/export/export_dialog.dart';
import 'package:anicel/src/ui/export/export_format_availability.dart';
import 'package:anicel/src/ui/export/export_frame_renderer.dart';
import 'package:anicel/src/ui/export/export_plan.dart';
import 'package:anicel/src/ui/export/frame_image_file.dart';
import 'package:anicel/src/ui/text/app_strings.dart';

import '../../helpers/export_format_pick.dart';
import '../../helpers/export_preview_probe.dart';
import '../../helpers/project_scratch_folder.dart';
import '../../helpers/temp_dir.dart';

/// The Image tab's frame written as a Photoshop document keeps the cut's
/// rows — 🗣️I-117-Q2 (유저 2026-10-22): 「층을 지키고 그 효과는 뺀다」: a
/// folder a folder of the file, 통과 kept 통과; each row's strength, blend
/// and eye in its own fields, its effects and its pose in its picture; a
/// hidden row kept, hidden; the ground one row at the bottom; an adjustment
/// a row of no picture under its name; a folder's effects left out — and
/// once the file is written, what it left out said, 「PSD 를 읽을 때 못 담은
/// 것을 알리듯이」. Its picture is the one its rows lay up: the cut's without
/// what no row of it holds — the cost the answer was chosen at.
void main() {
  const size = CanvasSize(width: 8, height: 8);

  // A row in multiply is composed over its backdrop in the shader.
  setUpAll(LayerBlendShader.load);

  const cutId = CutId('cut');
  const black = [0, 0, 0, 255];
  const blue = [10, 20, 220, 255];
  const red = [220, 20, 10, 255];
  const green = [10, 200, 30, 255];

  setUp(() => AppExport.settings.value = AppExportSettings());
  tearDown(() => AppExport.settings.value = AppExportSettings());

  /// A picture of the canvas's size holding [paint] alone: each (x, y) →
  /// its RGBA.
  Uint8List only(Map<(int, int), List<int>> paint) {
    final pixels = Uint8List(size.width * size.height * 4);
    for (final MapEntry(key: (x, y), value: rgba) in paint.entries) {
      pixels.setAll((y * size.width + x) * 4, rgba);
    }
    return pixels;
  }

  /// A drawing row named [id] in capitals, its one cel shown at frame 0.
  Layer drawn(
    String id, {
    String? folder,
    double opacity = 1,
    LayerBlendMode blendMode = LayerBlendMode.normal,
    bool visible = true,
  }) => Layer(
    id: LayerId(id),
    name: id.toUpperCase(),
    frames: [Frame(id: FrameId('$id-1'), duration: 1, strokes: const [])],
    timeline: {0: TimelineExposure.drawing(FrameId('$id-1'), length: 1)},
    folderId: folder == null ? null : LayerId(folder),
    opacity: opacity,
    blendMode: blendMode,
    isVisible: visible,
  );

  LayerEffect brighter() => LayerEffect(
    id: const EffectId('brighter'),
    kind: EffectKind.brightnessContrast,
    parameters: {'brightness': EffectParameter(value: 60)},
  );

  /// The cut's rows, bottom-up: 「A」; the folder 「F」 — 통과, at half —
  /// holding 「B」, multiplied at three quarters, and 「C」, hidden; 「FX」, an
  /// adjustment brightening all of it; the folder 「G」 — multiplied,
  /// brightened and hidden — holding 「D」; and the camera's row, which is no
  /// picture's.
  /// [effects] false takes out what no row of a file holds: the
  /// adjustment's filter and 「G」's effect. [posed] brightens 「A」 by an
  /// effect of its own and moves 「F」 one pixel to the right. [clipped]
  /// clips 「C」 to 「B」 and 「F」 to 「A」 (I-92).
  List<Layer> rows({
    required bool effects,
    bool posed = false,
    bool clipped = false,
  }) => [
    drawn('a').copyWith(effects: [if (posed) brighter()]),
    drawn(
      'b',
      folder: 'f',
      opacity: 0.75,
      blendMode: LayerBlendMode.multiply,
    ),
    drawn('c', folder: 'f', visible: false).copyWith(clipsToBelow: clipped),
    createFolderLayer(id: const LayerId('f'), name: 'F').copyWith(
      clipsToBelow: clipped,
      opacity: 0.5,
      transformTrack: posed
          ? TransformTrack(
              keyframes: {
                0: TransformPose(center: CanvasPoint(x: 5, y: 4)),
              },
            )
          : null,
    ),
    createAdjustmentLayer(
      id: const LayerId('fx'),
      name: 'FX',
    ).copyWith(effects: [if (effects) brighter()]),
    drawn('d', folder: 'g'),
    createFolderLayer(id: const LayerId('g'), name: 'G').copyWith(
      blendMode: LayerBlendMode.multiply,
      effects: [if (effects) brighter()],
      isVisible: false,
    ),
    createCameraLayer(cutId: cutId),
  ];

  /// A film of the one cut, its cels drawn: a black dot on 「A」, a blue one
  /// on 「B」, a red one on 「C」, a green one on 「D」 — 「A」's and 「B」's
  /// one over the other.
  EditorSessionManager film({
    bool effects = true,
    bool posed = false,
    bool clipped = false,
  }) {
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
                layers: rows(
                  effects: effects,
                  posed: posed,
                  clipped: clipped,
                ),
              ),
            ],
          ),
        ],
      ),
    );
    addTearDown(session.dispose);
    final cut = session.requireActiveCut;
    for (final (row, dot, rgba) in [
      ('a', (2, 2), black),
      ('b', (2, 2), blue),
      ('c', (3, 3), red),
      ('d', (4, 4), green),
    ]) {
      session.renderCaches.brushFrameStore.storeBakedSurface(
        session.brushFrameKeyForCut(cut, LayerId(row), FrameId('$row-1')),
        BitmapSurface(
          canvasSize: size,
          tileSize: 8,
          tiles: {
            TileCoord(x: 0, y: 0): BitmapTile(size: 8, pixels: only({dot: rgba})),
          },
        ),
      );
    }
    return session;
  }

  ExportFrameTask frameOf(EditorSessionManager session) =>
      ExportFrameTask(cut: session.requireActiveCut, frameIndex: 0);

  ImageExportSpec psdSpec({
    ExportChannels channels = ExportChannels.rgba,
    ExportLayerFx layerFx = ExportLayerFx.on,
  }) => ImageExportSpec(
    format: ExportFormatSelection(
      kind: ExportMediaKind.still,
      stillFormat: ExportStillFormat.psd,
      channels: channels,
    ),
    sizeMode: ExportSizeMode.canvas,
    layerFx: layerFx,
  );

  /// [session]'s frame written as [spec] says — the image tab's own call —
  /// read back, and what it said the file left out.
  Future<(PsdDocument, List<ImportWarning>)> written(
    EditorSessionManager session,
    ImageExportSpec spec,
  ) async {
    final folder = Directory.systemTemp.createTempSync('frame-psd');
    deleteAfterSessionEnds(folder);
    final leftOut = <ImportWarning>[];
    final wrote = await writeFrameImage(session, frameOf(session), spec, (
      directory: folder.path,
      name: 'frame.psd',
      isCancelled: null,
      onProgress: null,
      onLeftOut: leftOut.addAll,
    ));
    expect(wrote, isTrue);
    return (
      readPsdDocument(File('${folder.path}/frame.psd').readAsBytesSync()),
      leftOut,
    );
  }

  /// [read]'s records bottom-up as a reader of the Layers panel says them —
  /// a folder's opening record as `[`, its own row after its contents
  /// with `]` before its name.
  List<String> layout(PsdDocument read) => [
    for (final row in read.layers)
      switch (row.role) {
        PsdLayerRole.groupClose => '[',
        PsdLayerRole.groupOpen =>
          '] ${row.name} ${row.opacity} ${row.blendKey.trim()} '
              '${row.visible ? 'shown' : 'hidden'}',
        PsdLayerRole.raster =>
          '${row.name} ${row.opacity} ${row.blendKey.trim()} '
              '${row.visible ? 'shown' : 'hidden'}',
      },
  ];

  PsdLayer rowNamed(PsdDocument read, String name) => read.layers.singleWhere(
    (row) => row.role == PsdLayerRole.raster && row.name == name,
  );

  Future<Uint8List> straight(ui.Image image) async {
    final data = await image.toByteData(
      format: ui.ImageByteFormat.rawStraightRgba,
    );
    image.dispose();
    return data!.buffer.asUint8List();
  }

  /// [session]'s own frame as the app shows it, on nothing.
  Future<Uint8List> pictureOf(EditorSessionManager session) async =>
      straight(
        await ExportFrameRenderer(
          session: session,
          background: const ui.Color(0x00000000),
        ).renderComposite(frameOf(session), ExportSizeMode.canvas),
      );

  testWidgets('written as a PSD, a frame is the cut\'s rows, bottom-up — a '
      'folder a folder with what is in it, 통과 kept 통과, every row and '
      'folder with its strength, blend and eye; an adjustment a row of no '
      'picture under its name; the camera\'s row, no picture\'s, none', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final (read, _) = await written(film(), psdSpec());

      expect(layout(read), [
        'A 255 norm shown',
        '[',
        'B 191 mul shown',
        'C 255 norm hidden',
        '] F 128 pass shown',
        'FX 255 norm shown',
        '[',
        'D 255 norm shown',
        '] G 255 mul hidden',
      ]);
      final hidden = rowNamed(read, 'C');
      expect((hidden.left, hidden.top, hidden.right, hidden.bottom), (
        3,
        3,
        4,
        4,
      ));
      expect(
        hidden.pixels,
        red,
        reason: 'a hidden row keeps its picture, to be shown in the file',
      );
      expect(
        rowNamed(read, 'B').pixels,
        blue,
        reason: 'at full strength — the three quarters are the file\'s to '
            'apply, as the multiply is',
      );
      expect(
        rowNamed(read, 'FX').pixels,
        isNull,
        reason: 'the adjustment\'s place is kept, and no picture',
      );
    });
  });

  testWidgets('a row and a folder clipped to the layer below are clipped in '
      'the file — and read back in, clipped again (I-92)', (tester) async {
    await tester.runAsync(() async {
      final (read, _) = await written(film(clipped: true), psdSpec());

      expect(
        [
          for (final row in read.layers)
            if (row.role != PsdLayerRole.groupClose) (row.name, row.clipping),
        ],
        [
          ('A', false),
          ('B', false),
          ('C', true),
          ('F', true),
          ('FX', false),
          ('D', false),
          ('G', false),
        ],
      );
      var ids = 0;
      final back = planPsdExpansion(
        document: read,
        displayName: 'frame.psd',
        cutId: const CutId('back'),
        duration: 1,
        canvas: size,
        fit: MediaFitMode.none,
        mint: ImportIdMint(
          nextLayerId: () => LayerId('back-${ids += 1}'),
          nextFrameId: (layer) => FrameId('back-${ids += 1}'),
          nextCutId: () => const CutId('back'),
        ),
        newCut: true,
      );
      expect(
        {for (final layer in back.layers) layer.name: layer.clipsToBelow},
        {
          'A': false,
          'B': false,
          'C': true,
          'F': true,
          'FX': false,
          'D': false,
          'G': false,
        },
      );
    });
  });

  testWidgets('a row\'s effects are in its picture, and its pose — its '
      'folder\'s with it, a hidden member\'s too', (tester) async {
    await tester.runAsync(() async {
      final (read, _) = await written(film(posed: true), psdSpec());

      final lit = rowNamed(read, 'A').pixels!;
      for (var c = 0; c < 3; c += 1) {
        expect(lit[c], closeTo(153, 2), reason: 'black, brightened by 60');
      }
      for (final (name, rgba) in [('B', blue), ('C', red)]) {
        final row = rowNamed(read, name);
        final drawnAt = name == 'B' ? (2, 2) : (3, 3);
        expect(
          (row.left, row.top),
          (drawnAt.$1 + 1, drawnAt.$2),
          reason: '$name: one to the right, as its folder stands',
        );
        expect(row.pixels, rgba, reason: name);
      }
    });
  });

  testWidgets('an RGB frame stands on its ground — the bottom row, under '
      'every row of the cut; an RGBA one has none', (tester) async {
    await tester.runAsync(() async {
      final session = film();
      final (onGround, _) = await written(
        session,
        psdSpec(channels: ExportChannels.rgb),
      );

      final (clear, _) = await written(session, psdSpec());
      expect(layout(onGround), [
        '${AppText.strings.exBackground} 255 norm shown',
        ...layout(clear),
      ]);
      expect(
        rowNamed(onGround, AppText.strings.exBackground).pixels,
        only({
          for (var y = 0; y < size.height; y += 1)
            for (var x = 0; x < size.width; x += 1) (x, y): [255, 255, 255, 255],
        }),
      );
    });
  });

  testWidgets('its picture is the one its rows lay up: the cut\'s without '
      'the adjustment\'s filter and the folder\'s effect, which no row of '
      'the file holds — the PNG of the same frame keeps both', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final session = film();
      final (read, _) = await written(session, psdSpec());
      final unheld = await pictureOf(film(effects: false));
      final asTheAppShowsIt = await pictureOf(session);

      expect(
        asTheAppShowsIt,
        isNot(unheld),
        reason: 'fixture premise: the filter and the effect show',
      );
      expect(read.composite, unheld);
    });
  });

  testWidgets('what the file left out is said as a PSD\'s reader says it — '
      'the adjustment by its kind, the folder by its effects; with the '
      'layer FX off, the adjustment alone; nothing of a PNG', (tester) async {
    await tester.runAsync(() async {
      final session = film();

      expect((await written(session, psdSpec())).$2, [
        unsupportedLayerKind('FX'),
        layerEffectsNotApplied('G'),
      ]);
      expect(
        (await written(session, psdSpec(layerFx: ExportLayerFx.off))).$2,
        [unsupportedLayerKind('FX')],
        reason: 'the folder\'s effect is off for every file then',
      );
      expect(
        ExportFrameRenderer.forFormat(
          session: session,
          format: const ExportFormatSelection(kind: ExportMediaKind.still),
          layerFx: ExportLayerFx.on,
        ).leftOutOfRows(frameOf(session)),
        isEmpty,
      );
    });
  });

  group('in the export window', () {
    late Directory temp;

    setUp(() => temp = Directory.systemTemp.createTempSync('qa-frame-psd'));
    tearDown(() => deleteTempQuietly(temp));

    Future<ExportDialogState> pumpDialog(
      WidgetTester tester,
      EditorSessionManager session,
    ) async {
      await tester.binding.setSurfaceSize(const Size(1280, 720));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      addTearDown(() => tester.pumpWidget(const SizedBox.shrink()));
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ExportDialog(
              session: session,
              exportDirectoryPicker: () async => temp.path,
              formatAvailability: ExportFormatAvailability.permissive(),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey<String>('export-tab-image')));
      await tester.pump();
      return tester.state<ExportDialogState>(find.byType(ExportDialog));
    }

    final notice = find.byKey(const ValueKey<String>('export-left-out-notice'));
    Finder inNotice(String text) =>
        find.descendant(of: notice, matching: find.text(text));

    testWidgets('the Image tab writes the PSD and, once it has, says what the '
        'file left out — each name open, under what was left out of it', (
      tester,
    ) async {
      final state = await pumpDialog(tester, film());
      await pickExportStill(tester, ExportStillFormat.psd);

      await tester.runAsync(state.export);
      await tester.pump();
      await tester.pump();

      final files = temp.listSync().map((file) => file.uri.pathSegments.last);
      expect(files, hasLength(1));
      expect(files.single, endsWith('.psd'));
      expect(
        inNotice(AppText.strings.exLeftOutOfTheFile),
        findsOneWidget,
        reason: 'its own sentence, not the import\'s',
      );
      expect(inNotice('FX'), findsOneWidget);
      expect(inNotice('G'), findsOneWidget);
    });

    testWidgets('queued, it says the same once the queue rests', (
      tester,
    ) async {
      final state = await pumpDialog(tester, film());
      await pickExportStill(tester, ExportStillFormat.psd);
      await tester.tap(
        find.byKey(const ValueKey<String>('export-queue-add-button')),
      );
      await tester.pump();
      await tester.pump();

      await tester.runAsync(state.runQueue);
      await tester.pump();
      await tester.pump();

      expect(inNotice(AppText.strings.exLeftOutOfTheFile), findsOneWidget);
      expect(inNotice('FX'), findsOneWidget);
      expect(inNotice('G'), findsOneWidget);
    });

    testWidgets('a PNG of the same frame says nothing was left out', (
      tester,
    ) async {
      final state = await pumpDialog(tester, film());
      await pickExportStill(tester, ExportStillFormat.png);

      await tester.runAsync(state.export);
      await tester.pump();
      await tester.pump();

      expect(temp.listSync(), hasLength(1));
      expect(notice, findsNothing);
    });

    testWidgets('with PSD picked, the preview is the file\'s picture — '
        'without what no row of it holds', (tester) async {
      final session = film();
      await pumpDialog(tester, session);
      Future<Uint8List> previewed(ExportStillFormat still) async {
        await pickExportStill(tester, still);
        await tester.settleExportPreview();
        final image = tester.exportPreviewImage!;
        expect((image.width, image.height), (size.width, size.height));
        return (await tester.runAsync(() async {
          final data = await image.toByteData(
            format: ui.ImageByteFormat.rawStraightRgba,
          );
          return data!.buffer.asUint8List();
        }))!;
      }

      final asPng = await previewed(ExportStillFormat.png);
      final asPsd = await previewed(ExportStillFormat.psd);
      final unheld = (await tester.runAsync(
        () => pictureOf(film(effects: false)),
      ))!;

      expect(asPsd, unheld);
      expect(asPng, isNot(unheld), reason: 'a PNG keeps the effects');
    });
  });
}
