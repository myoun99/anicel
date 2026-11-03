import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/bitmap_tile.dart';
import 'package:anicel/src/models/camera_pose.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/conte/conte_ink_keys.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/pill_subject.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/tile_coord.dart';
import 'package:anicel/src/models/timesheet_ink_keys.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/timeline/toolbar_panel_context.dart';

import '../../helpers/conte_track_fixture.dart';
import '../../helpers/draw_on_current_frame.dart';
import '../../helpers/pill_row_clipboard.dart';

/// 🗣️I-150-Q3 (유저 2026-11-03): 「일단 다른 타임라인끼리는 단순 겸용컷
/// 작동안하게. 지금 겸용 만드는게 컷 복사하고 다른타임라인에 링크붙여넣기
/// 뿐인데 이 동작을 겸용컷이라기보다 새 시스템으로 … 이는 겸용컷이면서
/// 추가로 타임라인까지 완벽동기화된 실질 같은컷 취급」 — a cut linked into
/// another timeline is a 동기컷: the same cut, standing in both.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const first = CutId('cut-1');

  EditorSessionManager session() {
    final s = EditorSessionManager(initialProject: conteTrackProject());
    addTearDown(s.dispose);
    return s;
  }

  Project projectOf(EditorSessionManager s) => s.repository.requireProject();

  /// The cut [id] in the [timeline]-th timeline, open or not.
  Cut cutIn(EditorSessionManager s, int timeline, CutId id) =>
      projectOf(s).timelines[timeline].tracks
          .expand((track) => track.cuts)
          .singleWhere((cut) => cut.id == id);

  /// Copies cut-1 standing on it, opens a new timeline and link-pastes it
  /// there — the 동기컷, in the second timeline.
  Cut linkedIntoANewTimeline(EditorSessionManager s) {
    s.selectGlobalFrame(1);
    s.selectTrackRow(conteTrackId);
    StoryboardToolbarPanelContext(s).copyFrame();
    s.timelineVerbs.addTimeline();
    expect(projectOf(s).currentTimeline.number, 2, reason: '⛔전제');
    StoryboardToolbarPanelContext(s).pasteLinkedFrame();
    return projectOf(s).tracks.single.cuts.last;
  }

  void open(EditorSessionManager s, int timeline) =>
      s.timelineVerbs.openTimeline(projectOf(s).timelines[timeline].id);

  /// The picture of cel [cel] on [cut]'s first row, as [s] reads it there.
  BitmapSurface? pictureOf(EditorSessionManager s, Cut cut, FrameId cel) =>
      s.renderCaches.brushFrameStore.bakedSurfaceOrNull(
        s.brushFrameKeyForCut(cut, cut.layers.first.id, cel),
      );

  /// Stands on the 동기컷 [made] in the open timeline, on its first row,
  /// with no band up (a paste leaves one over what it pasted).
  void standIn(EditorSessionManager s, Cut made) {
    s.clearFrameRangeSelection();
    s.selectGlobalFrame(projectOf(s).tracks.single.cuts.first.duration + 1);
    s.selectLayer(made.layers.first.id);
    expect(s.requireActiveCut.id, made.id, reason: '⛔전제');
  }

  BitmapSurface ink({int seed = 1}) {
    final pixels = Uint8List(8 * 8 * 4);
    for (var i = 0; i < pixels.length; i += 1) {
      pixels[i] = (i * seed * 13 + seed) & 0xFF;
    }
    return BitmapSurface(
      canvasSize: const CanvasSize(width: 16, height: 16),
      tileSize: 8,
      tiles: {TileCoord(x: 0, y: 0): BitmapTile(size: 8, pixels: pixels)},
    );
  }

  test('the paste puts the SAME cut there — its length, its panels, every '
      'row linked to the row it copies — named by where it lands', () {
    final s = session();
    final made = linkedIntoANewTimeline(s);
    final source = cutIn(s, 0, first);
    final project = projectOf(s);

    expect(made.id, isNot(first));
    expect(made.name, '2', reason: 'I-150-Q5: counting on from the cut in '
        'front of where it lands');
    expect(made.duration, source.duration);
    expect(
      [for (final row in made.layers) row.timeline],
      [for (final row in source.layers) row.timeline],
      reason: 'the timing is the cut\'s, not started over as a 겸용\'s',
    );
    expect(
      [for (final row in made.layers) row.frames],
      [for (final row in source.layers) row.frames],
    );
    for (final (index, row) in source.layers.indexed) {
      expect(
        project.linkRegistry.counterpartIn(
          cutId: first,
          layerId: row.id,
          targetCutId: made.id,
        ),
        made.layers[index].id,
        reason: 'the pictures are one',
      );
    }
    expect(project.linkRegistry.syncOf(made.id)?.cuts, [first, made.id]);
    expect(
      Project.fromJson(project.toJson()).linkRegistry.syncOf(first)?.cuts,
      [first, made.id],
      reason: 'a saved project opens with its 동기컷',
    );
  });

  test('the paste undone and done again is the same 동기컷 again', () {
    final s = session();
    final made = linkedIntoANewTimeline(s);

    s.historyManager.undo();
    s.historyManager.redo();

    expect(projectOf(s).tracks.single.cuts.last, made);
    expect(projectOf(s).linkRegistry.syncOf(made.id)?.cuts, [first, made.id]);
  });

  test('an edit of either cut is the other\'s: the length drawn in the '
      'second timeline, a camera key put on in the first', () {
    final s = session();
    final made = linkedIntoANewTimeline(s);
    s.cutCommandCoordinator.commitCutDurationDrag(
      beforeDurations: {made.id: 12},
      afterDurations: {made.id: 16},
    );
    expect(cutIn(s, 0, first).duration, 16);

    open(s, 0);
    final pose = CameraPose(center: CanvasPoint(x: 5, y: 5), zoom: 1.5);
    s.cutCommandCoordinator.setCutCameraKeyframe(
      cutId: first,
      frameIndex: 3,
      pose: pose,
    );
    expect(cutIn(s, 1, made.id).camera.keyframes[3], pose);
    expect(cutIn(s, 1, made.id).name, '2', reason: 'its place is its own');

    s.historyManager.undo();
    expect(cutIn(s, 1, made.id).camera.keyframes, isEmpty);
    s.historyManager.undo();
    s.historyManager.undo();
    expect(cutIn(s, 0, first).duration, 12);
    expect(cutIn(s, 1, made.id).duration, 12);
  });

  test('a drawing on one is on the other — the cel, where it stands', () {
    final s = session();
    final made = linkedIntoANewTimeline(s);
    s.selectGlobalFrame(projectOf(s).tracks.single.cuts.first.duration + 1);
    expect(s.requireActiveCut.id, made.id, reason: '⛔전제');
    s.selectLayer(made.layers.first.id);
    drawOnCurrentFrame(s);

    final drawn = projectOf(s).tracks.single.cuts.last;
    final source = cutIn(s, 0, first);
    expect(source.layers.first.timeline, drawn.layers.first.timeline);
    final cel = drawn.layers.first.frames.last.id;
    final store = s.renderCaches.brushFrameStore;
    final picture = store.bakedSurfaceOrNull(
      s.brushFrameKeyForCut(drawn, drawn.layers.first.id, cel),
    );
    expect(picture, isNotNull, reason: '⛔전제: a drawing');
    expect(
      store.bakedSurfaceOrNull(
        s.brushFrameKeyForCut(source, source.layers.first.id, cel),
      ),
      same(picture),
    );

    s.historyManager.undo();
    expect(cutIn(s, 0, first).layers.first, isNot(source.layers.first));
    expect(
      cutIn(s, 1, made.id).layers.first.timeline,
      cutIn(s, 0, first).layers.first.timeline,
      reason: 'the undo takes the cel off both',
    );
    s.historyManager.redo();
    expect(cutIn(s, 0, first).layers.first, source.layers.first);
    expect(cutIn(s, 1, made.id).layers.first, drawn.layers.first);
  });

  test('drawn on in the first timeline, the cel is the second\'s too', () {
    final s = session();
    final made = linkedIntoANewTimeline(s);
    open(s, 0);
    s.selectGlobalFrame(1);
    s.selectLayer(cutIn(s, 0, first).layers.first.id);
    drawOnCurrentFrame(s);

    expect(
      cutIn(s, 1, made.id).layers.first.timeline,
      cutIn(s, 0, first).layers.first.timeline,
    );
    expect(
      cutIn(s, 1, made.id).layers.first.frames,
      cutIn(s, 0, first).layers.first.frames,
    );
  });

  test('what is written on one cut\'s sheets is on the other\'s — one '
      'timesheet page, one conte block, kept once', () {
    final s = session();
    final made = linkedIntoANewTimeline(s);
    final caches = s.renderCaches;
    final page = ink();
    final block = ink(seed: 2);
    caches.timesheetInkStore.storeBakedSurface(
      timesheetInkPageKey(made.id, 0),
      page,
    );
    caches.conteInkRowStore.storeBakedSurface(
      conteInkRowKey(made.id, 'block-1'),
      block,
    );

    expect(
      caches.timesheetInkStore.bakedSurfaceOrNull(
        timesheetInkPageKey(first, 0),
      ),
      same(page),
    );
    expect(
      caches.conteInkRowStore.bakedSurfaceOrNull(
        conteInkRowKey(first, 'block-1'),
      ),
      same(block),
    );
    expect(caches.timesheetInkStore.bakedSurfacesForCut(made.id), isEmpty);
    expect(caches.timesheetInkStore.bakedSurfacesForCut(first), hasLength(1));
  });

  test('undoing the paste takes the cut and the sync back, and the first '
      'cut is as it was', () {
    final s = session();
    final before = projectOf(s);
    linkedIntoANewTimeline(s);

    s.historyManager.undo();

    final project = projectOf(s);
    expect(project.linkRegistry.syncs, isEmpty);
    expect(project.linkRegistry.groups, before.linkRegistry.groups);
    expect(project.tracks.single.cuts, hasLength(1));
    expect(cutIn(s, 0, first), before.tracks.first.cuts.first);
  });

  test('the first timeline\'s cut deleted, the second is a cut of its own '
      'and the sheets\' paper — its handwriting moves to it, and back with '
      'the undo', () {
    final s = session();
    final made = linkedIntoANewTimeline(s);
    final caches = s.renderCaches;
    final page = ink();
    caches.timesheetInkStore.storeBakedSurface(
      timesheetInkPageKey(made.id, 0),
      page,
    );
    open(s, 0);

    s.cutCommandCoordinator.deleteCut(cutId: first);

    expect(projectOf(s).linkRegistry.syncs, isEmpty);
    expect(
      caches.timesheetInkStore.bakedSurfacesForCut(made.id).values,
      [same(page)],
    );
    expect(caches.timesheetInkStore.bakedSurfacesForCut(first), isEmpty);

    s.historyManager.undo();
    expect(projectOf(s).linkRegistry.syncOf(made.id)?.cuts, [first, made.id]);
    expect(
      caches.timesheetInkStore.bakedSurfacesForCut(first).values,
      [same(page)],
    );
  });

  test('a timeline deleted takes its cut out of the sync, and its sheets\' '
      'handwriting to the cut left', () {
    final s = session();
    final made = linkedIntoANewTimeline(s);
    final caches = s.renderCaches;
    final page = ink();
    caches.timesheetInkStore.storeBakedSurface(
      timesheetInkPageKey(first, 0),
      page,
    );

    s.timelineVerbs.deleteTimeline(projectOf(s).timelines.first.id);

    expect(projectOf(s).linkRegistry.syncs, isEmpty);
    expect(
      caches.timesheetInkStore.bakedSurfacesForCut(made.id).values,
      [same(page)],
    );
    s.historyManager.undo();
    expect(projectOf(s).linkRegistry.syncOf(first)?.cuts, [first, made.id]);
    expect(
      caches.timesheetInkStore.bakedSurfacesForCut(first).values,
      [same(page)],
    );
  });

  test('the second timeline duplicated, the copy of the 동기컷 is a cut of '
      'its own, with the sheets\' handwriting it showed', () {
    final s = session();
    final made = linkedIntoANewTimeline(s);
    final caches = s.renderCaches;
    caches.timesheetInkStore.storeBakedSurface(
      timesheetInkPageKey(made.id, 0),
      ink(),
    );

    s.timelineVerbs.duplicateTimeline(projectOf(s).timelines[1].id, 'copy');

    final copy = projectOf(s).tracks.single.cuts.last;
    expect(copy.id, isNot(made.id), reason: '⛔전제: the copy is open');
    expect(projectOf(s).linkRegistry.syncOf(copy.id), isNull);
    expect(projectOf(s).linkRegistry.syncOf(made.id)?.cuts, [first, made.id]);
    expect(caches.timesheetInkStore.bakedSurfacesForCut(copy.id), hasLength(1));
  });

  test('linked into a third timeline, the cut joins the same sync — one '
      'cut standing in three', () {
    final s = session();
    final made = linkedIntoANewTimeline(s);
    s.timelineVerbs.addTimeline();

    StoryboardToolbarPanelContext(s).pasteLinkedFrame();

    final third = projectOf(s).tracks.single.cuts.last;
    expect(
      projectOf(s).linkRegistry.syncs.single.cuts,
      [first, made.id, third.id],
    );
    expect(third.duration, made.duration);
  });

  test('a row deleted from one is gone from the other, and the undo puts '
      'it back in both', () {
    final s = session();
    final made = linkedIntoANewTimeline(s);
    final rowsBefore = [for (final row in cutIn(s, 0, first).layers) row.id];

    s.cutCommandCoordinator.deleteLayer(
      cutId: made.id,
      layerId: made.layers.first.id,
    );

    expect(cutIn(s, 0, first).layers, hasLength(rowsBefore.length - 1));
    expect(
      [for (final row in cutIn(s, 0, first).layers) row.name],
      [for (final row in cutIn(s, 1, made.id).layers) row.name],
    );
    s.historyManager.undo();
    expect([for (final row in cutIn(s, 0, first).layers) row.id], rowsBefore);
  });

  test('made a 겸용 of a cut where it stands, the 동기컷 takes its sync '
      'along — the other timeline\'s cut is the same 겸용', () {
    final s = session();
    final made = linkedIntoANewTimeline(s);
    final here = projectOf(s).tracks.single.cuts.first.id;

    s.cutCommandCoordinator.convertCutToLinked(
      originCutId: here,
      targetCutId: made.id,
    );

    final registry = projectOf(s).linkRegistry;
    final synced = cutIn(s, 1, made.id);
    expect(registry.syncOf(made.id)?.cuts, [first, made.id]);
    expect(
      [for (final row in cutIn(s, 0, first).layers) row.name],
      [for (final row in synced.layers) row.name],
    );
    for (final row in synced.layers) {
      if (registry.counterpartIn(
            cutId: made.id,
            layerId: row.id,
            targetCutId: here,
          ) !=
          null) {
        expect(
          registry.counterpartIn(
            cutId: made.id,
            layerId: row.id,
            targetCutId: first,
          ),
          isNotNull,
          reason: '${row.name}: one row of one cut',
        );
      }
    }
  });

  test('a row of the 동기컷 unlinked from the 겸용 where it stands leaves with '
      'the other timeline\'s row — still one row, every picture kept', () {
    final s = session();
    final made = linkedIntoANewTimeline(s);
    s.selectGlobalFrame(projectOf(s).tracks.single.cuts.first.duration + 1);
    s.selectLayer(made.layers.first.id);
    drawOnCurrentFrame(s);
    s.selectTrackRow(conteTrackId);
    final before = {for (final cut in projectOf(s).tracks.single.cuts) cut.id};
    StoryboardToolbarPanelContext(s).copyFrame();
    StoryboardToolbarPanelContext(s).pasteLinkedFrame();
    StoryboardToolbarPanelContext(s).pasteLinkedFrame();
    final kept = [
      for (final cut in projectOf(s).tracks.single.cuts)
        if (!before.contains(cut.id)) cut.id,
    ];
    expect(kept, hasLength(2), reason: '⛔전제: two 겸용 of it');
    final row = made.layers.first.id;
    LayerId? rowIn(CutId cut) => projectOf(s).linkRegistry.counterpartIn(
      cutId: made.id,
      layerId: row,
      targetCutId: cut,
    );
    final rows = {
      made.id: row,
      first: rowIn(first)!,
      for (final cut in kept) cut: rowIn(cut)!,
    };
    final cel = cutIn(s, 1, made.id).layers.first.frames.last.id;
    BitmapSurface? pictureOf(CutId id) {
      final cut = projectOf(s).tracksOfEveryTimeline
          .expand((track) => track.cuts)
          .singleWhere((cut) => cut.id == id);
      return s.renderCaches.brushFrameStore.bakedSurfaceOrNull(
        s.brushFrameKeyForCut(cut, rows[id]!, cel),
      );
    }

    final picture = pictureOf(made.id);
    expect(picture, isNotNull, reason: '⛔전제: a drawing');
    expect(pictureOf(kept.first), same(picture), reason: '⛔전제: 겸용');

    s.cutCommandCoordinator.unlinkLayer(cutId: made.id, layerId: row);

    final registry = projectOf(s).linkRegistry;
    expect(rowIn(first), rows[first]);
    expect([for (final cut in kept) rowIn(cut)], [null, null]);
    expect(
      registry.counterpartIn(
        cutId: kept.first,
        layerId: rows[kept.first]!,
        targetCutId: kept.last,
      ),
      rows[kept.last],
      reason: 'the 겸용 left behind are one another\'s still',
    );
    final left = registry.groupOf(
      cutId: kept.first,
      layerId: rows[kept.first]!,
    );
    expect(
      registry.groupOf(cutId: made.id, layerId: row)?.id,
      isNot(left?.id),
      reason: 'two groups, two names',
    );
    for (final cut in rows.keys) {
      expect(pictureOf(cut), same(picture), reason: '$cut');
    }

    s.historyManager.undo();
    expect([for (final cut in kept) rowIn(cut)], [
      for (final cut in kept) rows[cut],
    ]);
    for (final cut in rows.keys) {
      expect(pictureOf(cut), same(picture), reason: '$cut');
    }
  });

  // 🗣️I-150-Q3: 「실질 같은컷 취급」 — the other timeline's row is the row
  // itself, so a cel it shows is no cel shared; a row linked to it is.
  test("the frame axis's 링크 독립 finds nothing shared in a 동기컷's row — "
      'and, the row pasted linked beside it, it does', () {
    final s = session();
    final made = linkedIntoANewTimeline(s);
    standIn(s, made);
    drawOnCurrentFrame(s);
    expect(
      cutIn(s, 0, first).layers.first.frames,
      cutIn(s, 1, made.id).layers.first.frames,
      reason: '⛔전제: the cel is the other timeline\'s too',
    );

    expect(s.cells.canUnlinkCells, isFalse);
    expect(s.unlinkSubject, PillSubject.nothing);
    expect(s.cutVerbs.cutIsLinked(made.id), isFalse);
    expect(
      s.cutVerbs.syncedCutIds,
      {made.id},
      reason: 'of the open timeline\'s two cuts',
    );

    linkDuplicateActiveRow(s);
    standIn(s, made);

    expect(s.cells.canUnlinkCells, isTrue, reason: 'its copy shows the cel');
    expect(s.cutVerbs.cutIsLinked(made.id), isTrue);
  });

  // 🗣️I-150-Q6 (유저 2026-11-04): 「동기 해제 = 독립 컷」 — the cut leaves
  // the sync and every link of its rows, each cut keeping its pictures.
  test('동기 해제 makes the cut one of its own — every picture and the '
      "sheets' handwriting kept by both, and one undo makes them one "
      'again', () {
    final s = session();
    final made = linkedIntoANewTimeline(s);
    standIn(s, made);
    drawOnCurrentFrame(s);
    final cel = cutIn(s, 1, made.id).layers.first.frames.last.id;
    final caches = s.renderCaches;
    final page = ink();
    caches.timesheetInkStore.storeBakedSurface(
      timesheetInkPageKey(made.id, 0),
      page,
    );
    final picture = pictureOf(s, cutIn(s, 1, made.id), cel);
    expect(picture, isNotNull, reason: '⛔전제: a drawing');
    final depth = s.historyManager.undoCount;

    s.cutVerbs.unsyncCut(made.id);

    void expectApart() {
      final registry = projectOf(s).linkRegistry;
      expect(registry.syncs, isEmpty);
      for (final (cut, rows) in [
        (made.id, cutIn(s, 1, made.id).layers),
        (first, cutIn(s, 0, first).layers),
      ]) {
        for (final row in rows) {
          expect(
            registry.groupOf(cutId: cut, layerId: row.id),
            isNull,
            reason: '${row.name} of $cut',
          );
        }
      }
      expect(pictureOf(s, cutIn(s, 0, first), cel), same(picture));
      expect(pictureOf(s, cutIn(s, 1, made.id), cel), same(picture));
      for (final cut in [first, made.id]) {
        expect(
          caches.timesheetInkStore.bakedSurfacesForCut(cut).values,
          [same(page)],
          reason: '$cut',
        );
      }
    }

    expectApart();
    expect(s.historyManager.undoCount, depth + 1);

    s.historyManager.undo();
    final registry = projectOf(s).linkRegistry;
    expect(registry.syncOf(made.id)?.cuts, [first, made.id]);
    expect(
      registry.counterpartIn(
        cutId: first,
        layerId: cutIn(s, 0, first).layers.first.id,
        targetCutId: made.id,
      ),
      made.layers.first.id,
    );
    expect(pictureOf(s, cutIn(s, 1, made.id), cel), same(picture));
    expect(
      caches.timesheetInkStore.bakedSurfacesForCut(made.id),
      isEmpty,
      reason: 'one page, kept once',
    );
    expect(
      caches.timesheetInkStore.bakedSurfaceOrNull(
        timesheetInkPageKey(made.id, 0),
      ),
      same(page),
    );

    s.historyManager.redo();
    expectApart();

    s.cutCommandCoordinator.commitCutDurationDrag(
      beforeDurations: {made.id: made.duration},
      afterDurations: {made.id: made.duration + 4},
    );
    expect(
      cutIn(s, 0, first).duration,
      made.duration,
      reason: 'an edit of one is no longer the other\'s',
    );
  });

  test('동기 해제 of the cut whose id the sheets are kept under leaves the '
      'other a copy of them — a timesheet page and a conte block', () {
    final s = session();
    final made = linkedIntoANewTimeline(s);
    final caches = s.renderCaches;
    final page = ink();
    final block = ink(seed: 2);
    caches.timesheetInkStore.storeBakedSurface(
      timesheetInkPageKey(made.id, 0),
      page,
    );
    caches.conteInkRowStore.storeBakedSurface(
      conteInkRowKey(made.id, 'block-1'),
      block,
    );
    open(s, 0);

    s.cutVerbs.unsyncCut(first);

    expect(projectOf(s).linkRegistry.syncs, isEmpty);
    for (final cut in [first, made.id]) {
      expect(
        caches.timesheetInkStore.bakedSurfacesForCut(cut).values,
        [same(page)],
        reason: '$cut',
      );
      expect(
        caches.conteInkRowStore.bakedSurfaceOrNull(
          conteInkRowKey(cut, 'block-1'),
        ),
        same(block),
        reason: '$cut',
      );
    }

    s.historyManager.undo();
    expect(projectOf(s).linkRegistry.syncOf(first)?.cuts, [first, made.id]);
    expect(caches.timesheetInkStore.bakedSurfacesForCut(made.id), isEmpty);
    expect(caches.conteInkRowStore.bakedSurfacesForCut(made.id), isEmpty);
    expect(
      caches.timesheetInkStore.bakedSurfacesForCut(first).values,
      [same(page)],
    );
  });

  test('동기 해제 of one cut of three leaves the other two one cut', () {
    final s = session();
    final made = linkedIntoANewTimeline(s);
    s.timelineVerbs.addTimeline();
    StoryboardToolbarPanelContext(s).pasteLinkedFrame();
    final third = projectOf(s).tracks.single.cuts.last.id;
    expect(
      projectOf(s).linkRegistry.syncs.single.cuts,
      [first, made.id, third],
      reason: '⛔전제',
    );
    final caches = s.renderCaches;
    final page = ink();
    caches.timesheetInkStore.storeBakedSurface(
      timesheetInkPageKey(third, 0),
      page,
    );
    open(s, 1);

    s.cutVerbs.unsyncCut(made.id);

    final registry = projectOf(s).linkRegistry;
    final row = cutIn(s, 0, first).layers.first.id;
    expect(registry.syncs.single.cuts, [first, third]);
    expect(
      registry.counterpartIn(cutId: first, layerId: row, targetCutId: third),
      cutIn(s, 2, third).layers.first.id,
    );
    expect(
      registry.counterpartIn(cutId: first, layerId: row, targetCutId: made.id),
      isNull,
    );
    expect(
      caches.timesheetInkStore.bakedSurfacesForCut(made.id).values,
      [same(page)],
    );
    expect(
      caches.timesheetInkStore.bakedSurfacesForCut(third),
      isEmpty,
      reason: 'still kept under the first',
    );

    s.cutCommandCoordinator.commitCutDurationDrag(
      beforeDurations: {made.id: made.duration},
      afterDurations: {made.id: made.duration + 4},
    );
    expect(cutIn(s, 2, third).duration, made.duration);
    expect(cutIn(s, 0, first).duration, made.duration);
  });

  test('linked into the timeline the sync stands in already, it is a 겸용 '
      'of the cut there — a sync stands in a timeline once', () {
    final s = session();
    final made = linkedIntoANewTimeline(s);
    open(s, 0);
    s.selectGlobalFrame(1);
    s.selectTrackRow(conteTrackId);
    StoryboardToolbarPanelContext(s).copyFrame();
    open(s, 1);

    StoryboardToolbarPanelContext(s).pasteLinkedFrame();

    final project = projectOf(s);
    expect(project.linkRegistry.syncs.single.cuts, [first, made.id]);
    final again = project.tracks.single.cuts
        .where((cut) => cut.id != made.id && cut.name != '1')
        .single;
    expect(
      project.linkRegistry.counterpartIn(
        cutId: made.id,
        layerId: made.layers.first.id,
        targetCutId: again.id,
      ),
      isNotNull,
      reason: 'a 겸용 of the cut standing here',
    );
    expect(again.duration, isNot(made.duration), reason: 'a 겸용 starts anew');
  });

  test('a row pasted linked inside one is one more row of the other — the '
      'n-th as it is the n-th, never one row twice', () {
    final s = session();
    final made = linkedIntoANewTimeline(s);
    s.selectGlobalFrame(projectOf(s).tracks.single.cuts.first.duration + 1);
    s.selectLayer(made.layers.first.id);
    expect(s.requireActiveCut.id, made.id, reason: '⛔전제');
    drawOnCurrentFrame(s);

    linkDuplicateActiveRow(s);

    final here = projectOf(s).tracks.single.cuts.last;
    final there = cutIn(s, 0, first);
    final registry = projectOf(s).linkRegistry;
    expect(here.layers, hasLength(made.layers.length + 1), reason: '⛔전제');
    expect(
      {for (final row in there.layers) row.id},
      hasLength(there.layers.length),
      reason: 'no row twice',
    );
    expect(
      [
        for (final row in here.layers)
          registry.counterpartIn(
            cutId: made.id,
            layerId: row.id,
            targetCutId: first,
          ),
      ],
      [for (final row in there.layers) row.id],
      reason: 'each row of the one is the row of the other where it stands',
    );
    expect(
      [for (final row in there.layers) row.timeline],
      [for (final row in here.layers) row.timeline],
    );

    s.selectLayer(here.layers.first.id);
    drawOnCurrentFrame(s);
    expect(
      [for (final row in cutIn(s, 0, first).layers) row.timeline],
      [
        for (final row in projectOf(s).tracks.single.cuts.last.layers)
          row.timeline,
      ],
      reason: 'drawn on after, the two are one still',
    );
  });

  test('a row added to one is added to the other — a drawing row by its '
      'link, a direction row by the sync — and the undo takes both', () {
    final s = session();
    final made = linkedIntoANewTimeline(s);
    final layers = s.activeCutControllers.layerController;
    expect(s.requireActiveCut.id, made.id, reason: '⛔전제');
    final rowsBefore = [for (final row in cutIn(s, 0, first).layers) row.id];

    layers.addLayer(
      layer: Layer(id: const LayerId('row-b'), name: 'B', frames: const []),
    );
    layers.addLayer(
      layer: Layer(
        id: const LayerId('row-d'),
        name: 'Direction 2',
        kind: LayerKind.instruction,
        frames: const [],
      ),
    );

    final source = cutIn(s, 0, first);
    expect(
      projectOf(s).linkRegistry.counterpartIn(
        cutId: made.id,
        layerId: const LayerId('row-b'),
        targetCutId: first,
      ),
      isNotNull,
    );
    expect(
      [for (final row in source.layers) row.name],
      [for (final row in projectOf(s).tracks.single.cuts.last.layers) row.name],
    );
    expect(
      projectOf(s).linkRegistry.syncOf(first)?.cuts,
      [first, made.id],
      reason: 'the table rebuilt for the new link keeps the sync',
    );

    s.historyManager.undo();
    s.historyManager.undo();
    expect([for (final row in cutIn(s, 0, first).layers) row.id], rowsBefore);
    expect(
      [for (final row in projectOf(s).tracks.single.cuts.last.layers) row.id],
      [for (final row in made.layers) row.id],
    );
  });
}
