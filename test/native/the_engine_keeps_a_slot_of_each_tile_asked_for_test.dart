import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gpu_engine/gpu_engine.dart';

import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/bitmap_tile.dart';
import 'package:anicel/src/native/app_gpu_engine.dart';
import 'package:anicel/src/native/engine_tile_ledger.dart';
import 'package:anicel/src/ui/canvas/bitmap_tile_image_cache.dart';
import 'package:anicel/src/ui/canvas/tile_picture_budget.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';

import '../helpers/census_where_textures_are_ram.dart';

/// The app's tiles get their slots on the engine through the ledger
/// (screen-on-the-engine c4): stored inside the call that asks, once a
/// tile object, each slot holding its tile's bytes; kept while a hold has
/// them; let go when a pool is full of what no hold has; read back as
/// their bytes, a batch at a time. Let go with their tile is
/// a_tile_collected_lets_its_engine_slot_go_test.dart's, which waits for
/// the collector; what the pool does with a store is its own
/// test's (the_engine_pool_keeps_the_apps_tiles_test.dart) — here, what
/// the ledger asks of it.
void main() {
  late GpuComposite composite;
  const all = (-1 << 31, -1 << 31, (1 << 31) - 1, (1 << 31) - 1);
  const identity = [1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0];
  // Cels by the name a painter gives one.
  const a = (1, 1);
  const b = (1, 2);
  const c = (1, 3);

  setUpAll(() => composite = GpuComposite(appGpuEngine));
  tearDownAll(() => composite.free());

  /// An opaque tile of bytes of its own, by [seed].
  BitmapTile tileOf(int seed) => BitmapTile.written(
    size: gpuTileSide,
    write: (pixels) {
      for (var at = 0; at < pixels.length; at++) {
        pixels[at] = at % 4 == 3
            ? 255
            : (at * 2654435761 + seed * 40503) >> 13 & 255;
      }
    },
  );

  /// [count] tiles of nothing, objects of their own: a page's worth fills
  /// it, as a cel's tiles share one till none has room.
  List<BitmapTile> blanks(int count) => [
    for (var tile = 0; tile < count; tile++)
      BitmapTile.blank(size: gpuTileSide),
  ];

  /// What a row of [slots] lays back copied over nothing: their bytes, as
  /// [tileOf]'s are opaque.
  Uint8List laidBack(EngineTileLedger ledger, List<GpuTile> slots) {
    final plan = GpuPlan();
    addTearDown(plan.free);
    final added = plan.row(
      set: plan.set(0, 0, slots.length, 1, slots),
      inverse: identity,
      sampling: GpuSampling.blend,
      columns: slots.length * gpuTileSide,
      rows: gpuTileSide,
      mode: GpuBlend.normal,
    );
    expect(added, isTrue);
    final out = composite.run(ledger.pool, plan, [
      for (var column = 0; column < slots.length; column++) (column, 0),
    ], all);
    addTearDown(out.free);
    return out.read();
  }

  test('a tile asked for is stored once, in a slot holding its bytes — a '
      'tile alike it in one of its own', () {
    final ledger = EngineTileLedger(appGpuEngine);
    final first = tileOf(1);
    final second = tileOf(2);
    final twin = BitmapTile(size: gpuTileSide, pixels: first.pixels);

    ledger.held((hold) {
      final slots = hold.slotsOf(a, [first, second, first, twin]);

      expect(slots[2], slots[0]);
      expect(slots.toSet(), hasLength(3));
      expect(
        laidBack(ledger, slots),
        [...first.pixels, ...second.pixels, ...first.pixels, ...first.pixels],
      );
    });
    expect(ledger.slotCount, 3);
    expect(ledger.held((hold) => hold.slotsOf(a, [second])), [
      ledger.slotOf(second),
    ]);
    expect(ledger.slotCount, 3, reason: 'asked again, stored once');
  });

  test('a tile of another side is refused, and nothing the call asks for '
      'is stored', () {
    final ledger = EngineTileLedger(appGpuEngine);
    final kept = tileOf(3);
    final half = gpuTileSide ~/ 2;

    expect(
      () => ledger.held(
        (hold) => hold.slotsOf(a, [kept, BitmapTile.blank(size: half)]),
      ),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          contains('$half²'),
        ),
      ),
    );
    expect(ledger.slotOf(kept), isNull);
    expect(ledger.slotCount, 0);
  });

  test('a full pool lets go what no hold has, and stores what one has past '
      'the budget', () {
    final ledger = EngineTileLedger(appGpuEngine, byteBudget: 0);
    final one = tileOf(4);
    final two = tileOf(5);
    final three = tileOf(6);

    ledger.held((hold) => hold.slotsOf(a, [one]));
    final page = ledger.pool.bytes;
    expect(ledger.slotOf(one), isNotNull, reason: 'a call is never refused');
    expect(page, greaterThan(0));
    final rest = blanks(page ~/ gpuTileBytes - 1);
    ledger.held((hold) => hold.slotsOf(a, rest));
    expect(ledger.pool.bytes, page, reason: 'the page has room for them');

    ledger.held((hold) => hold.slotsOf(b, [two]));
    expect(ledger.slotOf(one), isNull, reason: 'no hold has it');
    expect(ledger.pool.bytes, page, reason: "its page is the next cel's");

    ledger.held((hold) {
      final kept = hold.slotsOf(a, [one, ...rest]).first;
      final [past] = hold.slotsOf(b, [three]);

      expect(ledger.slotOf(one), kept, reason: 'this hold has it');
      expect(laidBack(ledger, [kept, past]), [
        ...one.pixels,
        ...three.pixels,
      ]);
    });
    expect(ledger.slotOf(two), isNull);
    expect(ledger.pool.bytes, 2 * page);
    expect(ledger.slotCount, rest.length + 2);
  });

  test('the tiles read back are their bytes, in order — one without a slot '
      'stored for the read', () {
    final ledger = EngineTileLedger(appGpuEngine);
    final first = tileOf(10);
    final second = tileOf(11);
    ledger.held((hold) => hold.slotsOf(a, [first]));
    final into = malloc<Uint8>(3 * gpuTileBytes);
    addTearDown(() => malloc.free(into));

    ledger.read(a, [second, first, second], into);

    expect(into.asTypedList(3 * gpuTileBytes), [
      ...second.pixels,
      ...first.pixels,
      ...second.pixels,
    ]);
    expect(ledger.slotOf(second), isNotNull, reason: 'stored for the read');
    expect(ledger.slotCount, 2);
  });

  test('each tile read back a batch at a time is handed over in order', () {
    final ledger = EngineTileLedger(appGpuEngine);
    final tiles = [
      for (var seed = 0; seed < EngineTileLedger.readBatch + 2; seed++)
        tileOf(seed),
    ];
    final handed = <Uint8List>[];

    ledger.readEach(a, tiles, (bytes) => handed.add(Uint8List.fromList(bytes)));

    expect(handed, [for (final tile in tiles) tile.pixels]);
    ledger.readEach(a, const [], (_) => fail('none to hand over'));
  });

  test("a read of many batches asks for one batch's block, once, and gives "
      'it back — a read of fewer tiles, theirs alone', () {
    final ledger = EngineTileLedger(appGpuEngine);
    final tile = tileOf(12);
    final many = _Counted();
    final few = _Counted();

    ledger.readEach(
      a,
      List.filled(2 * EngineTileLedger.readBatch + 1, tile),
      (_) {},
      blocks: many,
    );
    ledger.readEach(a, [tile, tile], (_) {}, blocks: few);

    expect(many.asked, [EngineTileLedger.readBatch * gpuTileBytes]);
    expect(few.asked, [2 * gpuTileBytes]);
    expect([many.givenBack, few.givenBack], [1, 1]);
  });

  test('a hold is asked inside the call it was handed to', () {
    final ledger = EngineTileLedger(appGpuEngine);
    final kept = ledger.held((hold) => hold);

    expect(() => kept.slotsOf(a, [tileOf(7)]), throwsStateError);
    expect(ledger.slotCount, 0);
  });

  test('a budget moved is the one a full pool keeps to, the pages made '
      'staying', () {
    final ledger = EngineTileLedger(appGpuEngine);
    final one = tileOf(8);
    final two = tileOf(9);

    ledger.held((hold) => hold.slotsOf(a, [one]));
    final slots = ledger.pool.bytes ~/ gpuTileBytes;
    final rest = blanks(slots - 1);
    ledger.held((hold) => hold.slotsOf(a, rest));
    ledger.held((hold) => hold.slotsOf(b, [two]));
    final made = ledger.pool.bytes;
    expect(made, 2 * slots * gpuTileBytes, reason: 'no budget but the OS');
    expect(ledger.slotOf(one), isNotNull);

    ledger.byteBudget = 0;
    ledger.held((hold) => hold.slotsOf(c, blanks(slots)));

    expect(ledger.byteBudget, 0);
    expect(ledger.slotOf(one), isNull);
    expect(ledger.slotOf(two), isNull);
    expect(rest.map(ledger.slotOf), everyElement(isNull));
    expect(ledger.pool.bytes, made);
  });

  testWidgets("the app's ledger takes the session's line, before it opens "
      'and after, and the census counts its pages on that line', (
    tester,
  ) async {
    final session = EditorSessionManager(
      initialProject: createDefaultProject(),
    );
    addTearDown(session.dispose);
    final line = TilePictureBudget.instance.byteBudget;
    expect(EngineTileLedger.appByteBudget, line);

    final app = EngineTileLedger.instance;
    expect(app.byteBudget, line);
    EngineTileLedger.appByteBudget = line + 1;
    expect(app.byteBudget, line + 1);

    app.held((hold) => hold.slotsOf(a, [tileOf(11)]));
    expect(EngineTileLedger.appPoolBytes, app.pool.bytes);
    expect(app.pool.bytes, greaterThan(0));
    final rows = {
      for (final item in collectMemoryCensusWhereTexturesAreRam([
        session,
      ]).items)
        item.id: item.bytes,
    };
    expect(
      rows['tileImages'],
      BitmapTileImageCache.liveImageBytes + app.pool.bytes,
    );
  });
}

/// [malloc], counting what it is asked: each block's bytes, and the blocks
/// given back.
final class _Counted implements Allocator {
  final asked = <int>[];
  int givenBack = 0;

  @override
  Pointer<T> allocate<T extends NativeType>(int byteCount, {int? alignment}) {
    asked.add(byteCount);
    return malloc.allocate(byteCount, alignment: alignment);
  }

  @override
  void free(Pointer pointer) {
    givenBack += 1;
    malloc.free(pointer);
  }
}
