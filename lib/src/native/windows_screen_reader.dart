import 'dart:ffi';
import 'dart:io' show Platform;

import 'package:ffi/ffi.dart';

/// Whether Windows says a screen reader is running: the system flag that
/// Narrator, NVDA and JAWS raise while they run (`SPI_GETSCREENREADER`).
/// False wherever it cannot be asked — every platform but Windows.
///
/// Asked of `user32` straight, not through the app's engine: the answer is
/// wanted while the app's binding is still being made, and user32 is there
/// on every Windows the app runs on.
bool windowsScreenReaderRunning() {
  if (!Platform.isWindows) {
    return false;
  }
  try {
    final ask = DynamicLibrary.open('user32.dll').lookupFunction<
      Int32 Function(Uint32, Uint32, Pointer<Int32>, Uint32),
      int Function(int, int, Pointer<Int32>, int)
    >('SystemParametersInfoW');
    final running = calloc<Int32>();
    try {
      return ask(_spiGetScreenReader, 0, running, 0) != 0 && running.value != 0;
    } finally {
      calloc.free(running);
    }
  } on Object {
    return false;
  }
}

/// `SPI_GETSCREENREADER` (winuser.h).
const int _spiGetScreenReader = 0x0046;
