import 'package:flutter/gestures.dart'
    show PointerDeviceKind, kSecondaryButton;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/audio_clip.dart';
import 'package:anicel/src/models/camera_pose.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_camera.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/property_track.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/models/transform_track.dart';
import 'package:anicel/src/services/project_repository.dart';
import 'package:anicel/src/ui/home_page.dart';
import 'package:anicel/src/ui/timeline/property_lane_model.dart';
import 'package:anicel/src/ui/timeline/timeline_cell_style.dart'
    show timelineDrawingStartColor;
import 'package:anicel/src/ui/timeline/timeline_grid_metrics.dart'
    show TimelineGridMetrics;
import 'package:anicel/src/ui/timeline/timeline_lane_rows.dart'
    show TimelineLaneKeyMarker, timelineLaneUnionKeyMarkerSize;
import 'package:anicel/src/ui/timeline/transform_lane_editing.dart';
import 'package:anicel/src/ui/timeline/transform_lane_policy.dart';
import 'package:anicel/src/ui/timeline/xsheet_timeline_grid.dart';

import 'timeline_cell_probe.dart';

const _cameraLayerId = LayerId('lane-cam-layer');
const _laneToggleKey = ValueKey<String>('timeline-lane-toggle-lane-cam-layer');

Project _project({CutCamera? camera}) {
  return Project(
    id: const ProjectId('lanes-project'),
    name: 'Lanes Project',
    createdAt: DateTime.utc(2026, 7, 7),
    tracks: [
      Track(
        id: const TrackId('lanes-track'),
        name: 'Video Track',
        cuts: [
          Cut(
            id: const CutId('lanes-cut'),
            name: 'Lanes Cut',
            duration: 12,
            canvasSize: const CanvasSize(width: 1280, height: 720),
            camera: camera ?? CutCamera.empty(),
            layers: [
              Layer(
                id: const LayerId('lane-draw-layer'),
                name: 'Drawing',
                frames: const [],
              ),
              Layer(
                id: _cameraLayerId,
                name: 'Camera',
                kind: LayerKind.camera,
                frames: const [],
              ),
            ],
          ),
        ],
      ),
    ],
  );
}

CameraPose _pose(double x) => CameraPose(
  center: CanvasPoint(x: x, y: x),
  zoom: 1.5,
);

Future<void> _pump(WidgetTester tester, Project project) async {
  // The AE 'Transform' group header (+ anchor/opacity lanes on drawing
  // layers) deepens the twirl-down; a wide surface and a taller bottom
  // dock (splitter drag, like a user would) keep every lane row on screen.
  //
  // R10 R6: the drag went from -300 to -520. The old figure was calibrated
  // against a 112px x-sheet header; the sheet's header is the whole rail
  // stood up now, so a dock that used to leave several frame rows left
  // barely one — and a marker at the clip edge cannot be dragged.
  // ⚠️결정 8 (2026-08-22): a drag may open the bottom dock to HALF the
  // window and no further, so the window has to be twice what these rows
  // need. It used to lean on a ceiling of "everything but the canvas's
  // floor", which let this drag reach 1074 of 1200 — 89% of the screen.
  await tester.binding.setSurfaceSize(const Size(1280, 2200));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(MaterialApp(home: HomePage(initialProject: project)));
  await tester.pumpAndSettle();
  await tester.drag(
    find.byKey(const ValueKey<String>('dock-resize-bottom')),
    const Offset(0, -520),
  );
  await tester.pumpAndSettle();
}

Finder _laneLabel(String laneId) =>
    find.byKey(ValueKey<String>('timeline-lane-label-lane-cam-layer-$laneId'));

/// Twirls a layer's Transform GROUP open (R4: default collapsed — member
/// lanes only render after the group header toggle). No-op while the
/// header is absent (layer twirl-down closed).
Future<void> _expandTransformGroup(
  WidgetTester tester,
  String layerId, {
  String keyPrefix = 'timeline',
}) async {
  final toggle = find.byKey(
    ValueKey<String>('$keyPrefix-lane-group-toggle-$layerId-transform-group'),
  );
  if (toggle.evaluate().isEmpty) {
    return;
  }
  await tester.ensureVisible(toggle);
  await tester.pumpAndSettle();
  await tester.tap(toggle);
  await tester.pumpAndSettle();
}

Finder _laneKey(String laneId, int frame) => find.byKey(
  ValueKey<String>('timeline-lane-key-lane-cam-layer-$laneId-$frame'),
);

