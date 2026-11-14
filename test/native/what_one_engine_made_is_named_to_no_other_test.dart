/// Two engines are opened here, and each compiles the kernels of what it
/// is asked for beside a busy line: the bound is this file's own.
@Timeout(Duration(minutes: 3))
library;

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:gpu_engine/gpu_engine.dart';

/// 🚨WHAT ONE ENGINE MADE IS NAMED TO NO OTHER'S JOB (gpu_engine.dart,
/// `_OfAnEngine`): a job that names an object another engine made is
/// refused by name ([GpuRefused]) where it is asked, before the engine
/// hears of it.
///
/// 🗣️gpu-canonical-store-Q11 (유저 2026-11-10): 「장치를 잃으면 앱은 꺼지지
/// 않고 새 장치를 열어 사본으로 되살린다」 — an app that opens a second
/// engine in its life has what the first made still in hand for a moment:
/// 🔬2026-11-13, a picture made on the engine let go and carried by the
/// next one's kernels ended the process (wgpu: `Cannot get BufferId(2,2),
/// found other resource BufferId(2,1)`). ⚠️So each of these, where the
/// refusal is taken out, ends by the test never ending — or passes, a
/// buffer of one engine taken for the other's.
///
/// That EVERY read of another object's pointer goes this way is the scan's
/// to hold (`test/architecture/a_job_names_what_its_own_engine_made_test
/// .dart`); what the way does is pinned here, at one job of each shape.
///
/// On two engines of the test's own, neither lost.
void main() {
  late GpuEngine one;
  late GpuEngine other;

  setUpAll(() {
    one = GpuEngine.onFirstAdapter();
    other = GpuEngine.onFirstAdapter();
  });
  tearDownAll(() {
    one.close();
    other.close();
  });

  final refusedAsAnothers = throwsA(
    isA<GpuRefused>().having(
      (refused) => refused.message,
      'why',
      contains('another engine'),
    ),
  );

  test('🚨a picture made on one engine is carried by no kernels of '
      'another — the job that ended the process', () {
    final landing = GpuStampLanding(other);
    addTearDown(landing.free);
    final picture = GpuStampPicture(one, Uint8List(4), 1, 1);

    expect(
      () => landing.carried(
        picture,
        inverse: const [1, 0, 0, 0, 1, 0, 0, 0, 1],
        radiusFloor: 1,
        sampling: GpuSampling.blend,
        width: 1,
        height: 1,
      ),
      refusedAsAnothers,
    );
  });

  test('an executor runs a plan of its own engine over a pool of its own: '
      'neither of another', () {
    final composite = GpuComposite(one);
    addTearDown(composite.free);
    final (pool, anothers) = (GpuPool(one, 1 << 20), GpuPool(other, 1 << 20));
    addTearDown(pool.free);
    addTearDown(anothers.free);
    final (plan, ofAnother) = (GpuPlan(one), GpuPlan(other));
    addTearDown(plan.free);
    addTearDown(ofAnother.free);

    expect(
      () => composite.run(anothers, plan, [(0, 0)], (0, 0, 1, 1)),
      refusedAsAnothers,
    );
    expect(
      () => composite.run(pool, ofAnother, [(0, 0)], (0, 0, 1, 1)),
      refusedAsAnothers,
    );
  });

  test('a plan names what its own engine made', () {
    final plan = GpuPlan(one);
    addTearDown(plan.free);
    final read = GpuChainRead(other);
    addTearDown(read.free);

    expect(
      () => plan.chainRead(plan.chain(0, 0, 1, 1), read),
      refusedAsAnothers,
    );
  });

  test('a hold is the engine\'s whose plans named a number it has not let '
      'go of — and, each one let go, the next engine\'s: one hold '
      'outlives the engine an app lets go', () {
    final held = GpuHeldChains();
    addTearDown(held.free);
    final (first, next) = (GpuPlan(one), GpuPlan(other));
    addTearDown(first.free);
    addTearDown(next.free);
    final (ofFirst, ofNext) = (
      first.chain(0, 0, 1, 1),
      next.chain(0, 0, 1, 1),
    );

    first
      ..chainHeld(ofFirst, held, 7)
      ..chainHeld(ofFirst, held, 8);
    expect(() => next.chainHeld(ofNext, held, 7), refusedAsAnothers);
    expect(() => next.chainHeld(ofNext, held, 9), refusedAsAnothers);

    held.letGo(7);
    expect(
      () => next.chainHeld(ofNext, held, 9),
      refusedAsAnothers,
      reason: 'it holds a number of the first\'s still',
    );
    held.letGo(8);

    next.chainHeld(ofNext, held, 7);
    expect(() => first.chainHeld(ofFirst, held, 8), refusedAsAnothers);
  });
}
