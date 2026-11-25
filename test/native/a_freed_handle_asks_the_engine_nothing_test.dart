import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gpu_engine/gpu_engine.dart';

import 'package:anicel/src/native/app_gpu_engine.dart';

import '../helpers/a_shown_surface.dart';
import '../helpers/source_body.dart';
import '../helpers/source_ledger.dart';

/// A FREED HANDLE ASKS THE ENGINE NOTHING (관제 2026-11-24): what the
/// engine handed an object is asked through one holder, which refuses it
/// by name once it is freed (`_Held`, gpu_engine.dart). Twice an object
/// asked after its free read freed memory: a tile a ledger stored and
/// collected once a test had freed that ledger's pool let its slot go
/// there, the engine read a slot of no book, and the process ended (card
/// a-pool-release-aborts-on-an-empty-book); a screen's bytes asked after
/// it was freed read on on Windows and faulted on Linux (the crate's
/// `screens_composed_of_the_same_hold_one_tile_weighed_once`, card
/// release-2026-11-24). Each verb, asked after the free, is refused here
/// before it reaches the engine — a pool's let-go answered as for a slot
/// none holds.
/// ⚠️A read of freed memory need not crash, so a red here is the ask let
/// through, not the process ended.
void main() {
  group('a pool', () {
    late int asked;
    setUp(() {
      asked = 0;
      GpuPool.debugAsked = () => asked += 1;
    });
    tearDown(() => GpuPool.debugAsked = null);

    /// A pool with one tile stored in it, then freed: the tile it held.
    GpuTile storedThenFreed(GpuPool pool) {
      final bytes = calloc<Uint8>(gpuTileBytes);
      addTearDown(() => calloc.free(bytes));
      final tile = pool.store(pool.cel(), [bytes], (at) => at).single;
      pool.free();
      return tile;
    }

    test('a tile let go after its pool was freed lets go of nothing, and '
        'the engine is not asked', () {
      final pool = GpuPool(appGpuEngine, 1 << 30);
      final tile = storedThenFreed(pool);
      asked = 0;

      expect(pool.release(tile), isFalse);
      expect(asked, 0);
    });

    test('every other ask of a freed pool is refused by name, the engine '
        'asked none of them', () async {
      final pool = GpuPool(appGpuEngine, 1 << 30);
      final tile = storedThenFreed(pool);
      final into = calloc<Uint8>(gpuTileBytes);
      addTearDown(() => calloc.free(into));
      asked = 0;
      final refused = throwsA(_refusedAsFreed('a pool'));

      final asks = <String, Object? Function()>{
        'cel': pool.cel,
        'store': () => pool.store(0, [into], (at) => at),
        'read': () => pool.read([tile], into),
        'readout': () => pool.readout([tile]),
        'makeNoPagePast': () => pool.makeNoPagePast(0),
        'keepToInsteadOfTheOs': () => pool.keepToInsteadOfTheOs(0),
        'giveBackPast': () => pool.giveBackPast(0),
        'bytes': () => pool.bytes,
        'aheadBytes': () => pool.aheadBytes,
        'free': pool.free,
      };
      for (final MapEntry(key: verb, value: ask) in asks.entries) {
        expect(ask, refused, reason: verb);
      }
      final fold = GpuFold(appGpuEngine);
      addTearDown(fold.free);
      await expectLater(pool.fold(fold, 1), refused);
      expect(asked, 0);
    });

    test('a live pool tells the seam of each ask — ⛔CONTROL: the count '
        'above is of asks that would have gone', () {
      final pool = GpuPool(appGpuEngine, 1 << 30);
      addTearDown(pool.free);
      asked = 0;

      pool.bytes;
      expect(asked, 1);
    });
  });

  test('every ask of a freed screen is refused by name — of it, and of '
      'another that names it as its film', () {
    final composite = GpuComposite(appGpuEngine);
    addTearDown(composite.free);
    final pool = GpuPool(appGpuEngine, 1 << 30);
    addTearDown(pool.free);
    final plan = GpuPlan(appGpuEngine);
    addTearDown(plan.free);
    final target = shownSurfaceOf(4, 4);
    addTearDown(target.free);
    const page = (0, 0, 256, 256);
    final live = GpuScreen(composite, page);
    addTearDown(live.free);
    final freed = GpuScreen(composite, page)..free();
    final refused = throwsA(_refusedAsFreed('a screen'));

    final asks = <String, Object? Function()>{
      'bytes': () => freed.bytes,
      'compose': () => freed.compose(pool, plan, page),
      'composeOver': () => freed.composeOver(live, pool, plan, page),
      'composeOver, as the film': () =>
          live.composeOver(freed, pool, plan, page),
      'show': () => freed.show(
        target,
        inverse: const [1, 0, 0, 1, 0, 0],
        sampling: GpuSampling.nearest,
        rect: (0, 0, 4, 4),
      ),
      'free': freed.free,
    };
    for (final MapEntry(key: verb, value: ask) in asks.entries) {
      expect(ask, refused, reason: verb);
    }
    expect(live.bytes, isA<int>(), reason: '⛔CONTROL: a live one answers');
  });

  final source = File(
    'packages/gpu_engine/lib/gpu_engine.dart',
  ).readAsStringSync().replaceAll('\r\n', '\n');

  test('nothing but the holder reads the pointer it lets go of', () {
    final held = sourceBodyOf(source, RegExp(r'class _Held\b'));
    expect(held, contains('_live'), reason: '⛔premise: the holder has it');
    expect(
      source.replaceFirst(held, '').contains('_live'),
      isFalse,
      reason: 'every ask takes it through `ofIt`, which refuses a freed '
          'one — read past that, it names freed memory',
    );
  });

  test('every object the engine frees holds what it was handed so, outside '
      'the ledger — and every ledger entry is still one', () {
    final freed = {
      for (final declared in RegExp(
        r'^(?:\w+ )*class (Gpu\w+)',
        multiLine: true,
      ).allMatches(source))
        declared[1]!: sourceBodyOf(source, RegExp('class ${declared[1]}\\b')),
    }..removeWhere((_, body) => !body.contains('void free()'));
    expect(
      freed.keys,
      containsAll(['GpuPool', 'GpuScreen', 'GpuSurface']),
      reason: '⛔premise: the scan finds what is freed',
    );
    expectSetMatchesLedger(
      [
        for (final MapEntry(key: owner, value: body) in freed.entries)
          if (!body.contains('_Held<')) owner,
      ],
      _notYetHeld.keys,
      unledgered: 'hold what the engine handed it in a `_Held`, its pointer '
          'asked through `ofIt` and freed through `letGo`, as the pool and '
          'the screen do',
      paidOff: 'these are held so now — take them off the ledger',
    );
    expectEveryEntrySaysWhy(_notYetHeld);
  });
}

