import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut_camera.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/import/tvp_import_model.dart';
import 'package:anicel/src/models/layer_blend_mode.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/timeline_repeat.dart';
import 'package:anicel/src/services/import/media_import_planner.dart';
import 'package:anicel/src/services/import/tvp_import_planner.dart';
import 'package:flutter_test/flutter_test.dart';

/// The cut a TVPaint clip lands, planned without touching a pixel. The
/// clips are built directly as [TvpImportClip] — the shape the .tvpp
/// reader produces — so every pin here is about the PLANNER's rules.
void main() {
  ImportIdMint mint() {
    var layers = 0;
    var frames = 0;
    var cuts = 0;
    return ImportIdMint(
      nextLayerId: () => LayerId('layer-${++layers}'),
      nextFrameId: (layerId) => FrameId('${layerId.value}-cel-${++frames}'),
      nextCutId: () => CutId('cut-${++cuts}'),
    );
  }

  TvpExposureBlock block(
    int start,
    int length, {
    int? sourceIndex,
    String name = '',
    String file = 'slot',
    bool isReexposure = false,
  }) =>
      TvpExposureBlock(
        start: start,
        length: length,
        name: name,
        file: file,
        sourceIndex: sourceIndex ?? start,
        isReexposure: isReexposure,
      );

  TvpLayer layer(
    String name, {
    int position = 1,
    int start = 0,
    int end = 5,
    List<TvpExposureBlock> blocks = const [],
    TvpEdgeBehavior pre = TvpEdgeBehavior.none,
    TvpEdgeBehavior post = TvpEdgeBehavior.none,
    String blendingMode = 'Color',
  }) =>
      TvpLayer(
        name: name,
        position: position,
        visible: true,
        opacity: 1,
        start: start,
        end: end,
        preBehavior: pre,
        postBehavior: post,
        blendingMode: blendingMode,
        groupColor: null,
        blocks: blocks,
      );

  TvpImportClip clip({
    List<TvpLayer> layers = const [],
    TvpCamera? camera,
    int width = 10,
    int height = 10,
    int frameCount = 6,
  }) =>
      TvpImportClip(
        versionMajor: 0,
        versionMinor: 0,
        clipName: 'c',
        width: width,
        height: height,
        frameRate: 24,
        pixelAspectRatio: 1,
        frameCount: frameCount,
        background: const TvpColor(255, 255, 255),
        markIn: null,
        markOut: null,
        camera: camera ??
            const TvpCamera(
              width: 10,
              height: 10,
              keyframes: [],
              positions: [],
            ),
        layers: layers,
        warnings: const [],
      );

  TvpImportPlan plan(TvpImportClip parsed) => planTvpImport(
        parsed: parsed,
        resolveFile: (relative) => relative,
        mint: mint(),
      );

  group('cels and names', () {
    test('blocks sharing a sourceIndex re-expose ONE cel', () {
      final result = plan(
        clip(
          layers: [
            layer('A', blocks: [
              block(0, 2, sourceIndex: 0, name: '1'),
              block(2, 2, sourceIndex: 2, name: '2'),
              block(4, 2, sourceIndex: 0, name: '1', isReexposure: true),
            ]),
          ],
        ),
      );
      final a = result.cut.layers.firstWhere((l) => l.name == 'A');
      expect(a.frames, hasLength(2));
      expect(a.timeline[0]!.frameId, a.timeline[4]!.frameId);
      expect(a.timeline[2]!.frameId, isNot(a.timeline[0]!.frameId));
    });

    test('instance names become cel names; a reused name splits', () {
      final result = plan(
        clip(
          layers: [
            layer('A', blocks: [
              block(0, 1, name: '3'),
              block(1, 1, name: ''),
              block(2, 1, name: '3'),
            ]),
          ],
        ),
      );
      final names = result.cut.layers
          .firstWhere((l) => l.name == 'A')
          .frames
          .map((frame) => frame.name)
          .toList();
      expect(names, ['3', null, '3-1']);
    });

    test('one bake per drawing, resolved through the caller', () {
      final result = plan(
        clip(
          layers: [
            layer('A', blocks: [
              block(0, 2, sourceIndex: 0, file: 'k0'),
              block(2, 2, sourceIndex: 0, file: 'k0', isReexposure: true),
              block(4, 2, sourceIndex: 4, file: 'k4'),
            ]),
          ],
        ),
      );
      expect(result.bakes.map((bake) => bake.sourceFile).toList(), [
        'k0',
        'k4',
      ]);
    });

    test('an empty layer keeps its row, silently', () {
      final result = plan(clip(layers: [layer('빈행')]));
      final row = result.cut.layers.firstWhere((l) => l.name == '빈행');
      expect(row.frames, isEmpty);
      expect(result.warnings, isEmpty);
    });

    test('an unmapped blending mode falls back to normal and says so', () {
      final result = plan(
        clip(
          layers: [
            layer('A', blendingMode: 'Weird', blocks: [block(0, 1)]),
          ],
        ),
      );
      final a = result.cut.layers.firstWhere((l) => l.name == 'A');
      expect(a.blendMode, LayerBlendMode.normal);
      expect(result.warnings.single, contains('Weird'));
    });
  });

  group('edge behaviours', () {
    test('an end edge anchors on the cel the run ENDS on, not the last '
        'cel minted', () {
      final result = plan(
        clip(
          layers: [
            layer(
              'A',
              post: TvpEdgeBehavior.hold,
              blocks: [
                block(0, 2, sourceIndex: 0),
                block(2, 2, sourceIndex: 2),
                // The run ends on a RE-exposure of the first drawing.
                block(4, 2, sourceIndex: 0, isReexposure: true),
              ],
            ),
          ],
        ),
      );
      final a = result.cut.layers.firstWhere((l) => l.name == 'A');
      final behavior = a.runBehaviors.single;
      expect(behavior.mode, TimelineRunEdgeMode.hold);
      expect(behavior.anchorFrameId, a.timeline[4]!.frameId);
    });

    test('a hold edge arrives with its ghosts already synthesized', () {
      // The behaviours are LIVE specs whose ghost exposures only exist
      // after rederiveRunBehaviors runs; an imported cut never passes
      // through a timeline edit, so the planner must synthesize them
      // itself — H2 of the JSON era, resurfaced by 288 (every H layer
      // wore its tag but held nothing).
      final result = plan(
        clip(
          frameCount: 6,
          layers: [
            layer(
              'A',
              end: 3,
              post: TvpEdgeBehavior.hold,
              blocks: [block(0, 2, sourceIndex: 0), block(2, 2, sourceIndex: 2)],
            ),
          ],
        ),
      );
      final a = result.cut.layers.firstWhere((l) => l.name == 'A');
      final tail = a.timeline[4];
      expect(tail, isNotNull, reason: 'the free frames are filled');
      expect(tail!.ghost, isTrue);
    });

    test('a pre-behavior fills the lead-in from the FIRST block', () {
      final result = plan(
        clip(
          frameCount: 8,
          layers: [
            layer(
              'A',
              start: 3,
              end: 7,
              pre: TvpEdgeBehavior.repeat,
              blocks: [
                block(3, 2, sourceIndex: 3),
                block(5, 3, sourceIndex: 5),
              ],
            ),
          ],
        ),
      );
      final a = result.cut.layers.firstWhere((l) => l.name == 'A');
      final leading = a.runBehaviors
          .firstWhere((b) => b.side == TimelineRunEdgeSide.start);
      expect(leading.mode, TimelineRunEdgeMode.repeat);
      expect(leading.anchorFrameId, a.timeline[3]!.frameId);
    });
  });

  group('the camera zoom, in the FILE pose shape', () {
    // The LAW (#965, re-measured 2026-08-27): viewed width =
    // Camera.Width × scale, so Anicel zoom = 1 / scale. The pose's own
    // sizeX/sizeY is the CLIP CANVAS in file poses (288 stores
    // 2339×1653) and does not participate — #1270 read it as the
    // framing and imported 288 at half its true width.
    CutCamera cameraFrom({
      required double sizeX,
      required double sizeY,
      required double scale,
      required CanvasSize frame,
    }) {
      final pose = TvpCameraPose(
        frame: 1,
        x: 1170,
        y: 827,
        angleDegrees: 0,
        scale: scale,
        sizeX: sizeX,
        sizeY: sizeY,
      );
      return planTvpImport(
        parsed: clip(
          width: 2339,
          height: 1653,
          frameCount: 2,
          camera: TvpCamera(
            width: sizeX.round(),
            height: sizeY.round(),
            keyframes: [pose],
            positions: [pose],
          ),
        ),
        resolveFile: (relative) => relative,
        mint: mint(),
      ).cut.camera;
    }

    test("288's own numbers: zoom 207.1% on the 960 camera frames the "
        'layout paper box', () {
      // Hands-on truth (user screenshots, 08-27): TVPaint's blue
      // rectangle coincides with the 撮影フレーム box on the layout
      // paper — 960 × 2.070968 ≈ 1988 clip pixels, NOT the
      // 2339 / 2.070968 ≈ 1129 the #1270 reading framed.
      const frame = CanvasSize(width: 960, height: 430);
      final camera = cameraFrom(
        sizeX: 2339,
        sizeY: 1653,
        scale: 2.070968,
        frame: frame,
      );
      final framedWidth = frame.width / camera.keyframeAt(0)!.zoom;
      expect(framedWidth, closeTo(960 * 2.070968, 0.01));
    });

    test('more scale = a bigger rectangle = a wider view: zoom is the '
        'reciprocal', () {
      const frame = CanvasSize(width: 960, height: 430);
      final resized = cameraFrom(
          sizeX: 2339, sizeY: 1653, scale: 2.0, frame: frame);
      final base = cameraFrom(
          sizeX: 2339, sizeY: 1653, scale: 1.0, frame: frame);
      expect(
        resized.keyframeAt(0)!.zoom,
        closeTo(base.keyframeAt(0)!.zoom / 2, 1e-9),
      );
    });

    test('a rectangle the size of the shooting frame at scale 1 is the '
        'identity', () {
      const frame = CanvasSize(width: 1920, height: 1080);
      final camera = cameraFrom(
          sizeX: 1920, sizeY: 1080, scale: 1.0, frame: frame);
      expect(camera.keyframeAt(0)!.zoom, closeTo(1.0, 1e-9));
    });

    test('a STILL camera stays one key — the baked curve must not grow '
        'an end key', () {
      // 288: one authored key on frame 1 arrived as keys on frames 1
      // AND 96, because the track simplifier keeps both endpoints of
      // whatever it walks.
      const pose = TvpCameraPose(
        frame: 1,
        x: 100,
        y: 80,
        angleDegrees: 0,
        scale: 1,
        sizeX: 1920,
        sizeY: 1080,
      );
      final result = plan(
        clip(
          frameCount: 8,
          camera: TvpCamera(
            width: 1920,
            height: 1080,
            keyframes: [pose],
            positions: [
              for (var f = 1; f <= 8; f++)
                TvpCameraPose(
                  frame: f,
                  x: 100,
                  y: 80,
                  angleDegrees: 0,
                  scale: 1,
                  sizeX: 1920,
                  sizeY: 1080,
                ),
            ],
          ),
        ),
      );
      expect(result.cut.camera.track.keyframes, hasLength(1));
    });
  });
}
