import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/bitmap_tile.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/attached_mode.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_folder.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/property_track.dart';
import 'package:anicel/src/models/tile_coord.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/models/transform_track.dart';
import 'package:anicel/src/services/cut_frame_composite_plan.dart';

void main() {
  const canvasSize = CanvasSize(width: 4, height: 4);

  BitmapSurface surfaceWithMarker(int marker) {
    return BitmapSurface(
      canvasSize: canvasSize,
      tileSize: 4,
      tiles: {
        TileCoord(x: 0, y: 0): BitmapTile(
          coord: TileCoord(x: 0, y: 0),
          size: 4,
          pixels: Uint8List(4 * 4 * 4)..[0] = marker,
        ),
      },
    );
  }

  Frame frame(String id) =>
      Frame(id: FrameId(id), duration: 1, strokes: const []);

  Cut cut(List<Layer> layers) => Cut(
    id: const CutId('cut'),
    name: 'Cut',
    layers: layers,
    duration: 24,
    canvasSize: canvasSize,
  );

  // Resolver keyed by frame id suffix number as marker.
  BitmapSurface? resolver(Layer layer, Frame frame) {
    final marker = int.tryParse(frame.id.value.split('-').last);
    return marker == null ? null : surfaceWithMarker(marker);
  }

  int markerOf(CutFrameCompositeLayer layer) =>
      layer.surface.tiles.values.single.pixels[0];

  group('folder composite', () {
    Layer memberLayer({String folder = 'f'}) => Layer(
      id: const LayerId('member'),
      name: 'A',
      frames: [frame('frame-1')],
      timeline: {
        0: TimelineExposure.drawing(const FrameId('frame-1'), length: 1),
      },
      folderId: LayerId(folder),
    );

    // Folder ROWS sit directly above their member run in the stack.
    Layer folderRow(
      String id, {
      String? parent,
      bool isVisible = true,
      double opacity = 1,
      TransformTrack? transformTrack,
    }) => createFolderLayer(
      id: LayerId(id),
      name: id.toUpperCase(),
      parentId: parent == null ? null : LayerId(parent),
    ).copyWith(
      isVisible: isVisible,
      opacity: opacity,
      transformTrack: transformTrack,
    );

    test('a folder row paints nothing of its own', () {
      final plan = planCutFrameComposite(
        cut: cut([memberLayer(), folderRow('f')]),
        frameIndex: 0,
        surfaceResolver: resolver,
      );
      expect(plan, hasLength(1), reason: 'only the member contributes pixels');
    });

    test('a hidden folder (or hidden ancestor) hides its subtree', () {
      final hidden = planCutFrameComposite(
        cut: cut([memberLayer(), folderRow('f', isVisible: false)]),
        frameIndex: 0,
        surfaceResolver: resolver,
      );
      expect(hidden, isEmpty);

      final nestedHidden = planCutFrameComposite(
        cut: cut([
          memberLayer(folder: 'inner'),
          folderRow('inner', parent: 'outer'),
          folderRow('outer', isVisible: false),
        ]),
        frameIndex: 0,
        surfaceResolver: resolver,
      );
      expect(nestedHidden, isEmpty, reason: 'the hidden ANCESTOR gates');
    });

    test('folder opacity folds into the member (nested folders multiply)',
        () {
      final plan = planCutFrameComposite(
        cut: cut([
          memberLayer(folder: 'inner'),
          folderRow('inner', parent: 'outer', opacity: 0.5),
          folderRow('outer', opacity: 0.5),
        ]),
        frameIndex: 0,
        surfaceResolver: resolver,
      );
      expect(plan.single.opacity, closeTo(0.25, 1e-9));
    });

    test('folder FX composes into the entry pose: a member with no own '
        'pose rides the folder, one with a pose gets the composition', () {
      final folderTrack = TransformTrack(
        keyframes: {
          0: TransformPose(center: CanvasPoint(x: 3, y: 2), zoom: 2),
        },
      );
      final plan = planCutFrameComposite(
        cut: cut([
          memberLayer(),
          folderRow('f', transformTrack: folderTrack),
        ]),
        frameIndex: 0,
        surfaceResolver: resolver,
      );
      final pose = plan.single.pose!;
      expect(pose.center, CanvasPoint(x: 3, y: 2));
      expect(pose.zoom, 2);

      // Member with its OWN pose: folder composes over layer (zooms
      // multiply).
      final layerTrack = TransformTrack(
        keyframes: {
          0: TransformPose(center: CanvasPoint(x: 2, y: 2), zoom: 3),
        },
      );
      final composedPlan = planCutFrameComposite(
        cut: cut([
          memberLayer().copyWith(transformTrack: layerTrack),
          folderRow('f', transformTrack: folderTrack),
        ]),
        frameIndex: 0,
        surfaceResolver: resolver,
      );
      expect(composedPlan.single.pose!.zoom, 6);
    });

    test('the folder fx switch IS the layer fx switch', () {
      final folderTrack = TransformTrack(
        keyframes: {
          0: TransformPose(center: CanvasPoint(x: 3, y: 2), zoom: 2),
        },
      );
      final bypassed = planCutFrameComposite(
        cut: cut([
          memberLayer(),
          folderRow('f', transformTrack: folderTrack),
        ]),
        frameIndex: 0,
        surfaceResolver: resolver,
        fxBypassedLayerIds: {const LayerId('f')},
      );
      expect(
        bypassed.single.pose,
        isNull,
        reason: 'R28 #13: a bypassed folder contributes no FX — and it now '
            'sits in the ONE bypass set, keyed by its own layer id',
      );
    });
  });

  test('composites layers bottom to top in list order', () {
    final plan = planCutFrameComposite(
      cut: cut([
        Layer(
          id: const LayerId('bottom'),
          name: 'A',
          frames: [frame('frame-1')],
          timeline: {
            0: TimelineExposure.drawing(const FrameId('frame-1'), length: 1),
          },
        ),
        Layer(
          id: const LayerId('top'),
          name: 'B',
          frames: [frame('frame-2')],
          timeline: {
            0: TimelineExposure.drawing(const FrameId('frame-2'), length: 1),
          },
        ),
      ]),
      frameIndex: 0,
      surfaceResolver: resolver,
    );

    expect(plan.map(markerOf), [1, 2]);
  });

  test('skips camera, hidden and fully transparent layers', () {
    final plan = planCutFrameComposite(
      cut: cut([
        Layer(
          id: const LayerId('visible'),
          name: 'A',
          frames: [frame('frame-1')],
          timeline: {
            0: TimelineExposure.drawing(const FrameId('frame-1'), length: 1),
          },
        ),
        Layer(
          id: const LayerId('hidden'),
          name: 'B',
          frames: [frame('frame-2')],
          timeline: {
            0: TimelineExposure.drawing(const FrameId('frame-2'), length: 1),
          },
          isVisible: false,
        ),
        Layer(
          id: const LayerId('transparent'),
          name: 'C',
          frames: [frame('frame-3')],
          timeline: {
            0: TimelineExposure.drawing(const FrameId('frame-3'), length: 1),
          },
          opacity: 0,
        ),
        Layer(
          id: const LayerId('camera'),
          name: 'Camera',
          frames: const [],
          timeline: const {},
          kind: LayerKind.camera,
        ),
      ]),
      frameIndex: 0,
      surfaceResolver: resolver,
    );

    expect(plan.map(markerOf), [1]);
  });

  test('held exposures keep the frame across their block coverage', () {
    final layer = Layer(
      id: const LayerId('layer'),
      name: 'A',
      frames: [frame('frame-1'), frame('frame-2')],
      timeline: {
        0: TimelineExposure.drawing(const FrameId('frame-1'), length: 6),
        6: TimelineExposure.drawing(const FrameId('frame-2'), length: 4),
      },
    );

    List<CutFrameCompositeLayer> planAt(int index) => planCutFrameComposite(
      cut: cut([layer]),
      frameIndex: index,
      surfaceResolver: resolver,
    );

    expect(planAt(0).map(markerOf), [1]);
    expect(planAt(5).map(markerOf), [1]);
    expect(planAt(6).map(markerOf), [2]);
    expect(planAt(9).map(markerOf), [2]);
    // Past the last block's explicit end nothing shows.
    expect(planAt(99), isEmpty);
  });

  test('blank exposures and missing surfaces contribute nothing', () {
    final plan = planCutFrameComposite(
      cut: cut([
        Layer(
          id: const LayerId('blank'),
          name: 'A',
          frames: [frame('frame-1')],
          timeline: {
            0: TimelineExposure.drawing(const FrameId('frame-1'), length: 2),
          },
        ),
        Layer(
          id: const LayerId('undrawn'),
          name: 'B',
          frames: [frame('frame-x')],
          timeline: {
            0: TimelineExposure.drawing(const FrameId('frame-x'), length: 1),
          },
        ),
      ]),
      frameIndex: 3,
      surfaceResolver: resolver,
    );

    expect(plan, isEmpty);
  });

  test('layer opacity carries into the plan', () {
    final plan = planCutFrameComposite(
      cut: cut([
        Layer(
          id: const LayerId('faded'),
          name: 'A',
          frames: [frame('frame-1')],
          timeline: {
            0: TimelineExposure.drawing(const FrameId('frame-1'), length: 1),
          },
          opacity: 0.25,
        ),
      ]),
      frameIndex: 0,
      surfaceResolver: resolver,
    );

    expect(plan.single.opacity, 0.25);
  });

  test('layer transforms resolve into the plan; empty tracks stay the '
      'identity null', () {
    Layer transformed({TransformTrack? track}) => Layer(
      id: const LayerId('moved'),
      name: 'A',
      frames: [frame('frame-1')],
      timeline: {
        0: TimelineExposure.drawing(const FrameId('frame-1'), length: 12),
      },
      transformTrack: track,
    );

    // Empty track = identity: the plan carries null so compositors skip
    // the transform entirely.
    final identityPlan = planCutFrameComposite(
      cut: cut([transformed()]),
      frameIndex: 0,
      surfaceResolver: resolver,
    );
    expect(identityPlan.single.pose, isNull);

    // A keyed track resolves per frame (interpolating between keys); the
    // unkeyed components fall back to the identity pose (canvas center).
    final track = TransformTrack(
      keyframes: {
        0: TransformPose(center: CanvasPoint(x: 0, y: 0)),
        10: TransformPose(center: CanvasPoint(x: 10, y: 20)),
      },
    );
    final poseAt5 = planCutFrameComposite(
      cut: cut([transformed(track: track)]),
      frameIndex: 5,
      surfaceResolver: resolver,
    ).single.pose;
    expect(poseAt5, isNotNull);
    expect(poseAt5!.center.x, 5);
    expect(poseAt5.center.y, 10);
    expect(poseAt5.zoom, 1);
  });

  test('layerIdentityPose centers the canvas at zoom 1, no rotation', () {
    final pose = layerIdentityPose(canvasSize);
    expect(pose.center.x, 2);
    expect(pose.center.y, 2);
    expect(pose.zoom, 1);
    expect(pose.rotationDegrees, 0);
  });

  Layer animated({TransformTrack? track, double opacity = 1}) => Layer(
    id: const LayerId('animated'),
    name: 'A',
    frames: [frame('frame-1')],
    timeline: {
      0: TimelineExposure.drawing(const FrameId('frame-1'), length: 12),
    },
    transformTrack: track,
    opacity: opacity,
  );

  test('the animated Opacity lane multiplies the static layer opacity; a '
      'zero sample skips the layer', () {
    final fading = TransformTrack.empty().copyWith(
      opacity: PropertyTrack<double>().withKey(0, 1).withKey(10, 0),
    );

    final plan = planCutFrameComposite(
      cut: cut([animated(track: fading, opacity: 0.5)]),
      frameIndex: 5,
      surfaceResolver: resolver,
    );
    expect(plan.single.opacity, closeTo(0.25, 1e-9));
    // Opacity animation alone never forces the transform path.
    expect(plan.single.pose, isNull);

    final faded = planCutFrameComposite(
      cut: cut([animated(track: fading)]),
      frameIndex: 10,
      surfaceResolver: resolver,
    );
    expect(faded, isEmpty);
  });

  test('the anchor point resolves into the plan (null = canvas center)', () {
    final anchored = TransformTrack.empty().copyWith(
      position: PropertyTrack<CanvasPoint>().withKey(
        0,
        CanvasPoint(x: 3, y: 3),
      ),
      anchorPoint: PropertyTrack<CanvasPoint>().withKey(
        0,
        CanvasPoint(x: 1, y: 1),
      ),
    );

    final plan = planCutFrameComposite(
      cut: cut([animated(track: anchored)]),
      frameIndex: 0,
      surfaceResolver: resolver,
    );
    expect(plan.single.anchorPoint, CanvasPoint(x: 1, y: 1));

    final unanchored = planCutFrameComposite(
      cut: cut([
        animated(
          track: TransformTrack(
            keyframes: {0: TransformPose(center: CanvasPoint(x: 3, y: 3))},
          ),
        ),
      ]),
      frameIndex: 0,
      surfaceResolver: resolver,
    );
    expect(unanchored.single.anchorPoint, isNull);
  });

  test('fx-bypassed layers compose with identity pose and static opacity '
      '(the layer-label fx switch)', () {
    final track =
        TransformTrack(
          keyframes: {0: TransformPose(center: CanvasPoint(x: 0, y: 0))},
        ).copyWith(
          opacity: PropertyTrack<double>().withKey(0, 0.5),
          anchorPoint: PropertyTrack<CanvasPoint>().withKey(
            0,
            CanvasPoint(x: 1, y: 1),
          ),
        );

    final bypassed = planCutFrameComposite(
      cut: cut([animated(track: track, opacity: 0.8)]),
      frameIndex: 0,
      surfaceResolver: resolver,
      fxBypassedLayerIds: {const LayerId('animated')},
    ).single;

    expect(bypassed.pose, isNull);
    expect(bypassed.anchorPoint, isNull);
    expect(bypassed.opacity, closeTo(0.8, 1e-9));
  });

  group('attach layers (W5)', () {
    // Base at list position 1, flanked by its attach rows: [below, base,
    // above]. Base block b-1 at [0,4); links: below → f-2, above → f-3.
    Layer baseLayer({TransformTrack? track, bool isVisible = true}) => Layer(
      id: const LayerId('base'),
      name: 'A',
      frames: [frame('frame-1')],
      timeline: {
        0: TimelineExposure.drawing(const FrameId('frame-1'), length: 4),
      },
      transformTrack: track,
      isVisible: isVisible,
    );
    Layer attachRow(
      String id,
      int marker, {
      double opacity = 1,
      bool isVisible = true,
      LayerId attachedTo = const LayerId('base'),
    }) => Layer(
      id: LayerId(id),
      name: 'A +',
      frames: [frame('frame-$marker')],
      timeline: const {},
      opacity: opacity,
      isVisible: isVisible,
      attachedToLayerId: attachedTo,
      baseFrameLinks: {const FrameId('frame-1'): FrameId('frame-$marker')},
    );

    test('a FREE attach row composites from its OWN timeline (UI-R21 #3), '
        'independent of the base eye (UI-R24 #5)', () {
      Layer freeRow({bool baseVisible = true}) => Layer(
        id: const LayerId('free'),
        name: '+1',
        frames: [frame('frame-9')],
        // Own exposure PAST the base's block — a synced row could never
        // show here.
        timeline: {
          5: TimelineExposure.drawing(const FrameId('frame-9'), length: 2),
        },
        attachedToLayerId: const LayerId('base'),
        attachedMode: AttachedMode.free,
      );

      final plan = planCutFrameComposite(
        cut: cut([baseLayer(), freeRow()]),
        frameIndex: 5,
        surfaceResolver: resolver,
      );
      expect(plan.map(markerOf), [9], reason: 'own timeline resolves');

      // Hiding the base hides ONLY the base's own picture (UI-R24 #5):
      // the attach row keeps compositing under its own eye.
      final hidden = planCutFrameComposite(
        cut: cut([baseLayer(isVisible: false), freeRow()]),
        frameIndex: 5,
        surfaceResolver: resolver,
      );
      expect(hidden.map(markerOf), [9]);
    });

    test('attach rows composite in list order around their base — '
        '[below, base, above] — riding the base exposure', () {
      final plan = planCutFrameComposite(
        cut: cut([attachRow('below', 2), baseLayer(), attachRow('above', 3)]),
        frameIndex: 0,
        surfaceResolver: resolver,
      );
      expect(plan.map(markerOf), [2, 1, 3]);

      // Past the base's block, nothing on any of the three.
      final past = planCutFrameComposite(
        cut: cut([attachRow('below', 2), baseLayer(), attachRow('above', 3)]),
        frameIndex: 5,
        surfaceResolver: resolver,
      );
      expect(past, isEmpty);
    });

    test('the BASE pose and animated opacity apply to attach rows (fx '
        'shared), multiplied with each row own static opacity', () {
      final track = TransformTrack(
        keyframes: {0: TransformPose(center: CanvasPoint(x: 0, y: 0))},
      ).copyWith(opacity: PropertyTrack<double>().withKey(0, 0.5));
      final plan = planCutFrameComposite(
        cut: cut([
          baseLayer(track: track),
          attachRow('above', 3, opacity: 0.5),
        ]),
        frameIndex: 0,
        surfaceResolver: resolver,
      );

      expect(plan, hasLength(2));
      final basePlan = plan[0];
      final attachPlan = plan[1];
      expect(attachPlan.pose, isNotNull);
      expect(attachPlan.pose!.center.x, basePlan.pose!.center.x);
      expect(attachPlan.pose!.center.y, basePlan.pose!.center.y);
      // 0.5 static × 0.5 base opacity sample.
      expect(attachPlan.opacity, closeTo(0.25, 1e-9));
    });

    test('bypassing the BASE fx bypasses its attach rows too (one switch '
        'for the group)', () {
      final track = TransformTrack(
        keyframes: {0: TransformPose(center: CanvasPoint(x: 0, y: 0))},
      ).copyWith(opacity: PropertyTrack<double>().withKey(0, 0.5));
      final plan = planCutFrameComposite(
        cut: cut([baseLayer(track: track), attachRow('above', 3)]),
        frameIndex: 0,
        surfaceResolver: resolver,
        fxBypassedLayerIds: {const LayerId('base')},
      );

      expect(plan.map(markerOf), [1, 3]);
      expect(plan[1].pose, isNull);
      expect(plan[1].opacity, 1.0);
    });

    test('VISIBILITY is per-row independent (UI-R24 #5): hiding the base '
        'hides only the base; each row\'s own eye hides it alone; '
        'dangling links contribute nothing', () {
      // The base's eye no longer cascades: its synced attach row still
      // composites (the cell links resolve through the base's TIMELINE,
      // which visibility does not touch).
      final baseHidden = planCutFrameComposite(
        cut: cut([baseLayer(isVisible: false), attachRow('above', 3)]),
        frameIndex: 0,
        surfaceResolver: resolver,
      );
      expect(baseHidden.map(markerOf), [3]);

      final rowHidden = planCutFrameComposite(
        cut: cut([baseLayer(), attachRow('above', 3, isVisible: false)]),
        frameIndex: 0,
        surfaceResolver: resolver,
      );
      expect(rowHidden.map(markerOf), [1]);

      final dangling = planCutFrameComposite(
        cut: cut([
          baseLayer(),
          attachRow('above', 3, attachedTo: const LayerId('gone')),
        ]),
        frameIndex: 0,
        surfaceResolver: resolver,
      );
      expect(dangling.map(markerOf), [1]);
    });
  });
}
