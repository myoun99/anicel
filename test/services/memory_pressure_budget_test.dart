import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/services/memory_pressure_budget.dart';
import 'package:anicel/src/services/history_manager.dart';
import 'package:anicel/src/services/brush_frame_store.dart';
import 'package:anicel/src/ui/media/viewer_raster_budget.dart';

/// The one law three caches used to keep three copies of: a memory
/// warning only ever LOWERS a byte cap, and says so idempotently.
void main() {
  const mb = 1024 * 1024;

  group('halving', () {
    test('halves, and keeps halving as warnings repeat', () {
      final budget = MemoryPressureBudget.halving(
        normal: 1024 * mb,
        floor: 64 * mb,
      );
      expect(budget.bytes, 1024 * mb);
      expect(budget.respondToMemoryPressure(), isTrue);
      expect(budget.bytes, 512 * mb);
      expect(budget.respondToMemoryPressure(), isTrue);
      expect(budget.bytes, 256 * mb);
    });

    test('stops at the floor, and then reports it did nothing', () {
      final budget = MemoryPressureBudget.halving(
        normal: 128 * mb,
        floor: 64 * mb,
      );
      expect(budget.respondToMemoryPressure(), isTrue);
      expect(budget.bytes, 64 * mb);
      // 🚨The second warning is the one that mattered: iOS sends them
      // repeatedly as things get worse, and a budget that kept halving
      // would walk to zero and thrash.
      expect(budget.respondToMemoryPressure(), isFalse);
      expect(budget.bytes, 64 * mb);
    });

    test('a budget ALREADY under the floor is not raised by pressure', () {
      // The signal that says memory is scarce must not hand memory out.
      final budget = MemoryPressureBudget.halving(
        normal: 8 * mb,
        floor: 64 * mb,
      );
      expect(budget.respondToMemoryPressure(), isFalse);
      expect(budget.bytes, 8 * mb);
    });
  });

  group('droppingTo', () {
    test('drops straight to the target, once', () {
      final budget = MemoryPressureBudget.droppingTo(
        normal: 512 * mb,
        underPressure: 64 * mb,
      );
      expect(budget.respondToMemoryPressure(), isTrue);
      expect(budget.bytes, 64 * mb);
      expect(budget.respondToMemoryPressure(), isFalse);
      expect(budget.bytes, 64 * mb);
    });

    test('a tighter caller is left alone', () {
      final budget = MemoryPressureBudget.droppingTo(
        normal: 16 * mb,
        underPressure: 64 * mb,
      );
      expect(budget.respondToMemoryPressure(), isFalse);
      expect(budget.bytes, 16 * mb);
    });
  });

  test('assigning states a new normal — it is NOT the lowers-only path', () {
    final budget = MemoryPressureBudget.halving(
      normal: 128 * mb,
      floor: 16 * mb,
    );
    budget.respondToMemoryPressure();
    expect(budget.bytes, 64 * mb);
    // The session seeds the device-scaled number this way, and a test
    // builds a tight fixture this way. Neither is the OS talking.
    budget.bytes = 900 * mb;
    expect(budget.bytes, 900 * mb);
  });

  /// 🚨★★★**THE POINT OF THE SHARED TYPE.**
  ///
  /// Every cache that holds pixels must stand down when the OS warns, and
  /// each used to re-derive the guard. These assert the three call it —
  /// they are what goes red if a fourth cache is added with its own copy
  /// and the answer diverges again.
  group('every pixel cache lowers on the same law', () {
    test('the cel store halves, floored', () {
      final store = BrushFrameStore()..hotCelByteBudget = 1024 * mb;
      store.respondToMemoryPressure();
      expect(store.hotCelByteBudget, 512 * mb);
      store.hotCelByteBudget = 300 * mb;
      store.respondToMemoryPressure();
      expect(
        store.hotCelByteBudget,
        256 * mb,
        reason: 'floored, not halved to 150',
      );
      store.respondToMemoryPressure();
      expect(store.hotCelByteBudget, 256 * mb, reason: 'and it stays there');
    });

    test('the viewer halves, floored at one page', () {
      final budget = ViewerRasterBudget(physicalMemoryBytes: null);
      expect(
        budget.byteBudget,
        viewerPageBytesAtCap * 4,
        reason: 'desktop default: four pages at the render cap',
      );
      expect(budget.respondToMemoryPressure(), isTrue);
      expect(budget.byteBudget, viewerPageBytesAtCap * 2);
      expect(budget.respondToMemoryPressure(), isTrue);
      expect(budget.byteBudget, viewerPageBytesAtCap);
      expect(
        budget.respondToMemoryPressure(),
        isFalse,
        reason: 'the page being LOOKED AT survives every warning',
      );
    });

    test('the undo stack drops in one step', () {
      // Its own test file drives the stack; this asserts the SHAPE — a
      // drop, not the store's halving — because the difference between
      // the two policies is deliberate, and a well-meaning unification
      // would erase it.
      final budget = MemoryPressureBudget.droppingTo(
        normal: HistoryManager.retainedByteBudget,
        underPressure: HistoryManager.retainedByteBudgetUnderPressure,
      );
      budget.respondToMemoryPressure();
      expect(budget.bytes, HistoryManager.retainedByteBudgetUnderPressure);
      expect(
        budget.bytes * 2,
        lessThan(HistoryManager.retainedByteBudget),
        reason: 'a drop, not a halving — undo bytes have nowhere to cool to',
      );
    });
  });

  /// 🚨The divisor in [viewerRasterBytesFor] is fixed by BOTH endpoints of
  /// the canvas clamp, not chosen. If either end stops landing on a whole
  /// number of pages, the derivation in that file's doc is no longer true.
  group('the viewer share is derived from the canvas law', () {
    test('a desktop keeps exactly what the old count bound allowed', () {
      expect(
        viewerRasterBytesFor(physicalMemoryBytes: 32 * 1024 * mb),
        viewerPageBytesAtCap * 4,
      );
    });

    test('the device floor lands on exactly one page', () {
      // 1GB of RAM: the canvas clamps up to its 384MB floor.
      expect(
        viewerRasterBytesFor(physicalMemoryBytes: 1024 * mb),
        viewerPageBytesAtCap,
      );
    });

    test('a 3GB tablet lands between them, and below the desktop', () {
      final tablet = viewerRasterBytesFor(physicalMemoryBytes: 3 * 1024 * mb);
      expect(tablet, greaterThan(viewerPageBytesAtCap));
      expect(tablet, lessThan(viewerPageBytesAtCap * 4));
    });
  });
}