void main() {
  group('buildTimelineDisplayRows', () {
    test('interleaves lane rows under expanded layers only', () {
      final drawing = Layer(
        id: const LayerId('a'),
        name: 'A',
        frames: const [],
      );
      final camera = Layer(
        id: const LayerId('cam'),
        name: 'Cam',
        kind: LayerKind.camera,
        frames: const [],
      );
      const lane = PropertyLaneRow(
        laneId: 'position',
        label: 'Position',
        keyedFrames: {1},
      );

      final collapsed = buildTimelineDisplayRows(
        layers: [drawing, camera],
        expandedLayerIds: const {},
        lanesForLayer: (layer) =>
            layer.kind == LayerKind.camera ? const [lane] : const [],
      );
      expect(collapsed.length, 2);
      expect(collapsed.every((row) => !row.isLane), isTrue);

      final expanded = buildTimelineDisplayRows(
        layers: [drawing, camera],
        expandedLayerIds: {const LayerId('cam')},
        lanesForLayer: (layer) =>
            layer.kind == LayerKind.camera ? const [lane] : const [],
      );
      expect(expanded.length, 3);
      expect(expanded[2].isLane, isTrue);
      expect(expanded[2].layer.id, const LayerId('cam'));
      // Lane rows keep their layer's index so section dividers stay put.
      expect(expanded[2].layerIndex, 1);
    });

    test('R26 #36: a base\'s lanes land AFTER its trailing attach rows — '
        'the attach group never splits', () {
      final base = Layer(
        id: const LayerId('base'),
        name: 'B',
        frames: const [],
      );
      final attach1 = Layer(
        id: const LayerId('at1'),
        name: 'B+1',
        frames: const [],
        attachedToLayerId: const LayerId('base'),
      );
      final attach2 = Layer(
        id: const LayerId('at2'),
        name: 'B+2',
        frames: const [],
        attachedToLayerId: const LayerId('base'),
      );
      const lane = PropertyLaneRow(
        laneId: 'position',
        label: 'Position',
        keyedFrames: {},
      );
      List<String> orderOf(List<Layer> layers, Set<LayerId> expanded) =>
          buildTimelineDisplayRows(
            layers: layers,
            expandedLayerIds: expanded,
            lanesForLayer: (layer) => const [lane],
          )
              .map(
                (row) => row.isLane
                    ? 'lane:${row.layer.id.value}'
                    : row.layer.id.value,
              )
              .toList();

      // Trailing attach rows: the base's lanes wait past the whole group.
      expect(orderOf([base, attach1, attach2], {base.id}), [
        'base',
        'at1',
        'at2',
        'lane:base',
      ]);

      // Attach rows PRECEDING the base keep the classic order — the group
      // already ends at the base there.
      expect(orderOf([attach1, attach2, base], {base.id}), [
        'at1',
        'at2',
        'base',
        'lane:base',
      ]);

      // An expanded attach layer's own lanes emit in place; the base's
      // still wait for the run to end.
      expect(orderOf([base, attach1, attach2], {base.id, attach1.id}), [
        'base',
        'at1',
        'lane:at1',
        'at2',
        'lane:base',
      ]);
    });
  });

  group('transformPropertyLanes', () {
    test('exposes the AE transform group with keyed/hold frames', () {
      final track = TransformTrack.empty().copyWith(
        position: PropertyTrack<CanvasPoint>()
            .withKey(0, CanvasPoint(x: 0, y: 0))
            .withKey(
              6,
              CanvasPoint(x: 5, y: 5),
              interpolation: PropertyKeyInterpolation.hold,
            ),
        rotation: PropertyTrack<double>().withKey(3, 90),
      );

      final lanes = transformPropertyLanes(track);

      // The AE structure: the 'Transform' GROUP HEADER leads its lanes
      // (Effects stack below on the same substrate later).
      expect(lanes.map((lane) => lane.laneId), [
        'transform-group',
        'position',
        'scale',
        'rotation',
      ]);
      expect(lanes.first.isGroupHeader, isTrue);
      expect(lanes.first.showsKeyNavigator, isFalse);
      expect(lanes[1].keyedFrames, {0, 6});
      expect(lanes[1].holdOutFrames, {6});
      expect(lanes[2].keyedFrames, isEmpty);
      expect(lanes[3].keyedFrames, {3});
    });

    test('includeAnchorAndOpacity adds the two layer-only lanes in AE '
        'order (Anchor Point first, Opacity last)', () {
      final track = TransformTrack.empty().copyWith(
        anchorPoint: PropertyTrack<CanvasPoint>().withKey(
          2,
          CanvasPoint(x: 10, y: 20),
        ),
        opacity: PropertyTrack<double>().withKey(5, 0.5),
      );

      final lanes = transformPropertyLanes(
        track,
        includeAnchorAndOpacity: true,
        anchorAt: (_) => CanvasPoint(x: 10, y: 20),
        opacityAt: (_) => 0.5,
      );

      expect(lanes.map((lane) => lane.laneId), [
        'transform-group',
        'anchor-point',
        'position',
        'scale',
        'rotation',
        'opacity',
      ]);
      expect(lanes[1].keyedFrames, {2});
      expect(lanes[1].valueLabel!(0), '10, 20');
      expect(lanes[5].keyedFrames, {5});
      expect(lanes[5].valueLabel!(0), '50%');
    });
  });

  group('camera property lanes in the timeline', () {
    testWidgets('twirl-down shows the AE transform lanes with key '
        'diamonds', (tester) async {
      await _pump(
        tester,
        _project(camera: CutCamera(keyframes: {0: _pose(0), 8: _pose(80)})),
      );

      // Collapsed by default: chevron present, lanes hidden.
      expect(find.byKey(_laneToggleKey), findsOneWidget);
      expect(_laneLabel('position'), findsNothing);

      await tester.tap(find.byKey(_laneToggleKey));
      await tester.pumpAndSettle();

      // ㉙ (유저 2026-08-12): the camera row has NO Transform group header —
      // it IS that group, and its own band already draws the members' key
      // union, so a header on top said the same noun twice. ONE twirl is the
      // whole way in here; every other kind still opens onto its header,
      // which `lane_row_standing_test` pins on the drawing row.
      expect(_laneLabel('transform-group'), findsNothing);

      // The whole AE Transform group, with no second twirl.
      expect(_laneLabel('position'), findsOneWidget);
      expect(_laneLabel('scale'), findsOneWidget);
      expect(_laneLabel('rotation'), findsOneWidget);
      // Pose keys write synchronized keys on all three lanes.
      for (final laneId in ['position', 'scale', 'rotation']) {
        expect(_laneKey(laneId, 0), findsOneWidget);
        expect(_laneKey(laneId, 8), findsOneWidget);
      }

      // EVERY key diamond fills WHITE like the frame blocks (UI-R24 #9)
      // — union headers and member lanes alike; selection speaks through
      // the accent silhouette alone.
      Color markerFill(Finder marker) {
        final container = tester.widget<Container>(
          find.descendant(of: marker, matching: find.byType(Container)).first,
        );
        return (container.decoration! as BoxDecoration).color!;
      }

      expect(markerFill(_laneKey('position', 0)), timelineDrawingStartColor);

      // ㉙: no header to collapse here, so the ROW's twirl is the only fold —
      // and it takes every lane with it.
      await tester.tap(find.byKey(_laneToggleKey));
      await tester.pumpAndSettle();
      expect(_laneLabel('position'), findsNothing);
      expect(_laneLabel('scale'), findsNothing);
      expect(_laneLabel('rotation'), findsNothing);
    });

    testWidgets('independently keyed properties diamond only their own '
        'lane', (tester) async {
      await _pump(
        tester,
        _project(
          camera: CutCamera.fromTrack(
            TransformTrack.empty().copyWith(
              position: PropertyTrack<CanvasPoint>().withKey(
                4,
                CanvasPoint(x: 1, y: 1),
                interpolation: PropertyKeyInterpolation.hold,
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.byKey(_laneToggleKey));
      await tester.pumpAndSettle();
      await _expandTransformGroup(tester, 'lane-cam-layer');

      expect(_laneKey('position', 4), findsOneWidget);
      expect(_laneKey('scale', 4), findsNothing);
      expect(_laneKey('rotation', 4), findsNothing);
    });

    testWidgets('drawing layers twirl down the same Transform lanes onto '
        'their OWN track (L3), keyed and undone through the session', (
      tester,
    ) async {
      late ProjectRepository repository;
      await tester.binding.setSurfaceSize(const Size(1280, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          home: HomePage(
            initialProject: _project(),
            onRepositoryCreated: (repo) => repository = repo,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.drag(
        find.byKey(const ValueKey<String>('dock-resize-bottom')),
        const Offset(0, -300),
      );
      await tester.pumpAndSettle();

      Layer drawLayer() => repository
          .requireProject()
          .tracks
          .single
          .cuts
          .single
          .layers
          .firstWhere((layer) => layer.id == const LayerId('lane-draw-layer'));

      // The drawing layer carries the twirl-down chevron now.
      final toggle = find.byKey(
        const ValueKey<String>('timeline-lane-toggle-lane-draw-layer'),
      );
      expect(toggle, findsOneWidget);
      await tester.tap(toggle);
      await tester.pumpAndSettle();
      await _expandTransformGroup(tester, 'lane-draw-layer');
      expect(
        find.byKey(
          const ValueKey<String>(
            'timeline-lane-label-lane-draw-layer-position',
          ),
        ),
        findsOneWidget,
      );

      // The navigator diamond keys the layer's own track at the playhead
      // (freezing the identity pose) — one undo step.
      expect(drawLayer().transformTrack.isEmpty, isTrue);
      await tester.tap(
        find.byKey(
          const ValueKey<String>(
            'timeline-lane-key-toggle-lane-draw-layer-position',
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(drawLayer().transformTrack.position.keys.keys, {0});
      expect(
        drawLayer().transformTrack.position.keys[0]!.value.x,
        640,
        reason: 'identity pose = canvas center (1280/2)',
      );

      await tester.tap(find.byKey(const ValueKey<String>('undo-button')));
      await tester.pumpAndSettle();
      expect(drawLayer().transformTrack.isEmpty, isTrue);
    });
  });

  // ⑤ unified lanes: truly EVERY kind twirls down the same Transform
  // group — SE rows (their transform moves the canvas dialogue) keep the
  // audio lane BELOW the transform lanes, instruction rows get the lanes
  // too (entrance parity).
  group('transform lanes on SE and instruction rows', () {
    const seLayerId = LayerId('lane-se-layer');
    const instructionLayerId = LayerId('lane-instr-layer');

    Project seInstructionProject() {
      return Project(
        id: const ProjectId('lanes-se-project'),
        name: 'Lanes SE Project',
        createdAt: DateTime.utc(2026, 7, 10),
        tracks: [
          Track(
            id: const TrackId('lanes-track'),
            name: 'Video Track',
            cuts: [
              Cut(
                id: const CutId('lanes-cut'),
                name: 'Lanes Cut',
                duration: 12,
                canvasSize: const CanvasSize(width: 1280, height: 720),
                layers: [
                  Layer(
                    id: const LayerId('lane-draw-layer'),
                    name: 'Drawing',
                    frames: const [],
                  ),
                  Layer(
                    id: seLayerId,
                    name: 'S1',
                    kind: LayerKind.se,
                    frames: const [],
                    audioClips: const [
                      AudioClip(
                        filePath: 'hit.wav',
                        frameId: FrameId('se-frame'),
                      ),
                    ],
                  ),
                  Layer(
                    id: instructionLayerId,
                    name: 'CAM 1',
                    kind: LayerKind.instruction,
                    frames: const [],
                  ),
                  Layer(
                    id: _cameraLayerId,
                    name: 'Camera',
                    kind: LayerKind.camera,
                    frames: const [],
                  ),
                ],
              ),
            ],
          ),
        ],
      );
    }

    testWidgets('SE rows twirl down Transform lanes above the audio lane '
        'and key their own track', (tester) async {
      late ProjectRepository repository;
      await tester.pumpWidget(
        MaterialApp(
          home: HomePage(
            initialProject: seInstructionProject(),
            onRepositoryCreated: (repo) => repository = repo,
          ),
        ),
      );
      await tester.pumpAndSettle();

      Layer seLayer() => repository
          .requireProject()
          .tracks
          .single
          .cuts
          .single
          .layers
          .firstWhere((layer) => layer.id == seLayerId);

      await tester.tap(
        find.byKey(
          const ValueKey<String>('timeline-lane-toggle-lane-se-layer'),
        ),
      );
      await tester.pumpAndSettle();

      final groupHeader = find.byKey(
        const ValueKey<String>(
          'timeline-lane-label-lane-se-layer-transform-group',
        ),
      );
      final audioLabel = find.byKey(
        const ValueKey<String>('timeline-lane-label-lane-se-layer-se-audio'),
      );
      expect(groupHeader, findsOneWidget);
      expect(audioLabel, findsOneWidget);
      // R4 ordering: the Audio controls lead the SE twirl-down, the
      // Transform group sits BELOW them (collapsed by default).
      expect(
        tester.getTopLeft(audioLabel).dy,
        lessThan(tester.getTopLeft(groupHeader).dy),
      );

      await _expandTransformGroup(tester, 'lane-se-layer');
      final positionLabel = find.byKey(
        const ValueKey<String>('timeline-lane-label-lane-se-layer-position'),
      );
      expect(positionLabel, findsOneWidget);
      expect(
        tester.getTopLeft(audioLabel).dy,
        lessThan(tester.getTopLeft(positionLabel).dy),
      );
      // R6-④: the group is the FULL AE set, identical to drawing layers —
      // Anchor Point and Opacity included. The layer axis is virtualized,
      // so rows below the viewport need a scroll to be built at all.
      //
      // Drive the scroll through the viewport's own controller, the way the
      // pinned rail scrollbar does (see timeline_expand_scroll_anchor_test).
      // A `drag` on the body cannot scroll here — the cells under the drag
      // point own their own drag recognizers, so the gesture never reaches
      // the Scrollable. `scrollUntilVisible` used to sit here and looked
      // green only because the last lane happened to be built already.
      final verticalScroll = tester
          .widget<SingleChildScrollView>(
            find.byKey(
              const ValueKey<String>('timeline-vertical-scroll-viewport'),
            ),
          )
          .controller!;
      expect(
        find.byKey(
          const ValueKey<String>(
            'timeline-lane-label-lane-se-layer-anchor-point',
          ),
        ),
        findsOneWidget,
      );
      verticalScroll.jumpTo(verticalScroll.position.maxScrollExtent);
      await tester.pumpAndSettle();
      expect(
        find.byKey(
          const ValueKey<String>('timeline-lane-label-lane-se-layer-opacity'),
        ),
        findsOneWidget,
      );

      // The navigator diamond keys the SE layer's OWN transform track.
      expect(seLayer().transformTrack.isEmpty, isTrue);
      verticalScroll.jumpTo(0);
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.byKey(
          const ValueKey<String>(
            'timeline-lane-key-toggle-lane-se-layer-position',
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(
          const ValueKey<String>(
            'timeline-lane-key-toggle-lane-se-layer-position',
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(seLayer().transformTrack.position.keys.keys, {0});
    });

    testWidgets('instruction rows twirl down the same Transform lanes', (
      tester,
    ) async {
      late ProjectRepository repository;
      await tester.pumpWidget(
        MaterialApp(
          home: HomePage(
            initialProject: seInstructionProject(),
            onRepositoryCreated: (repo) => repository = repo,
          ),
        ),
      );
      await tester.pumpAndSettle();

      Layer instructionLayer() => repository
          .requireProject()
          .tracks
          .single
          .cuts
          .single
          .layers
          .firstWhere((layer) => layer.id == instructionLayerId);

      final toggle = find.byKey(
        const ValueKey<String>('timeline-lane-toggle-lane-instr-layer'),
      );
      expect(toggle, findsOneWidget);
      await tester.tap(toggle);
      await tester.pumpAndSettle();
      await _expandTransformGroup(tester, 'lane-instr-layer');

      expect(
        find.byKey(
          const ValueKey<String>(
            'timeline-lane-label-lane-instr-layer-position',
          ),
        ),
        findsOneWidget,
      );
      // No audio lane on instruction rows.
      expect(
        find.byKey(
          const ValueKey<String>(
            'timeline-lane-label-lane-instr-layer-se-audio',
          ),
        ),
        findsNothing,
      );

      expect(instructionLayer().transformTrack.isEmpty, isTrue);
      await tester.ensureVisible(
        find.byKey(
          const ValueKey<String>(
            'timeline-lane-key-toggle-lane-instr-layer-rotation',
          ),
        ),
      );
      await tester.tap(
        find.byKey(
          const ValueKey<String>(
            'timeline-lane-key-toggle-lane-instr-layer-rotation',
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(instructionLayer().transformTrack.rotation.keys.keys, {0});
    });
  });

  group('collapsed camera row key-union summary', () {
    // The camera row PAINTS its cells (R28 #4); the key summary rides the
    // SHARED lane key markers since B4 (2026-08-17) — the same
    // [TimelineLaneKeyMarker] the fx transform header's union draws — so
    // the text-glyph channel stays empty on this row.
    String cameraGlyph(WidgetTester tester, int frame) =>
        timelineCellModel(tester, 'lane-cam-layer', frame).glyph;

    TimelineLaneKeyMarker cameraUnionMarker(WidgetTester tester, int frame) =>
        tester.widget<TimelineLaneKeyMarker>(
          find.byKey(
            ValueKey<String>(
              'timeline-lane-key-lane-cam-layer-transform-group-$frame',
            ),
          ),
        );

    testWidgets('keyed frames show the shared union diamonds instead of '
        'paper cells', (tester) async {
      await _pump(
        tester,
        _project(camera: CutCamera(keyframes: {0: _pose(0), 8: _pose(80)})),
      );

      // The union marks are the SHARED widget at the SHARED union size —
      // not a text glyph of their own any more.
      expect(cameraUnionMarker(tester, 0).hold, isFalse);
      expect(cameraUnionMarker(tester, 8).hold, isFalse);
      expect(
        cameraUnionMarker(tester, 0).markerSize,
        timelineLaneUnionKeyMarkerSize(
          TimelineGridMetrics.defaults.layerRowHeight,
          frameCellExtent: TimelineGridMetrics.defaults.frameCellWidth,
        ),
      );
      // The text channel says NOTHING on a camera row — no ◆/■, and never
      // the paper-cell ○; the cells carry no block chrome either.
      for (var frame = 0; frame < 12; frame += 1) {
        expect(cameraGlyph(tester, frame), '', reason: 'frame $frame');
        expect(
          timelineCellDecoration(tester, 'lane-cam-layer', frame).borderRadius,
          isNull,
          reason: 'frame $frame draws no paper block',
        );
      }
      // The a11y surface moved from a per-cell Semantics widget to the row
      // painter's semanticsBuilder — still a real semantics tree, just not
      // one `find.bySemanticsLabel` can see.
      final semantics = tester.ensureSemantics();
      await tester.pumpAndSettle();
      expect(
        timelineCellSemanticsLabels(
          tester,
          'lane-cam-layer',
        ).where((label) => label == 'camera keyframe'),
        hasLength(2),
      );
      semantics.dispose();
    });

    testWidgets('a frame whose keyed lanes ALL hold shows the hold SQUARE', (
      tester,
    ) async {
      await _pump(
        tester,
        _project(
          camera: CutCamera.fromTrack(
            TransformTrack.empty().copyWith(
              position: PropertyTrack<CanvasPoint>().withKey(
                4,
                CanvasPoint(x: 1, y: 1),
                interpolation: PropertyKeyInterpolation.hold,
              ),
              rotation: PropertyTrack<double>()
                  .withKey(8, 12, interpolation: PropertyKeyInterpolation.hold)
                  .withKey(8, 12),
            ),
          ),
        ),
      );

      expect(cameraUnionMarker(tester, 4).hold, isTrue);
      // A linear key (the second withKey overwrote hold with the default
      // linear) reads as a diamond even when another lane would hold
      // elsewhere — [transformKeyHoldUnion], the one ■ law.
      expect(cameraUnionMarker(tester, 8).hold, isFalse);
    });
  });

  group('transform lane editing policy', () {
    test('toggle adds a key with the resolved value and removes it again', () {
      final track = TransformTrack(keyframes: {0: _pose(0), 8: _pose(80)});

      final added = transformTrackWithLaneKeyToggled(
        track,
        laneId: 'position',
        frameIndex: 4,
        resolvedPose: track.resolveAt(frameIndex: 4, orElse: () => _pose(0)),
      )!;
      expect(added.position.keyAt(4)!.value, CanvasPoint(x: 40, y: 40));
      // Only the position lane changed.
      expect(added.scale.keyAt(4), isNull);

      final removed = transformTrackWithLaneKeyToggled(
        added,
        laneId: 'position',
        frameIndex: 4,
        resolvedPose: _pose(0),
      )!;
      expect(removed.position.keyAt(4), isNull);
    });

    test('lane-range shift (UI-R23 #3 part 2) moves ONLY the named lane\'s '
        'keys in range; landings below 0 or on an unshifted key void', () {
      final track = TransformTrack.empty().copyWith(
        position: PropertyTrack<CanvasPoint>()
            .withKey(2, CanvasPoint(x: 1, y: 1))
            .withKey(8, CanvasPoint(x: 9, y: 9)),
        scale: PropertyTrack<double>().withKey(2, 1.5),
      );

      final shifted = transformTrackWithLaneKeysShifted(
        track,
        laneId: 'position',
        rangeStartIndex: 0,
        rangeEndIndexExclusive: 4,
        frameDelta: 3,
      )!;
      expect(shifted.position.keys.keys.toSet(), {5, 8});
      expect(shifted.scale.keys.keys.toSet(), {2}, reason: 'other lanes stay');

      // Landing on the UNSHIFTED key at 8 voids (nothing merges silently).
      expect(
        transformTrackWithLaneKeysShifted(
          track,
          laneId: 'position',
          rangeStartIndex: 0,
          rangeEndIndexExclusive: 4,
          frameDelta: 6,
        ),
        isNull,
      );
      // Below frame 0 voids.
      expect(
        transformTrackWithLaneKeysShifted(
          track,
          laneId: 'position',
          rangeStartIndex: 0,
          rangeEndIndexExclusive: 4,
          frameDelta: -3,
        ),
        isNull,
      );
      // No keys in range = nothing to move.
      expect(
        transformTrackWithLaneKeysShifted(
          track,
          laneId: 'rotation',
          rangeStartIndex: 0,
          rangeEndIndexExclusive: 4,
          frameDelta: 1,
        ),
        isNull,
      );
    });

    // 2026-08-08: the single-key MOVE policy went out with the key
    // marker's private drag — re-timing is the span shift below, which
    // this group already covers ('lane-range shift … moves ONLY the named
    // lane's keys in range').

    test('value edits parse AE units and preserve interpolation', () {
      final track = TransformTrack.empty().copyWith(
        scale: PropertyTrack<double>().withKey(
          0,
          1,
          interpolation: PropertyKeyInterpolation.hold,
        ),
      );

      final scaled = transformTrackWithLaneValueEdited(
        track,
        laneId: 'scale',
        frameIndex: 0,
        input: '250%',
      )!;
      expect(scaled.scale.keyAt(0)!.value, 2.5);
      expect(
        scaled.scale.keyAt(0)!.interpolation,
        PropertyKeyInterpolation.hold,
        reason: 'editing a value keeps the key interpolation',
      );

      final positioned = transformTrackWithLaneValueEdited(
        track,
        laneId: 'position',
        frameIndex: 4,
        input: ' 320, 180 ',
      )!;
      expect(positioned.position.keyAt(4)!.value, CanvasPoint(x: 320, y: 180));

      final rotated = transformTrackWithLaneValueEdited(
        track,
        laneId: 'rotation',
        frameIndex: 2,
        input: '-45°',
      )!;
      expect(rotated.rotation.keyAt(2)!.value, -45);

      // Garbage input is rejected.
      expect(
        transformTrackWithLaneValueEdited(
          track,
          laneId: 'scale',
          frameIndex: 0,
          input: 'abc',
        ),
        isNull,
      );
      expect(
        transformTrackWithLaneValueEdited(
          track,
          laneId: 'position',
          frameIndex: 0,
          input: '12',
        ),
        isNull,
      );
    });

    test('hold toggle flips a key between linear and hold', () {
      final track = TransformTrack.empty().copyWith(
        rotation: PropertyTrack<double>().withKey(3, 45),
      );

      final held = transformTrackWithLaneHoldToggled(
        track,
        laneId: 'rotation',
        frameIndex: 3,
      )!;
      expect(
        held.rotation.keyAt(3)!.interpolation,
        PropertyKeyInterpolation.hold,
      );

      final linear = transformTrackWithLaneHoldToggled(
        held,
        laneId: 'rotation',
        frameIndex: 3,
      )!;
      expect(
        linear.rotation.keyAt(3)!.interpolation,
        PropertyKeyInterpolation.linear,
      );
    });
  });

  group('camera lane key editing in the timeline', () {
    Future<void> expand(WidgetTester tester) async {
      await tester.tap(find.byKey(_laneToggleKey));
      await tester.pumpAndSettle();
      await _expandTransformGroup(tester, 'lane-cam-layer');
    }

    testWidgets('the navigator diamond toggles a key at the playhead on '
        'ONE lane', (tester) async {
      await _pump(
        tester,
        _project(camera: CutCamera(keyframes: {0: _pose(0), 8: _pose(80)})),
      );
      await expand(tester);

      // Playhead starts at frame 0 where all lanes are keyed; toggling the
      // position lane removes only its key.
      await tester.tap(
        find.byKey(
          const ValueKey<String>(
            'timeline-lane-key-toggle-lane-cam-layer-position',
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(_laneKey('position', 0), findsNothing);
      expect(_laneKey('scale', 0), findsOneWidget);

      // Toggling again re-keys the property at its resolved value.
      await tester.tap(
        find.byKey(
          const ValueKey<String>(
            'timeline-lane-key-toggle-lane-cam-layer-position',
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(_laneKey('position', 0), findsOneWidget);

      // One undo step per toggle.
      await tester.tap(find.byKey(const ValueKey<String>('undo-button')));
      await tester.pumpAndSettle();
      expect(_laneKey('position', 0), findsNothing);
    });

    testWidgets('a camera key is SELECTED and then moved, like every other '
        'lane and like a frame block', (tester) async {
      await _pump(
        tester,
        _project(camera: CutCamera(keyframes: {0: _pose(0), 8: _pose(80)})),
      );
      await expand(tester);

      // 2026-08-08: this used to be a marker drag that re-timed the key on
      // the spot — the camera row was the last place on this axis with a
      // grammar of its own, because the lane-move path had no arm for the
      // track its lanes actually edit (`cut.camera.track`).
      //
      // Default zoom = 24px per frame. The first drag SELECTS frame 8; the
      // second, starting inside that selection, moves it +2.
      final band = find.byKey(
        const ValueKey<String>(
          'timeline-lane-range-gesture-lane-cam-layer-position',
        ),
      );
      final keyAt8 = tester.getCenter(_laneKey('position', 8));
      await tester.dragFrom(keyAt8, const Offset(4, 0), kind: PointerDeviceKind.mouse);
      await tester.pumpAndSettle();
      expect(band, findsOneWidget, reason: 'the camera lane has a band now');

      await tester.dragFrom(keyAt8, const Offset(48, 0), kind: PointerDeviceKind.mouse);
      await tester.pumpAndSettle();

      expect(_laneKey('position', 8), findsNothing);
      expect(_laneKey('position', 10), findsOneWidget);
      // Other lanes keep their key at 8 — the camera's lanes are per
      // PROPERTY, whatever the row's cells summarise.
      expect(_laneKey('scale', 8), findsOneWidget);
    });

    testWidgets('a LAYER lane hands its key to Frame ▾ Delete — press the '
        'diamond to stand there, then Delete. R10 R3 retired the marker\'s '
        'own menu and the toolbar is the home', (tester) async {
      await _pump(tester, _project());
      // Open the DRAWING layer's Transform lanes: unlike the camera's
      // atomic keyframes, they carry the lane selection domain, which is
      // what lets a press make the lane the verb's subject.
      await tester.tap(
        find.byKey(
          const ValueKey<String>('timeline-lane-toggle-lane-draw-layer'),
        ),
      );
      await tester.pumpAndSettle();
      await _expandTransformGroup(tester, 'lane-draw-layer');

      Finder drawKey(String laneId, int frame) => find.byKey(
        ValueKey<String>('timeline-lane-key-lane-draw-layer-$laneId-$frame'),
      );

      // Key rotation at the playhead through its navigator diamond.
      await tester.tap(
        find.byKey(
          const ValueKey<String>(
            'timeline-lane-key-toggle-lane-draw-layer-rotation',
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(drawKey('rotation', 0), findsOneWidget);

      // A press does all three at once (R10 #19's _standOnLane): seek,
      // take the layer, and make the LANE the verb's subject. It lands on
      // the DIAMOND, which is the point — its hit box covers the cell, so
      // a keyed frame would otherwise be the one frame no press can reach.
      await tester.tap(drawKey('rotation', 0));
      await tester.pumpAndSettle();

      // The ONE delete (T24 retired the frame menu's copy). Standing on the
      // lane names no ROWS, so the ladder falls through to the cell rung —
      // and that rung has always answered a lane key first.
      final sharedDelete = find.byKey(
        const ValueKey<String>('shared-delete-button'),
      );
      // The bar scrolls, so the pill can sit off the right edge.
      await tester.ensureVisible(sharedDelete);
      await tester.pumpAndSettle();
      await tester.tap(sharedDelete);
      await tester.pumpAndSettle();

      expect(drawKey('rotation', 0), findsNothing);
    });

    testWidgets('the marker\'s long-press and right-click open nothing', (
      tester,
    ) async {
      await _pump(
        tester,
        _project(camera: CutCamera(keyframes: {0: _pose(0), 8: _pose(80)})),
      );
      await expand(tester);
      await tester.ensureVisible(_laneKey('rotation', 8));
      await tester.pumpAndSettle();

      await tester.longPress(_laneKey('rotation', 8));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey<String>('lane-key-menu-delete')),
        findsNothing,
      );

      await tester.tap(_laneKey('rotation', 8), buttons: kSecondaryButton);
      await tester.pumpAndSettle();
      expect(find.byType(PopupMenuItem<String>), findsNothing);
      expect(_laneKey('rotation', 8), findsOneWidget);
    });

    testWidgets('the value column shows AE units and typing keys the '
        'value at the playhead', (tester) async {
      await _pump(
        tester,
        _project(camera: CutCamera(keyframes: {0: _pose(100), 8: _pose(80)})),
      );
      await expand(tester);

      // Resolved values at the playhead (frame 0), AE display units.
      expect(
        tester
            .widget<Text>(
              find.descendant(
                of: find.byKey(
                  const ValueKey<String>(
                    'timeline-lane-value-lane-cam-layer-scale',
                  ),
                ),
                matching: find.byType(Text),
              ),
            )
            .data,
        '150%',
      );

      // Type a new scale: Enter commits and keys the value there.
      await tester.tap(
        find.byKey(
          const ValueKey<String>('timeline-lane-value-lane-cam-layer-scale'),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(
          const ValueKey<String>(
            'timeline-lane-value-field-lane-cam-layer-scale',
          ),
        ),
        '200%',
      );
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      expect(
        tester
            .widget<Text>(
              find.descendant(
                of: find.byKey(
                  const ValueKey<String>(
                    'timeline-lane-value-lane-cam-layer-scale',
                  ),
                ),
                matching: find.byType(Text),
              ),
            )
            .data,
        '200%',
      );
      // The scale lane stays keyed at frame 0 with the new value; other
      // lanes are untouched.
      expect(_laneKey('scale', 0), findsOneWidget);
    });

    test('scrubTransformLaneValue maps drag axes onto components in the '
        'editor text form', () {
      expect(
        scrubTransformLaneValue('position', '12, -3', const Offset(10, 5)),
        '22, 2',
      );
      expect(
        scrubTransformLaneValue('scale', '150%', const Offset(40, 0)),
        '170%',
      );
      expect(
        scrubTransformLaneValue('rotation', '0°', const Offset(-10, 0)),
        '-5°',
      );
      // The anchor lane scrubs like position; opacity clamps to 0–100.
      expect(
        scrubTransformLaneValue('anchor-point', '10, 20', const Offset(4, -6)),
        '14, 14',
      );
      expect(
        scrubTransformLaneValue('opacity', '100%', const Offset(-30, 0)),
        '85%',
      );
      expect(
        scrubTransformLaneValue('opacity', '100%', const Offset(30, 0)),
        '100%',
      );
      expect(
        scrubTransformLaneValue('scale', 'garbage', const Offset(1, 0)),
        isNull,
      );
    });

    testWidgets('dragging the value scrubs it and commits ONE key on '
        'release', (tester) async {
      await _pump(
        tester,
        _project(camera: CutCamera(keyframes: {0: _pose(100), 8: _pose(80)})),
      );
      await expand(tester);

      // +40px horizontally = +20% at the scale lane's 0.5%/px rate.
      await tester.drag(
        find.byKey(
          const ValueKey<String>('timeline-lane-value-lane-cam-layer-scale'),
        ),
        const Offset(40, 0),
      );
      await tester.pumpAndSettle();

      expect(
        tester
            .widget<Text>(
              find.descendant(
                of: find.byKey(
                  const ValueKey<String>(
                    'timeline-lane-value-lane-cam-layer-scale',
                  ),
                ),
                matching: find.byType(Text),
              ),
            )
            .data,
        '170%',
      );
      expect(_laneKey('scale', 0), findsOneWidget);
    });

    testWidgets('prev/next navigator jumps the playhead between keys', (
      tester,
    ) async {
      await _pump(
        tester,
        _project(camera: CutCamera(keyframes: {0: _pose(0), 8: _pose(80)})),
      );
      await expand(tester);

      await tester.tap(
        find.byKey(
          const ValueKey<String>(
            'timeline-lane-next-key-lane-cam-layer-position',
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        tester
            .widget<Text>(
              find.byKey(
                const ValueKey<String>('timeline-local-frame-counter'),
              ),
            )
            .data,
        '9',
      );
    });
  });

  group('camera property lanes in the X-sheet', () {
    const laneToggleKey = ValueKey<String>('xsheet-lane-toggle-lane-cam-layer');

    Finder laneLabel(String laneId) => find.byKey(
      ValueKey<String>('xsheet-lane-label-lane-cam-layer-$laneId'),
    );
    Finder laneKey(String laneId, int frame) => find.byKey(
      ValueKey<String>('xsheet-lane-key-lane-cam-layer-$laneId-$frame'),
    );

    // Lane COLUMNS extend the sheet rightward and the default 36px frame
    // rows put late frames below the bottom dock's fold — a wide surface,
    // near keys (frames 0/4) AND a taller bottom dock (splitter drag, like
    // a user would) keep every gesture target on screen.
    Future<void> pumpXSheet(WidgetTester tester, Project project) async {
      await tester.binding.setSurfaceSize(const Size(1280, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await _pump(tester, project);
      await tester.drag(
        find.byKey(const ValueKey<String>('dock-resize-bottom')),
        const Offset(0, -300),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(
          const ValueKey<String>('timeline-orientation-toggle-button'),
        ),
      );
      await tester.pumpAndSettle();
    }

    Future<void> expand(WidgetTester tester) async {
      await tester.tap(find.byKey(laneToggleKey));
      await tester.pumpAndSettle();
      await _expandTransformGroup(
        tester,
        'lane-cam-layer',
        keyPrefix: 'xsheet',
      );
    }

    testWidgets('twirl-down opens the transform lanes as COLUMNS with key '
        'markers', (tester) async {
      await pumpXSheet(
        tester,
        _project(camera: CutCamera(keyframes: {0: _pose(0), 4: _pose(80)})),
      );

      // Collapsed by default: chevron on the camera column header, no lane
      // columns.
      expect(find.byKey(laneToggleKey), findsOneWidget);
      expect(laneLabel('position'), findsNothing);

      await expand(tester);

      expect(laneLabel('position'), findsOneWidget);
      expect(laneLabel('scale'), findsOneWidget);
      expect(laneLabel('rotation'), findsOneWidget);
      for (final laneId in ['position', 'scale', 'rotation']) {
        expect(laneKey(laneId, 0), findsOneWidget);
        expect(laneKey(laneId, 4), findsOneWidget);
      }

      await expand(tester);
      expect(laneLabel('position'), findsNothing);
    });

    testWidgets('the navigator diamond toggles a key at the playhead on '
        'ONE lane', (tester) async {
      await pumpXSheet(
        tester,
        _project(camera: CutCamera(keyframes: {0: _pose(0), 4: _pose(80)})),
      );
      await expand(tester);

      await tester.tap(
        find.byKey(
          const ValueKey<String>(
            'xsheet-lane-key-toggle-lane-cam-layer-position',
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(laneKey('position', 0), findsNothing);
      expect(laneKey('scale', 0), findsOneWidget);

      await tester.tap(
        find.byKey(
          const ValueKey<String>(
            'xsheet-lane-key-toggle-lane-cam-layer-position',
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(laneKey('position', 0), findsOneWidget);
    });

    testWidgets('select, then move — VERTICALLY, frame-snapped', (
      tester,
    ) async {
      await pumpXSheet(
        tester,
        _project(camera: CutCamera(keyframes: {0: _pose(0), 4: _pose(80)})),
      );
      await expand(tester);

      // R10: the slop is part of the travel, so the TOTAL snaps — two
      // frame rows is +2 frames. Read from the metrics rather than typed:
      // R6 made the sheet's frame row the timeline's frame cell (36 → 24),
      // and a literal here just meant a different answer, silently.
      //
      // Drag the key at frame 0, not the one at 4: R6's header is the whole
      // rail stood up, so even a maxed bottom dock leaves the sheet about
      // four rows and frame 4's marker sits on the clip edge, where a drag
      // cannot start. (The sheet is meant for a tall SIDE dock; the bottom
      // dock's own 640 ceiling is what bounds this.)
      final step = XSheetTimelineGrid.defaultMetrics.frameCellWidth;
      final keyAt0 = tester.getCenter(laneKey('position', 0));
      // 2026-08-08: two drags, not one. The first selects frame 0 — the
      // marker has no drag of its own any more, on this row or any other.
      await tester.dragFrom(
        keyAt0,
        const Offset(0, 4),
        kind: PointerDeviceKind.mouse,
      );
      await tester.pumpAndSettle();
      await tester.dragFrom(
        keyAt0,
        Offset(0, step * 2),
        kind: PointerDeviceKind.mouse,
      );
      await tester.pumpAndSettle();

      expect(laneKey('position', 0), findsNothing);
      expect(laneKey('position', 2), findsOneWidget);
      // The lane's OTHER key is untouched, and so is every other lane.
      expect(laneKey('position', 4), findsOneWidget);
      expect(laneKey('scale', 0), findsOneWidget);
    });

    testWidgets('the marker\'s long-press and right-click open nothing (the '
        'x-sheet twin) — the camera lane keeps its navigator diamond as '
        'the per-key home', (tester) async {
      await pumpXSheet(
        tester,
        _project(camera: CutCamera(keyframes: {0: _pose(0), 4: _pose(80)})),
      );
      await expand(tester);

      // Frame 0's marker, not frame 4's. The sheet is a tall panel in a
      // dock capped at 640, so its last row sits right on the content
      // edge — and the 문턱 is on that edge now. A marker under the
      // threshold is a fact about the sheet's height, not about what a
      // long-press does to a key, and this test is about the latter.
      await tester.longPress(laneKey('rotation', 0));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey<String>('lane-key-menu-delete')),
        findsNothing,
      );

      await tester.tap(laneKey('rotation', 0), buttons: kSecondaryButton);
      await tester.pumpAndSettle();
      expect(find.byType(PopupMenuItem<String>), findsNothing);
      expect(laneKey('rotation', 0), findsOneWidget);
    });

    testWidgets('the header value cell shows AE units, types and scrubs', (
      tester,
    ) async {
      await pumpXSheet(
        tester,
        _project(camera: CutCamera(keyframes: {0: _pose(100), 4: _pose(80)})),
      );
      await expand(tester);

      // The readout is stacked LINES of horizontal text (user, 2026-08-08).
      // It used to go through the vertical writer with the rest of the
      // sheet's labels, which spelled a number out one glyph per cell.
      List<String> valueLines() => tester
          .widgetList<Text>(
            find.descendant(
              of: find.byKey(
                const ValueKey<String>('xsheet-lane-value-lane-cam-layer-scale'),
              ),
              matching: find.byType(Text),
            ),
          )
          .map((text) => text.data ?? '')
          .toList();

      expect(valueLines(), ['150%']);

      // Typing keys the value at the playhead (Enter commits).
      await tester.tap(
        find.byKey(
          const ValueKey<String>('xsheet-lane-value-lane-cam-layer-scale'),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(
          const ValueKey<String>(
            'xsheet-lane-value-field-lane-cam-layer-scale',
          ),
        ),
        '200%',
      );
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(valueLines(), ['200%']);

      // Scrubbing: +40px horizontally = +20% at the 0.5%/px rate — the
      // drag-axis mapping is the LANE's, identical in both orientations.
      await tester.drag(
        find.byKey(
          const ValueKey<String>('xsheet-lane-value-lane-cam-layer-scale'),
        ),
        const Offset(40, 0),
      );
      await tester.pumpAndSettle();
      expect(valueLines(), ['220%']);
      expect(laneKey('scale', 0), findsOneWidget);
    });

    testWidgets('a coordinate pair stacks as number, comma, number', (
      tester,
    ) async {
      await pumpXSheet(
        tester,
        _project(camera: CutCamera(keyframes: {0: _pose(100), 4: _pose(80)})),
      );
      await expand(tester);

      // The whole point of the change (user, 2026-08-08): `1170, 827` is
      // three READABLE tokens down the column, not seven glyph cells —
      // a four-digit run is past the 縦中横 limit and the vertical writer
      // used to fall back to one digit per cell.
      expect(
        tester
            .widgetList<Text>(
              find.descendant(
                of: find.byKey(
                  const ValueKey<String>(
                    'xsheet-lane-value-lane-cam-layer-position',
                  ),
                ),
                matching: find.byType(Text),
              ),
            )
            .map((text) => text.data ?? '')
            .toList(),
        hasLength(3),
      );
    });

    testWidgets('prev/next navigator jumps the playhead between keys', (
      tester,
    ) async {
      await pumpXSheet(
        tester,
        _project(camera: CutCamera(keyframes: {0: _pose(0), 4: _pose(80)})),
      );
      await expand(tester);

      await tester.tap(
        find.byKey(
          const ValueKey<String>(
            'xsheet-lane-next-key-lane-cam-layer-position',
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        tester
            .widget<Text>(
              find.byKey(
                const ValueKey<String>('timeline-local-frame-counter'),
              ),
            )
            .data,
        '5',
      );
    });
  });
}
