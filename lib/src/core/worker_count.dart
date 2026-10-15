import 'dart:math' as math;

/// How many workers a machine with [cores] processors may run at once for
/// one kind of work: at least one, at most [ceiling].
///
/// ⛔`cores - 1`, never `cores`: the UI isolate is one of the things
/// competing for them, and it is the one the user is looking at. A two-core
/// tablet runs ONE worker beside it.
///
/// ⚠️The ceiling is each use's own, measured where it is passed — where the
/// wall clock stops falling for that work. The formula is the one law: the
/// brush roster's rasters and both import pools spelled it each on their
/// own, and the cel thaw would have been the fourth.
int workersFor(int cores, {required int ceiling}) =>
    math.max(1, math.min(cores - 1, ceiling));
