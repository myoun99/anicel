import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

/// The file modes dart:io has no call for, set in-process — a test may not
/// spawn `attrib` or `chmod` (`tests_do_not_race_the_code_test`).

/// Marks [path] read-only, or writable again. False when the OS refused.
bool setReadOnly(String path, {required bool on}) => Platform.isWindows
    // FILE_ATTRIBUTE_READONLY, or FILE_ATTRIBUTE_NORMAL to clear it.
    ? _setAttributes(path, on ? 0x1 : 0x80)
    : _chmod(path, on ? 0x124 : 0x1A4); // 0444, 0644

/// Makes the file at [path] one the OS refuses to DELETE, or deletable
/// again. Windows refuses a read-only file; elsewhere unlinking is its
/// folder's to allow, so the folder goes read-only (0555). False where
/// nothing can be refused — root may delete anything.
bool setUndeletable(String path, {required bool on}) {
  if (Platform.isWindows) {
    return setReadOnly(path, on: on);
  }
  if (on && _getuid() == 0) {
    return false;
  }
  return _chmod(File(path).parent.path, on ? 0x16D : 0x1ED); // 0555, 0755
}

bool _setAttributes(String path, int attributes) => using((arena) {
  final setAttributes = DynamicLibrary.open('kernel32.dll')
      .lookupFunction<
        Int32 Function(Pointer<Utf16>, Uint32),
        int Function(Pointer<Utf16>, int)
      >('SetFileAttributesW');
  return setAttributes(path.toNativeUtf16(allocator: arena), attributes) != 0;
});

bool _chmod(String path, int mode) => using((arena) {
  final chmod = DynamicLibrary.process()
      .lookupFunction<
        Int32 Function(Pointer<Utf8>, Uint32),
        int Function(Pointer<Utf8>, int)
      >('chmod');
  return chmod(path.toNativeUtf8(allocator: arena), mode) == 0;
});

int _getuid() => DynamicLibrary.process()
    .lookupFunction<Uint32 Function(), int Function()>('getuid')();
