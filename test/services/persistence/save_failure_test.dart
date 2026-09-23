import 'dart:ffi';
import 'dart:io';

import 'package:anicel/src/services/persistence/save_failure.dart';
import 'package:ffi/ffi.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/temp_dir.dart';

/// 🗣️유저 2026-09-23 (whole-write-temp-beside-the-file Q2): 「왜
/// 실패했는지(파일을 잡고있어서)같은것들 정확하게 알기쉽게 명시」. The reason
/// is read off the platform's own error number — and on Windows the numbers
/// were MEASURED before they were written down (2026-09-23): a rename onto a
/// file another process holds answers 5, not 32; an append onto it answers
/// 32; a read-only file answers 5 to both and reports mode 444.
void main() {
  late Directory folder;

  setUp(() {
    folder = Directory.systemTemp.createTempSync('anicel-save-failure');
  });

  tearDown(() => deleteTempQuietly(folder));

  FileSystemException refused(int code) =>
      FileSystemException('refused', 'x', OSError('refused', code));

  SaveFailureCause windows(int code, {String? projectPath}) =>
      saveFailureCauseOf(
        refused(code),
        projectPath: projectPath ?? '${folder.path}/missing.anicel',
        onWindows: true,
      );

  SaveFailureCause posix(int code) => saveFailureCauseOf(
    refused(code),
    projectPath: '${folder.path}/missing.anicel',
    onWindows: false,
  );

  test('Windows: a sharing or lock violation is another program holding '
      'the file', () {
    expect(windows(32), SaveFailureCause.fileInUse);
    expect(windows(33), SaveFailureCause.fileInUse);
  });

  test('🚨Windows: access denied is 「in use」 when the file itself is '
      'writable — a rename onto a held file answers 5 — and 「read-only」 '
      'when it is not there to hold', () {
    final writable = File('${folder.path}/project.anicel')
      ..writeAsStringSync('x');

    expect(
      windows(5, projectPath: writable.path),
      SaveFailureCause.fileInUse,
    );
    expect(
      windows(5, projectPath: '${folder.path}/missing.anicel'),
      SaveFailureCause.readOnly,
      reason: 'nothing to hold — the folder refused',
    );
  });

  test('🚨Windows: access denied on a file that IS there but read-only is '
      '「read-only」 — nothing holds it, it cannot be written', () {
    final readOnly = File('${folder.path}/locked.anicel')
      ..writeAsStringSync('x');
    _setReadOnly(readOnly.path, on: true);
    addTearDown(() => _setReadOnly(readOnly.path, on: false));

    expect(
      windows(5, projectPath: readOnly.path),
      SaveFailureCause.readOnly,
    );
  });

  test('Windows: the rest of the numbers', () {
    expect(windows(19), SaveFailureCause.readOnly);
    expect(windows(112), SaveFailureCause.diskFull);
    expect(windows(39), SaveFailureCause.diskFull);
    for (final gone in [2, 3, 15, 21, 53, 64, 67, 1167, 1231]) {
      expect(windows(gone), SaveFailureCause.locationGone, reason: '$gone');
    }
    expect(windows(1), SaveFailureCause.unknown);
  });

  test('POSIX reads the same numbers its own way', () {
    expect(posix(16), SaveFailureCause.fileInUse);
    expect(posix(26), SaveFailureCause.fileInUse);
    for (final denied in [1, 13, 30]) {
      expect(posix(denied), SaveFailureCause.readOnly, reason: '$denied');
    }
    for (final full in [28, 122, 69]) {
      expect(posix(full), SaveFailureCause.diskFull, reason: '$full');
    }
    for (final gone in [2, 6, 19]) {
      expect(posix(gone), SaveFailureCause.locationGone, reason: '$gone');
    }
    expect(
      posix(5),
      SaveFailureCause.unknown,
      reason: '5 is an I/O error on POSIX, not access denied',
    );
  });

  test('a provider that refused the replace is its own reason, whatever '
      'else the error carries', () {
    final refusal = SaveNotSwappedIn(
      archive: '${folder.path}/a.anicel.tmp-1',
      error: const FileSystemException('refused', 'x'),
      refusedByProvider: true,
    );

    expect(
      saveFailureCauseOf(refusal, projectPath: 'x', onWindows: true),
      SaveFailureCause.replaceRefused,
    );
  });

  test('an archive a rename could not swap in keeps the reason the rename '
      'gave', () {
    final refusal = SaveNotSwappedIn(
      archive: '${folder.path}/a.anicel.tmp-1',
      error: refused(32),
    );

    expect(refusal, isA<FileSystemException>(), reason: 'Android falls back '
        'to the staging road on exactly that type');
    expect(
      saveFailureCauseOf(refusal, projectPath: 'x', onWindows: true),
      SaveFailureCause.fileInUse,
    );
  });

  test('what carries no number says nothing it does not know', () {
    expect(
      saveFailureCauseOf(StateError('x'), projectPath: 'x', onWindows: true),
      SaveFailureCause.unknown,
    );
    expect(
      saveFailureCauseOf(
        const FileSystemException('no os error'),
        projectPath: 'x',
        onWindows: true,
      ),
      SaveFailureCause.unknown,
    );
  });
}

/// Marks [path] read-only, or writable again — in-process: dart:io has no
/// call for it, and a test may not spawn `attrib` or `chmod`
/// (`tests_do_not_race_the_code_test`).
void _setReadOnly(String path, {required bool on}) {
  using((arena) {
    if (Platform.isWindows) {
      final setAttributes = DynamicLibrary.open('kernel32.dll')
          .lookupFunction<
            Int32 Function(Pointer<Utf16>, Uint32),
            int Function(Pointer<Utf16>, int)
          >('SetFileAttributesW');
      final done = setAttributes(
        path.toNativeUtf16(allocator: arena),
        // FILE_ATTRIBUTE_READONLY, or FILE_ATTRIBUTE_NORMAL to clear it.
        on ? 0x1 : 0x80,
      );
      expect(done, isNot(0), reason: 'SetFileAttributesW refused $path');
    } else {
      final chmod = DynamicLibrary.process()
          .lookupFunction<
            Int32 Function(Pointer<Utf8>, Uint32),
            int Function(Pointer<Utf8>, int)
          >('chmod');
      final mode = on ? 0x124 : 0x1A4; // 0444, 0644
      expect(chmod(path.toNativeUtf8(allocator: arena), mode), 0);
    }
  });
}
