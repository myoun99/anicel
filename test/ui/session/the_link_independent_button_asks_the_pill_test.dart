import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/bitmap_tile.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/pill_subject.dart';
import 'package:anicel/src/models/tile_coord.dart';
import 'package:anicel/src/models/timeline_frame_range.dart';
import 'package:anicel/src/models/timeline_row_address.dart';
import 'package:anicel/src/models/timeline_run_behavior.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/editor_workspace.dart';
import 'package:anicel/src/ui/home_page.dart';
import 'package:anicel/src/ui/session/cell_verbs.dart';
import 'package:anicel/src/ui/session/cut_verbs.dart';
import 'package:anicel/src/ui/session/frame_clipboard.dart';
import 'package:anicel/src/ui/session/layer_verbs.dart';
import 'package:anicel/src/ui/timeline/toolbar_panel_context.dart';

import '../../helpers/home_page_probes.dart';

/// 🚨I-45 — THE LINK-INDEPENDENT BUTTON ASKS THE SHARED PILL'S ONE LADDER.
///
/// 유저 2026-09-20: 「링크 독립버튼. 위치는 타임라인의 공용 알약부분? 프레임
/// 독립시키거나 레이어나 컷이나」 — answered 2026-09-23: 「정확히는 다른
/// 편집버튼등의 로직 그대로 따라감. 그거 공용화해서 재사용할수있으면 재사용해서
/// 법 하나로 통일. 선택안하면 현재프레임, 선택하면 해당 선택한 소재가 기준임」.
///
/// The collaborators are held BY THEIR OWN TYPES so the mutation runner names
/// this file as their witness (it picks witnesses by import).
void main() {
  /// A picture at the CUT's canvas size — the store answers only that shape.
  BitmapSurface ink(CanvasSize canvasSize) {
    const tile = 256;
    final pixels = Uint8List(tile * tile * 4)..fillRange(0, 16, 255);
    return BitmapSurface(canvasSize: canvasSize, tileSize: tile).putTiles([
      (
        coord: TileCoord(x: 0, y: 0),
        tile: BitmapTile(size: tile, pixels: pixels),
      ),
    ]);
  }

  EditorSessionManager session() {
    final s = EditorSessionManager(initialProject: createDefaultProject());
    addTearDown(s.dispose);
    return s;
  }

  Layer row(EditorSessionManager s) =>
      s.layers.firstWhere((layer) => layer.id == s.activeLayerId);

  FrameId? shownAt(EditorSessionManager s, int index) =>
      row(s).timeline[index]?.frameId;

  /// Cel A drawn at 0, with a picture, and LINK-pasted at each of [links]
  /// (Ctrl+B — the same picture exposed again). Returns A's id.
  FrameId drawnAndLinked(EditorSessionManager s, List<int> links) {
    s.selectFrameIndex(0);
    s.createDrawingAtCurrentFrame();
    final a = row(s).frames.single.id;
    s.renderCaches.brushFrameStore.storeBakedSurface(
      s.brushFrameKeyForCut(s.activeCutOrNull!, row(s).id, a),
      ink(s.activeCutOrNull!.canvasSize),
    );
    s.copyFrameAtCurrentFrame();
    for (final index in links) {
      s.selectFrameIndex(index);
      s.pasteLinkedFrameAtCurrentFrame();
    }
    for (final index in links) {
      expect(shownAt(s, index), a, reason: '⛔전제: $index 은 A 의 링크다');
    }
    return a;
  }

  group('the frame axis', () {
    test('standing on a link: that block gets a copy of its own — the '
        'picture comes with it, the other showing keeps A, ONE undo', () {
      final s = session();
      final CellVerbs cells = s.cells;
      final a = drawnAndLinked(s, [5]);
      s.selectFrameIndex(5);
      expect(s.unlinkSubject, PillSubject.cells);
      expect(TimelineToolbarPanelContext(s).canUnlink, isTrue);
      expect(cells.canUnlinkCells, isTrue);
      final entries = s.historyManager.undoCount;

      TimelineToolbarPanelContext(s).unlink();

      final copy = shownAt(s, 5)!;
      expect(copy, isNot(a), reason: '「이 자리만 새 그림으로」');
      expect(shownAt(s, 0), a, reason: 'the other showing keeps A');
      final copied = row(s).frames.firstWhere((frame) => frame.id == copy);
      expect(
        s.brushSurfaceForLayerFrame(row(s), copied)?.tiles,
        isNotEmpty,
        reason: 'the copy shows the same drawing (F-62)',
      );
      expect(s.historyManager.undoCount, entries + 1, reason: 'ONE step');

      s.undo();
      expect(shownAt(s, 5), a, reason: 'one undo links it back');
    });

    test('⛔a picture nobody else shows is independent already — the button '
        'dims and the press does nothing', () {
      final s = session();
      drawnAndLinked(s, const []);
      s.selectFrameIndex(0);
      expect(s.unlinkSubject, PillSubject.nothing);
      expect(TimelineToolbarPanelContext(s).canUnlink, isFalse);
      final entries = s.historyManager.undoCount;
      TimelineToolbarPanelContext(s).unlink();
      expect(s.historyManager.undoCount, entries);
    });

    test('a band means its own blocks: two showings INSIDE it stay one '
        'picture, and only a showing OUTSIDE makes them shared', () {
      final s = session();
      final a = drawnAndLinked(s, [5]);
      // B, a picture of its own, between them — inside the band too.
      s.selectFrameIndex(2);
      s.createDrawingAtCurrentFrame();
      final b = shownAt(s, 2)!;
      expect(shownAt(s, 5), a, reason: '⛔전제: B moved nothing');
      s.frameRangeSelection.value = TimelineFrameRangeSelection(
        layerId: row(s).id,
        startIndex: 0,
        endIndexExclusive: 6,
      );
      expect(
        s.unlinkSubject,
        PillSubject.nothing,
        reason: 'A is shown only inside the band — nothing to separate',
      );

      s.frameRangeSelection.value = null;
      s.selectFrameIndex(10);
      s.pasteLinkedFrameAtCurrentFrame();
      expect(shownAt(s, 10), a, reason: '⛔전제: a third showing, outside');
      s.frameRangeSelection.value = TimelineFrameRangeSelection(
        layerId: row(s).id,
        startIndex: 0,
        endIndexExclusive: 6,
      );
      expect(s.unlinkSubject, PillSubject.cells);

      TimelineToolbarPanelContext(s).unlink();

      final inside = shownAt(s, 0)!;
      expect(inside, isNot(a));
      expect(
        shownAt(s, 5),
        inside,
        reason: 'minted per SOURCE cel — the band\'s two showings stay one '
            'picture, linked to each other',
      );
      expect(shownAt(s, 10), a, reason: 'the showing outside keeps A');
      expect(
        shownAt(s, 2),
        b,
        reason: '⛔B is shown nowhere else — independent already, it keeps '
            'its cel (and its name)',
      );
    });

    test('⛔a hold\'s GHOST is its own block going on, not a second showing',
        () {
      final s = session();
      drawnAndLinked(s, const []);
      s.rangeMove.setRunEdgeBehavior(
        layerId: row(s).id,
        blockStartIndex: 0,
        side: TimelineRunEdgeSide.end,
        mode: TimelineRunEdgeMode.hold,
      );
      expect(
        row(s).timeline.values.where((entry) => entry.ghost),
        isNotEmpty,
        reason: '⛔전제: the hold drew ghosts of A past its block',
      );
      s.selectFrameIndex(0);
      expect(s.unlinkSubject, PillSubject.nothing);
    });

    test('⛔a band over empty cells claims the press — never a redirect onto '
        'the block under the playhead', () {
      final s = session();
      drawnAndLinked(s, [5]);
      s.selectFrameIndex(5);
      expect(s.unlinkSubject, PillSubject.cells, reason: '⛔전제');
      s.frameRangeSelection.value = TimelineFrameRangeSelection(
        layerId: row(s).id,
        startIndex: 20,
        endIndexExclusive: 22,
      );
      expect(s.unlinkSubject, PillSubject.nothing);
    });

    test('⛔a lane row claims the press — its keys have no pictures', () {
      final s = session();
      drawnAndLinked(s, [5]);
      s.selectFrameIndex(5);
      expect(s.unlinkSubject, PillSubject.cells, reason: '⛔전제');
      s.standOnRow(
        LaneRowAddress(row(s).id, 'position'),
      );
      expect(s.unlinkSubject, PillSubject.nothing);
    });
  });

  group('the rows', () {
    test('selected linked rows outrank the frame axis and fork out of their '
        'links as ONE step', () {
      final s = session();
      final LayerVerbs layers = s.layerVerbs;
      drawnAndLinked(s, [5]);
      final original = row(s).id;
      layers.linkDuplicateActiveLayer();
      final copy = s.layers
          .firstWhere(
            (layer) => layer.id != original && layers.isLayerLinked(layer.id),
          )
          .id;
      s.selectFrameIndex(5);
      expect(s.unlinkSubject, PillSubject.cells, reason: '⛔전제: 칸도 있다');

      s.rowSelectionVerbs.beginRowSelection(LayerRowAddress(copy));
      expect(s.unlinkSubject, PillSubject.layers, reason: '⑨: rows outrank');
      final entries = s.historyManager.undoCount;

      TimelineToolbarPanelContext(s).unlink();

      expect(layers.isLayerLinked(copy), isFalse);
      expect(layers.isLayerLinked(original), isFalse);
      expect(s.historyManager.undoCount, entries + 1, reason: 'ONE step');
      s.undo();
      expect(layers.isLayerLinked(copy), isTrue, reason: 'one undo relinks');
    });

    test('two linked groups selected together fork as ONE step', () {
      final s = session();
      final LayerVerbs layers = s.layerVerbs;
      final first = row(s).id;
      layers.linkDuplicateActiveLayer();
      s.layerStack.addLayerOfKind(LayerKind.animation);
      final second = row(s).id;
      layers.linkDuplicateActiveLayer();
      s.rowSelectionVerbs.beginRowSelection(LayerRowAddress(first));
      s.rowSelectionVerbs.rowSelection.value = [
        LayerRowAddress(first),
        LayerRowAddress(second),
      ];
      expect(s.unlinkSubject, PillSubject.layers);
      final entries = s.historyManager.undoCount;

      TimelineToolbarPanelContext(s).unlink();

      expect(layers.isLayerLinked(first), isFalse);
      expect(layers.isLayerLinked(second), isFalse);
      expect(s.historyManager.undoCount, entries + 1, reason: 'ONE step');
    });

    test('the three row verbs share one step-and-stand: a duplicate stands '
        'on its last copy, a rename on the first row', () {
      final s = session();
      final LayerVerbs layers = s.layerVerbs;
      final first = row(s).id;
      s.layerStack.addLayerOfKind(LayerKind.animation);
      final second = row(s).id;
      void selectBoth() {
        s.rowSelectionVerbs.beginRowSelection(LayerRowAddress(first));
        s.rowSelectionVerbs.rowSelection.value = [
          LayerRowAddress(first),
          LayerRowAddress(second),
        ];
      }

      selectBoth();
      final before = {for (final layer in s.layers) layer.id};
      final undos = s.historyManager.undoCount;
      layers.duplicateSelectedLayers();
      expect(s.historyManager.undoCount, undos + 1, reason: 'ONE step');
      expect(
        before.contains(s.activeLayerId),
        isFalse,
        reason: 'standing on a copy — the last one made',
      );

      s.selectLayer(second);
      selectBoth();
      layers.renameSelectedLayers('X');
      expect(s.activeLayerId, first, reason: 'a rename stands on the first');
    });

    test('⛔a selected row with no link holds nothing on this rung — the '
        'ladder goes on, as it does for every pill verb', () {
      final s = session();
      final lone = row(s).id;
      s.rowSelectionVerbs.beginRowSelection(LayerRowAddress(lone));
      expect(s.unlinkSubject, isNot(PillSubject.layers));
    });
  });

  group('the cuts — the storyboard\'s noun', () {
    test('standing on the track row: the linked cut under the cursor forks '
        'out of its links, as ONE step', () {
      final s = session();
      final CutVerbs cuts = s.cutVerbs;
      cuts.createLinkedCutFromActiveCut();
      final linked = s.activeCutId!;
      expect(cuts.cutIsLinked(linked), isTrue, reason: '⛔전제');
      final storyboard = StoryboardToolbarPanelContext(s);
      s.frameRangeSelection.value = TimelineFrameRangeSelection(
        layerId: s.activeLayerId!,
        startIndex: 0,
        endIndexExclusive: 1,
      );
      expect(
        storyboard.canUnlink,
        isFalse,
        reason: 'a live cell band claims the storyboard\'s press (its edit '
            'target) — it names no cut',
      );
      s.frameRangeSelection.value = null;
      s.selectTrackRow(s.selectedTrackId);
      expect(storyboard.canUnlink, isTrue);
      final entries = s.historyManager.undoCount;

      storyboard.unlink();

      expect(cuts.cutIsLinked(linked), isFalse);
      expect(s.historyManager.undoCount, entries + 1, reason: 'ONE step');
      s.undo();
      expect(cuts.cutIsLinked(linked), isTrue);
    });

    test('⛔a cut with no links dims the button', () {
      final s = session();
      s.selectTrackRow(s.selectedTrackId);
      expect(s.cutVerbs.cutIsLinked(s.activeCutId!), isFalse, reason: '⛔전제');
      expect(StoryboardToolbarPanelContext(s).canUnlink, isFalse);
    });

    test('⛔the TIMELINE does not reach for cuts', () {
      final s = session();
      s.cutVerbs.createLinkedCutFromActiveCut();
      s.updateStoryboardCutSelectionByFrame(
        anchorGlobalFrame: 0,
        headGlobalFrame: 1,
      );
      expect(s.trackFrameRangeSelection.value, isNotNull, reason: '⛔전제');
      expect(s.unlinkSubject, isNot(PillSubject.cuts));
    });
  });

  test('the linked paste and the unlink ask ONE row law (F-115)', () {
    final s = session();
    s.selectFrameIndex(0);
    s.createDrawingAtCurrentFrame();
    expect(rowHoldsLinks(row(s)), isTrue);
  });

  testWidgets('the button is on the shared pill and presses the ladder', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1600, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const MaterialApp(home: HomePage()));
    await tester.pumpAndSettle();
    final s = tester
        .widget<EditorWorkspace>(find.byType(EditorWorkspace))
        .session;
    final a = drawnAndLinked(s, [5]);
    s.selectFrameIndex(5);
    await tester.pumpAndSettle();
    const button = ValueKey<String>('shared-unlink-button');
    expect(await isActionButtonEnabled(tester, button), isTrue);

    await tapToolbarButton(tester, button);

    expect(shownAt(s, 5), isNot(a));
    expect(
      await isActionButtonEnabled(tester, button),
      isFalse,
      reason: 'nothing left to separate — the button dims',
    );
  });
}
