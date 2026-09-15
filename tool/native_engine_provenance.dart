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
// The name is the C itself, the way CI already names it: CI keys its engine
// cache on `hashFiles('packages/qa_native/src/**')`
// (`.github/actions/native-engine/action.yml`), a hash of every file under
// the directory. Here it is the same idea — every file's path and bytes, in
// path order — so an edit is other C the moment it is saved, and a lane that
// edits its C and rebuilds is current without committing anything.
// ⚠️CI also keys on the runner image, because the compiler ships with it;
// every checkout on one machine builds with the same compiler, so the C is
// the only thing that differs between them.
//
// ⛔IN-PROCESS, NOT GIT. The first version asked git for the tree it would
// record (a throwaway index, then `write-tree`), and proving that meant a
// test that started git and dart — which `tests_do_not_race_the_code_test`
// refuses for the reason it gives: a subprocess per case turns the bulk run
// into a fight for cores (#1361). Git was also answering a question nobody
// here asked — what it would TRACK — while CMake compiles what is on disk.
//
// ⚠️The fold is 64-bit FNV-1a: it tells two states of one directory apart,
// it is not a signature, and nothing trusts it further than 「was this
// binary built from these bytes」.
//
// Asked by `tool/lane.sh` (open, land, native, engine), which builds when the
// answer is no, and by `tool/affected_tests.dart`, which says so before and
// after a run.
//
// Usage:
//   dart tool/native_engine_provenance.dart check <checkout>
// Prints `<source id> <provenance>`. Exit 0 when the engine there was built
// from that C; 1 when it was not, or there is none; 2 when the checkout
// holds no C to name.

import 'dart:convert';
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

  /// Built from other C: the stamp names different bytes.
  foreign,

  /// A build nobody stamped, so nothing says which C it came from.
  unstamped,

  /// No engine build here at all.
  absent,
}

/// The name of the C [checkout] would build, or null when it holds none.
///
/// Every file under [nativeSourceDir] — its path from there, then its bytes
/// — in path order, each framed by its length, so bytes cannot slide from
/// one field into the next and come out the same.
String? nativeSourceId(String checkout) {
  final root = Directory('$checkout/$nativeSourceDir');
  if (!root.existsSync()) return null;
  final files = <String, File>{
    for (final entity in root.listSync(recursive: true, followLinks: false))
      if (entity is File) _pathWithin(root.path, entity.path): entity,
  };
  final fold = _SourceFold();
  for (final path in files.keys.toList()..sort()) {
    fold
      ..addFramed(utf8.encode(path))
      ..addFramed(files[path]!.readAsBytesSync());
  }
  return fold.name;
}

/// [path] from [root], with `/` between its parts on every platform.
String _pathWithin(String root, String path) {
  final tail = path.substring(root.length).replaceAll(r'\', '/');
  return tail.startsWith('/') ? tail.substring(1) : tail;
}

/// 64-bit FNV-1a over length-framed fields.
class _SourceFold {
  static const int _offsetBasis = (0xcbf29ce4 << 32) | 0x84222325;
  static const int _prime = 0x100000001b3;

  int _hash = _offsetBasis;

  void addFramed(List<int> bytes) {
    final length = bytes.length;
    _add([for (var shift = 0; shift < 64; shift += 8) (length >> shift) & 0xff]);
    _add(bytes);
  }

  void _add(List<int> bytes) {
    var hash = _hash;
    for (final byte in bytes) {
      hash = (hash ^ byte) * _prime;
    }
    _hash = hash;
  }

  String get name =>
      BigInt.from(_hash).toUnsigned(64).toRadixString(16).padLeft(16, '0');
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

/// What `check` says about [checkout]: the line `tool/lane.sh` parses —
/// `<source id> <provenance>`, null when there is no C to name — and the
/// exit code it branches on.
({String? line, int exitCode}) checkReport(String checkout) {
  final id = nativeSourceId(checkout);
  if (id == null) return (line: null, exitCode: 2);
  final provenance = engineProvenance(checkout, id);
  return (
    line: '$id ${provenance.name}',
    exitCode: provenance == EngineProvenance.current ? 0 : 1,
  );
}

void main(List<String> args) {
  if (args.length != 2 || args.first != 'check') {
    stderr.writeln(
      'usage: dart tool/native_engine_provenance.dart check <checkout>',
    );
    exit(64);
  }
  final report = checkReport(args[1]);
  final line = report.line;
  if (line == null) {
    stderr.writeln('no C to name under ${args[1]}/$nativeSourceDir');
  } else {
    stdout.writeln(line);
  }
  exit(report.exitCode);
}
