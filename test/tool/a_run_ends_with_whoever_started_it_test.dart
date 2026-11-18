@TestOn('vm')
library;

import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../tool/process_tree.dart';
import '../helpers/dart_sources.dart';

/// 🚨Card a-wide-check-cut-by-an-outer-timeout-leaves-its-runner-running:
/// an outer `timeout` ended `master_check`, and the `affected_tests` it had
/// started went on launching batches for a verdict nobody would read. What a
/// tool starts ends when the tool ends, however it ends — asked here of the
/// operating system, in this very process (no test starts one).
void main() {
  group('the job', () {
    late final job = endWhatThisStartsWithIt();

    test('holds this process', () {
      expect(job, isNotNull);
      final inIt = calloc<Int32>();
      try {
        expect(_isProcessInJob(_thisProcess, job!, inIt), isNot(0));
        expect(inIt.value, isNot(0));
      } finally {
        calloc.free(inIt);
      }
    });

    test('ends what it holds when its last handle closes', () {
      expect(_limitFlagsOf(job!) & _killOnJobClose, _killOnJobClose);
    });

    test('⛔lets nothing break away — a bash `exec` would leave it', () {
      expect(_limitFlagsOf(job!) & (_breakawayOk | _silentBreakawayOk), 0);
    });

    test('⛔is a handle no child inherits — one would hold the job open', () {
      final flags = calloc<Uint32>();
      try {
        expect(_handleInformation(job!, flags), isNot(0));
        expect(flags.value & _handleFlagInherit, 0);
      } finally {
        calloc.free(flags);
      }
    });
  }, skip: Platform.isWindows ? false : 'a job is a Windows object');

  test('⛔every tool that starts a test run ends it with itself', () {
    // The four by name so a change to any of them reruns this; the walk so
    // a launcher that can cut a run cannot be added without it.
    const launchers = [
      'tool/affected_tests.dart',
      'tool/master_check.dart',
      'tool/mutation_run.dart',
      'tool/test_queue.dart',
    ];
    final cutters = [
      for (final file in dartFilesUnder('tool'))
        if (!file.path.endsWith('process_tree.dart') &&
            file.readAsStringSync().contains('cutTree('))
          file.path.replaceAll(r'\', '/'),
    ];
    final unended = [
      for (final path in {...launchers, ...cutters})
        if (!RegExp(
          r'main\(List<String> args\) async \{\s*endWhatThisStartsWithIt\(\);',
        ).hasMatch(File(path).readAsStringSync()))
          path,
    ];
    expect(unended, isEmpty);
  });
}

const _thisProcess = -1;
const _extendedLimitInformation = 9;
const _breakawayOk = 0x800;
const _silentBreakawayOk = 0x1000;
const _killOnJobClose = 0x2000;
const _handleFlagInherit = 1;

/// `LimitFlags` of the job's `JOBOBJECT_EXTENDED_LIMIT_INFORMATION`: it
/// stands after two 8-byte time limits, on 32 and 64 bits alike.
int _limitFlagsOf(int job) {
  final size = sizeOf<IntPtr>() == 8 ? 144 : 112;
  final limits = calloc<Uint8>(size);
  try {
    expect(
      _queryJob(job, _extendedLimitInformation, limits, size, nullptr),
      isNot(0),
    );
    return limits.cast<Uint32>()[4];
  } finally {
    calloc.free(limits);
  }
}

final _kernel32 = DynamicLibrary.open('kernel32.dll');
final _isProcessInJob = _kernel32
    .lookupFunction<
      Int32 Function(IntPtr, IntPtr, Pointer<Int32>),
      int Function(int, int, Pointer<Int32>)
    >('IsProcessInJob');
final _queryJob = _kernel32
    .lookupFunction<
      Int32 Function(IntPtr, Int32, Pointer<Uint8>, Uint32, Pointer<Uint32>),
      int Function(int, int, Pointer<Uint8>, int, Pointer<Uint32>)
    >('QueryInformationJobObject');
final _handleInformation = _kernel32
    .lookupFunction<
      Int32 Function(IntPtr, Pointer<Uint32>),
      int Function(int, Pointer<Uint32>)
    >('GetHandleInformation');
