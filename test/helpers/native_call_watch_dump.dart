import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

/// Writes a minidump of another process — every thread's stack, its handles
/// and its modules — to a file, and ends:
/// `dart test/helpers/native_call_watch_dump.dart <pid> <file>`.
///
/// The native call watch (`native_call_watch.dart`) runs this ONCE, from
/// OUTSIDE the process it dumps, when a step there has not ended in time.
/// ⛔Never from inside: Microsoft's advice for `MiniDumpWriteDump` is a
/// separate process — in its own, the call stops every other thread, and
/// one of them may hold a lock the call then waits for, which would bring
/// back the stop the watch is there to end (board
/// `the-trimmed-movie-test-can-hang-on-windows-ci-Q1`).
///
/// The dump is written beside [file] and moved onto it whole, so a file of
/// that name is a dump that is done. Windows only.
void main(List<String> args) {
  final pid = int.parse(args[0]);
  final file = args[1];
  final part = '$file.part';
  final process = _openProcess(_canBeDumped, 0, pid);
  if (process == 0) {
    stderr.writeln('native call watch: process $pid would not open');
    exit(1);
  }
  final name = part.toNativeUtf16();
  final out = _createFile(
    name,
    _genericWrite,
    0,
    nullptr,
    _createAlways,
    _fileAttributeNormal,
    0,
  );
  calloc.free(name);
  if (out == _invalidHandle) {
    _closeHandle(process);
    stderr.writeln('native call watch: $part would not open');
    exit(1);
  }
  final written =
      _writeDump(process, pid, out, _whatIsKept, nullptr, nullptr, nullptr);
  _closeHandle(out);
  _closeHandle(process);
  if (written == 0) {
    stderr.writeln('native call watch: the dump of $pid was not written');
    exit(1);
  }
  File(part).renameSync(file);
}

/// What the dump keeps: the threads' stacks and what they point at, the
/// handles they wait on, the modules loaded and unloaded, and the memory
/// map — not the heap. 🔬A test's process dumped this way (2026-10-17, the
/// Surface): 368 KB, written in 1.1 s.
const _whatIsKept =
    0x4 | // MiniDumpWithHandleData
    0x20 | // MiniDumpWithUnloadedModules
    0x40 | // MiniDumpWithIndirectlyReferencedMemory
    0x800 | // MiniDumpWithFullMemoryInfo
    0x1000; // MiniDumpWithThreadInfo

/// PROCESS_QUERY_INFORMATION | PROCESS_VM_READ | PROCESS_DUP_HANDLE — what
/// `MiniDumpWriteDump` reads a process with, the handles included.
const _canBeDumped = 0x0400 | 0x0010 | 0x0040;

const _genericWrite = 0x40000000;
const _createAlways = 2;
const _fileAttributeNormal = 0x80;
const _invalidHandle = -1;

final _kernel32 = DynamicLibrary.open('kernel32.dll');

final _openProcess = _kernel32.lookupFunction<
  IntPtr Function(Uint32, Int32, Uint32),
  int Function(int, int, int)
>('OpenProcess');

final _createFile = _kernel32.lookupFunction<
  IntPtr Function(
    Pointer<Utf16>,
    Uint32,
    Uint32,
    Pointer<Void>,
    Uint32,
    Uint32,
    IntPtr,
  ),
  int Function(Pointer<Utf16>, int, int, Pointer<Void>, int, int, int)
>('CreateFileW');

final _closeHandle = _kernel32
    .lookupFunction<Int32 Function(IntPtr), int Function(int)>('CloseHandle');

final _writeDump = DynamicLibrary.open('dbghelp.dll').lookupFunction<
  Int32 Function(
    IntPtr,
    Uint32,
    IntPtr,
    Int32,
    Pointer<Void>,
    Pointer<Void>,
    Pointer<Void>,
  ),
  int Function(int, int, int, int, Pointer<Void>, Pointer<Void>, Pointer<Void>)
>('MiniDumpWriteDump');
