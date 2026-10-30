/// An fx plugin's file (anicel_fx_plugin.h, THE FILE): the module every
/// device runs, and the native builds of the same source a desktop may run
/// instead (🗣️I-132-Q5 b, 유저 2026-10-27: 「a + 데스크톱은 같은 규격의
/// 네이티브(.dll · .dylib)도」).
library;

import 'dart:ffi' show Abi;
import 'dart:typed_data';

import 'package:archive/archive.dart';

/// The extension of an fx plugin's file — one of the app's own, named as
/// its others are (`anibrush` · `anipalette`).
const String anicelFxPluginExtension = 'anifx';

/// What an fx plugin's file holds for this device: its module, and the
/// native build of its own where the file has one.
typedef FxPluginBundle = ({Uint8List wasm, Uint8List? native});

/// Where a plugin's file keeps the module.
const String fxPluginWasmEntry = 'plugin.wasm';

/// Where a plugin's file keeps the native build for [abi] — null where
/// [abi] takes none: a phone or a tablet runs the module alone.
String? fxPluginNativeEntryFor(Abi abi) => switch (abi) {
  Abi.windowsX64 => 'native/windows-x64.dll',
  Abi.windowsArm64 => 'native/windows-arm64.dll',
  Abi.macosArm64 || Abi.macosX64 => 'native/macos.dylib',
  Abi.linuxX64 => 'native/linux-x64.so',
  Abi.linuxArm64 => 'native/linux-arm64.so',
  _ => null,
};

/// [bytes] read as a plugin's file for [abi] (this device's where none is
/// named) — null where they are no zip, or one without the module.
FxPluginBundle? readFxPluginBundle(Uint8List bytes, {Abi? abi}) {
  final Archive archive;
  try {
    archive = ZipDecoder().decodeBytes(bytes);
  } on Object {
    return null;
  }
  Uint8List? entry(String? name) =>
      name == null ? null : archive.findFile(name)?.readBytes();

  final wasm = entry(fxPluginWasmEntry);
  if (wasm == null) {
    return null;
  }
  final native = entry(fxPluginNativeEntryFor(abi ?? Abi.current()));
  return (wasm: wasm, native: native);
}
