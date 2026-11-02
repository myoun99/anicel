import 'dart:collection';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/camera_instruction.dart';
import 'package:anicel/src/models/camera_path_settings.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/drawing_guide.dart';
import 'package:anicel/src/models/export_format_selection.dart';
import 'package:anicel/src/models/export_spec.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_effect.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/layer_section_defaults.dart';
import 'package:anicel/src/models/onion_skin_settings.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/models/timeline_row_address.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/services/editing/default_cut_helpers.dart';
import 'package:anicel/src/services/photoshop/psd_reader.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/export/export_frame_renderer.dart';
import 'package:anicel/src/ui/export/export_plan.dart';
import 'package:anicel/src/ui/export/frame_image_file.dart';
import 'package:anicel/src/ui/text/app_strings.dart';

import '../../helpers/draw_on_current_frame.dart';
import '../../helpers/project_scratch_folder.dart';

/// 🗣️F-547 (유저 2026-11-03): 「파일 다른이름저장으로 png등으로 저장할때,
/// 카메라 경로가 출력안되있음」 · 「다른이름저장은 진짜 보이는대로 출력이니까
/// 가이드던 어니언스킨이던 뭐던 화면 보이는 그대로 캔버스사이즈로 크롭해서
/// 출력하도록」 · 「출력탭 이미지저장도 마찬가지」.
///
/// One picture answers for both doors (`writeFrameImage`,
/// `the_image_tab_and_save_as_write_one_picture_test`), so each thing the
/// canvas shows is pinned against the picture of the frame without it: shown
/// on the canvas it is in the picture, hidden it is not. Every cut here keeps
/// its camera's eye shut unless the test opens it, as an open eye dims the
/// picture round the frame.
void main() {
  const canvas = CanvasSize(width: 200, height: 200);
  const cameraSize = CanvasSize(width: 100, height: 100);
  const cutId = CutId('cut');
  const trackId = TrackId('track');
  const rowId = LayerId('row');
  const earlier = FrameId('earlier');
  const stood = FrameId('stood');
  const guideInk = ui.Color(0xFF1E5AC8);

  void reset() {
    CameraPathSettings.settings.value = const CameraPathSettings();
  }

  setUp(reset);
  tearDown(reset);

  /// A cut of two drawings of one row, a frame each, its camera's eye shut,
  /// stood on the second: what a ghost is of. [fade] names a fade over its
  /// last five frames.
  EditorSessionManager sessionOf({String? fade}) {
    final s = EditorSessionManager(
      initialProject: Project(
        id: const ProjectId('project'),
        name: 'Project',
        createdAt: DateTime.utc(2026),
        cameraSize: cameraSize,
        tracks: [
          Track(
            id: trackId,
            name: 'V',
            cuts: [
              Cut(
                id: cutId,
                name: 'Cut',
                duration: 10,
                canvasSize: canvas,
                layers: [
                  Layer(
                    id: rowId,
                    name: 'A',
                    frames: [
                      Frame(id: earlier, duration: 1, strokes: const []),
                      Frame(id: stood, duration: 9, strokes: const []),
                    ],
                    timeline: const {
                      0: TimelineExposure.drawing(earlier, length: 1),
                      1: TimelineExposure.drawing(stood, length: 9),
                    },
                  ),
                  createCameraLayer(cutId: cutId).copyWith(isVisible: false),
                ],
              ),
            ],
            transitionLayer: fade == null
                ? null
                : createTrackTransitionLayer(trackId).copyWith(
                    instructions: SplayTreeMap.of({
                      5: InstructionEvent(instructionId: fade, length: 5),
                    }),
                  ),
          ),
        ],
      ),
    );
    addTearDown(s.dispose);
    s.selectFrameIndex(1);
    return s;
  }

  /// A dab of ink [size] across at ([x], [y]) in [cel] of the row.
  void ink(
    EditorSessionManager s,
    FrameId cel,
    double x,
    double y, {
    double size = 30,
  }) => inkCel(
    s,
    s.brushFrameKeyForCut(s.requireActiveCut, rowId, cel),
    canvasSize: canvas,
    at: CanvasPoint(x: x, y: y),
    size: size,
  );

  /// The camera panning [by] canvas pixels right from frame 0 to frame 5, at
  /// [zoom].
  void pan(EditorSessionManager s, {double by = 40, double zoom = 1}) {
    final camera = s.camera;
    s.selectFrameIndex(0);
    final start = camera.cameraPoseAtCurrentFrame.copyWith(zoom: zoom);
    camera.setCameraKeyframeAtCurrentFrame(start);
    s.selectFrameIndex(5);
    camera.setCameraKeyframeAtCurrentFrame(
      start.copyWith(
        center: CanvasPoint(x: start.center.x + by, y: start.center.y),
      ),
    );
    s.selectFrameIndex(1);
  }

  ExportFrameRenderer rendererOf(EditorSessionManager s) {
    final renderer = ExportFrameRenderer(
      session: s,
      background: const ui.Color(0x00000000),
    );
    addTearDown(renderer.dispose);
    return renderer;
  }

  ExportFrameTask standing(EditorSessionManager s) =>
      ExportFrameTask(cut: s.requireActiveCut, frameIndex: s.currentFrameIndex);

  Future<Uint8List> bytesOf(ui.Image image) async {
    final data = await image.toByteData(
      format: ui.ImageByteFormat.rawStraightRgba,
    );
    image.dispose();
    return data!.buffer.asUint8List();
  }

  /// [s]'s frame as the canvas shows it, on nothing.
  Future<Uint8List> shown(
    EditorSessionManager s, {
    ExportSizeMode mode = ExportSizeMode.canvas,
  }) async => bytesOf(
    await rendererOf(s).renderAsShown(standing(s), mode, guideInk: guideInk),
  );

  /// [s]'s frame as a film shows it, on nothing.
  Future<Uint8List> film(EditorSessionManager s) async => bytesOf(
    await rendererOf(s).renderComposite(standing(s), ExportSizeMode.canvas),
  );

  /// The RGBA of ([x], [y]) of a [width] wide picture.
  List<int> at(Uint8List rgba, int x, int y, {int width = 200}) {
    final offset = (y * width + x) * 4;
    return rgba.sublist(offset, offset + 4);
  }

  testWidgets('⛔with nothing over it the picture IS the film\'s, to the '
      'byte: nothing is laid that the canvas does not show', (tester) async {
    await tester.runAsync(() async {
      final s = sessionOf();
      ink(s, stood, 100, 100);
      expect(s.cameraViewMode.enabled.value, isFalse, reason: '⛔premise');
      expect(await shown(s), await film(s));
    });
  });

  group('the camera\'s path', () {
    testWidgets('🚨written as the canvas draws it — and not where its '
        'settings turn it off', (tester) async {
      await tester.runAsync(() async {
        final s = sessionOf();
        pan(s);
        expect(await shown(s), isNot(await film(s)));

        CameraPathSettings.settings.value = const CameraPathSettings(
          show: CameraPathShow.off,
        );
        expect(await shown(s), await film(s));
      });
    });

    testWidgets('around the playhead it keeps to the frames the canvas does '
        '— the far key\'s frame is not written', (tester) async {
      await tester.runAsync(() async {
        final s = sessionOf();
        pan(s);
        // The right edge of the frame the key at frame 5 stands in.
        const edgeX = 190;
        expect(at(await shown(s), edgeX, 100)[3], greaterThan(0));

        CameraPathSettings.settings.value = const CameraPathSettings(
          range: CameraPathRange.aroundPlayhead,
          around: 1,
        );
        expect(at(await shown(s), edgeX, 100)[3], 0);
      });
    });

    testWidgets('around the frame the picture is of — the one the image tab '
        'turned to — not the playhead', (tester) async {
      await tester.runAsync(() async {
        final s = sessionOf();
        pan(s);
        CameraPathSettings.settings.value = const CameraPathSettings(
          range: CameraPathRange.aroundPlayhead,
          around: 1,
        );
        expect(s.currentFrameIndex, 1, reason: '⛔premise: not the far key');
        final rgba = await bytesOf(
          await rendererOf(s).renderAsShown(
            ExportFrameTask(cut: s.requireActiveCut, frameIndex: 5),
            ExportSizeMode.canvas,
            guideInk: guideInk,
          ),
        );
        expect(at(rgba, 190, 100)[3], greaterThan(0));
      });
    });

    testWidgets('as large on the picture as the camera prints it, as the '
        'canvas draws it (F-421): a camera at a quarter writes four times '
        'as wide', (tester) async {
      await tester.runAsync(() async {
        /// The ink crossing the row of pixels through the frame's middle.
        Future<int> widestRun(double zoom) async {
          final s = sessionOf();
          pan(s, by: 10, zoom: zoom);
          final rgba = await shown(s);
          var widest = 0;
          var run = 0;
          for (var x = 0; x < 200; x += 1) {
            run = at(rgba, x, 100)[3] > 0 ? run + 1 : 0;
            widest = run > widest ? run : widest;
          }
          return widest;
        }

        final wide = await widestRun(0.25);
        expect(wide, greaterThan(await widestRun(1)));
        expect(wide, greaterThanOrEqualTo(5));
      });
    });
  });

  group('the guides', () {
    final mirror = DrawingGuide(
      id: const GuideId('mirror'),
      name: 'mirror',
      shape: SymmetryShape(
        axis: GuideAxis(origin: CanvasPoint(x: 100, y: 100), angleDegrees: 90),
      ),
    );

    testWidgets('🚨every guide the canvas shows, a symmetry\'s too, in the '
        'ink it is handed — and none it has hidden', (tester) async {
      await tester.runAsync(() async {
        final s = sessionOf();
        s.cutVerbs.setActiveCutGuides(CutGuides(guides: [mirror]));
        final line = at(await shown(s), 100, 150);
        expect(line[3], greaterThan(0));
        expect(line[0], closeTo(guideInk.r * 255, 3));
        expect(line[1], closeTo(guideInk.g * 255, 3));
        expect(line[2], closeTo(guideInk.b * 255, 3));

        s.cutVerbs.setActiveCutGuides(
          CutGuides(guides: [mirror.copyWith(visible: false)]),
        );
        expect(await shown(s), await film(s));
      });
    });
  });

  testWidgets('the SE rows\' name tags: the frame a presentation render '
      'makes, as the canvas lays them over its picture', (tester) async {
    await tester.runAsync(() async {
      const se = LayerId('se');
      final s = EditorSessionManager(
        initialProject: Project(
          id: const ProjectId('project'),
          name: 'Project',
          createdAt: DateTime.utc(2026),
          cameraSize: cameraSize,
          tracks: [
            Track(
              id: trackId,
              name: 'V',
              cuts: [
                Cut(
                  id: cutId,
                  name: 'Cut',
                  duration: 10,
                  canvasSize: canvas,
                  layers: [
                    createCameraLayer(cutId: cutId).copyWith(isVisible: false),
                  ],
                ),
              ],
              seLayers: [
                Layer(
                  id: se,
                  name: 'S1',
                  kind: LayerKind.se,
                  frames: [
                    Frame(
                      id: const FrameId('line'),
                      duration: 10,
                      strokes: const [],
                      name: 'the line',
                      seName: 'who',
                    ),
                  ],
                  timeline: const {
                    0: TimelineExposure.drawing(FrameId('line'), length: 10),
                  },
                ),
              ],
            ),
          ],
        ),
      );
      addTearDown(s.dispose);
      final named = await bytesOf(
        await rendererOf(s).renderComposite(
          standing(s),
          ExportSizeMode.canvas,
          withNameTags: true,
        ),
      );
      expect(named, isNot(await film(s)), reason: '⛔premise: a tag is drawn');
      expect(await shown(s), named);
    });
  });

  testWidgets('a one-sided transition\'s screen, as the canvas lays it: an '
      'F.O\'s last frame is black', (tester) async {
    await tester.runAsync(() async {
      final s = sessionOf(fade: 'fo');
      s.selectFrameIndex(4);
      expect(at(await shown(s), 100, 100)[3], 0, reason: 'before the fade');
      s.selectFrameIndex(9);
      expect(at(await shown(s), 100, 100), [0, 0, 0, 255]);
    });
  });

  group('the camera view', () {
    void openTheEye(EditorSessionManager s) {
      s.cameraViewMode.toggle();
      expect(s.cameraViewMode.enabled.value, isTrue, reason: '⛔premise');
    }

    testWidgets('its eye open, the picture round the frame is dimmed as the '
        'canvas dims it, and nothing is laid inside — no hairline, no cross, '
        'which the canvas draws at the screen\'s size', (tester) async {
      await tester.runAsync(() async {
        final s = sessionOf();
        openTheEye(s);
        final rgba = await shown(s);
        expect(
          at(rgba, 10, 10)[3],
          (s.cameraViewMode.dim.value * 255).round(),
        );
        expect(at(rgba, 60, 60)[3], 0);
        expect(at(rgba, 100, 100)[3], 0, reason: 'where its cross stands');
      });
    });

    testWidgets('⛔through the camera there is nothing of it to see: a '
        'camera-size picture is the film\'s', (tester) async {
      await tester.runAsync(() async {
        final s = sessionOf();
        ink(s, stood, 100, 100);
        openTheEye(s);
        expect(
          await shown(s, mode: ExportSizeMode.camera),
          await bytesOf(
            await rendererOf(s).renderComposite(
              standing(s),
              ExportSizeMode.camera,
            ),
          ),
        );
      });
    });

    testWidgets('⛔stood on its row with its eye shut, the canvas dims '
        'nothing and neither does the picture', (tester) async {
      await tester.runAsync(() async {
        final s = sessionOf();
        final row = s.requireActiveCut.layers.firstWhere(
          (layer) => layer.kind == LayerKind.camera,
        );
        s.standOnRow(LayerRowAddress(row.id));
        expect(await shown(s), await film(s));
      });
    });
  });

  group('the onion', () {
    void ghosting(EditorSessionManager s, OnionSkinPlacement placement) {
      s.onionSkin.toggleLayerOnionSkin(rowId);
      final settings = s.onionSkin.settings;
      final before = settings.value;
      settings.value = before.copyWith(placement: placement);
      addTearDown(() => settings.value = before);
    }

    for (final placement in OnionSkinPlacement.values) {
      testWidgets('🚨${placement.name}: the frame before lies in the picture '
          'at its peg, in its side\'s tint', (tester) async {
        await tester.runAsync(() async {
          final s = sessionOf();
          ink(s, earlier, 40, 40);
          ink(s, stood, 150, 150);
          final bare = await shown(s);
          expect(at(bare, 40, 40)[3], 0, reason: '⛔premise: no ghost yet');

          ghosting(s, placement);
          final ghost = at(await shown(s), 40, 40);
          expect(ghost[3], closeTo(0.4 * 255, 3));
          final tint = const OnionSkinSettings().tintBefore;
          expect(ghost[0], closeTo((tint >> 16) & 0xFF, 3));
          expect(ghost[1], closeTo((tint >> 8) & 0xFF, 3));
          expect(ghost[2], closeTo(tint & 0xFF, 3));
        });
      });
    }

    testWidgets('the tab\'s 레이어 FX reach the ghost: off, its row\'s chain is '
        'off it as it is off the row', (tester) async {
      await tester.runAsync(() async {
        final s = sessionOf();
        ink(s, earlier, 40, 40);
        s.effectsAndFx.updateLayerEffects(rowId, [
          LayerEffect(
            id: const EffectId('blur'),
            kind: EffectKind.blur,
            parameters: {'blurriness': EffectParameter(value: 8)},
          ),
        ]);
        ghosting(s, OnionSkinPlacement.onTop);

        /// How many pixels of the dab's row the ghost reaches: a blur
        /// spreads it past the dab.
        Future<int> reach(ExportLayerFx fx) async {
          final renderer = ExportFrameRenderer(
            session: s,
            background: const ui.Color(0x00000000),
            layerFx: fx,
          );
          addTearDown(renderer.dispose);
          final rgba = await bytesOf(
            await renderer.renderAsShown(
              standing(s),
              ExportSizeMode.canvas,
              guideInk: guideInk,
            ),
          );
          return [
            for (var x = 0; x < 200; x += 1)
              if (at(rgba, x, 40)[3] > 0) x,
          ].length;
        }

        final bare = await reach(ExportLayerFx.off);
        expect(bare, greaterThan(0), reason: '⛔premise: a ghost is drawn');
        expect(await reach(ExportLayerFx.on), greaterThan(bare));
      });
    });

    testWidgets('🚨where it lies: under the row\'s own drawing in place, over '
        'it on top — as the canvas lays it', (tester) async {
      await tester.runAsync(() async {
        final s = sessionOf();
        ink(s, earlier, 100, 100);
        ink(s, stood, 100, 100);
        final drawing = at(await film(s), 100, 100);

        ghosting(s, OnionSkinPlacement.inPlace);
        expect(at(await shown(s), 100, 100), drawing);

        s.onionSkin.settings.value = s.onionSkin.settings.value.copyWith(
          placement: OnionSkinPlacement.onTop,
        );
        expect(at(await shown(s), 100, 100), isNot(drawing));
      });
    });
  });

  testWidgets('the image tab\'s camera size is the same picture through the '
      'camera: the size the camera says, its guide where the frame sees it', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final s = sessionOf();
      s.cutVerbs.setActiveCutGuides(
        CutGuides(
          guides: [
            DrawingGuide(
              id: const GuideId('mirror'),
              name: 'mirror',
              shape: SymmetryShape(
                axis: GuideAxis(
                  origin: CanvasPoint(x: 100, y: 100),
                  angleDegrees: 90,
                ),
              ),
            ),
          ],
        ),
      );
      final rgba = await shown(s, mode: ExportSizeMode.camera);
      expect(rgba.length, cameraSize.width * cameraSize.height * 4);
      expect(at(rgba, 50, 80, width: 100)[3], greaterThan(0));
    });
  });

  group('a file that keeps the rows apart', () {
    /// The rows of the PSD [s]'s frame is written as, bottom-up.
    Future<PsdDocument> psdOf(EditorSessionManager s) async {
      final folder = Directory.systemTemp.createTempSync('shown-psd');
      deleteAfterSessionEnds(folder);
      final wrote = await writeFrameImage(
        s,
        standing(s),
        const ImageExportSpec(
          format: ExportFormatSelection(
            kind: ExportMediaKind.still,
            stillFormat: ExportStillFormat.psd,
          ),
          sizeMode: ExportSizeMode.canvas,
        ),
        (
          directory: folder.path,
          name: 'frame.psd',
          isCancelled: null,
          onProgress: null,
          onLeftOut: null,
        ),
        guideInk: guideInk,
      );
      expect(wrote, isTrue);
      return readPsdDocument(
        File('${folder.path}/frame.psd').readAsBytesSync(),
      );
    }

    testWidgets('🚨keeps what is shown over them in a row of its own, top of '
        'the file — hidden with one eye', (tester) async {
      await tester.runAsync(() async {
        final s = sessionOf();
        ink(s, stood, 100, 100);
        pan(s);
        final name = AppText.notation.exOnScreen;
        expect((await psdOf(s)).layers.last.name, name);

        CameraPathSettings.settings.value = const CameraPathSettings(
          show: CameraPathShow.off,
        );
        expect(
          (await psdOf(s)).layers.map((row) => row.name),
          isNot(contains(name)),
        );
      });
    });

    testWidgets('the ghosts are in that row, as no other holds one', (
      tester,
    ) async {
      await tester.runAsync(() async {
        final s = sessionOf();
        ink(s, earlier, 40, 40);
        ink(s, stood, 150, 150);
        final renderer = rendererOf(s);
        expect(
          renderer.rowShownOver(
            standing(s),
            ExportSizeMode.canvas,
            guideInk: guideInk,
          ),
          isNull,
        );

        s.onionSkin.toggleLayerOnionSkin(rowId);
        final row = renderer.rowShownOver(
          standing(s),
          ExportSizeMode.canvas,
          guideInk: guideInk,
        )!;
        expect(at(await bytesOf(await row.draw()), 40, 40)[3], greaterThan(0));
      });
    });
  });
}
