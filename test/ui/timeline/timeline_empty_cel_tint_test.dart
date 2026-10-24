import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/camera_instruction.dart';
import 'package:anicel/src/models/bitmap_tile.dart';
import 'package:anicel/src/models/brush_frame_key.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/layer_mark.dart';
import 'package:anicel/src/models/layer_process.dart';
import 'package:anicel/src/models/tile_coord.dart';
import 'package:anicel/src/models/timeline_coverage.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/timeline/layer_label_controls.dart'
    show layerMarkColor;
import 'package:anicel/src/ui/timeline/property_lane_model.dart';
import 'package:anicel/src/ui/timeline/timeline_cell_exposure_state.dart';
import 'package:anicel/src/ui/timeline/timeline_cell_style.dart';
import 'package:anicel/src/ui/timeline/timeline_frame_rows_scroll_body.dart';
import 'package:anicel/src/ui/timeline/timeline_grid_hooks.dart';
import 'package:anicel/src/ui/timeline/timeline_grid_metrics.dart';
import 'package:anicel/src/ui/timeline/timeline_row_edges.dart';
import 'package:anicel/src/ui/timeline/timeline_cel_content_source.dart';
import 'package:anicel/src/ui/timeline/timeline_drag_preview.dart'
    show ExposureEdgeDragPreview;
import 'package:anicel/src/ui/timeline/timeline_row_cells_painter.dart';
import 'package:anicel/src/ui/timeline/timeline_ruler_cursor_overlay.dart';

import '../../helpers/row_berths_in_order.dart';
import 'timeline_frame_geometry_probe.dart';

