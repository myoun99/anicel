import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/audio_clip.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_timeline.dart';
import 'package:anicel/src/models/timeline_id.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/services/editing/default_cut_helpers.dart';
import 'package:anicel/src/services/media/media_moves.dart';
import 'package:anicel/src/services/persistence/anicel_project_archive.dart'
    show projectMediaPaths;
import 'package:anicel/src/services/project_lookup.dart';
import 'package:anicel/src/services/project_tree_editor.dart';

/// 🗣️I-150 (유저 2026-11-03): 「새로운 타임라인을 만들수있음」 · 「트랙바꾸면
/// 타임라인 완전 바꿔치기됨. se던 뭐던 싹 다」 · 「미디어풀을 공용」.
///
/// A project holds several timelines: what the panels read is the open
/// one's, what the project holds is every one's.
void main() {
  const a = TimelineId('a');
  const b = TimelineId('b');

  /// A timeline [id] of one track of one cut, the cut's row [row] — playing
  /// [clip] when one is given.
  ProjectTimeline timeline(
    TimelineId id, {
    required int number,
    String? name,
    int trailingFrames = 0,
    String? clip,
  }) {
    final track = createDefaultTrack(
      trackId: TrackId('${id.value}-track'),
      firstCut: createDefaultCut(
        cutId: CutId('${id.value}-cut'),
        name: '1',
        layerId: LayerId('${id.value}-row'),
      ),
    );
    return ProjectTimeline(
      id: id,
      number: number,
      name: name,
      trailingFrames: trailingFrames,
      tracks: [
        if (clip == null)
          track
        else
          track.copyWith(
            seLayers: [
              track.seLayers.first.copyWith(
                audioClips: [
                  AudioClip(filePath: clip, frameId: FrameId('${id.value}-se')),
                ],
              ),
              ...track.seLayers.skip(1),
            ],
          ),
      ],
    );
  }

  /// A and B, B open — A playing [clipOfA].
  Project twoTimelines({String? clipOfA}) =>
      createDefaultProject().copyWith(
        timelines: [
          timeline(a, number: 1, trailingFrames: 4, clip: clipOfA),
          timeline(b, number: 2, name: '본편'),
        ],
        currentTimelineId: b,
      );

  test('a project made of tracks holds one timeline of them, and reads them '
      'and its trailing gap as it always did', () {
    final track = createDefaultTrack();
    final project = Project(
      id: createDefaultProject().id,
      name: 'p',
      createdAt: DateTime.utc(2026),
      tracks: [track],
      trailingFrames: 7,
    );

    expect(project.timelines.single.id, firstProjectTimelineId);
    expect(project.currentTimelineId, firstProjectTimelineId);
    expect(project.tracks, [track]);
    expect(project.trailingFrames, 7);
  });

  test('the tracks read are the open timeline\'s, and a write of them or of '
      'the trailing gap lands there alone', () {
    final project = twoTimelines();
    final before = project.timelines.first;
    expect(project.tracks.single.id, const TrackId('b-track'));
    expect(project.trailingFrames, 0);

    final written = project.copyWith(
      tracks: [project.tracks.single.copyWith(fxEnabled: false)],
      trailingFrames: 3,
    );

    expect(written.timelines.first, same(before));
    expect(written.timelines.last.tracks.single.fxEnabled, isFalse);
    expect(written.timelines.last.trailingFrames, 3);
    expect(written.timelines.last.name, '본편');
  });

  test('a timeline named nowhere opens the first', () {
    final project = twoTimelines().copyWith(
      currentTimelineId: const TimelineId('gone'),
    );

    expect(project.currentTimelineId, a);
    expect(project.trailingFrames, 4);
  });

  test('every timeline, its number, its name, its trailing gap and the open '
      'one come back from the file\'s words — and nothing stands outside '
      'them', () {
    final project = twoTimelines();
    final json = project.toJson();
    final reread = Project.fromJson(
      jsonDecode(jsonEncode(json)) as Map<String, dynamic>,
    );

    expect(json.containsKey('tracks'), isFalse);
    expect(json.containsKey('trailingFrames'), isFalse);
    expect(reread, project);
    expect(reread.currentTimelineId, b);
    expect([for (final t in reread.timelines) t.number], [1, 2]);
    expect([for (final t in reread.timelines) t.name], [null, '본편']);
    expect(reread.timelines.first.trailingFrames, 4);
  });

  test('a renamed timeline differs from the one it was', () {
    final project = twoTimelines();
    final renamed = project.copyWith(
      timelines: [project.timelines.first.named('예고'), project.timelines.last],
    );

    expect(renamed == project, isFalse);
    expect(renamed.timelines.first.named(null), project.timelines.first);
  });

  group('🚨what the project holds is every timeline\'s', () {
    test('a cut, a row and an id are found in a closed timeline', () {
      final project = twoTimelines();

      expect(
        cutPositionOf(project, const CutId('a-cut'))?.trackId,
        const TrackId('a-track'),
      );
      expect(
        layerAnywhereOrNull(project, const LayerId('a-row')),
        isNotNull,
      );
      expect(projectLayerIdValues(project), contains('a-row'));
      expect(projectLayerIdValues(project), contains('a-track-se-1'));
    });

    test('a write addressed by id reaches a closed timeline, and only the '
        'one that holds it', () {
      final project = twoTimelines();
      final open = project.timelines.last;

      final renamed = updateCutAnywhere(
        project,
        const CutId('a-cut'),
        (cut) => cut.copyWith(name: '9'),
      )!;
      final rowRenamed = updateLayerAnywhere(
        project,
        const LayerId('a-row'),
        (row) => row.copyWith(name: 'Z'),
      )!;
      final gone = removeCutAnywhere(project, const CutId('a-cut'));

      expect(renamed.timelines.first.tracks.single.cuts.single.name, '9');
      expect(renamed.timelines.last, open);
      expect(renamed.currentTimelineId, b);
      expect(
        rowRenamed.timelines.first.tracks.single.cuts.single.layers
            .firstWhere((row) => row.id == const LayerId('a-row'))
            .name,
        'Z',
      );
      expect(gone.removed?.id, const CutId('a-cut'));
      expect(gone.project.timelines.first.tracks.single.cuts, isEmpty);
      expect(gone.project.timelines.last, open);
    });

    test('a rebuild that changes nothing is the project it was', () {
      final project = twoTimelines();

      expect(
        project.withTracksOfEveryTimeline((tracks) => tracks),
        same(project),
      );
    });

    test('a closed timeline\'s sound is a file the project uses: the pool '
        'holds it, a move follows it, and a save carries it', () {
      final project = twoTimelines(clipOfA: 'C:/se/door.wav');
      final reread = Project.fromJson(
        jsonDecode(jsonEncode(project.toJson())) as Map<String, dynamic>,
      );
      final moved = projectWithMediaMoved(project, {
        'C:/se/door.wav': 'D:/se/door.wav',
      });

      expect(projectMediaPaths(project), contains('C:/se/door.wav'));
      expect(
        [for (final asset in reread.mediaAssets) asset.path],
        contains('C:/se/door.wav'),
      );
      expect(
        moved.timelines.first.tracks.single.seLayers.first.audioClips.single
            .filePath,
        'D:/se/door.wav',
      );
      expect(moved.timelines.last, same(project.timelines.last));
    });
  });

  test('a new timeline is numbered after the last, under ids the project '
      'holds nowhere', () {
    final project = twoTimelines();

    final made = newTimelineIn(
      project,
      rowA: const LayerId('fresh-row'),
      canvasSize: defaultCutCanvasSize,
    );
    final track = made.tracks.single;

    expect(made.number, 3);
    expect(made.name, isNull);
    expect([for (final t in project.timelines) t.id], isNot(contains(made.id)));
    expect(
      [for (final t in project.tracksOfEveryTimeline) t.id],
      isNot(contains(track.id)),
    );
    expect(
      projectLayerIdValues(project).intersection({
        for (final row in track.seLayers) row.id.value,
        track.transitionLayer.id.value,
      }),
      isEmpty,
    );
    expect(track.cuts.single.name, '1');
    expect(
      track.cuts.single.layers
          .firstWhere((row) => row.id == const LayerId('fresh-row'))
          .timeline[0]
          ?.frameId,
      isNotNull,
      reason: 'row A is drawn on from its first frame, as a new project\'s',
    );
  });

  test('a new project is the track a new timeline is', () {
    final project = newUntitledProject();
    final made = newTimelineIn(
      project,
      rowA: project.tracks.single.cuts.single.layers.first.id,
      canvasSize: defaultCutCanvasSize,
    );
    Object shape(Track track) => [
      track.name,
      track.seLayers.length,
      [
        for (final cut in track.cuts)
          [
            cut.name,
            cut.canvasSize,
            for (final row in cut.layers)
              (row.name, row.kind, row.frames.length, row.timeline.keys),
          ],
      ],
    ];

    expect(
      shape(made.tracks.single).toString(),
      shape(project.tracks.single).toString(),
    );
  });
}
