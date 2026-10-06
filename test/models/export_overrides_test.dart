import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/export_overrides.dart';
import 'package:anicel/src/models/frame_id.dart';
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

    ExportCelRef ref(String row, String cel) =>
        (row: LayerId(row), cel: FrameId(cel));

    test('a drawing is turned off and back on, one drawing at a time', () {
      // 유저 2026-10-06: 「셀의 프레임버튼 누르면 내보내기 적용/미적용」.
      final off = ExportCelsCutDelta()
          .withCelSkipped(ref('a', 'f1'), true)
          .withCelSkipped(ref('a', 'f2'), true);
      expect(off.skippedCels, {ref('a', 'f1'), ref('a', 'f2')});
      expect(off.isEmpty, isFalse);
      expect(off.leavesTheRules, isTrue);
      final one = off.withCelSkipped(ref('a', 'f1'), false);
      expect(one.skippedCels, {ref('a', 'f2')});
      expect(
        one.withCelSkipped(ref('a', 'f2'), false),
        ExportCelsCutDelta(),
        reason: 'nothing turned off is the empty delta again',
      );
      expect(one, isNot(off));
    });

    test('a direction is laid over ONE drawing, and taken off it', () {
      // 유저 2026-10-06: 「BG의 1번 그림에 디렉션레이어의 1번을
      // 얹고싶다거나」.
      final laid = ExportCelsCutDelta()
          .withDirectionOver(ref('bg', 'b1'), ref('dir', 'd1'), true)
          .withDirectionOver(ref('bg', 'b1'), ref('dir', 'd2'), true)
          .withDirectionOver(ref('a', 'f1'), ref('dir', 'd1'), true);
      expect(laid.directionsOver(ref('bg', 'b1')), {
        ref('dir', 'd1'),
        ref('dir', 'd2'),
      });
      expect(laid.directionsOver(ref('a', 'f1')), {ref('dir', 'd1')});
      expect(laid.directionsOver(ref('bg', 'b2')), isEmpty);
      expect(laid.isEmpty, isFalse);
      expect(
        laid.leavesTheRules,
        isFalse,
        reason: 'what is laid over a drawing is no answer to a rule',
      );
      final less = laid.withDirectionOver(
        ref('bg', 'b1'),
        ref('dir', 'd1'),
        false,
      );
      expect(less.directionsOver(ref('bg', 'b1')), {ref('dir', 'd2')});
      expect(less.directionsOver(ref('a', 'f1')), {ref('dir', 'd1')});
      expect(less, isNot(laid));
    });

    test('a filter press drops the row answers alone; Reset drops the '
        'drawings turned off too — and what is laid over a drawing stays '
        'through both', () {
      final delta = ExportCelsCutDelta()
          .withLayerOverride(const LayerId('l1'), true)
          .withCelSkipped(ref('a', 'f1'), true)
          .withDirectionOver(ref('a', 'f2'), ref('dir', 'd1'), true);

      final refiltered = delta.withoutLayerOverrides();
      expect(refiltered.layerOverrides, isEmpty);
      expect(refiltered.skippedCels, {ref('a', 'f1')});
      expect(refiltered.directionsOver(ref('a', 'f2')), {ref('dir', 'd1')});

      final reset = delta.backOnTheRules();
      expect(reset.layerOverrides, isEmpty);
      expect(reset.skippedCels, isEmpty);
      expect(reset.leavesTheRules, isFalse);
      expect(reset.directionsOver(ref('a', 'f2')), {ref('dir', 'd1')});
      expect(reset.isEmpty, isFalse);
    });

    test('all of it round-trips, written in one order whatever order the '
        'hand worked in', () {
      ExportCelsCutDelta made(List<String> order) {
        var delta = ExportCelsCutDelta().withLayerOverride(
          const LayerId('l1'),
          false,
        );
        for (final cel in order) {
          delta = delta
              .withCelSkipped(ref('a', cel), true)
              .withDirectionOver(ref('bg', cel), ref('dir', 'd1'), true)
              .withDirectionOver(ref('bg', cel), ref('dir', 'd0'), true);
        }
        return delta;
      }

      final forward = made(['f1', 'f2', 'f3']);
      final backward = made(['f3', 'f2', 'f1']);
      expect(backward, forward);
      expect(backward.hashCode, forward.hashCode);
      expect('${backward.toJson()}', '${forward.toJson()}');
      final restored = ExportCelsCutDelta.fromJson(forward.toJson());
      expect(restored, forward);
      expect(restored.skippedCels, hasLength(3));
      expect(restored.directionsOver(ref('bg', 'f2')), {
        ref('dir', 'd0'),
        ref('dir', 'd1'),
      });
      expect(
        ExportCelsCutDelta().toJson().keys,
        ['layerOverrides'],
        reason: 'an empty set is not written',
      );
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
