import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/brush_settings.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_section_defaults.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_frame_rate.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/stroke.dart';
import 'package:anicel/src/models/stroke_id.dart';
import 'package:anicel/src/models/stroke_point.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/services/project_file_service.dart';
import 'package:anicel/src/services/project_repository.dart';

void main() {
  group('ProjectFileService', () {
    const service = ProjectFileService();
    late Directory tempDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('quick_animaker_project_');
    });

    tearDown(() {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    test('saves a project to a file path', () async {
      final project = _sampleProject();
      final file = File('${tempDir.path}/project.json');

      await service.saveProject(project: project, filePath: file.path);

      expect(file.existsSync(), isTrue);
      expect(file.readAsStringSync(), isNotEmpty);
    });

    test('loads a project from a file path', () async {
      final project = _sampleProject();
      final file = File('${tempDir.path}/project.json');
      await service.saveProject(project: project, filePath: file.path);

      final loaded = await service.loadProject(filePath: file.path);

      expect(loaded, project);
    });

    test('throws when loading a missing file', () {
      final missingPath = '${tempDir.path}/missing.json';

      expect(
        service.loadProject(filePath: missingPath),
        throwsA(isA<FileSystemException>()),
      );
    });

    test('throws a FormatException when loading invalid file content', () {
      final file = File('${tempDir.path}/invalid.json')
        ..writeAsStringSync('not json');

      expect(service.loadProject(filePath: file.path), throwsFormatException);
    });

    test('saves the current repository project to a file path', () async {
      final project = _sampleProject();
      final repository = ProjectRepository(initialProject: project);
      final file = File('${tempDir.path}/current_project.json');

      await service.saveCurrentProject(
        repository: repository,
        filePath: file.path,
      );

      expect(file.existsSync(), isTrue);
      expect(await service.loadProject(filePath: file.path), project);
    });

    test('loads a project into the repository', () async {
      final project = _sampleProject();
      final repository = ProjectRepository();
      final file = File('${tempDir.path}/repository_project.json');
      await service.saveProject(project: project, filePath: file.path);

      final loaded = await service.loadIntoRepository(
        repository: repository,
        filePath: file.path,
      );

      expect(loaded, project);
      expect(repository.currentProject, project);
    });
  });
}

Project _sampleProject() {
  return Project(
    id: const ProjectId('project-1'),
    name: 'Sample Project',
    tracks: [_sampleTrack()],
    createdAt: DateTime.utc(2026, 6, 2, 12),
    frameRate: const ProjectFrameRate.integer(12),
  );
}

Track _sampleTrack() {
  return Track(
    id: const TrackId('track-1'),
    name: 'Video Track',
    cuts: [_sampleCut()],
    // The track's SE floor, so save → load stays an identity round-trip
    // (SE rows are TRACK-owned).
    seLayers: withEnsuredTrackSeLayers(const TrackId('track-1'), const []),
  );
}

Cut _sampleCut() {
  const id = CutId('cut-1');
  return Cut(
    id: id,
    name: 'Cut 1',
    // Include the SE/instruction fixture rows loading would backfill, so
    // save → load stays an identity round-trip.
    layers: withEnsuredSectionLayers(id, [_sampleLayer()]),
    duration: 24,
    canvasSize: const CanvasSize(width: 1280, height: 720),
  );
}

Layer _sampleLayer() {
  return Layer(
    id: const LayerId('layer-1'),
    name: 'Ink Layer',
    frames: [_sampleFrame()],
    opacity: 0.75,
  );
}

Frame _sampleFrame() {
  return Frame(
    id: const FrameId('frame-1'),
    duration: 2,
    strokes: [_sampleStroke()],
  );
}

Stroke _sampleStroke() {
  return Stroke(
    id: const StrokeId('stroke-1'),
    points: const [StrokePoint(x: 1.5, y: 2.5), StrokePoint(x: 3.5, y: 4.5)],
    brushSettings: BrushSettings(color: 0xFF336699, size: 8, opacity: 0.5),
  );
}
