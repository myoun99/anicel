// Which C a native engine build came from — the ONE answer.
//
// 🚨★★★A BUILD THAT DOES NOT SAY WHICH C IT CAME FROM IS TRUSTED WHEREVER IT
// LANDS. `tool/lane.sh open` copies the trunk's `build/native_standalone`
// into every new lane, and nothing asked whether that binary was still the
// trunk's C. Five times in five days a checkout ran its native pins against
// another checkout's C, and every time it was found by running the same
// files somewhere else:
//   2026-09-09  ABI v32: seventy red tests at once, one cause.
//   2026-09-10  a lane that never touched C: three native reds, master green.
//   2026-09-10  the same lane rebased over ABI 34, still holding its copy.
//   2026-09-11  the trunk's own DLL older than the trunk's C — `land` built
//               a lane's C in the lane and never rebuilt the trunk.
//   2026-09-13  a lane gate red 156: the trunk's 09-10 DLL, copied.
//
// ⛔NOT A FILE TIME: a fresh worktree writes every source file seconds
// before the copy, so there every .c is newer than every binary. ⛔NOT THE
// ABI NUMBER: it moves only on a bump, and the C changes far more often than
// its interface does.
//
// The name is the C itself, the way CI already names it — CI keys its engine
// cache on `hashFiles('packages/qa_native/src/**')`
// (`.github/actions/native-engine/action.yml`). Here it is the tree id git
// would record for that directory as it sits on disk now, committed or not,
// so a lane that edits its C and rebuilds is current without committing.
// ⚠️CI also keys on the runner image, because the compiler ships with it;
// every checkout on one machine builds with the same compiler, so the C is
// the only thing that differs between them.
//
// Asked by `tool/lane.sh` (open, land, native, engine), which builds when the
// answer is no, and by `tool/affected_tests.dart`, which says so before and
// after a run.
//
// Usage:
//   dart tool/native_engine_provenance.dart check <checkout>
// Prints `<source id> <provenance>`. Exit 0 when the engine there was built
// from that C; 1 when it was not, or there is none; 2 when the C cannot be
// named.

import 'dart:io';

/// Where a checkout builds its standalone engine.
const String engineBuildDir = 'build/native_standalone';

/// The file beside the build that names the C it was built from.
///
/// `tool/lane.sh` removes it before a build starts and writes it once the
/// build is green, so a build that dies half way is never read as current.
const String engineStampPath = '$engineBuildDir/.built-from';

/// The directory an engine is built from.
const String nativeSourceDir = 'packages/qa_native/src';

/// What the engine in a checkout is, measured against the C beside it.
enum EngineProvenance {
  /// Built from exactly the C this checkout holds.
  current,

  /// Built from other C: the stamp names a different tree.
  foreign,

  /// A build nobody stamped, so nothing says which C it came from.
  unstamped,

  /// No engine build here at all.
  absent,
}

/// The name of the C [checkout] would build, or null when git cannot say.
///
/// A THROWAWAY INDEX, so the checkout's own index — what its author has
/// staged — is never touched: HEAD is read into it, the source directory as
/// it sits on disk is added over that, and the tree git would record for the
/// directory is the answer. Files nobody added count, because CMake compiles
/// what is on disk, not what is committed.
String? nativeSourceId(String checkout) {
  final scratch = Directory.systemTemp.createTempSync('native_source_id_');
  final index = '${scratch.path}${Platform.pathSeparator}index';
  ProcessResult git(List<String> args) => Process.runSync(
        'git',
        ['-C', checkout, ...args],
        environment: {'GIT_INDEX_FILE': index},
      );
  try {
    if (git(['read-tree', 'HEAD']).exitCode != 0) return null;
    if (git(['add', '--', nativeSourceDir]).exitCode != 0) return null;
    final tree = git(['write-tree', '--prefix=$nativeSourceDir/']);
    final id = (tree.stdout as String).trim();
    return tree.exitCode == 0 && id.isNotEmpty ? id : null;
  } finally {
    scratch.deleteSync(recursive: true);
  }
}

/// The name of the C the engine build in [checkout] says it came from.
String? engineStampOf(String checkout) {
  final stamp = File('$checkout/$engineStampPath');
  if (!stamp.existsSync()) return null;
  final id = stamp.readAsStringSync().trim();
  return id.isEmpty ? null : id;
}

/// Whether the engine in [checkout] was built from the C named [sourceId].
EngineProvenance engineProvenance(String checkout, String sourceId) {
  if (!Directory('$checkout/$engineBuildDir').existsSync()) {
    return EngineProvenance.absent;
  }
  final stamp = engineStampOf(checkout);
  if (stamp == null) return EngineProvenance.unstamped;
  return stamp == sourceId
      ? EngineProvenance.current
      : EngineProvenance.foreign;
}

void main(List<String> args) {
  if (args.length != 2 || args.first != 'check') {
    stderr.writeln(
      'usage: dart tool/native_engine_provenance.dart check <checkout>',
    );
    exit(64);
  }
  final checkout = args[1];
  final id = nativeSourceId(checkout);
  if (id == null) {
    stderr.writeln('could not name the C in $checkout');
    exit(2);
  }
  final provenance = engineProvenance(checkout, id);
  stdout.writeln('$id ${provenance.name}');
  exit(provenance == EngineProvenance.current ? 0 : 1);
}
