import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/audio_clip.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/media_asset.dart';
import 'package:anicel/src/models/media_reference.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/timesheet_info.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/services/brush_frame_store.dart';
import 'package:anicel/src/services/media/media_moves.dart';
import 'package:anicel/src/services/persistence/anicel_file_service.dart';
import '../../helpers/temp_dir.dart';

/// 🚨EVERY MOVE OF A FILE TAKES ONE WALK (`projectWithMediaMoved`).
///
/// A file's path changes two ways — a relink finds it somewhere else, a
/// load finds the folder moved — and the two walked the project each for
/// itself: the load's missed the rows that show a file
/// (`Layer.mediaReference`), so a folder that travelled opened with its pool
/// at the new place and those rows at the old one. And the work's pictures
/// (its logo and its cover) are references too, since they are taken from
/// the pool (답 logo-home 「작품 설정 한 곳」).
void main() {
  const old = 'D:/work/film/media/still.png';
  const now = 'E:/moved/film/media/still.png';

  /// A project whose every kind of reference names [path]: the pool entry,
  /// a clip on the track's sound row, a row showing it, and both of the
  /// work's pictures.
  Project referencing(String path) {
    final info = WorkPicture.cover.withPath(
      WorkPicture.logo.withPath(TimesheetInfo.empty, path),
      path,
    );
    return Project(
      id: const ProjectId('p'),
      name: 'P',
      createdAt: DateTime.utc(2026, 9, 27),
      timesheetInfo: info,
      mediaAssets: [
        MediaAsset(path: path, name: 'still', kind: MediaAssetKind.image),
      ],
      tracks: [
        Track(
          id: const TrackId('t'),
          name: 'V',
          seLayers: [
            Layer(
              id: const LayerId('se'),
              name: 'S1',
              frames: const [],
              kind: LayerKind.se,
              audioClips: [
                AudioClip(filePath: path, frameId: const FrameId('se-f')),
              ],
            ),
          ],
          cuts: [
            Cut(
              id: const CutId('c'),
              name: '1',
              duration: 12,
              canvasSize: const CanvasSize(width: 100, height: 100),
              layers: [
                Layer(
                  id: const LayerId('still'),
                  name: 'Still',
                  frames: const [],
                  kind: LayerKind.image,
                  mediaReference: MediaReference(assetPath: path),
                ),
              ],
            ),
          ],
        ),
      ],
    );
  }

  /// Where each kind of reference points, in [referencing]'s order — the
  /// rows found by their ids: a load gives a track and a cut the fixture
  /// rows they always carry.
  List<String?> pointedAt(Project project) {
    final track = project.tracks.single;
    Layer row(List<Layer> rows, String id) =>
        rows.singleWhere((layer) => layer.id == LayerId(id));
    return [
      project.mediaAssets.single.path,
      row(track.seLayers, 'se').audioClips.single.filePath,
      row(track.cuts.single.layers, 'still').mediaReference?.assetPath,
      WorkPicture.logo.pathIn(project.timesheetInfo),
      WorkPicture.cover.pathIn(project.timesheetInfo),
    ];
  }

  test('a move takes every reference along: the pool, the clips, the row '
      'that shows the file and the work\'s pictures', () {
    expect(pointedAt(referencing(old)), everyElement(old), reason: 'fixture');

    expect(
      pointedAt(projectWithMediaMoved(referencing(old), {old: now})),
      everyElement(now),
    );
  });

  test('a move is read as its mover spelled it: a load\'s manifest keeps '
      'backslashes, every reference the pool\'s one spelling', () {
    final moved = projectWithMediaMoved(referencing(old), {
      old.replaceAll('/', r'\'): now.replaceAll('/', r'\'),
    });

    expect(pointedAt(moved), everyElement(now));
  });

  test('what no move names keeps its IDENTITY', () {
    final project = referencing(old);

    final moved = projectWithMediaMoved(project, {
      'D:/elsewhere/other.png': now,
    });

    expect(identical(moved.tracks.single, project.tracks.single), isTrue);
    expect(pointedAt(moved), everyElement(old));
  });

  group('through the file', () {
    late Directory there;
    late Directory here;

    setUp(() async {
      there = await Directory.systemTemp.createTemp('anicel-walk-there');
      here = await Directory.systemTemp.createTemp('anicel-walk-here');
    });

    tearDown(() {
      deleteTempQuietly(there);
      deleteTempQuietly(here);
    });

    test('🚨a folder that travelled opens with EVERY reference where the '
        'folder is now — the rows that show its file too', () async {
      String slashed(Directory directory) =>
          directory.path.replaceAll('\\', '/');
      final saved = '${slashed(there)}/media/still.png';
      final landed = '${slashed(here)}/media/still.png';
      for (final path in [saved, landed]) {
        File(path)
          ..createSync(recursive: true)
          ..writeAsBytesSync(const [0, 1, 2, 3], flush: true);
      }
      const service = AnicelFileService();
      await service.save(
        project: referencing(saved),
        brushFrameStore: BrushFrameStore(),
        filePath: '${slashed(there)}/film.anicel',
      );
      // The folder travels: the document and its media, side by side.
      File(
        '${slashed(there)}/film.anicel',
      ).copySync('${slashed(here)}/film.anicel');

      final opened = await service.open(
        filePath: '${slashed(here)}/film.anicel',
      );

      expect(pointedAt(opened.project), everyElement(landed));
    });
  });
}
