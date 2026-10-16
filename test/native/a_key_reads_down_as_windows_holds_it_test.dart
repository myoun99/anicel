import 'dart:ffi';
import 'dart:io' show Platform;

import 'package:anicel/src/native/windows_key_state.dart';
import 'package:ffi/ffi.dart';
import 'package:flutter_test/flutter_test.dart';

/// `windowsKeyIsDown` reads `GetKeyState` as Windows means it — down is the
/// high bit of the SHORT it answers — because on Windows it is what decides
/// whether Shift is held under a pen (I-61, `ModifierKeys`), and no test
/// with a stand-in for it would see it read the wrong bit.
///
/// The key is held on THIS thread's own table (`SetKeyboardState`, which
/// changes no other thread's input and no key of the machine), and put back
/// as it was.
void main() {
  test('a key reads down exactly while Windows holds it for this thread — '
      'and where there is no Windows, none is', () {
    const modifiers = [
      vkShift,
      vkControl,
      vkMenu,
      vkLeftWindows,
      vkRightWindows,
    ];
    if (!Platform.isWindows) {
      for (final key in modifiers) {
        expect(windowsKeyIsDown(key), isFalse, reason: 'virtual key $key');
      }
      return;
    }
    final user32 = DynamicLibrary.open('user32.dll');
    final getTable = user32
        .lookupFunction<
          Int32 Function(Pointer<Uint8>),
          int Function(Pointer<Uint8>)
        >('GetKeyboardState');
    final setTable = user32
        .lookupFunction<
          Int32 Function(Pointer<Uint8>),
          int Function(Pointer<Uint8>)
        >('SetKeyboardState');
    final kept = calloc<Uint8>(256);
    final table = calloc<Uint8>(256);
    try {
      expect(getTable(kept), isNonZero, reason: 'premise: a table to read');
      for (final key in modifiers) {
        for (var at = 0; at < 256; at += 1) {
          table[at] = kept[at] & 0x01;
        }
        table[key] = 0x80;
        expect(setTable(table), isNonZero, reason: 'premise: it was taken');
        for (final other in modifiers) {
          expect(
            windowsKeyIsDown(other),
            other == key,
            reason: 'virtual key $other with $key held',
          );
        }
      }
    } finally {
      setTable(kept);
      calloc.free(table);
      calloc.free(kept);
    }
  });
}
