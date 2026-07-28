import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/export_overrides.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/services/project_repository.dart';

void main() {
  Project project({ExportProjectOverrides? overrides}) => Project(
    id: const ProjectId('project'),
    name: 'Project',
    tracks: [
      Track(
        id: const TrackId('track'),
        name: 'Track',
        cuts: [
          Cut(
            id: const CutId('a'),
            name: 'Cut A',
            duration: 3,
            canvasSize: const CanvasSize(width: 8, height: 8),
            layers: [
              Layer(id: const LayerId('l1'), name: 'A', frames: const []),
            ],
          ),
        ],
      ),
    ],
    createdAt: DateTime.utc(2026),
    exportOverrides: overrides,
  );

  group('ExportCelsCutDelta', () {
    test('round-trips and drops entries on null override', () {
      final delta = ExportCelsCutDelta()
          .withLayerOverride(const LayerId('l1'), true)
          .withLayerOverride(const LayerId('l2'), false);
      expect(ExportCelsCutDelta.fromJson(delta.toJson()), delta);
      final dropped = delta.withLayerOverride(const LayerId('l1'), null);
      expect(dropped.layerOverrides.keys, [const LayerId('l2')]);
    });
  });

  group('ExportProjectOverrides', () {
    test('round-trips cut checks and deltas', () {
      final overrides = ExportProjectOverrides()
          .withCutIncluded(const CutId('a'), false)
          .withCutIncluded(const CutId('b'), false)
          .withCelsDelta(
            const CutId('a'),
            ExportCelsCutDelta().withLayerOverride(const LayerId('l1'), false),
          );
      expect(ExportProjectOverrides.fromJson(overrides.toJson()), overrides);
      expect(overrides.cutIncluded(const CutId('a')), isFalse);
      expect(overrides.cutIncluded(const CutId('c')), isTrue);
    });

    test('withAllCutsIncluded keeps the deltas (All resets scope only)', () {
      final overrides = ExportProjectOverrides()
          .withCutIncluded(const CutId('a'), false)
          .withCelsDelta(
            const CutId('a'),
            ExportCelsCutDelta().withLayerOverride(const LayerId('l1'), true),
          )
          .withAllCutsIncluded();
      expect(overrides.excludedCutIds, isEmpty);
      expect(overrides.deltaFor(const CutId('a')), isNotNull);
    });

    test('an empty delta never persists', () {
      final overrides = ExportProjectOverrides().withCelsDelta(
        const CutId('a'),
        ExportCelsCutDelta(),
      );
      expect(overrides.isEmpty, isTrue);
    });
  });

  group('Project serialization', () {
    test('empty overrides stay out of the JSON (legacy files unchanged)', () {
      expect(project().toJson().containsKey('exportOverrides'), isFalse);
    });

    test('non-empty overrides round-trip through Project JSON', () {
      final overrides = ExportProjectOverrides()
          .withCutIncluded(const CutId('a'), false)
          .withCelsDelta(
            const CutId('a'),
            ExportCelsCutDelta().withLayerOverride(const LayerId('l1'), false),
          );
      final json = project(overrides: overrides).toJson();
      expect(json['exportOverrides'], isNotNull);
      final restored = Project.fromJson(json);
      expect(restored.exportOverrides, overrides);
    });

    test('absent key restores as empty', () {
      final restored = Project.fromJson(project().toJson());
      expect(restored.exportOverrides.isEmpty, isTrue);
    });
  });

  group('ProjectRepository.updateExportOverrides', () {
    test('writes through with no other project change', () {
      final repository = ProjectRepository(initialProject: project());
      repository.updateExportOverrides(
        (overrides) => overrides.withCutIncluded(const CutId('a'), false),
      );
      expect(
        repository.requireProject().exportOverrides.cutIncluded(
          const CutId('a'),
        ),
        isFalse,
      );
      // Second update composes over the first.
      repository.updateExportOverrides(
        (overrides) => overrides.withAllCutsIncluded(),
      );
      expect(repository.requireProject().exportOverrides.isEmpty, isTrue);
    });
  });
}