/// What the engine frees and asks still past the holder: a freed one's ask
/// reaches the engine. 🚨Debt, each to be brought under [_Held]'s law (card
/// every-freed-handle-is-refused-by-name) — not a list of exceptions.
final _notYetHeld = <String, String>{
  for (final owner in [
    'GpuBlurs',
    'GpuCelPassed',
    'GpuCelPixels',
    'GpuChainRead',
    'GpuComposite',
    'GpuComposited',
    'GpuCover',
    'GpuExport',
    'GpuFaces',
    'GpuFinished',
    'GpuFloodPicture',
    'GpuFloods',
    'GpuFold',
    'GpuGridLay',
    'GpuHeldChains',
    'GpuInk',
    'GpuLetters',
    'GpuPlugin',
    'GpuPluginMade',
    'GpuReadout',
    'GpuSelectionMasks',
    'GpuShown',
    'GpuStampLanding',
    'GpuStroke',
    'GpuSurface',
    'GpuWord',
  ])
    owner: _notYet,
  'GpuPlan': 'its free waits for the weighs on their way, which still read '
      'it — a holder for it lets go after them, not at the call',
  'GpuMask': 'its free detaches the finalizer that would free it again: '
      'that goes with the let-go',
  'GpuGridBatch': 'two pointers, the tiles and the sounds, each freed: one '
      'holder each',
  'GpuGridPicture': 'made at its batch\'s flush, null till then: what the '
      'holder holds is set after it is made',
};

const _notYet = 'not yet under the holder — a freed one is asked through to '
    'the engine';

/// A refusal of an ask of [what] once it was freed — by its words, so a
/// refusal for anything else is not taken for it.
Matcher _refusedAsFreed(String what) => isA<GpuRefused>().having(
  (refused) => refused.message,
  'message',
  '$what was asked after it was freed',
);
