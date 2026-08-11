import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/drawing_guide.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_link_registry.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/services/commands/resize_cut_canvas_command.dart';
import 'package:anicel/src/services/commands/set_cut_guides_command.dart';
import 'package:anicel/src/services/project_lookup.dart';
import 'package:anicel/src/services/project_repository.dart';
import 'package:flutter_test/flutter_test.dart';

const _track = TrackId('track');
const _cut1 = CutId('cut-1');
const _cut2 = CutId('cut-2');
const _cut3 = CutId('cut-3');
const _loose = CutId('cut-loose');
const _layer1 = LayerId('layer-1');
const _layer2 = LayerId('layer-2');
const _layer3 = LayerId('layer-3');
const _layerLoose = LayerId('layer-loose');

const _canvas = CanvasSize(width: 400, height: 300);

Cut _cut(CutId id, LayerId layerId, {CutGuides? guides}) => Cut(
  id: id,
  name: id.value,
  layers: [Layer(id: layerId, name: 'A', frames: const [])],
  duration: 12,
  canvasSize: _canvas,
  guides: guides,
);

/// [cutIds] all sharing one cel bank — the 겸용 relation as the app records
/// it: a group of (track, cut, layer) use sites over ONE physical picture.
LayerLinkGroup _group(String id, List<(CutId, LayerId)> members) =>
    LayerLinkGroup(
      id: id,
      members: [
        for (final (cutId, layerId) in members)
          LayerLinkMember(trackId: _track, cutId: cutId, layerId: layerId),
      ],
    );

ProjectRepository _repository({
  required List<Cut> cuts,
  List<LayerLinkGroup> groups = const [],
}) {
  final repository = ProjectRepository();
  repository.replaceProject(
    Project(
      id: const ProjectId('project'),
      name: 'Project',
      tracks: [Track(id: _track, name: 'Video', cuts: cuts)],
      createdAt: DateTime(2020),
      linkRegistry: LayerLinkRegistry(groups: groups),
    ),
  );
  return repository;
}

CutGuides _guides({double axisX = 200}) {
  const id = GuideId('sym');
  return CutGuides(
    guides: [
      DrawingGuide(
        id: id,
        name: 'Symmetry',
        shape: SymmetryShape(
          axis: GuideAxis(
            origin: CanvasPoint(x: axisX, y: 150),
            angleDegrees: 90,
          ),
        ),
      ),
    ],
    activeSymmetryId: id,
  );
}

CutGuides _guidesOf(ProjectRepository repository, CutId cutId) =>
    requireCut(repository.requireProject(), cutId).guides;

