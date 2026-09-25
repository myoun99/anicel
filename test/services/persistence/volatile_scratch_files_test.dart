import 'dart:io';
import 'dart:typed_data';

import 'package:anicel/src/services/persistence/scratch_cel_files.dart';
import 'package:anicel/src/services/persistence/scratch_file.dart';
import 'package:anicel/src/services/persistence/session_scratch.dart';
import 'package:anicel/src/services/persistence/volatile_scratch_files.dart';
import 'package:flutter_test/flutter_test.dart';

/// 🚨THE TWO ROOMS MUST NOT BECOME ONE. A cooled cel is unsaved work
/// waiting to move into the project file; an undo payload names a history
/// that dies with its isolate. They share the file MECHANISM and nothing
/// else — and the day something deletes "the scratch" instead of naming
/// what it deletes is the day an undo silently stops working.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Uint8List bytes(int n) => Uint8List.fromList(List<int>.filled(n, 7));

  test('an undo payload lands in the VOLATILE room, a cel in the staged '
      'one — the save deletes one and must not reach the other', () {
    final undo = VolatileScratchFiles.write(bytes(16));
    final cel = ScratchCelFiles.write(
      ScratchCelFiles.newNamespace(),
      'cels/abc.celz',
      bytes(16),
    );

    expect(undo, isNotNull);
    expect(cel, isNotNull);
    expect(undo, contains('/Volatile/'));
    expect(cel, contains('/Staged/'));
    expect(
      File(undo!).parent.path,
      isNot(File(cel!).parent.path),
      reason: 'one verb that emptied a shared folder would take both',
    );
  });

  test('what was written reads back byte for byte', () {
    final payload = Uint8List.fromList([1, 2, 3, 250, 0, 99]);
    final path = VolatileScratchFiles.write(payload)!;
    expect(ScratchFile.read(path), payload);
  });

  test('every payload gets its own file — one run parks many', () {
    final first = VolatileScratchFiles.write(bytes(4))!;
    final second = VolatileScratchFiles.write(bytes(4))!;
    expect(first, isNot(second));
    expect(File(first).existsSync(), isTrue);
    expect(File(second).existsSync(), isTrue);
  });

  test('a payload that is gone reads as null rather than a blank', () {
    final path = VolatileScratchFiles.write(bytes(8))!;
    ScratchFile.remove(path);
    // 🚨Null is a LOST STEP the caller has to report, not a cache miss it
    // may paper over: whatever was parked here is already dropped.
    expect(ScratchFile.read(path), isNull);
  });

  test('removing what is not there is silent — the room outlives the file',
      () {
    expect(
      () => ScratchFile.remove(
        '${SessionScratch.volatileFolder()}/never-written.undo',
      ),
      returnsNormally,
    );
  });

  group('the mechanism refuses rather than throws', () {
    test('a write with nowhere to land answers null, so the caller can '
        'KEEP what it was going to park', () {
      // A path whose parent cannot be made: an existing FILE stands where
      // the folder would go.
      final blocker = File('${SessionScratch.volatileFolder()}/blocker')
        ..writeAsBytesSync(bytes(1));
      expect(ScratchFile.write('${blocker.path}/child.undo', bytes(4)), isNull);
    });

    test('a read of a folder answers null', () {
      expect(ScratchFile.read(SessionScratch.volatileFolder()), isNull);
    });

    test('the write leaves no .part behind on success', () {
      final path = VolatileScratchFiles.write(bytes(32))!;
      expect(File('$path.part').existsSync(), isFalse);
    });
  });
}
