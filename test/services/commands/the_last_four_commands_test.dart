import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/attached_layer_mount.dart';
import 'package:anicel/src/models/attached_mode.dart';
import 'package:anicel/src/models/attached_placement.dart';
import 'package:anicel/src/models/camera_pose.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_camera.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/media_asset.dart';
import 'package:anicel/src/models/media_reference.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/services/commands/rasterize_layer_reference_command.dart';
import 'package:anicel/src/services/commands/set_layer_attachment_command.dart';
import 'package:anicel/src/services/commands/set_layer_placement_command.dart';
import 'package:anicel/src/services/commands/update_cut_camera_command.dart';
import 'package:anicel/src/services/project_repository.dart';

/// The last four commands on the undo stack with nothing naming them.
void main() {
  Layer layer(
    String id, {
    LayerKind kind = LayerKind.image,
    MediaReference? mediaReference,
  }) => Layer(
    id: LayerId(id),
    name: id,
    frames: const [],
    timeline: const {},
    kind: kind,
    mediaReference: mediaReference,
  );

  Cut cut(String id, List<Layer> layers) => Cut(
    id: CutId(id),
    name: id,
    layers: layers,
    duration: 12,
    canvasSize: const CanvasSize(width: 100, height: 100),
  );

  Project projectWith({
    required List<Cut> cuts,
    List<Layer> seLayers = const [],
    List<MediaAsset> assets = const [],
  }) => Project(
    id: const ProjectId('p'),
    name: 'P',
    createdAt: DateTime.utc(2026, 9, 5),
    mediaAssets: assets,
    tracks: [
      Track(id: const TrackId('t'), name: 'V', seLayers: seLayers, cuts: cuts),
    ],
  );

  Layer rowOf(ProjectRepository repository, String layerId) => repository
      .requireProject()
      .tracks
      .single
      .cuts
      .single
      .layers
      .firstWhere((l) => l.id == LayerId(layerId));

  group('UpdateCutCameraCommand', () {
    ProjectRepository open() => ProjectRepository(
      initialProject: projectWith(
        cuts: [
          cut('c', [layer('l')]),
        ],
      ),
    );

    CutCamera cameraWithKey() => CutCamera(
      keyframes: {0: CameraPose(center: CanvasPoint(x: 10, y: 20))},
    );

    test('the camera track is written and undone whole', () {
      final repository = open();
      final command = UpdateCutCameraCommand(
        repository: repository,
        cutId: const CutId('c'),
        camera: cameraWithKey(),
        description: 'Move camera keys',
      );

      command.execute();
      expect(
        repository
            .requireProject()
            .tracks
            .single
            .cuts
            .single
            .camera
            .track
            .keyframes,
        isNotEmpty,
      );

      command.undo();
      expect(
        repository
            .requireProject()
            .tracks
            .single
            .cuts
            .single
            .camera
            .track
            .keyframes,
        isEmpty,
      );
    });

    test('the description is the CALLER\'s — a key drag and a dialog edit '
        'are different entries', () {
      expect(
        UpdateCutCameraCommand(
          repository: open(),
          cutId: const CutId('c'),
          camera: cameraWithKey(),
          description: 'Edit camera key',
        ).description,
        'Edit camera key',
      );
    });

    test('undo before execute is refused', () {
      expect(
        UpdateCutCameraCommand(
          repository: open(),
          cutId: const CutId('c'),
          camera: cameraWithKey(),
          description: 'Move camera keys',
        ).undo,
        throwsStateError,
      );
    });
  });

  group('SetLayerAttachmentCommand', () {
    ProjectRepository open() => ProjectRepository(
      initialProject: projectWith(
        cuts: [
          cut('c', [layer('base'), layer('rider')]),
        ],
      ),
    );

    LayerAttachment mountedOn(String baseId) => LayerAttachment(
      attachedToLayerId: LayerId(baseId),
      placement: AttachedPlacement.above,
      mode: AttachedMode.synced,
      timeline: const {},
      baseFrameLinks: const {},
    );

    test('a row becomes an attach row, and undo makes it ordinary again', () {
      final repository = open();
      final command = SetLayerAttachmentCommand(
        repository: repository,
        layerId: const LayerId('rider'),
        attachment: mountedOn('base'),
      );

      command.execute();
      expect(
        rowOf(repository, 'rider').attachedToLayerId,
        const LayerId('base'),
      );

      command.undo();
      expect(rowOf(repository, 'rider').attachedToLayerId, isNull);
    });

    test('🚨a REDO writes exactly what the first execute wrote — the bake '
        'and the cell links were read at plan time and must not be '
        're-derived against a later timeline', () {
      final repository = open();
      final command = SetLayerAttachmentCommand(
        repository: repository,
        layerId: const LayerId('rider'),
        attachment: mountedOn('base'),
      );

      command.execute();
      command.execute();
      command.undo();

      expect(rowOf(repository, 'rider').attachedToLayerId, isNull);
    });

    test('undo before execute is refused', () {
      expect(
        SetLayerAttachmentCommand(
          repository: open(),
          layerId: const LayerId('rider'),
          attachment: mountedOn('base'),
        ).undo,
        throwsStateError,
      );
    });
  });

  group('SetTrackSeOrderCommand', () {
    ProjectRepository open() => ProjectRepository(
      initialProject: projectWith(
        cuts: [cut('c', const [])],
        seLayers: [
          layer('a', kind: LayerKind.se),
          layer('b', kind: LayerKind.se),
          layer('c', kind: LayerKind.se),
        ],
      ),
    );

    List<String> orderOf(ProjectRepository repository) => [
      for (final l in repository.requireProject().tracks.single.seLayers)
        l.id.value,
    ];

    test('the SE rows resequence, and undo restores the order', () {
      final repository = open();
      final command = SetTrackSeOrderCommand(
        repository: repository,
        trackId: const TrackId('t'),
        order: const [LayerId('c'), LayerId('b'), LayerId('a')],
      );

      command.execute();
      expect(orderOf(repository), ['c', 'b', 'a']);

      command.undo();
      expect(orderOf(repository), ['a', 'b', 'c']);
    });

    test('🚨executing TWICE keeps the FIRST order — the drag re-applies it '
        'and undo still walks all the way back', () {
      final repository = open();
      final command = SetTrackSeOrderCommand(
        repository: repository,
        trackId: const TrackId('t'),
        order: const [LayerId('c'), LayerId('b'), LayerId('a')],
      );

      command.execute();
      command.execute();
      command.undo();

      expect(orderOf(repository), ['a', 'b', 'c']);
    });

    test('undo before execute is refused', () {
      expect(
        SetTrackSeOrderCommand(
          repository: open(),
          trackId: const TrackId('t'),
          order: const [LayerId('a')],
        ).undo,
        throwsStateError,
      );
    });
  });

  group('RasterizeLayerReferenceCommand', () {
    ProjectRepository open({bool withAsset = true}) => ProjectRepository(
      initialProject: projectWith(
        assets: withAsset
            ? const [MediaAsset(path: '/still.png', name: 'still')]
            : const [],
        cuts: [
          cut('c', [
            layer(
              'l',
              mediaReference: const MediaReference(assetPath: '/still.png'),
            ),
          ]),
        ],
      ),
    );

    test('🚨the reference is dropped and the pool entry STAYS — a baked '
        'file is still the pool\'s to offer again (유저 2026-09-11: 「구워도 '
        '풀에 남음」; it used to go when nobody else held it)', () {
      final repository = open();
      final command = RasterizeLayerReferenceCommand(
        repository: repository,
        cutId: const CutId('c'),
        layerId: const LayerId('l'),
      );

      command.execute();
      expect(rowOf(repository, 'l').mediaReference, isNull);
      expect(repository.requireProject().mediaAssets, hasLength(1));

      command.undo();
      expect(rowOf(repository, 'l').mediaReference?.assetPath, '/still.png');
      expect(repository.requireProject().mediaAssets, hasLength(1));
    });

    test('a layer that references nothing is left alone, and so is its '
        'undo', () {
      final repository = open(withAsset: false);
      final command = RasterizeLayerReferenceCommand(
        repository: repository,
        cutId: const CutId('c'),
        layerId: const LayerId('l'),
      )..execute();
      command.undo();
      expect(
        rowOf(repository, 'l').mediaReference?.assetPath,
        '/still.png',
        reason: 'the first execute found a reference; undo puts it back',
      );
    });

    test('undo before execute is refused', () {
      expect(
        RasterizeLayerReferenceCommand(
          repository: open(),
          cutId: const CutId('c'),
          layerId: const LayerId('l'),
        ).undo,
        throwsStateError,
      );
    });
  });
}
