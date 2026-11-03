import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/bitmap_tile.dart';
import 'package:anicel/src/models/brush_frame_key.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_link_registry.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_timeline.dart';
import 'package:anicel/src/models/tile_coord.dart';
import 'package:anicel/src/models/timesheet_ink_keys.dart'
    show timesheetInkPageKey;
import 'package:anicel/src/services/project_tree_editor.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';

/// 🗣️I-150 (유저 2026-11-03): 「트랙편집(우선은 이름?)/삭제/복제 가능」 —
/// a timeline copied is a copy: every track, cut, row and cel of it under
/// ids of its own, its pictures and handwriting along (「복제는 전부
/// 복사」, cut-duplicate-sheet-ink-Q1), and opened. Rows linked to each
/// other in it (겸용) stay linked — to each other's copies (I-150-Q2,
/// recommended a).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  EditorSessionManager session() {
    final s = EditorSessionManager(initialProject: newUntitledProject());
    addTearDown(s.dispose);
    return s;
  }

  Project projectOf(EditorSessionManager s) => s.repository.requireProject();

  ProjectTimeline openOf(EditorSessionManager s) =>
      projectOf(s).currentTimeline;

  Iterable<Cut> cutsOf(ProjectTimeline timeline) =>
      timeline.tracks.expand((track) => track.cuts);

  Set<String> idsOf(ProjectTimeline timeline) => {
    for (final track in timeline.tracks) ...[
      track.id.value,
      for (final row in [...track.seLayers, track.transitionLayer])
        row.id.value,
      for (final cut in track.cuts) ...[
        cut.id.value,
        for (final row in cut.layers) ...[
          row.id.value,
          for (final cel in row.frames) cel.id.value,
        ],
      ],
    ],
  };

  BitmapSurface surfaceOf(EditorSessionManager s, int red) {
    final pixels = Uint8List(256 * 256 * 4);
    for (var at = 0; at < pixels.length; at += 4) {
      pixels.setRange(at, at + 4, [red, 0, 0, 255]);
    }
    return BitmapSurface(
      canvasSize: s.requireActiveCut.canvasSize,
      tileSize: 256,
    ).putTiles([
      (
        coord: TileCoord(x: 0, y: 0),
        tile: BitmapTile(size: 256, pixels: pixels),
      ),
    ]);
  }

  BrushFrameKey keyOfOpenCel(EditorSessionManager s) {
    final row = s.activeLayer!;
    return s.brushFrameKeyForCut(
      s.requireActiveCut,
      row.id,
      row.frames.first.id,
    );
  }

  test('a copied timeline holds what its source does, under ids of its own, '
      'right after it in the list, and opened', () {
    final s = session();
    s.cutVerbs.createCut();
    s.timelineVerbs.addTimeline();
    final source = s.timelineVerbs.timelines.first;
    final last = s.timelineVerbs.timelines.last;

    s.timelineVerbs.duplicateTimeline(source.id, '  예고 ');

    final copy = openOf(s);
    expect(s.timelineVerbs.timelines.map((timeline) => timeline.id), [
      source.id,
      copy.id,
      last.id,
    ]);
    expect(copy.name, '예고');
    expect(copy.number, 3);
    expect(copy.trailingFrames, source.trailingFrames);
    expect(
      [
        for (final cut in cutsOf(copy))
          [cut.name, for (final row in cut.layers) row.name],
      ],
      [
        for (final cut in cutsOf(source))
          [cut.name, for (final row in cut.layers) row.name],
      ],
    );
    expect(
      [for (final row in copy.tracks.single.seLayers) row.name],
      [for (final row in source.tracks.single.seLayers) row.name],
    );
    expect(idsOf(copy).intersection(idsOf(source)), isEmpty);
    expect(s.activeCutId, cutsOf(copy).first.id);
  });

  test('a copy with a blank name is called by its number', () {
    final s = session();

    s.timelineVerbs.duplicateTimeline(openOf(s).id, ' ');

    expect(openOf(s).name, isNull);
    expect(openOf(s).number, 2);
  });

  test('copying a timeline the project holds not is no step', () {
    final s = session();
    final steps = s.historyManager.undoCount;
    final before = projectOf(s);

    s.timelineVerbs.duplicateTimeline(
      newTimelineIn(
        before,
        rowA: s.layerIds.mint(),
        canvasSize: s.requireActiveCut.canvasSize,
      ).id,
      '',
    );

    expect(s.historyManager.undoCount, steps);
    expect(identical(projectOf(s), before), isTrue);
  });

  test('a copy\'s pictures and handwriting are its source\'s, and drawing on '
      'the copy leaves the source as it was', () {
    final s = session();
    final store = s.renderCaches.brushFrameStore;
    final ofSource = keyOfOpenCel(s);
    final drawn = surfaceOf(s, 40);
    store.storeBakedSurface(ofSource, drawn);
    final sheet = timesheetInkPageKey(s.activeCutId!, 0);
    s.renderCaches.timesheetInkStore.storeBakedSurface(sheet, surfaceOf(s, 7));

    s.timelineVerbs.duplicateTimeline(openOf(s).id, '');

    final ofCopy = keyOfOpenCel(s);
    expect(ofCopy, isNot(ofSource));
    expect(store.bakedSurfaceOrNull(ofCopy), isNotNull);
    expect(
      s.renderCaches.timesheetInkStore.bakedSurfaceOrNull(
        timesheetInkPageKey(s.activeCutId!, 0),
      ),
      isNotNull,
    );

    store.storeBakedSurface(ofCopy, surfaceOf(s, 200));

    expect(identical(store.bakedSurfaceOrNull(ofSource), drawn), isTrue);
  });

  test('🚨rows linked in the source stay linked — to each other\'s copies, '
      'sharing the copied cels, and never to the source', () {
    final s = session();
    s.cutVerbs.createLinkedCutFromActiveCut();
    final source = openOf(s);
    final sourceCuts = {for (final cut in cutsOf(source)) cut.id};
    final before = projectOf(s).linkRegistry.groups;
    expect(before, isNotEmpty);

    s.timelineVerbs.duplicateTimeline(source.id, '');

    final copyCuts = {for (final cut in cutsOf(openOf(s))) cut.id};
    final groups = projectOf(s).linkRegistry.groups;
    expect(groups, hasLength(before.length * 2));
    for (final group in groups.skip(before.length)) {
      expect(group.members.map((member) => member.cutId), everyElement(
        isIn(copyCuts),
      ));
      final cels = {
        for (final member in group.members)
          [
            for (final cel in _rowOf(projectOf(s), member).frames)
              cel.id.value,
          ].join(','),
      };
      expect(cels, hasLength(1), reason: 'linked rows share their cels');
    }
    for (final group in groups.take(before.length)) {
      expect(group.members.map((member) => member.cutId), everyElement(
        isIn(sourceCuts),
      ));
    }
  });

  test('one undo takes the copy away and stands where it was; the copy '
      'deleted takes its links with it', () {
    final s = session();
    s.cutVerbs.createLinkedCutFromActiveCut();
    final source = openOf(s).id;
    final standing = s.activeCutId;
    final links = projectOf(s).linkRegistry;

    s.timelineVerbs.duplicateTimeline(source, '');
    s.undo();

    expect(s.timelineVerbs.timelines, hasLength(1));
    expect(s.activeCutId, standing);
    expect(projectOf(s).linkRegistry, links);

    s.redo();
    expect(s.timelineVerbs.timelines, hasLength(2));
    s.timelineVerbs.deleteTimeline(openOf(s).id);

    expect(s.timelineVerbs.timelines, hasLength(1));
    expect(projectOf(s).linkRegistry, links);
  });

  test('🚨a timeline deleted under the canonical of a group that reaches '
      'another hands its cels to the survivor, and the undo takes them '
      'back', () {
    final s = session();
    final survivorCut = s.requireActiveCut;
    final survivor = s.activeLayer!;
    s.timelineVerbs.addTimeline();
    final gone = openOf(s).id;
    final canonicalCut = s.requireActiveCut;
    final canonicalRow = s.activeLayer!;
    s.repository.updateProject(
      (project) => updateLayerAnywhere(
        project,
        canonicalRow.id,
        (row) => row.copyWith(
          frames: survivor.frames,
          timeline: survivor.timeline,
        ),
      )!.copyWith(
        linkRegistry: LayerLinkRegistry(
          groups: [
            LayerLinkGroup(
              id: 'across',
              members: [
                LayerLinkMember(
                  trackId: openOf(s).tracks.single.id,
                  cutId: canonicalCut.id,
                  layerId: canonicalRow.id,
                ),
                LayerLinkMember(
                  trackId: project.timelines.first.tracks.single.id,
                  cutId: survivorCut.id,
                  layerId: survivor.id,
                ),
              ],
            ),
          ],
        ),
      ),
    );
    final cel = survivor.frames.first.id;
    final store = s.renderCaches.brushFrameStore;
    final drawn = surfaceOf(s, 90);
    final atCanonical = s.brushFrameKeyForCut(
      s.requireActiveCut,
      canonicalRow.id,
      cel,
    );
    store.storeBakedSurface(atCanonical, drawn);

    s.timelineVerbs.deleteTimeline(gone);

    final atSurvivor = s.brushFrameKeyForCut(survivorCut, survivor.id, cel);
    expect(projectOf(s).linkRegistry.groups, isEmpty);
    expect(identical(store.bakedSurfaceOrNull(atSurvivor), drawn), isTrue);

    s.undo();

    expect(projectOf(s).linkRegistry.groups, hasLength(1));
    expect(identical(store.bakedSurfaceOrNull(atCanonical), drawn), isTrue);
  });
}

Layer _rowOf(Project project, LayerLinkMember member) => project
    .tracksOfEveryTimeline
    .expand((track) => track.cuts)
    .singleWhere((cut) => cut.id == member.cutId)
    .layers
    .singleWhere((row) => row.id == member.layerId);
