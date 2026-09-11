import 'dart:developer' show reachabilityBarrier;

/// Runs full collections until two have completed, then two turns of the
/// event loop — a finalizer's callback is delivered there, never inside a
/// GC. For tests that prove a holder LETS GO: what nothing reaches is
/// collected, and after this its finalizer has run.
///
/// Churns small lists instead of asking the VM, because a test cannot
/// reach the VM service — the way `leak_tracker`'s `forceGC` does it.
Future<void> collectGarbage() async {
  final target = reachabilityBarrier + 2;
  final churn = <List<int>>[];
  while (reachabilityBarrier < target) {
    await Future<void>.delayed(Duration.zero);
    churn.add(List<int>.filled(30000, 0));
    if (churn.length > 100) {
      churn.removeAt(0);
    }
  }
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);
}
