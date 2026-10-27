import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderRepaintBoundary;
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/camera_pose.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/canvas_viewport.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/pasteboard_bounds.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_background.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/storyboard_timeline_layout.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/services/brush_frame_store.dart';
import 'package:anicel/src/services/playback/playback_frame_mapping.dart';
import 'package:anicel/src/ui/canvas/stage_planes_painter.dart';
import 'package:anicel/src/ui/playback/canvas_track_stack_view.dart';
import 'package:anicel/src/ui/playback/frame_picture_store.dart';
import 'package:anicel/src/ui/playback/frame_picture_view.dart';
import 'package:anicel/src/ui/playback/frame_pictures.dart';
import 'package:anicel/src/ui/playback/layer_frame_image_cache.dart';
import 'package:anicel/src/ui/playback/stacked_frame_picture.dart';

/// 🚨AN ABSENT PLANE IS ONE CHECKERBOARD ON THE SCREEN, and it lies where
/// the stack lies (F-114 — 유저 2026-09-15: 「없음버튼 누르면 없는상태. 즉 해당
/// 용지부분이 체크무늬되도록. 페이스트보드도 백그라운드도 동일하게」; 유저 09-17:
/// 「보이는 중이랑 결과랑 절대로 다르면 안 되」).
///
/// The editing canvas lays its planes in its box, so its cells are the
/// screen's: eight logical pixels from the box's corner at every zoom. A
/// run through the camera lays the floor, the apron and the paper under the
/// view and the camera, and laid there the same checker took the canvas's
/// cells — four pixels at 50% (camera-checkerboard-rides-the-canvas,
/// measured 10-23) — so pressing play with the camera view on changed the
/// pattern.
///
/// And the canvas's planes took the view by hand, off the pan-phase snap
/// the stack over them takes (stage-planes-are-not-pan-snapped, measured
/// 10-23 at a pan of 10.3): an absent paper's edge was a blended column at
/// 100% and at 150% where the paper's own edge was crisp, so turning the
/// paper off and on moved its edge.
void main() {
  const canvasSize = CanvasSize(width: 96, height: 64);
  const box = Size(200, 140);
  const backdrop = Color(0xFF2040C0);
  const pasteboard = Color(0xFF20A040);
  // The paper a colour no cell of the checker is.
  const paper = ProjectBackground.color(0xFFCC3333);
  const absentPaper = ProjectBackground.color(0xFFCC3333, none: true);
  const cells = [
    [0xFF, 0xFF, 0xFF, 0xFF],
    [0xCC, 0xCC, 0xCC, 0xFF],
  ];
  // Room for every plane inside the camera's frame: the paper, the apron
  // a quarter of it past each edge, and the floor past the apron's wall.
  const reach = PasteboardReach.quarter;

  const cutId = CutId('c');
  final cut = Cut(
    id: cutId,
    name: 'Cut',
    duration: 1,
    canvasSize: canvasSize,
    layers: [
      Layer(
        id: const LayerId('l'),
        name: 'Layer',
        frames: [Frame(id: const FrameId('f'), duration: 1, strokes: const [])],
        timeline: {0: const TimelineExposure.drawing(FrameId('f'), length: 1)},
      ),
    ],
  );
  final layout = buildStoryboardTimelineLayout(
    Project(
      id: const ProjectId('p'),
      name: 'Project',
      cameraSize: canvasSize,
      tracks: [
        Track(id: const TrackId('t'), name: 'Track', cuts: [cut]),
      ],
      createdAt: DateTime.utc(2026),
    ),
  );

  final screen = GlobalKey();

  Future<void> pump(WidgetTester tester, Widget picture) => tester.pumpWidget(
    MaterialApp(
      home: Align(
        alignment: Alignment.topLeft,
        child: RepaintBoundary(
          key: screen,
          child: SizedBox.fromSize(size: box, child: picture),
        ),
      ),
    ),
  );

  /// What the last pump put on the screen, in device pixels.
  Future<Shot> onScreen(WidgetTester tester) async {
    final render =
        screen.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final ratio = tester.view.devicePixelRatio;
    final shot = await tester.runAsync(() async {
      final image = await render.toImage(pixelRatio: ratio);
      final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      final width = image.width;
      final height = image.height;
      image.dispose();
      return (rgba: data!.buffer.asUint8List(), width: width, height: height);
    });
    return shot!;
  }

  List<int> pixelAt(Shot shot, int x, int y) => shot.rgba.sublist(
    (y * shot.width + x) * 4,
    (y * shot.width + x) * 4 + 4,
  );

  bool aCell(List<int> rgba) =>
      cells.any((cell) => listEquals(cell, rgba));

  /// The frames' pictures a screen shows, each on its page: [background] —
  /// the paper, or its absence — and the pasteboard past it to [reach].
  StackRun picturesOn(ProjectBackground background) {
    final cache = LayerFrameImageCache(frameStore: BrushFrameStore());
    addTearDown(cache.dispose);
    final store = FramePictureStore<FramePictureKey>();
    addTearDown(store.dispose);
    final landings = ValueNotifier<int>(0);
    addTearDown(landings.dispose);
    return (
      landings: landings,
      pictures: FramePictures(
        store: store,
        layerImages: cache,
        stackOf: (_) => const [],
        pageOf: (picture) => (
          canvasSize: picture.cut.canvasSize,
          pasteboardReach: reach,
          paintPaper: picture.paintPaper,
          paperBackground: background,
        ),
      ),
    );
  }

  /// The editing canvas's planes, every one of them absent: the
  /// checkerboard the canvas shows, over the whole box.
  Widget theCanvasChecker(CanvasViewport view, double ratio) => CustomPaint(
    painter: StagePlanesPainter(
      backdrop: (color: backdrop, none: true),
      pasteboard: (color: pasteboard, none: true),
      pasteboardReach: reach,
      paperNone: true,
      canvasSize: canvasSize,
      viewport: view,
      devicePixelRatio: ratio,
    ),
  );

  /// The film at its one frame through the camera at [pose], nothing drawn:
  /// the stage alone.
  Widget theFilm({
    required CanvasViewport view,
    required CameraPose pose,
    bool backdropNone = false,
    bool pasteboardNone = false,
    ProjectBackground background = paper,
  }) => CanvasTrackStackView(
    globalFrame: const AlwaysStoppedAnimation<int?>(0),
    positionsOf: (frame) => resolveTrackStackContributions(
      layout: layout,
      spansOf: (_) => const [],
      globalFrameIndex: frame,
    ),
    stackOf: (_, _) => const [],
    pictures: picturesOn(background),
    cameraFrameSize: canvasSize,
    cameraViewEnabled: true,
    cameraPoseOf: (_, _) => pose,
    viewport: view,
    background: background,
    backdropArgb: backdrop.toARGB32(),
    backdropNone: backdropNone,
    pasteboardArgb: pasteboard.toARGB32(),
    pasteboardNone: pasteboardNone,
    pasteboardReach: reach,
  );

  const ratios = [1.0, 1.25, 1.5];

  group('through the camera, an absent plane checkers the editing '
      'canvas\'s cells', () {
    // The camera sees twice the canvas, so its frame holds the paper, the
    // apron round it and the floor past the apron's wall; the view zooms
    // it to 150% off whole pixels.
    final view = CanvasViewport(zoom: 1.5, panX: 13.4, panY: 9.7);
    const planes = {
      'paper': (backdropNone: false, pasteboardNone: false, paperNone: true),
      'apron': (backdropNone: false, pasteboardNone: true, paperNone: false),
      'floor': (backdropNone: true, pasteboardNone: false, paperNone: false),
    };
    for (final ratio in ratios) {
      for (final turn in const [0.0, 10.0]) {
        for (final MapEntry(
              key: plane,
              value: (:backdropNone, :pasteboardNone, :paperNone),
            )
            in planes.entries) {
          testWidgets('🚨an absent $plane at ratio $ratio, the camera turned '
              '$turn°', (tester) async {
            tester.view.devicePixelRatio = ratio;
            addTearDown(tester.view.resetDevicePixelRatio);
            final pose = CameraPose(
              center: CanvasPoint(
                x: canvasSize.width / 2,
                y: canvasSize.height / 2,
              ),
              zoom: 0.5,
              rotationDegrees: turn,
            );

            await pump(tester, theCanvasChecker(view, ratio));
            final canvas = await onScreen(tester);
            await pump(
              tester,
              theFilm(
                view: view,
                pose: pose,
                backdropNone: backdropNone,
                pasteboardNone: pasteboardNone,
                background: paperNone ? absentPaper : paper,
              ),
            );
            await tester.pump();
            final film = await onScreen(tester);

            var checkered = 0;
            final strays = <String>[];
            for (var y = 0; y < film.height; y += 1) {
              for (var x = 0; x < film.width; x += 1) {
                final seen = pixelAt(film, x, y);
                if (!aCell(seen)) {
                  continue;
                }
                checkered += 1;
                if (!listEquals(seen, pixelAt(canvas, x, y)) &&
                    strays.length < 8) {
                  strays.add('($x, $y): $seen, the canvas '
                      '${pixelAt(canvas, x, y)}');
                }
              }
            }
            expect(
              checkered,
              greaterThan((1000 * ratio * ratio).round()),
              reason: 'LIVENESS: the absent $plane is on the screen',
            );
            expect(
              strays,
              isEmpty,
              reason: 'the absent $plane lies in the cells the editing '
                  'canvas lays',
            );
          });
        }
      }
    }
  });

  group('the canvas\'s planes land where its stack lands', () {
    // Off whole pixels, at the zooms the display does not smooth, where
    // the paper's edge is crisp.
    const pan = (x: 10.3, y: 7.65);
    for (final ratio in ratios) {
      for (final zoom in const [1.0, 1.1, 2.0]) {
        testWidgets('🚨at ${(zoom * ratio * 100).round()}% (ratio $ratio) an '
            'absent paper\'s checkerboard covers the pixels the paper '
            'covers', (tester) async {
          tester.view.devicePixelRatio = ratio;
          addTearDown(tester.view.resetDevicePixelRatio);
          final view = CanvasViewport(zoom: zoom, panX: pan.x, panY: pan.y);
          Widget still({required bool paperNone}) => CustomPaint(
            painter: StagePlanesPainter(
              backdrop: (color: backdrop, none: false),
              pasteboard: (color: pasteboard, none: false),
              pasteboardReach: reach,
              paperNone: paperNone,
              canvasSize: canvasSize,
              viewport: view,
              devicePixelRatio: ratio,
            ),
            // The canvas standing on a frame of no row: its page alone.
            child: FramePictureView(
              key: ValueKey<bool>(paperNone),
              run: picturesOn(paperNone ? absentPaper : paper),
              picture: (
                cut: cut,
                frameIndex: 0,
                paintPaper: true,
                ghosts: false,
              ),
              nodes: const [],
              viewport: view,
              laysWhatItMisses: true,
              wholeFrames: false,
            ),
          );

          await pump(tester, still(paperNone: false));
          final present = await onScreen(tester);
          await pump(tester, still(paperNone: true));
          final absent = await onScreen(tester);

          final redOf = [0xCC, 0x33, 0x33, 0xFF];
          var papered = 0;
          final moved = <String>[];
          for (var y = 0; y < present.height; y += 1) {
            for (var x = 0; x < present.width; x += 1) {
              final isPaper = listEquals(pixelAt(present, x, y), redOf);
              if (isPaper) {
                papered += 1;
              }
              if (isPaper != aCell(pixelAt(absent, x, y)) &&
                  moved.length < 8) {
                moved.add('($x, $y): the paper ${pixelAt(present, x, y)}, '
                    'absent ${pixelAt(absent, x, y)}');
              }
            }
          }
          expect(
            papered,
            greaterThan((1000 * ratio * ratio).round()),
            reason: 'LIVENESS: the paper is on the screen',
          );
          expect(
            moved,
            isEmpty,
            reason: 'turning the paper off moves no edge: its checkerboard '
                'lies on the pixels the paper lay on, and only there',
          );
        });
      }
    }
  });

  group('an absent plane keeps the edge the plane has', () {
    // A zoom that cuts the pasteboard's wall part-way through a pixel,
    // where a cut that is not the plane's own shows.
    final view = CanvasViewport(zoom: 1.37, panX: 10.3, panY: 7.65);
    const backdropOf = [0x20, 0x40, 0xC0, 0xFF];
    const pasteboardOf = [0x20, 0xA0, 0x40, 0xFF];
    for (final ratio in ratios) {
      testWidgets('🚨at ratio $ratio turning the pasteboard off moves no '
          'edge', (tester) async {
        tester.view.devicePixelRatio = ratio;
        addTearDown(tester.view.resetDevicePixelRatio);
        Widget planes({required bool none}) => CustomPaint(
          painter: StagePlanesPainter(
            backdrop: (color: backdrop, none: false),
            pasteboard: (color: pasteboard, none: none),
            pasteboardReach: reach,
            paperNone: false,
            canvasSize: canvasSize,
            viewport: view,
            devicePixelRatio: ratio,
          ),
        );

        await pump(tester, planes(none: false));
        final present = await onScreen(tester);
        await pump(tester, planes(none: true));
        final absent = await onScreen(tester);

        // How much of a pixel the pasteboard covers, read off its green.
        // ⚠️Only a clear part: a sliver a 255th of a level wide falls on
        // either side of it as a fill or as a clip rounds it.
        double covered(List<int> rgba) =>
            (rgba[1] - backdropOf[1]) / (pasteboardOf[1] - backdropOf[1]);
        var cut = 0;
        final moved = <String>[];
        for (var y = 0; y < present.height; y += 1) {
          for (var x = 0; x < present.width; x += 1) {
            final share = covered(pixelAt(present, x, y));
            if (share < 0.25 || share > 0.75) {
              continue;
            }
            cut += 1;
            final off = pixelAt(absent, x, y);
            if ((listEquals(off, backdropOf) || aCell(off)) &&
                moved.length < 8) {
              moved.add('($x, $y): the pasteboard covers '
                  '${(share * 100).round()}% of it, absent $off');
            }
          }
        }
        expect(
          cut,
          greaterThan((50 * ratio).round()),
          reason: 'LIVENESS: the pasteboard\'s wall cuts pixels part-way',
        );
        expect(
          moved,
          isEmpty,
          reason: 'an absent pasteboard\'s checkerboard is cut where the '
              'pasteboard is cut, so turning it off and on moves no edge',
        );
      });
    }
  });
}

/// A screen shot in device pixels.
typedef Shot = ({Uint8List rgba, int width, int height});