void main() {
  group('SetCutGuidesCommand', () {
    test('an unlinked cut keeps its guides to itself', () {
      final repository = _repository(
        cuts: [_cut(_cut1, _layer1), _cut(_loose, _layerLoose)],
      );

      SetCutGuidesCommand(
        repository: repository,
        cutId: _cut1,
        guides: _guides(),
      ).execute();

      expect(_guidesOf(repository, _cut1).guides, hasLength(1));
      expect(_guidesOf(repository, _loose).isEmpty, isTrue);
    });

    test('겸용 members all receive the same guides', () {
      final repository = _repository(
        cuts: [
          _cut(_cut1, _layer1),
          _cut(_cut2, _layer2),
          _cut(_loose, _layerLoose),
        ],
        groups: [
          _group('g', [(_cut1, _layer1), (_cut2, _layer2)]),
        ],
      );

      SetCutGuidesCommand(
        repository: repository,
        cutId: _cut1,
        guides: _guides(),
      ).execute();

      expect(_guidesOf(repository, _cut1), _guidesOf(repository, _cut2));
      expect(
        _guidesOf(repository, _loose).isEmpty,
        isTrue,
        reason: 'a cut that shares no picture is not 겸용',
      );
    });

    test('editing from ANY member reaches the whole group', () {
      final repository = _repository(
        cuts: [_cut(_cut1, _layer1), _cut(_cut2, _layer2)],
        groups: [
          _group('g', [(_cut1, _layer1), (_cut2, _layer2)]),
        ],
      );

      // Edited from the member that is NOT the group's canonical one.
      SetCutGuidesCommand(
        repository: repository,
        cutId: _cut2,
        guides: _guides(axisX: 111),
      ).execute();

      expect(_guidesOf(repository, _cut1), _guidesOf(repository, _cut2));
    });

    test('a three-cut 겸용 group stays identical throughout', () {
      final repository = _repository(
        cuts: [
          _cut(_cut1, _layer1),
          _cut(_cut2, _layer2),
          _cut(_cut3, _layer3),
        ],
        groups: [
          _group('g', [(_cut1, _layer1), (_cut2, _layer2), (_cut3, _layer3)]),
        ],
      );

      SetCutGuidesCommand(
        repository: repository,
        cutId: _cut3,
        guides: _guides(),
      ).execute();

      expect(_guidesOf(repository, _cut1), _guidesOf(repository, _cut2));
      expect(_guidesOf(repository, _cut2), _guidesOf(repository, _cut3));
    });

    test('one undo puts EVERY member back', () {
      final repository = _repository(
        cuts: [
          _cut(_cut1, _layer1, guides: _guides(axisX: 10)),
          _cut(_cut2, _layer2, guides: _guides(axisX: 10)),
        ],
        groups: [
          _group('g', [(_cut1, _layer1), (_cut2, _layer2)]),
        ],
      );
      final command = SetCutGuidesCommand(
        repository: repository,
        cutId: _cut1,
        guides: _guides(axisX: 999),
      )..execute();

      command.undo();

      expect(_guidesOf(repository, _cut1), _guides(axisX: 10));
      expect(
        _guidesOf(repository, _cut2),
        _guides(axisX: 10),
        reason: 'a half-undone fan-out would leave the members disagreeing',
      );
    });

    test('redo after undo lands the same everywhere', () {
      final repository = _repository(
        cuts: [_cut(_cut1, _layer1), _cut(_cut2, _layer2)],
        groups: [
          _group('g', [(_cut1, _layer1), (_cut2, _layer2)]),
        ],
      );
      final command = SetCutGuidesCommand(
        repository: repository,
        cutId: _cut1,
        guides: _guides(),
      )..execute();

      command.undo();
      command.execute();

      expect(_guidesOf(repository, _cut1), _guides());
      expect(_guidesOf(repository, _cut2), _guides());
    });

    test('undoing before executing is an error, not a silent no-op', () {
      final repository = _repository(cuts: [_cut(_cut1, _layer1)]);

      expect(
        () => SetCutGuidesCommand(
          repository: repository,
          cutId: _cut1,
          guides: _guides(),
        ).undo(),
        throwsStateError,
      );
    });

    test('copying one cut\'s guides to another is the same command', () {
      // Cut-to-cut copy needs no machinery of its own: the guides are a
      // value, and setting them somewhere else is setting them.
      final repository = _repository(
        cuts: [_cut(_cut1, _layer1, guides: _guides()), _cut(_loose, _layerLoose)],
      );

      SetCutGuidesCommand(
        repository: repository,
        cutId: _loose,
        guides: _guidesOf(repository, _cut1),
      ).execute();

      expect(_guidesOf(repository, _loose), _guidesOf(repository, _cut1));
    });
  });

  group('ResizeCutCanvasCommand over 겸용 cuts', () {
    test('resizing one member resizes them all', () {
      // Linked cuts show ONE physical cel; different canvas sizes would put
      // that one picture in two differently-shaped frames.
      final repository = _repository(
        cuts: [
          _cut(_cut1, _layer1),
          _cut(_cut2, _layer2),
          _cut(_loose, _layerLoose),
        ],
        groups: [
          _group('g', [(_cut1, _layer1), (_cut2, _layer2)]),
        ],
      );

      ResizeCutCanvasCommand(
        repository: repository,
        cutId: _cut1,
        canvasSize: const CanvasSize(width: 1920, height: 1080),
      ).execute();

      CanvasSize sizeOf(CutId id) =>
          requireCut(repository.requireProject(), id).canvasSize;
      expect(sizeOf(_cut1), const CanvasSize(width: 1920, height: 1080));
      expect(sizeOf(_cut2), const CanvasSize(width: 1920, height: 1080));
      expect(sizeOf(_loose), _canvas, reason: 'unlinked cuts are untouched');
    });

    test('undo restores every member', () {
      final repository = _repository(
        cuts: [_cut(_cut1, _layer1), _cut(_cut2, _layer2)],
        groups: [
          _group('g', [(_cut1, _layer1), (_cut2, _layer2)]),
        ],
      );
      final command = ResizeCutCanvasCommand(
        repository: repository,
        cutId: _cut1,
        canvasSize: const CanvasSize(width: 1920, height: 1080),
      )..execute();

      command.undo();

      CanvasSize sizeOf(CutId id) =>
          requireCut(repository.requireProject(), id).canvasSize;
      expect(sizeOf(_cut1), _canvas);
      expect(sizeOf(_cut2), _canvas);
    });
  });
}