/// R26 #44: ACTION-section blocks whose cel holds no picture yet paint a
/// slightly grayed paper — the painter's style resolution, the session's
/// fact/token pair, and the row memo's token invalidation.
void main() {
  // The DEFAULT paper's empty-cel look — the unlabelled row's paper through
  // the one tint rule; the tests below pin that it never drifts from it.
  final timelineEmptyCelBlockColor = timelineEmptyCelPaperColor(
    timelineDrawingHeldColor,
  );
  TimelineCellExposureState stateFor(Layer layer, int frameIndex) {
    if (layer.timeline[frameIndex]?.isDrawing ?? false) {
      return TimelineCellExposureState.drawingStart;
    }
    if (coveringDrawingBlockAt(layer.timeline, frameIndex) != null) {
      return TimelineCellExposureState.held;
    }
    return TimelineCellExposureState.uncovered;
  }

  Layer twoBlockLayer() => Layer(
    id: const LayerId('layer-a'),
    name: 'A',
    frames: [
      Frame(id: const FrameId('f1'), duration: 1, strokes: const []),
      Frame(id: const FrameId('f2'), duration: 1, strokes: const []),
    ],
    timeline: {
      0: const TimelineExposure.drawing(FrameId('f1'), length: 2),
      2: const TimelineExposure.drawing(FrameId('f2'), length: 1),
    },
  );

  TimelineRowCellsPainter painterFor(
    Layer layer, {
    bool Function(Layer layer, int frameIndex)? celHasContentForLayer,
    bool Function(Layer layer, int frameIndex) celCannotBeReadForLayer =
        _readsEveryCel,
  }) {
    return TimelineRowCellsPainter(
      layer: layer,
      geometry: testFrameGeometry(
        frameCellExtent: 24,
        frameEndIndexExclusive: 24,
      ),
      crossAxisExtent: 28,
      exposureStateForLayer: stateFor,
      celContent: celHasContentForLayer == null
          ? null
          : TimelineCelContentSource(
              hasContent: celHasContentForLayer,
              cannotRead: celCannotBeReadForLayer,
              revision: CelContentRevision.everyRow(ValueNotifier<int>(0)),
            ),
      colorScheme: const ColorScheme.dark(),
      baseTextStyle: const TextStyle(fontSize: 11),
    );
  }

  group('painter style resolution', () {
    test('an empty-cel block grays its WHOLE run (start + held); a block '
        'with content and uncovered cells stay untouched', () {
      final painter = painterFor(
        twoBlockLayer(),
        // f1's block (cells 0-1) is unworked, f2's block (cell 2) has ink.
        celHasContentForLayer: (layer, frameIndex) => frameIndex >= 2,
      );

      expect(
        painter.resolvedCellStyleFor(0).background,
        timelineEmptyCelBlockColor,
        reason: 'the empty block\'s start cell grays',
      );
      expect(
        painter.resolvedCellStyleFor(1).background,
        timelineEmptyCelBlockColor,
        reason: 'the held cell follows its block',
      );
      expect(
        painter.resolvedCellStyleFor(2).background,
        timelineDrawingStartColor,
        reason: 'a worked block keeps the plain paper',
      );
      expect(
        painter.resolvedCellStyleFor(5).background,
        Colors.transparent,
        reason: 'uncovered cells carry no substrate at all',
      );
    });

    test('no resolver = no tint (every block keeps the plain paper)', () {
      final painter = painterFor(twoBlockLayer());
      expect(
        painter.resolvedCellStyleFor(0).background,
        timelineDrawingStartColor,
      );
    });

    // 유저 2026-10-16 (frame-picture-indicator-Q1 b): 「a + 그 셀이 있는
    // 타임라인 칸에도 빨간 표시」.
    test('🚨a block whose cel cannot be read is red — its WHOLE run, the '
        'empty-cel grey included; the block beside it keeps its paper', () {
      final painter = painterFor(
        twoBlockLayer(),
        // f1's block (cells 0-1) cannot be read — and says it holds nothing,
        // so red has to win over grey. Cell 5 is asked too, and is no block.
        celHasContentForLayer: (layer, frameIndex) => frameIndex >= 2,
        celCannotBeReadForLayer: (layer, frameIndex) =>
            frameIndex < 2 || frameIndex == 5,
      );

      expect(
        painter.resolvedCellStyleFor(0).background,
        timelineUnreadableCelPaperColor,
        reason: 'the unreadable block\'s start cell is red',
      );
      expect(
        painter.resolvedCellStyleFor(1).background,
        timelineUnreadableCelPaperColor,
        reason: 'the held cell follows its block',
      );
      expect(
        painter.resolvedCellStyleFor(2).background,
        timelineDrawingStartColor,
        reason: 'a block whose cel reads keeps the plain paper',
      );
      expect(
        painter.resolvedCellStyleFor(5).background,
        Colors.transparent,
        reason: 'uncovered cells carry no substrate at all',
      );
    });

    test('the block\'s red is the ruler bar\'s — one red for a cel that '
        'cannot be read, on both', () {
      expect(
        timelineUnreadableCelPaperColor,
        TimelineRulerCursorOverlayPainter.unreadableBarColor,
      );
    });
  });

  // ⑲/⑳ (user, 2026-08-12): 「블록 모드의 프레임블록은 레이어 색라벨 색을
  // 그대로 따라간다 (…) 그냥 블록의 고정 하얀색을 레이어 색라벨 따라가도록」
  // + 「레이어 색라벨 기본 = 흰색」. The two are one statement: a layer's
  // mark IS the colour of its paper.
  group('a block is its layer\'s colour label', () {
    test('the DEFAULT label is the paper, so an unlabelled row is painted '
        'by exactly the number it always was', () {
      expect(layerMarkColor(LayerMark.none), timelineDrawingHeldColor);
    });

    test('a marked layer\'s blocks take the mark', () {
      final painter = painterFor(
        twoBlockLayer().copyWith(
          mark: const LayerMark(process: LayerProcess.layout),
        ),
      );

      expect(
        painter.resolvedCellStyleFor(0).background,
        layerMarkColor(const LayerMark(process: LayerProcess.layout)),
      );
      expect(
        painter.resolvedCellStyleFor(1).background,
        layerMarkColor(const LayerMark(process: LayerProcess.layout)),
        reason: 'a run is one sheet of paper — held cells too',
      );
      expect(
        painter.resolvedCellStyleFor(5).background,
        Colors.transparent,
        reason: 'and an uncovered cell is still no paper at all',
      );
    });

    test('the unworked-cel tint is the MARK at low opacity, not the old '
        'grey', () {
      final painter = painterFor(
        twoBlockLayer().copyWith(
          mark: const LayerMark(process: LayerProcess.conte),
        ),
        celHasContentForLayer: (layer, frameIndex) => frameIndex >= 2,
      );

      final tinted = painter.resolvedCellStyleFor(0).background;
      expect(
        tinted,
        timelineEmptyCelPaperColor(
          layerMarkColor(const LayerMark(process: LayerProcess.conte)),
        ),
      );
      // Derived from the paper, not a second colour beside it: same hue,
      // the transparency is the only difference.
      expect(
        tinted.r,
        layerMarkColor(const LayerMark(process: LayerProcess.conte)).r,
      );
      expect(tinted.a, lessThan(1));
      expect(
        painter.resolvedCellStyleFor(2).background,
        layerMarkColor(const LayerMark(process: LayerProcess.conte)),
        reason: 'a worked block keeps the full mark',
      );
    });

    test('and the unmarked row\'s tint is still the old constant', () {
      // The regression the pair has to keep: nothing about an unlabelled
      // layer moved.
      expect(
        timelineEmptyCelPaperColor(layerMarkColor(LayerMark.none)),
        timelineEmptyCelBlockColor,
      );
    });
  });

  group('session fact + memo token', () {
    BitmapSurface surfaceWithInk() {
      final pixels = Uint8List(4 * 4 * 4)..fillRange(0, 16, 255);
      return BitmapSurface(
        canvasSize: const CanvasSize(width: 4, height: 4),
        tileSize: 4,
      ).putTiles([
        (coord: TileCoord(x: 0, y: 0), tile: BitmapTile(size: 4, pixels: pixels)),
      ]);
    }

    test('an undrawn cel answers false; storing ink flips it; non-drawing '
        'sections always answer true', () {
      final s = EditorSessionManager(initialProject: createDefaultProject());
      addTearDown(s.dispose);
      s.createDrawingAtCurrentFrame();
      final layer = s.activeLayer!;
      final frameId = layer.frames.single.id;

      expect(s.layerStack.celHasContentForLayer(layer, 0), isFalse);
      final before = s.layerStack.celTintRevision.value;

      s.renderCaches.brushFrameStore.storeBakedSurface(
        s.brushFrameKeyForCut(s.activeCutOrNull!, layer.id, frameId),
        surfaceWithInk(),
      );
      expect(s.layerStack.celHasContentForLayer(layer, 0), isTrue);
      expect(
        s.layerStack.celTintRevision.value,
        greaterThan(before),
        reason: 'the timeline has to be TOLD; that is the whole fix',
      );

      // A row with no cels of its own never tints — the camera row mirrors
      // keyframes and has no block to grey.
      final camera = s.layers.firstWhere((l) => l.kind == LayerKind.camera);
      expect(s.layerStack.celHasContentForLayer(camera, 0), isTrue);
    });

    test('F-357: a cut the editor is NOT on answers by its own pixels — '
        'and the pen down on the active cut counts only there', () {
      final s = EditorSessionManager(initialProject: createDefaultProject());
      addTearDown(s.dispose);
      s.createDrawingAtCurrentFrame();
      final away = s.activeCutOrNull!;
      final row = s.activeLayer!.id;
      final cel = s.activeLayer!.frames.single.id;
      s.cutVerbs.createCut();
      expect(s.activeCutOrNull!.id, isNot(away.id), reason: '⛔전제');

      expect(s.layerStack.celHoldsAPicture(away, row, cel), isFalse);
      s.renderCaches.brushFrameStore.storeBakedSurface(
        s.brushFrameKeyForCut(away, row, cel),
        surfaceWithInk(),
      );
      expect(s.layerStack.celHoldsAPicture(away, row, cel), isTrue);

      s.createDrawingAtCurrentFrame();
      final here = s.activeCutOrNull!;
      final liveRow = s.activeLayer!.id;
      final liveCel = s.activeLayer!.frames.single.id;
      s.setBrushInputActive(true);
      expect(s.layerStack.celHoldsAPicture(here, liveRow, liveCel), isTrue);
      expect(
        s.layerStack.celHoldsAPicture(away, liveRow, liveCel),
        isFalse,
        reason:
            'the live stroke is on the active cut; a cel of another cut '
            'the same names reach keeps its own pixels',
      );
    });

    test('🚨R27 #16: the direction row can actually BE GIVEN a cel', () {
      // 유저 2026-08-27: 「그림은 그려지지도않아. **프레임이 없다고 뜨거든**」.
      //
      // ⚠️THE PREDICATE TEST IS NOT THIS TEST. Asserting
      // `instruction.takesAuthoredCels` proves a switch statement;
      // this drives the session and reads what came out, because the gate
      // sits behind three more conditions the predicate knows nothing about.
      final s = EditorSessionManager(initialProject: createDefaultProject());
      addTearDown(s.dispose);
      final row = s.layers.firstWhere((l) => l.kind == LayerKind.instruction);
      s.selectLayer(row.id);
      s.selectFrameIndex(0);

      expect(
        s.frameVerbs.canCreateDrawingAtCurrentFrame,
        isTrue,
        reason: 'the row takes a brush, so it has to be able to hold a cel',
      );
      s.createDrawingAtCurrentFrame();
      final after = s.layers.firstWhere((l) => l.id == row.id);
      expect(after.frames, hasLength(1));
      expect(
        s.layerStack.celHasContentForLayer(after, 0),
        isFalse,
        reason:
            'a fresh cel holds no picture — so the block is grey until '
            'a line starts, which is the other half of this round',
      );
    });

    test('🚨R27 #16: a DIRECTION span with nothing drawn on it is grey', () {
      // 유저 2026-08-27: 「그림 그릴 수 있는 기능(추가로 **없으면 블록을
      // 회색으로**. 로직은 통일)만 추가하라했지」.
      //
      // ⚠️THE SECOND LAYER OF THE SAME BUG. The section test above this
      // used to send every CAM row home with `true`, so a direction row
      // could never tint.
      //
      // ↩️It had a third: a span-covered cell resolved NO FRAME, which every
      // other row is right to call 「not a block, nothing to tint」, so this
      // row was the exception. Since R27 a span is a block on a blank cel
      // of its own — laid here the way a row from before R27 opens — and
      // it is grey by the rule every empty cel follows.
      final s = EditorSessionManager(initialProject: createDefaultProject());
      addTearDown(s.dispose);
      final row = s.layers.firstWhere((l) => l.kind == LayerKind.instruction);
      final withSpan = Layer(
        id: row.id,
        name: row.name,
        kind: row.kind,
        frames: const [],
        instructions: {
          2: const InstructionEvent(instructionId: 'fi', length: 3),
        },
      );

      expect(
        s.layerStack.celHasContentForLayer(withSpan, 2),
        isFalse,
        reason: 'the span start is a block, and it holds no picture',
      );
      expect(
        s.layerStack.celHasContentForLayer(withSpan, 4),
        isFalse,
        reason: 'and so is the rest of its run',
      );
      expect(
        s.layerStack.celHasContentForLayer(withSpan, 9),
        isTrue,
        reason:
            '⛔off the span there is no block, so nothing to grey — a '
            'row washed grey end to end is not what was asked for',
      );
    });

    test('the block goes white when the LINE STARTS, not when the pen '
        'lifts', () {
      final s = EditorSessionManager(initialProject: createDefaultProject());
      addTearDown(s.dispose);
      s.createDrawingAtCurrentFrame();
      final layer = s.activeLayer!;

      // Nothing committed yet: the store only learns about pixels at
      // stroke commit, which is why waiting for it left the block grey
      // for the whole stroke.
      expect(s.layerStack.celHasContentForLayer(layer, 0), isFalse);
      final before = s.layerStack.celTintRevision.value;

      s.setBrushInputActive(true);

      expect(
        s.layerStack.celHasContentForLayer(layer, 0),
        isTrue,
        reason: 'pen down on the active cel already counts as worked',
      );
      expect(
        s.layerStack.celTintRevision.value,
        greaterThan(before),
        reason: 'and it announces, so the row repaints now',
      );

      // A cel the pen is NOT on is unaffected.
      final other = s.layers.firstWhere((l) => l.id != layer.id);
      expect(s.layerStack.celHasContentForLayer(other, 0), isTrue);

      final beforeUp = s.layerStack.celTintRevision.value;
      s.setBrushInputActive(false);
      expect(
        s.layerStack.celHasContentForLayer(layer, 0),
        isFalse,
        reason: 'an abandoned stroke that drew nothing leaves it unworked',
      );
      expect(
        s.layerStack.celTintRevision.value,
        greaterThan(beforeUp),
        reason: 'and the row has to hear it go grey again',
      );
    });

    test('F-166: the pen going down and up on a DRAWN cel moves no tint — '
        'a bump repainted every row and threw the timeline dock\'s still '
        'image away for the stroke\'s first frames', () {
      final s = EditorSessionManager(initialProject: createDefaultProject());
      addTearDown(s.dispose);
      s.createDrawingAtCurrentFrame();
      final layer = s.activeLayer!;
      s.renderCaches.brushFrameStore.storeBakedSurface(
        s.brushFrameKeyForCut(
          s.activeCutOrNull!,
          layer.id,
          layer.frames.single.id,
        ),
        surfaceWithInk(),
      );
      final before = s.layerStack.celTintRevision.value;

      s.setBrushInputActive(true);
      expect(s.layerStack.celHasContentForLayer(layer, 0), isTrue);
      s.setBrushInputActive(false);
      expect(s.layerStack.celHasContentForLayer(layer, 0), isTrue);

      expect(
        s.layerStack.celTintRevision.value,
        before,
        reason: 'no block changed its answer, so no row may repaint',
      );
    });

    test('F-166: a committed stroke that crosses nothing moves no tint', () {
      final s = EditorSessionManager(initialProject: createDefaultProject());
      addTearDown(s.dispose);
      s.createDrawingAtCurrentFrame();
      final layer = s.activeLayer!;
      final store = s.renderCaches.brushFrameStore;
      final key = s.brushFrameKeyForCut(
        s.activeCutOrNull!,
        layer.id,
        layer.frames.single.id,
      );
      store.storeBakedSurface(key, surfaceWithInk());
      final before = s.layerStack.celTintRevision.value;

      // What a commit does to a drawn cel: the edit mark, then the donation.
      store.markCelEdited(key);
      store.storeBakedSurface(key, surfaceWithInk());

      expect(s.layerStack.celTintRevision.value, before);
    });

    test('R27 #13: the store ANNOUNCES the empty↔drawn crossing, and only '
        'the crossing — the tint had no signal to clear on before', () {
      final s = EditorSessionManager(initialProject: createDefaultProject());
      addTearDown(s.dispose);
      s.createDrawingAtCurrentFrame();
      final layer = s.activeLayer!;
      final key = s.brushFrameKeyForCut(
        s.activeCutOrNull!,
        layer.id,
        layer.frames.single.id,
      );

      var bumps = 0;
      s.renderCaches.brushFrameStore.celContentRevision.addListener(
        () => bumps += 1,
      );

      s.renderCaches.brushFrameStore.storeBakedSurface(key, surfaceWithInk());
      expect(bumps, 1, reason: 'empty → drawn');

      // A second stroke on an already-drawn cel changes no emptiness.
      s.renderCaches.brushFrameStore.storeBakedSurface(key, surfaceWithInk());
      expect(bumps, 1);

      // Back to blank (an undo to an empty surface).
      s.renderCaches.brushFrameStore.storeBakedSurface(
        key,
        BitmapSurface(
          canvasSize: const CanvasSize(width: 4, height: 4),
          tileSize: 4,
        ),
      );
      expect(bumps, 2, reason: 'drawn → empty');
      expect(s.layerStack.celHasContentForLayer(layer, 0), isFalse);
    });

    // pen-up-dock-tail (2026-10-24): the stroke's landing crossed its cel
    // in the store, and the tint moved for a block already white since
    // pen-down — every row repainted, the timeline dock drew five frames
    // whole, and not one of the panel's pixels changed.
    group('the first stroke LANDING on an empty cel', () {
      /// [linkedCut] first makes the 겸용 cut of the default one and comes
      /// back to draw on the default cut's row: the group's canonical
      /// member, so the store names the very key the live stroke stands on.
      ({EditorSessionManager s, Layer layer, BrushFrameKey key}) penDown({
        bool linkedCut = false,
      }) {
        final s = EditorSessionManager(initialProject: createDefaultProject());
        addTearDown(s.dispose);
        if (linkedCut) {
          final cut = s.activeCutOrNull!.id;
          final row = s.activeLayer!.id;
          s.cutVerbs.createLinkedCutFromActiveCut();
          s.selectCut(cut);
          s.selectLayer(row);
          s.selectFrameIndex(0);
        }
        s.createDrawingAtCurrentFrame();
        final layer = s.activeLayer!;
        expect(
          s.selectedFrame?.id,
          layer.frames.single.id,
          reason: 'premise: the live stroke stands on the new cel',
        );
        final key = s.brushFrameKeyForCut(
          s.activeCutOrNull!,
          layer.id,
          layer.frames.single.id,
        );
        s.setBrushInputActive(true);
        return (s: s, layer: layer, key: key);
      }

      /// What a pen-up does, in its order: the commit lands with the pen
      /// still down, then the stroke ends.
      void lift(EditorSessionManager s, BrushFrameKey key) {
        s.renderCaches.brushFrameStore.storeBakedSurface(key, surfaceWithInk());
        s.setBrushInputActive(false);
      }

      test('moves no tint — the line counted the cel from pen-down', () {
        final (:s, :layer, :key) = penDown();
        final down = s.layerStack.celTintRevision.value;
        final store = s.renderCaches.brushFrameStore;
        final crossings = store.celContentRevision.value;

        lift(s, key);

        expect(
          store.celContentRevision.value,
          greaterThan(crossings),
          reason: 'premise: the store DID cross the cel',
        );
        expect(store.celsLastCrossed, {key}, reason: 'and named it');
        expect(s.layerStack.celHasContentForLayer(layer, 0), isTrue);
        expect(
          s.layerStack.celTintRevision.value,
          down,
          reason: 'white since pen-down, white now: no row may repaint',
        );
      });

      test('🚨a linked row still hears it — it windows the same bank, and '
          'the live stroke answered only for its own row', () {
        final (:s, :layer, :key) = penDown(linkedCut: true);
        expect(
          s.repository.requireProject().linkRegistry.isLinked(
            cutId: key.cutId,
            layerId: layer.id,
          ),
          isTrue,
          reason: 'premise: the row is linked',
        );
        final down = s.layerStack.celTintRevision.value;

        lift(s, key);

        expect(
          s.renderCaches.brushFrameStore.celsLastCrossed,
          {key},
          reason: 'premise: the live row is the group\'s own key',
        );
        expect(s.layerStack.celTintRevision.value, greaterThan(down));
      });

      test('🚨another cel crossing WITH it still moves the tint', () {
        final (:s, :layer, :key) = penDown();
        final down = s.layerStack.celTintRevision.value;
        final other = s.brushFrameKeyForCut(
          s.activeCutOrNull!,
          layer.id,
          const FrameId('another-cel'),
        );

        // One announcement for both — a batch, as an undo restores a cut.
        s.renderCaches.brushFrameStore.restoreBakedForCut(key.cutId, {
          key: surfaceWithInk(),
          other: surfaceWithInk(),
        });

        expect(
          s.renderCaches.brushFrameStore.celsLastCrossed,
          {key, other},
          reason: 'premise: one announcement names both',
        );
        expect(s.layerStack.celTintRevision.value, greaterThan(down));
      });

      test('an announcement that names no cel moves the tint — nothing '
          'says the live stroke answers for it', () {
        final (:s, layer: _, key: _) = penDown();
        final down = s.layerStack.celTintRevision.value;

        // A bump with no names, as a test of the canvas sends one.
        s.renderCaches.brushFrameStore.celContentRevision.value += 1;

        expect(s.renderCaches.brushFrameStore.celsLastCrossed, isEmpty);
        expect(s.layerStack.celTintRevision.value, greaterThan(down));
      });

      test('🚨a drag in flight still hears it — it can hang the cel '
          'where it is not', () {
        final (:s, :layer, :key) = penDown();
        s.dragPreview.value = ExposureEdgeDragPreview(previewLayer: layer);
        final down = s.layerStack.celTintRevision.value;

        lift(s, key);

        expect(s.layerStack.celTintRevision.value, greaterThan(down));
      });
    });
  });

  group('the tint follows the cel content signal', () {
    testWidgets('a cel gaining pixels updates the tint WITHOUT rebuilding '
        'the row, and moves the revision the tile store bakes on', (
      tester,
    ) async {
      final layer = twoBlockLayer();
      var hasContent = false;
      final revision = ValueNotifier<int>(0);
      addTearDown(revision.dispose);
      // STABLE closures across pumps — session method tear-offs compare
      // equal in production; here the same objects stand in for them.
      bool celHasContent(Layer l, int frameIndex) => hasContent;
      final celContent = TimelineCelContentSource(
        hasContent: celHasContent,
        cannotRead: (_, _) => false,
        revision: CelContentRevision.everyRow(revision),
      );
      void onSelectLayer(LayerId id) {}
      void onSelectFrame(int index) {}
      final rows = [TimelineDisplayRow.layer(layer, layerIndex: 0)];

      Widget body() => MaterialApp(
        home: Material(
          child: SizedBox(
            width: 700,
            height: 200,
            child: TimelineFrameRowsScrollBody(
              rows: rows,
              berths: berthsInOrder(rows),
              edges: TimelineRowEdges.uniform(
                1,
                TimelineGridMetrics.defaults.layerRowHeight,
              ),
              hooks: TimelineGridHooks(
                activeLayerId: null,
                frameCursor: ValueNotifier<int>(0),
                playbackFrameCount: 24,
                exposureStateForLayer: stateFor,
                celContent: celContent,
                onSelectLayer: onSelectLayer,
                onSelectFrame: onSelectFrame,
                onToggleLayerVisibility: (_) {},
                onLayerOpacityChanged: (_, _) {},
                onToggleLayerTimesheet: (_) {},
                onLayerMarkSelected: (_, _) {},
              ),
              frameStartIndex: 0,
              frameEndIndexExclusive: 24,
              leadingFrameSpacerWidth: 0,
              trailingFrameSpacerWidth: 0,
              totalFrameContentWidth: 24 * 24,
              metrics: TimelineGridMetrics.defaults,
            ),
          ),
        ),
      );

      TimelineRowCellsPainter painterOf() => tester
          .widgetList<CustomPaint>(find.byType(CustomPaint))
          .map((w) => w.painter)
          .whereType<TimelineRowCellsPainter>()
          .single;

      await tester.pumpWidget(body());
      final first = painterOf();
      expect(
        first.resolvedCellStyleFor(0).background,
        timelineEmptyCelBlockColor,
      );

      // Same inputs = memo hit: the row (and its painter) is reused.
      await tester.pumpWidget(body());
      expect(
        identical(painterOf(), first),
        isTrue,
        reason: 'unchanged inputs must reuse the cached row',
      );
      expect(first.celContentRevision, 0);

      // A cel gains pixels: store state moves and the revision announces
      // it. The Layer instance is untouched, and so is the ROW — the point
      // of the signal is that the painter re-reads instead of the row
      // rebuilding.
      hasContent = true;
      revision.value += 1;
      await tester.pump();

      final after = painterOf();
      expect(
        identical(after, first),
        isTrue,
        reason: 'the tint must not cost a row rebuild',
      );
      expect(
        after.resolvedCellStyleFor(0).background,
        timelineDrawingStartColor,
        reason: 'the painter re-reads the fact it was told changed',
      );
      // Read LIVE off the same painter instance — a captured value would
      // leave the tile store baking against a stale key forever.
      expect(after.celContentRevision, 1);
    });
  });
}

/// No cel that cannot be read — a source with no cel store behind it.
bool _readsEveryCel(Layer layer, int frameIndex) => false;
