import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/bitmap_tile.dart';
import 'package:anicel/src/models/brush_frame_key.dart';
import 'package:anicel/src/models/project_timeline.dart';
import 'package:anicel/src/models/tile_coord.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/session/project_file_door.dart' show SaveAsked;

import '../../helpers/opened_session.dart';
import '../../helpers/project_scratch_folder.dart';

/// 🗣️I-150 (유저 2026-11-03): 「새로운 타임라인을 만들수있음」 · 「새 트랙은
/// 타임라인이 완전초기화되있음. 새 프로젝트를 만드는것과 동일하게」 ·
/// 「트랙편집(우선은 이름?)/삭제/복제 가능」 · 「트랙바꾸면 타임라인 완전
/// 바꿔치기됨. se던 뭐던 싹 다」.
///
/// The timeline list's verbs, each a step of the history; one that opens
/// another timeline stands on its first cut.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  EditorSessionManager session() {
    final s = EditorSessionManager(initialProject: newUntitledProject());
    addTearDown(s.dispose);
    return s;
  }

  ProjectTimeline openOf(EditorSessionManager s) =>
      s.repository.requireProject().currentTimeline;

  test('a new timeline opens as a new project does — and the one left is '
      'kept as it was', () {
    final s = session();
    s.cutVerbs.createCut();
    final left = openOf(s);

    s.timelineVerbs.addTimeline();

    final made = openOf(s);
    final cut = made.tracks.single.cuts.single;
    expect(s.timelineVerbs.timelines, hasLength(2));
    expect(s.timelineVerbs.timelines.first.tracks, left.tracks);
    expect(made.number, 2);
    expect(s.activeCutId, cut.id);
    expect(cut.name, '1');
    expect(s.activeLayer?.name, 'A');
    expect(
      s.activeLayer?.timeline[0]?.frameId,
      isNotNull,
      reason: 'drawn on from its first frame, as a new project is (F-211)',
    );
    expect(s.activeTrack.id, made.tracks.single.id);
    expect(made.tracks.single.id, isNot(left.tracks.single.id));
  });

  test('🚨opening another timeline swaps all the panels read, SE rows and '
      'all — and changes nothing of either', () {
    final s = session();
    s.cutVerbs.createCut();
    final first = openOf(s);
    s.timelineVerbs.addTimeline();
    final made = openOf(s);
    final registry = s.repository.requireProject().linkRegistry;

    s.timelineVerbs.openTimeline(first.id);

    expect(openOf(s), first);
    expect(s.repository.requireProject().tracks, first.tracks);
    expect(s.activeCutId, first.tracks.single.cuts.first.id);
    expect(s.activeTrack.id, first.tracks.single.id);

    s.timelineVerbs.openTimeline(made.id);

    expect(openOf(s), made);
    expect(s.repository.requireProject().linkRegistry, registry);
  });

  test('🚨an undo after opening another opens the one before first, and the '
      'next takes back the edit made there (I-150-Q1)', () {
    final s = session();
    final first = openOf(s).id;
    s.cutVerbs.createCut();
    final standing = s.activeCutId;

    s.timelineVerbs.addTimeline();
    s.undo();

    expect(openOf(s).id, first);
    expect(s.timelineVerbs.timelines, hasLength(1));
    expect(s.activeCutId, standing);
    expect(openOf(s).tracks.single.cuts, hasLength(2));

    s.undo();

    expect(openOf(s).tracks.single.cuts, hasLength(1));

    s.redo();
    s.redo();

    expect(s.timelineVerbs.timelines, hasLength(2));
    expect(openOf(s).id, isNot(first));
    expect(s.activeCutId, openOf(s).tracks.single.cuts.single.id);
  });

  test('a timeline is named, a blank name gives it back its number\'s, and '
      'the same name is no step', () {
    final s = session();
    final id = openOf(s).id;

    s.timelineVerbs.renameTimeline(id, '  본편 ');
    expect(openOf(s).name, '본편');
    final steps = s.historyManager.undoCount;

    s.timelineVerbs.renameTimeline(id, '본편');
    expect(s.historyManager.undoCount, steps);

    s.timelineVerbs.renameTimeline(id, ' ');
    expect(openOf(s).name, isNull);

    s.undo();
    expect(openOf(s).name, '본편');
  });

  test('the open timeline deleted opens the one taking its place; the last '
      'one stays; an undo brings it back open', () {
    final s = session();
    final first = openOf(s);
    s.timelineVerbs.addTimeline();
    s.cutVerbs.createCut();
    final made = openOf(s);

    s.timelineVerbs.deleteTimeline(made.id);

    expect(s.timelineVerbs.timelines, [first]);
    expect(s.activeCutId, first.tracks.single.cuts.single.id);

    s.timelineVerbs.deleteTimeline(first.id);
    expect(s.timelineVerbs.timelines, [first], reason: 'never the last one');

    s.undo();

    expect(openOf(s), made);
    expect(made.tracks.single.cuts, hasLength(2));
  });

  test('🚨every timeline\'s pictures and which one is open come back from a '
      'save', () async {
    final dir = Directory.systemTemp.createTempSync('anicel-timelines');
    deleteAfterSessionEnds(dir);
    final path = '${dir.path}/two.anicel';
    final s = session();
    BrushFrameKey keyOfOpenCel() {
      final cut = s.requireActiveCut;
      final row = s.activeLayer!;
      return s.brushFrameKeyForCut(cut, row.id, row.frames.first.id);
    }

    void paint(BrushFrameKey key, int red) {
      final pixels = Uint8List(256 * 256 * 4);
      for (var at = 0; at < pixels.length; at += 4) {
        pixels.setRange(at, at + 4, [red, 0, 0, 255]);
      }
      s.renderCaches.brushFrameStore.storeBakedSurface(
        key,
        BitmapSurface(
          canvasSize: s.requireActiveCut.canvasSize,
          tileSize: 256,
        ).putTiles([
          (
            coord: TileCoord(x: 0, y: 0),
            tile: BitmapTile(size: 256, pixels: pixels),
          ),
        ]),
      );
    }

    final ofFirst = keyOfOpenCel();
    paint(ofFirst, 40);
    s.timelineVerbs.addTimeline();
    final ofMade = keyOfOpenCel();
    paint(ofMade, 90);
    expect(ofMade.trackId, isNot(ofFirst.trackId), reason: '전제');
    await s.projectDoor.saveProjectToFile(path, asked: SaveAsked.byAPerson);

    final loaded = await openedSession(path);
    addTearDown(loaded.dispose);
    int redOf(BrushFrameKey key) => loaded.renderCaches.brushFrameStore
        .bakedSurfaceOrNull(key)!
        .tileAt(TileCoord(x: 0, y: 0))!
        .readPixels((_, view) => view[0]);

    expect(
      loaded.repository.requireProject().timelines,
      s.repository.requireProject().timelines,
    );
    expect(loaded.timelineVerbs.currentTimelineId, openOf(s).id);
    expect(loaded.activeCutId, s.activeCutId);
    expect(redOf(ofFirst), 40);
    expect(redOf(ofMade), 90);
  });
}
