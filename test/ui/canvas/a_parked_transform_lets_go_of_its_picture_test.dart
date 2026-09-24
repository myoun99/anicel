@Tags(['gc'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/bitmap_tile.dart';
import 'package:anicel/src/models/brush_dab.dart';
import 'package:anicel/src/models/brush_history_policy.dart';
import 'package:anicel/src/models/brush_tip_shape.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/canvas_viewport.dart';
import 'package:anicel/src/services/bitmap_surface_geometry.dart';
import 'package:anicel/src/services/brush_frame_edit_session_store.dart';
import 'package:anicel/src/services/brush_frame_editing_coordinator.dart';
import 'package:anicel/src/services/brush_frame_store.dart';
import 'package:anicel/src/services/canvas_selection_region.dart';
import 'package:anicel/src/services/canvas_selection_shape.dart';
import 'package:anicel/src/services/command.dart';
import 'package:anicel/src/services/history_manager.dart';
import 'package:anicel/src/services/persistence/volatile_scratch_files.dart';
import 'package:anicel/src/ui/brush/brush_canvas_panel.dart';
import 'package:anicel/src/ui/brush/brush_edit_cache_invalidation_sink.dart';
import 'package:anicel/src/ui/brush/brush_tool_state.dart';
import 'package:anicel/src/ui/brush/canvas_selection_commands.dart';
import 'package:anicel/src/ui/brush/transform_tool_options.dart';

import '../../helpers/brush_canvas_fixture.dart';
import '../../helpers/collect_garbage.dart';
import '../../helpers/device_viewport.dart';

/// 🚨★★★A CONFIRMED TRANSFORM WHOSE UNDO ENTRY WAS PARKED HOLDS NONE OF
/// THE PICTURE IT WOULD UNDO TO (C-ipad-crash ①, 2026-09-15).
///
/// 유저 2026-09-14: 「2000x1400정도의 소재를 2배크게, 작게 변형을 반복해봤는데
/// 반복시마다 약 150mb가 늘어남 … 2200mb정도에서 다음 변형시 앱이 튕김」.
///
/// 🔬What it was, read off a VM heap snapshot after ten ×2 → ×0.5 rounds: the
/// region doors a confirm hands its undo entry were closures made inside the
/// confirm itself, and a closure keeps the whole scope it was made in — the
/// pre-lift picture and the landed stamp with it. 526.9MB of stamps and 70MB
/// of tiles were held by nothing but those closures, for as long as the
/// entries stayed in the history, and parking an entry freed none of it.
///
/// ⛔A FIELD CHECK COULD NOT SEE THIS, and one existed: the command nulls its
/// own `_preLiftSurface` and `retainsPreLiftSurface` read false the whole
/// time. So this reads what a user's memory reads — whether the picture's
/// tiles are still ALIVE once the budget parked the entry — with a control
/// on each side: the resident entry DOES hold them, and the entry was PARKED
/// (still in the history), not deleted.
void main() {
  testWidgets('🚨once its entry parks, a confirmed transform lets go of the '
      'picture it would undo to', (tester) async {
    const canvasSize = CanvasSize(width: 1024, height: 1024);
    final frameKeys = BrushCanvasFixture.createFrameKeys();
    final coordinator = BrushFrameEditingCoordinator(
      initialFrameKey: frameKeys.first,
      frameStore: BrushFrameStore(),
      sessionStore: BrushFrameEditSessionStore(canvasSize: canvasSize),
      historyPolicy: const BrushHistoryPolicy(),
    );
    final history = HistoryManager();
    addTearDown(history.dispose);
    addTearDown(() => VolatileScratchFiles.ceilingBytes = 0);
    final commands = CanvasSelectionCommands();
    final transformOptions = ValueNotifier(TransformToolOptions.defaults);
    addTearDown(transformOptions.dispose);

    // A 400×300 opaque picture in the middle of the cel.
    coordinator.commitSourceStroke(
      sourceDabs: [
        for (var y = 382.0; y <= 642; y += 20)
          for (var x = 332.0; x <= 692; x += 20)
            BrushDab(
              center: CanvasPoint(x: x, y: y),
              color: 0xFF3060C0,
              size: 24,
              opacity: 1,
              flow: 1,
              hardness: 1,
              tipShape: BrushTipShape.square,
              pressure: 1,
              sequence: 0,
            ),
      ],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BrushCanvasPanel(
            coordinator: coordinator,
            canvasSize: canvasSize,
            availableFrameKeys: frameKeys,
            cacheInvalidationSink: BrushEditCacheInvalidationSink(),
            historyManager: history,
            brushToolState: ValueNotifier(BrushToolState.defaults.copyWith(
              tool: CanvasTool.select,
            )),
            selectionCommands: commands,
            viewport: seedFromRender(tester, CanvasViewport(zoom: 0.5)),
            transformOptions: transformOptions,
          ),
        ),
      ),
    );

    Future<void> settle() async {
      for (var i = 0; i < 12; i += 1) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 16)),
        );
        await tester.pump();
      }
    }

    await settle();

    // The picture's own ink box through the layer's region door, Ctrl+T,
    // the percentage, Enter — no handle has to be on screen.
    Future<void> scale(double factor) async {
      commands.deselect();
      await tester.pump();
      final bounds = bitmapSurfaceContentBounds(
        coordinator.currentSurfaceOf(coordinator.activeFrameKey),
      )!;
      commands.applyRegion(
        CanvasSelectionRegion.shape(
          CanvasSelectionShape([
            CanvasPoint(x: bounds.left - 2.0, y: bounds.top - 2.0),
            CanvasPoint(x: bounds.rightExclusive + 2.0, y: bounds.top - 2.0),
            CanvasPoint(
              x: bounds.rightExclusive + 2.0,
              y: bounds.bottomExclusive + 2.0,
            ),
            CanvasPoint(x: bounds.left - 2.0, y: bounds.bottomExclusive + 2.0),
          ]),
        ),
      );
      await tester.pump();
      final before = coordinator.currentSurfaceOf(coordinator.activeFrameKey);
      commands.beginTransform();
      await tester.pump();
      commands.setTransformValues(
        tx: 0,
        ty: 0,
        rotationDegrees: 0,
        scale: factor,
      );
      await tester.pump();
      expect(commands.transformActive, isTrue, reason: 'the box opened');
      commands.applyTransform();
      await tester.pump();
      await settle();
      expect(commands.transformActive, isFalse, reason: 'Enter closed it');
      expect(
        identical(
          coordinator.currentSurfaceOf(coordinator.activeFrameKey),
          before,
        ),
        isFalse,
        reason: 'the landing replaced the cel',
      );
    }

    final picture = _weakTilesOfTheActiveCel(coordinator);
    expect(picture, isNotEmpty, reason: 'fixture: the picture made tiles');
    int alive() => picture.where((tile) => tile.target != null).length;

    await scale(2);
    await tester.runAsync(collectGarbage);
    expect(
      alive(),
      greaterThan(0),
      reason: 'control: while its entry is resident, the transform holds the '
          'picture it would undo to — the measurement can see a holder',
    );
    await scale(0.5);

    // ⚠️PARK THE ENTRIES AND DELETE NOTHING, asked the way a user's next edit
    // asks. A stack that cannot get under its budget with the top entry
    // resident stands the spill down and DELETES — and a deleted entry frees
    // whatever its closures hold, so the mutant that brought the leak back
    // passed that way twice (a one-byte budget; then a budget computed from
    // the picture, which the top entry's bill still exceeded). So the budget
    // sits one byte under what the stack holds now, and the next entry
    // weighs nothing: everything beneath it can park, and the stack ends
    // under any budget. The setter narrows the room along with it, and the
    // room is not what this is about — reopened.
    final held = history.retainedBytes;
    final entries = history.undoCount;
    history.byteBudget = held - 1;
    VolatileScratchFiles.ceilingBytes = 0;
    history.execute(_WeighsNothing());
    // ⚠️BOTH CLOCKS, NOT `drainSpilling`. The spill starts where the entry
    // was pushed — inside the test's fake-async zone — and it advances only
    // while that zone is pumped; awaiting it from real time alone waited on
    // a future that nothing could complete, and a run sat idle for six
    // minutes (2026-09-15). Real time lets the parking isolate answer, the
    // pump lets the zone take the answer.
    for (var i = 0; i < 50 && history.retainedBytes >= held; i += 1) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
    }
    expect(
      history.retainedBytes,
      lessThan(held),
      reason: 'control: the budget parked the entries beneath the new one',
    );
    expect(
      history.undoCount,
      entries + 1,
      reason: 'control: PARKED, not deleted — a deleted entry frees its '
          'closures whatever they hold, and would prove nothing',
    );
    await settle();
    // ⚠️A FEW rounds, not the helper's fifty: when something still holds the
    // picture the condition never comes true, and fifty rounds of the churn
    // under a heap that large took one run past ten gigabytes and five
    // minutes before it could say so (2026-09-15).
    await tester.runAsync(
      () => collectGarbageUntil(() => alive() == 0, rounds: 6),
    );
    expect(
      alive(),
      0,
      reason: 'a parked transform must keep none of its pre-lift picture — '
          '${picture.length} tiles, ${alive()} still alive',
    );
  });
}

/// Weak references to every tile of [coordinator]'s active cel.
///
/// ⚠️IN A FUNCTION OF ITS OWN, AND THAT IS PART OF THE MEASUREMENT
/// (2026-09-15). Written as a collection-`for` inside the test body, the
/// loop's iterator — and through it the surface's tile map — stayed in the
/// async test frame for the rest of the test: a heap snapshot found all
/// sixteen tiles alive behind a map and an iterator that nothing in the heap
/// referred to, after the product had already let go of them. A frame that
/// has returned cannot pin anything.
List<WeakReference<BitmapTile>> _weakTilesOfTheActiveCel(
  BrushFrameEditingCoordinator coordinator,
) => [
  for (final tile in coordinator
      .currentSurfaceOf(coordinator.activeFrameKey)
      .tiles
      .values)
    WeakReference<BitmapTile>(tile),
];

/// The next edit, reduced to what the stack does with it: an entry that
/// holds no payload, so pushing it trims the stack and nothing it holds can
/// stop everything beneath it from parking.
class _WeighsNothing implements Command {
  @override
  String get description => 'Nothing';

  @override
  void execute() {}

  @override
  void undo() {}
}
