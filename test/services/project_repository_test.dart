import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/brush_settings.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_metadata.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/exposure_memo.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/models/stroke.dart';
import 'package:anicel/src/models/stroke_id.dart';
import 'package:anicel/src/models/stroke_point.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/services/project_repository.dart';

void main() {
  group('ProjectRepository', () {
    test('starts empty when no initial project is provided', () {
      final repository = ProjectRepository();

      expect(repository.currentProject, isNull);
      expect(repository.hasProject, isFalse);
      expect(repository.requireProject, throwsStateError);
    });

    test('holds and replaces the current project', () {
      final firstProject = _project(id: 'project-1', name: 'First');
      final secondProject = _project(id: 'project-2', name: 'Second');
      final repository = ProjectRepository(initialProject: firstProject);

      expect(repository.currentProject, firstProject);
      expect(repository.hasProject, isTrue);

      repository.replaceProject(secondProject);

      expect(repository.currentProject, secondProject);
      expect(repository.requireProject(), secondProject);
    });

    test('updates the current project with immutable copies', () {
      final originalProject = _project(id: 'project-1', name: 'Original');
      final repository = ProjectRepository(initialProject: originalProject);

      repository.updateProject((project) => project.copyWith(name: 'Updated'));

      expect(repository.requireProject().name, 'Updated');
      expect(originalProject.name, 'Original');
    });

    test('adds, replaces, and removes tracks through project copies', () {
      final originalProject = _project(id: 'project-1', name: 'Project');
      final repository = ProjectRepository(initialProject: originalProject);
      final track = _track(id: 'track-1', name: 'Video');
      final replacementTrack = _track(id: 'track-1', name: 'Renamed Video');

      repository.addTrack(track);

      expect(repository.requireProject().tracks, [track]);
      expect(originalProject.tracks, isEmpty);

      repository.replaceTrack(replacementTrack);

      expect(repository.requireProject().tracks, [replacementTrack]);

      repository.removeTrack(const TrackId('track-1'));

      expect(repository.requireProject().tracks, isEmpty);
    });

    test('throws when replacing or removing a missing track', () {
      final repository = ProjectRepository(
        initialProject: _project(id: 'project-1', name: 'Project'),
      );

      expect(
        () => repository.replaceTrack(_track(id: 'missing', name: 'Missing')),
        throwsStateError,
      );

      expect(
        () => repository.removeTrack(const TrackId('missing')),
        throwsStateError,
      );
    });

    test('adds a cut to an existing track', () {
      final track = _track(id: 'track-1', name: 'Video');
      final project = _project(
        id: 'project-1',
        name: 'Project',
        tracks: [track],
      );
      final repository = ProjectRepository(initialProject: project);
      final cut = _cut(id: 'cut-1', name: 'Cut 1');

      repository.addCut(trackId: const TrackId('track-1'), cut: cut);

      expect(repository.requireProject().tracks.single.cuts, [cut]);
      expect(project.tracks.single.cuts, isEmpty);
    });

    test('throws when adding a cut to a missing track', () {
      final repository = ProjectRepository(
        initialProject: _project(id: 'project-1', name: 'Project'),
      );

      expect(
        () => repository.addCut(
          trackId: const TrackId('missing'),
          cut: _cut(id: 'cut-1', name: 'Cut 1'),
        ),
        throwsStateError,
      );
    });

    test(
      'inserts cuts by appending or by index without unique name checks',
      () {
        final cutA = _cut(id: 'cut-a', name: 'Shared Name');
        final cutB = _cut(id: 'cut-b', name: 'Middle');
        final track = _track(id: 'track-1', name: 'Video', cuts: [cutA]);
        final project = _project(
          id: 'project-1',
          name: 'Project',
          tracks: [track],
        );
        final repository = ProjectRepository(initialProject: project);
        final cutC = _cut(id: 'cut-c', name: 'Shared Name');

        repository.insertCut(trackId: const TrackId('track-1'), cut: cutC);
        repository.insertCut(
          trackId: const TrackId('track-1'),
          cut: cutB,
          index: 1,
        );

        final cuts = repository.requireProject().tracks.single.cuts;
        expect(cuts, [cutA, cutB, cutC]);
        expect(cuts.map((cut) => cut.name), [
          'Shared Name',
          'Middle',
          'Shared Name',
        ]);
        expect(project.tracks.single.cuts, [cutA]);
      },
    );

    test('throws when inserting a cut into a missing track', () {
      final repository = ProjectRepository(
        initialProject: _project(id: 'project-1', name: 'Project'),
      );

      expect(
        () => repository.insertCut(
          trackId: const TrackId('missing'),
          cut: _cut(id: 'cut-1', name: 'Cut 1'),
        ),
        throwsStateError,
      );
    });

    test('throws when inserting a cut at an out-of-range index', () {
      final track = _track(id: 'track-1', name: 'Video');
      final project = _project(
        id: 'project-1',
        name: 'Project',
        tracks: [track],
      );
      final repository = ProjectRepository(initialProject: project);

      expect(
        () => repository.insertCut(
          trackId: const TrackId('track-1'),
          cut: _cut(id: 'cut-1', name: 'Cut 1'),
          index: 1,
        ),
        throwsA(isA<RangeError>()),
      );
      expect(repository.requireProject().tracks.single.cuts, isEmpty);
    });

    test('removes a cut by project-wide id and returns it', () {
      final cutA = _cut(id: 'cut-a', name: 'Track 1 Cut');
      final cutB = _cut(id: 'cut-b', name: 'Track 2 Cut');
      final trackA = _track(id: 'track-a', name: 'Video A', cuts: [cutA]);
      final trackB = _track(id: 'track-b', name: 'Video B', cuts: [cutB]);
      final project = _project(
        id: 'project-1',
        name: 'Project',
        tracks: [trackA, trackB],
      );
      final repository = ProjectRepository(initialProject: project);

      final removedCut = repository.removeCut(cutId: const CutId('cut-b'));

      expect(removedCut, cutB);
      expect(repository.requireProject().tracks.first.cuts, [cutA]);
      expect(repository.requireProject().tracks.last.cuts, isEmpty);
      expect(project.tracks.last.cuts, [cutB]);
    });

    test('throws when removing a missing cut', () {
      final repository = ProjectRepository(
        initialProject: _project(id: 'project-1', name: 'Project'),
      );

      expect(
        () => repository.removeCut(cutId: const CutId('missing')),
        throwsStateError,
      );
    });

    test('reorders a cut within one track while preserving cut content', () {
      final layer = _layer(id: 'layer-a', name: 'Line');
      final cutA = _cut(id: 'cut-a', name: 'Cut A', layers: [layer]);
      final cutB = _cut(id: 'cut-b', name: 'Cut B');
      final cutC = _cut(id: 'cut-c', name: 'Cut C');
      final project = _project(
        id: 'project-1',
        name: 'Project',
        tracks: [
          _track(id: 'track-1', name: 'Video', cuts: [cutA, cutB, cutC]),
        ],
      );
      final repository = ProjectRepository(initialProject: project);

      repository.reorderCut(
        trackId: const TrackId('track-1'),
        cutId: cutA.id,
        newIndex: 2,
      );

      var cuts = repository.requireProject().tracks.single.cuts;
      expect(cuts, [cutB, cutC, cutA]);
      expect(cuts.last.id, cutA.id);
      expect(cuts.last.layers, [layer]);
      expect(cuts.last.duration, cutA.duration);
      expect(cuts.last.canvasSize, cutA.canvasSize);
      expect(project.tracks.single.cuts, [cutA, cutB, cutC]);

      final secondRepository = ProjectRepository(
        initialProject: _project(
          id: 'project-2',
          name: 'Project 2',
          tracks: [
            _track(id: 'track-1', name: 'Video', cuts: [cutA, cutB, cutC]),
          ],
        ),
      );

      secondRepository.reorderCut(
        trackId: const TrackId('track-1'),
        cutId: cutC.id,
        newIndex: 0,
      );

      cuts = secondRepository.requireProject().tracks.single.cuts;
      expect(cuts, [cutC, cutA, cutB]);
    });

    test('reordering a cut to the same index keeps the order unchanged', () {
      final cutA = _cut(id: 'cut-a', name: 'Cut A');
      final cutB = _cut(id: 'cut-b', name: 'Cut B');
      final cutC = _cut(id: 'cut-c', name: 'Cut C');
      final repository = ProjectRepository(
        initialProject: _project(
          id: 'project-1',
          name: 'Project',
          tracks: [
            _track(id: 'track-1', name: 'Video', cuts: [cutA, cutB, cutC]),
          ],
        ),
      );

      repository.reorderCut(
        trackId: const TrackId('track-1'),
        cutId: cutB.id,
        newIndex: 1,
      );

      expect(repository.requireProject().tracks.single.cuts, [
        cutA,
        cutB,
        cutC,
      ]);
    });

    test('throws when reordering a cut with missing track or missing cut', () {
      final cutA = _cut(id: 'cut-a', name: 'Cut A');
      final cutB = _cut(id: 'cut-b', name: 'Cut B');
      final repository = ProjectRepository(
        initialProject: _project(
          id: 'project-1',
          name: 'Project',
          tracks: [
            _track(id: 'track-1', name: 'Video', cuts: [cutA]),
            _track(id: 'track-2', name: 'Overlay', cuts: [cutB]),
          ],
        ),
      );
      final beforeJson = repository.requireProject().toJson();

      expect(
        () => repository.reorderCut(
          trackId: const TrackId('missing'),
          cutId: cutA.id,
          newIndex: 0,
        ),
        throwsStateError,
      );
      expect(repository.requireProject().toJson(), beforeJson);

      expect(
        () => repository.reorderCut(
          trackId: const TrackId('track-1'),
          cutId: cutB.id,
          newIndex: 0,
        ),
        throwsStateError,
      );
      expect(repository.requireProject().toJson(), beforeJson);
    });

    test('throws when reordering a cut to an out-of-range index', () {
      final cutA = _cut(id: 'cut-a', name: 'Cut A');
      final cutB = _cut(id: 'cut-b', name: 'Cut B');
      final repository = ProjectRepository(
        initialProject: _project(
          id: 'project-1',
          name: 'Project',
          tracks: [
            _track(id: 'track-1', name: 'Video', cuts: [cutA, cutB]),
          ],
        ),
      );
      final beforeJson = repository.requireProject().toJson();

      expect(
        () => repository.reorderCut(
          trackId: const TrackId('track-1'),
          cutId: cutA.id,
          newIndex: 2,
        ),
        throwsA(isA<RangeError>()),
      );
      expect(repository.requireProject().toJson(), beforeJson);
    });

    test('renames only the target cut display name and allows duplicates', () {
      final layer = _layer(id: 'layer-1', name: 'Line');
      final targetCut = _cut(id: 'cut-a', name: 'Original', layers: [layer]);
      final otherCut = _cut(id: 'cut-b', name: 'Duplicate');
      final track = _track(
        id: 'track-1',
        name: 'Video',
        cuts: [targetCut, otherCut],
      );
      final project = _project(
        id: 'project-1',
        name: 'Project',
        tracks: [track],
      );
      final repository = ProjectRepository(initialProject: project);

      repository.renameCut(cutId: const CutId('cut-a'), name: 'Duplicate');

      final cuts = repository.requireProject().tracks.single.cuts;
      expect(cuts.first.id, targetCut.id);
      expect(cuts.first.name, 'Duplicate');
      expect(cuts.first.layers, [layer]);
      expect(cuts.first.duration, targetCut.duration);
      expect(cuts.first.canvasSize, targetCut.canvasSize);
      expect(cuts.last, otherCut);
      expect(project.tracks.single.cuts.first, targetCut);
    });

    test('throws when renaming a missing cut', () {
      final repository = ProjectRepository(
        initialProject: _project(id: 'project-1', name: 'Project'),
      );

      expect(
        () => repository.renameCut(
          cutId: const CutId('missing'),
          name: 'Renamed',
        ),
        throwsStateError,
      );
    });

    test('adds a layer to an existing cut', () {
      final cut = _cut(id: 'cut-1', name: 'Cut 1');
      final track = _track(id: 'track-1', name: 'Video', cuts: [cut]);
      final project = _project(
        id: 'project-1',
        name: 'Project',
        tracks: [track],
      );
      final repository = ProjectRepository(initialProject: project);
      final layer = _layer(id: 'layer-1', name: 'Line');

      repository.addLayer(cutId: const CutId('cut-1'), layer: layer);

      expect(repository.requireProject().tracks.single.cuts.single.layers, [
        layer,
      ]);
      expect(project.tracks.single.cuts.single.layers, isEmpty);
    });

    test('throws when adding a layer to a missing cut', () {
      final repository = ProjectRepository(
        initialProject: _project(id: 'project-1', name: 'Project'),
      );

      expect(
        () => repository.addLayer(
          cutId: const CutId('missing'),
          layer: _layer(id: 'layer-1', name: 'Line'),
        ),
        throwsStateError,
      );
    });

    test('adds a frame to an existing layer', () {
      final layer = _layer(id: 'layer-1', name: 'Line');
      final cut = _cut(id: 'cut-1', name: 'Cut 1', layers: [layer]);
      final track = _track(id: 'track-1', name: 'Video', cuts: [cut]);
      final project = _project(
        id: 'project-1',
        name: 'Project',
        tracks: [track],
      );
      final repository = ProjectRepository(initialProject: project);
      final frame = _frame(id: 'frame-1');

      repository.addFrame(layerId: const LayerId('layer-1'), frame: frame);

      expect(
        repository
            .requireProject()
            .tracks
            .single
            .cuts
            .single
            .layers
            .single
            .frames,
        [frame],
      );
      expect(project.tracks.single.cuts.single.layers.single.frames, isEmpty);
    });

    test('throws when adding a frame to a missing layer', () {
      final repository = ProjectRepository(
        initialProject: _project(id: 'project-1', name: 'Project'),
      );

      expect(
        () => repository.addFrame(
          layerId: const LayerId('missing'),
          frame: _frame(id: 'frame-1'),
        ),
        throwsStateError,
      );
    });

    test('adds a stroke to an existing frame', () {
      final frame = _frame(id: 'frame-1');
      final layer = _layer(id: 'layer-1', name: 'Line', frames: [frame]);
      final cut = _cut(id: 'cut-1', name: 'Cut 1', layers: [layer]);
      final track = _track(id: 'track-1', name: 'Video', cuts: [cut]);
      final project = _project(
        id: 'project-1',
        name: 'Project',
        tracks: [track],
      );
      final repository = ProjectRepository(initialProject: project);
      final stroke = _stroke(id: 'stroke-1');

      repository.addStroke(frameId: const FrameId('frame-1'), stroke: stroke);

      expect(
        repository
            .requireProject()
            .tracks
            .single
            .cuts
            .single
            .layers
            .single
            .frames
            .single
            .strokes,
        [stroke],
      );
      expect(
        project.tracks.single.cuts.single.layers.single.frames.single.strokes,
        isEmpty,
      );
    });

    test('updates only the target frame through immutable copies', () {
      final frameA = _frame(id: 'frame-a');
      final frameB = _frame(id: 'frame-b');
      final layer = _layer(
        id: 'layer-1',
        name: 'Line',
        frames: [frameA, frameB],
      );
      final cut = _cut(id: 'cut-1', name: 'Cut 1', layers: [layer]);
      final track = _track(id: 'track-1', name: 'Video', cuts: [cut]);
      final project = _project(
        id: 'project-1',
        name: 'Project',
        tracks: [track],
      );
      final repository = ProjectRepository(initialProject: project);

      repository.updateFrame(
        frameId: const FrameId('frame-b'),
        update: (frame) => frame.copyWith(duration: 3),
      );

      final updatedFrames = repository
          .requireProject()
          .tracks
          .single
          .cuts
          .single
          .layers
          .single
          .frames;
      expect(updatedFrames.first, frameA);
      expect(updatedFrames.last.duration, 3);
      expect(
        project.tracks.single.cuts.single.layers.single.frames.last,
        frameB,
      );
      expect(updatedFrames.last, isNot(same(frameB)));
    });

    test('throws when updating a missing frame', () {
      final repository = ProjectRepository(
        initialProject: _project(id: 'project-1', name: 'Project'),
      );

      expect(
        () => repository.updateFrame(
          frameId: const FrameId('missing'),
          update: (frame) => frame,
        ),
        throwsStateError,
      );
    });

    test('throws when adding a stroke to a missing frame', () {
      final repository = ProjectRepository(
        initialProject: _project(id: 'project-1', name: 'Project'),
      );

      expect(
        () => repository.addStroke(
          frameId: const FrameId('missing'),
          stroke: _stroke(id: 'stroke-1'),
        ),
        throwsStateError,
      );
    });

    test(
      'keeps original project and frame unchanged after adding a stroke',
      () {
        final originalFrame = _frame(id: 'frame-1');
        final originalLayer = _layer(
          id: 'layer-1',
          name: 'Line',
          frames: [originalFrame],
        );
        final originalCut = _cut(
          id: 'cut-1',
          name: 'Cut 1',
          layers: [originalLayer],
        );
        final originalTrack = _track(
          id: 'track-1',
          name: 'Video',
          cuts: [originalCut],
        );
        final originalProject = _project(
          id: 'project-1',
          name: 'Project',
          tracks: [originalTrack],
        );
        final repository = ProjectRepository(initialProject: originalProject);
        final stroke = _stroke(id: 'stroke-1');

        repository.addStroke(frameId: const FrameId('frame-1'), stroke: stroke);

        final updatedProject = repository.requireProject();
        final updatedFrame = updatedProject
            .tracks
            .single
            .cuts
            .single
            .layers
            .single
            .frames
            .single;

        expect(updatedProject, isNot(same(originalProject)));
        expect(updatedFrame, isNot(same(originalFrame)));
        expect(updatedFrame.strokes, [stroke]);
        expect(
          originalProject
              .tracks
              .single
              .cuts
              .single
              .layers
              .single
              .frames
              .single
              .strokes,
          isEmpty,
        );
        expect(originalFrame.strokes, isEmpty);
      },
    );

    test('replaces an existing layer', () {
      final layer = _layer(id: 'layer-1', name: 'Line');
      final cut = _cut(id: 'cut-1', name: 'Cut 1', layers: [layer]);
      final track = _track(id: 'track-1', name: 'Video', cuts: [cut]);
      final project = _project(
        id: 'project-1',
        name: 'Project',
        tracks: [track],
      );
      final repository = ProjectRepository(initialProject: project);
      final replacement = _layer(id: 'layer-1', name: 'Paint');

      repository.replaceLayer(layer: replacement);

      expect(
        repository.requireProject().tracks.single.cuts.single.layers.single,
        replacement,
      );
      expect(project.tracks.single.cuts.single.layers.single, layer);
    });

    test('updates an existing layer', () {
      final layer = _layer(id: 'layer-1', name: 'Line');
      final cut = _cut(id: 'cut-1', name: 'Cut 1', layers: [layer]);
      final track = _track(id: 'track-1', name: 'Video', cuts: [cut]);
      final project = _project(
        id: 'project-1',
        name: 'Project',
        tracks: [track],
      );
      final repository = ProjectRepository(initialProject: project);

      repository.updateLayer(
        layerId: const LayerId('layer-1'),
        update: (layer) => layer.copyWith(isVisible: false, opacity: 0.5),
      );

      final updatedLayer = repository
          .requireProject()
          .tracks
          .single
          .cuts
          .single
          .layers
          .single;
      expect(updatedLayer.isVisible, isFalse);
      expect(updatedLayer.opacity, 0.5);
      expect(project.tracks.single.cuts.single.layers.single.isVisible, isTrue);
    });

    test('throws when replacing or updating a missing layer', () {
      final repository = ProjectRepository(
        initialProject: _project(id: 'project-1', name: 'Project'),
      );

      expect(
        () => repository.replaceLayer(
          layer: _layer(id: 'missing', name: 'Missing'),
        ),
        throwsStateError,
      );

      expect(
        () => repository.updateLayer(
          layerId: const LayerId('missing'),
          update: (layer) => layer,
        ),
        throwsStateError,
      );
    });

    test('updates frame storyboard metadata and preserves contents', () {
      final stroke = _stroke(id: 'stroke-1');
      final frame = _frame(id: 'frame-1', strokes: [stroke]);
      final layer = _layer(
        id: 'layer-1',
        name: 'Storyboard',
        kind: LayerKind.storyboard,
        frames: [frame],
      );
      final cut = _cut(id: 'cut-1', name: 'Cut 1', layers: [layer]);
      final project = _project(
        id: 'project-1',
        name: 'Project',
        tracks: [
          _track(id: 'track-1', name: 'Video', cuts: [cut]),
        ],
      );
      final repository = ProjectRepository(initialProject: project);
      const memo = ExposureMemo(actionMemo: 'Action', note: 'Note');

      repository.updateExposureMemo(
        cutId: cut.id,
        layerId: layer.id,
        blockStartIndex: 0,
        memo: memo,
      );

      final updatedLayer = repository
          .requireProject()
          .tracks
          .single
          .cuts
          .single
          .layers
          .single;
      final updatedFrame = updatedLayer.frames.single;
      expect(updatedLayer.timeline[0]!.memo, memo);
      expect(updatedFrame.id, frame.id);
      expect(updatedFrame.duration, frame.duration);
      expect(updatedFrame.name, frame.name);
      expect(updatedFrame.strokes, [stroke]);
      expect(updatedLayer.kind, LayerKind.storyboard);
      expect(
        project.tracks.single.cuts.single.layers.single.frames.single,
        frame,
      );
    });

    test('updateExposureMemo throws for missing target', () {
      final frame = _frame(id: 'frame-1');
      final layer = _layer(id: 'layer-1', name: 'Storyboard', frames: [frame]);
      final cut = _cut(id: 'cut-1', name: 'Cut 1', layers: [layer]);
      final repository = ProjectRepository(
        initialProject: _project(
          id: 'project-1',
          name: 'Project',
          tracks: [
            _track(id: 'track-1', name: 'Video', cuts: [cut]),
          ],
        ),
      );
      final beforeJson = repository.requireProject().toJson();

      expect(
        () => repository.updateExposureMemo(
          cutId: const CutId('missing'),
          layerId: layer.id,
          blockStartIndex: 0,
          memo: const ExposureMemo(note: 'New'),
        ),
        throwsStateError,
      );
      expect(repository.requireProject().toJson(), beforeJson);

      expect(
        () => repository.updateExposureMemo(
          cutId: cut.id,
          layerId: const LayerId('missing'),
          blockStartIndex: 0,
          memo: const ExposureMemo(note: 'New'),
        ),
        throwsStateError,
      );
      expect(repository.requireProject().toJson(), beforeJson);

      expect(
        () => repository.updateExposureMemo(
          cutId: cut.id,
          layerId: layer.id,
          blockStartIndex: 99,
          memo: const ExposureMemo(note: 'New'),
        ),
        throwsStateError,
      );
      expect(repository.requireProject().toJson(), beforeJson);
    });

    test('updateLayerKind replaces only kind and preserves layer data', () {
      final frame = _frame(
        id: 'frame-1',
        strokes: [_stroke(id: 'stroke-1')],
      );
      final layer = Layer(
        id: const LayerId('layer-1'),
        name: 'Layer 1',
        frames: [frame],
        timeline: {
          0: TimelineExposure.drawing(
            frame.id,
            length: 6,
            breakdownOffsets: const [3],
          ),
        },
        isVisible: false,
        opacity: 0.25,
      );
      final cut = Cut(
        id: const CutId('cut-1'),
        name: 'Cut 1',
        layers: [layer],
        duration: 24,
        canvasSize: const CanvasSize(width: 1920, height: 1080),
        metadata: const CutMetadata(note: 'Cut note'),
      );
      final repository = ProjectRepository(
        initialProject: _project(
          id: 'project-1',
          name: 'Project',
          tracks: [
            _track(id: 'track-1', name: 'Video', cuts: [cut]),
          ],
        ),
      );

      repository.updateLayerKind(
        cutId: cut.id,
        layerId: layer.id,
        kind: LayerKind.storyboard,
      );

      final updatedCut = repository.requireProject().tracks.single.cuts.single;
      final updatedLayer = updatedCut.layers.single;
      expect(updatedLayer.kind, LayerKind.storyboard);
      expect(updatedLayer.id, layer.id);
      expect(updatedLayer.name, layer.name);
      expect(updatedLayer.frames, [frame]);
      expect(updatedLayer.timeline, layer.timeline);
      expect(updatedLayer.isVisible, isFalse);
      expect(updatedLayer.opacity, 0.25);
      expect(updatedCut.metadata, const CutMetadata(note: 'Cut note'));
      expect(cut.layers.single.kind, LayerKind.animation);
    });

    test('insertLayer inserts at requested index', () {
      final cut = _cut(
        id: 'cut-1',
        name: 'Cut 1',
        layers: [
          _layer(id: 'layer-a', name: 'A'),
          _layer(id: 'layer-b', name: 'B'),
        ],
      );
      final repository = ProjectRepository(
        initialProject: _project(
          id: 'project-1',
          name: 'Project',
          tracks: [
            _track(id: 'track-1', name: 'Video', cuts: [cut]),
          ],
        ),
      );

      repository.insertLayer(
        cutId: cut.id,
        layer: _layer(id: 'layer-c', name: 'C'),
        index: 1,
      );

      expect(
        repository.requireProject().tracks.single.cuts.single.layers.map(
          (layer) => layer.name,
        ),
        ['A', 'C', 'B'],
      );
    });

    test('updateLayerKind rejects creating a second storyboard layer', () {
      final storyboard = _layer(
        id: 'storyboard',
        name: 'A',
        kind: LayerKind.storyboard,
      );
      final animation = _layer(id: 'animation', name: 'B');
      final cut = _cut(
        id: 'cut-1',
        name: 'Cut 1',
        layers: [storyboard, animation],
      );
      final repository = ProjectRepository(
        initialProject: _project(
          id: 'project-1',
          name: 'Project',
          tracks: [
            _track(id: 'track-1', name: 'Video', cuts: [cut]),
          ],
        ),
      );
      final beforeJson = repository.requireProject().toJson();

      expect(
        () => repository.updateLayerKind(
          cutId: cut.id,
          layerId: animation.id,
          kind: LayerKind.storyboard,
        ),
        throwsStateError,
      );
      expect(repository.requireProject().toJson(), beforeJson);
    });

    test('updateLayerKind throws for missing cut or layer', () {
      final layer = _layer(id: 'layer-1', name: 'Layer 1');
      final cut = _cut(id: 'cut-1', name: 'Cut 1', layers: [layer]);
      final repository = ProjectRepository(
        initialProject: _project(
          id: 'project-1',
          name: 'Project',
          tracks: [
            _track(id: 'track-1', name: 'Video', cuts: [cut]),
          ],
        ),
      );
      final beforeJson = repository.requireProject().toJson();

      expect(
        () => repository.updateLayerKind(
          cutId: const CutId('missing'),
          layerId: layer.id,
          kind: LayerKind.storyboard,
        ),
        throwsStateError,
      );
      expect(repository.requireProject().toJson(), beforeJson);

      expect(
        () => repository.updateLayerKind(
          cutId: cut.id,
          layerId: const LayerId('missing'),
          kind: LayerKind.storyboard,
        ),
        throwsStateError,
      );
      expect(repository.requireProject().toJson(), beforeJson);
    });

    test('clears the current project', () {
      final repository = ProjectRepository(
        initialProject: _project(id: 'project-1', name: 'Project'),
      );

      repository.clearProject();

      expect(repository.currentProject, isNull);
      expect(repository.hasProject, isFalse);
    });
  });
}

Project _project({
  required String id,
  required String name,
  List<Track> tracks = const [],
}) {
  return Project(
    id: ProjectId(id),
    name: name,
    tracks: tracks,
    createdAt: DateTime.utc(2026, 6, 2),
  );
}

Track _track({
  required String id,
  required String name,
  List<Cut> cuts = const [],
}) {
  return Track(id: TrackId(id), name: name, cuts: cuts);
}

Cut _cut({
  required String id,
  required String name,
  List<Layer> layers = const [],
}) {
  return Cut(
    id: CutId(id),
    name: name,
    layers: layers,
    duration: 24,
    canvasSize: const CanvasSize(width: 1920, height: 1080),
  );
}

Layer _layer({
  required String id,
  required String name,
  List<Frame> frames = const [],
  LayerKind kind = LayerKind.animation,
}) {
  return Layer(id: LayerId(id), name: name, frames: frames, kind: kind);
}

Frame _frame({required String id, List<Stroke> strokes = const []}) {
  return Frame(id: FrameId(id), duration: 1, strokes: strokes);
}

Stroke _stroke({required String id}) {
  return Stroke(
    id: StrokeId(id),
    points: const [StrokePoint(x: 1, y: 2)],
    brushSettings: BrushSettings(),
  );
}
