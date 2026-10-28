import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

import '../services/feedback/feedback_forms.dart';

/// The device the app runs on, as the feedback forms ask for it (I-139):
/// read straight from each OS — the registry on Windows, the system
/// properties on Android, `sysctl` on iOS and the Mac, the kernel's files on
/// Linux — as `DeviceBattery` asks Windows and Linux straight.
///
/// ⚠️`Platform.operatingSystemVersion` does not answer it: on Android it is
/// the kernel's version, not Android's, and on Windows 11 it still says
/// Windows 10. And no package names a Windows PC's model.
///
/// What cannot be read says [unknown] rather than nothing: the forms make
/// every field required, and a blank one would stop the sender at it.
abstract final class DeviceDescriptions {
  static const unknown = 'Unknown';

  static DeviceDescription read() {
    if (Platform.isWindows) return _windows();
    if (Platform.isAndroid) return _android();
    if (Platform.isIOS) return _ios();
    if (Platform.isMacOS) return _macOS();
    return _linux();
  }

  static DeviceDescription _windows() => (
    model: _or(() {
      const bios = r'HARDWARE\DESCRIPTION\System\BIOS';
      return joinedModel(
        _registryString(bios, 'SystemManufacturer'),
        _registryString(bios, 'SystemProductName'),
      );
    }),
    os: FeedbackOs.windows,
    osVersion: _or(() {
      const current = r'SOFTWARE\Microsoft\Windows NT\CurrentVersion';
      return windowsVersion(
        build: _registryString(current, 'CurrentBuild'),
        release: _registryString(current, 'DisplayVersion'),
        update: _registryNumber(current, 'UBR'),
      );
    }),
  );

  static DeviceDescription _android() => (
    model: _or(
      () => joinedModel(
        _systemProperty('ro.product.manufacturer'),
        _systemProperty('ro.product.model'),
      ),
    ),
    os: FeedbackOs.android,
    osVersion: _or(() => _systemProperty('ro.build.version.release')),
  );

  static DeviceDescription _ios() {
    final model = _or(() => _sysctl('hw.machine'));
    return (
      model: model,
      os: model.startsWith('iPad') ? FeedbackOs.iPadOS : FeedbackOs.iOS,
      osVersion: _or(() => _sysctl('kern.osproductversion')),
    );
  }

  static DeviceDescription _macOS() => (
    model: _or(() => _sysctl('hw.model')),
    os: FeedbackOs.macOS,
    osVersion: _or(() => _sysctl('kern.osproductversion')),
  );

  static DeviceDescription _linux() => (
    model: _or(() {
      String? line(String name) =>
          File('/sys/class/dmi/id/$name').readAsStringSync().trim();
      return joinedModel(line('sys_vendor'), line('product_name'));
    }),
    os: FeedbackOs.linux,
    osVersion: _or(
      () => prettyNameIn(File('/etc/os-release').readAsStringSync()),
    ),
  );

  /// [read]'s answer, or [unknown] where it failed or came back empty.
  static String _or(String? Function() read) {
    try {
      final value = read()?.trim();
      return value == null || value.isEmpty ? unknown : value;
    } on Object {
      return unknown;
    }
  }

  /// `Microsoft Corporation` + `Surface Pro, 11th Edition` — the maker once,
  /// where the model already starts with it (`LENOVO` + `Lenovo TB-X606F`).
  static String? joinedModel(String? maker, String? model) {
    final m = _named(maker);
    final name = _named(model);
    if (name.isEmpty) return m.isEmpty ? null : m;
    if (m.isEmpty || name.toLowerCase().startsWith(m.toLowerCase())) {
      return name;
    }
    return '$m $name';
  }

  /// [value], or empty where it is a board maker's blank-to-fill.
  ///
  /// 🧪The main PC (2026-10-28), a self-built desktop, reads
  /// `To Be Filled By O.E.M.` · `Z690 Steel Legend/D5`: the maker field is
  /// a placeholder the BIOS ships with, and says nothing about the device.
  /// The others are the same blank under other boards' wording.
  static String _named(String? value) {
    final v = value?.trim() ?? '';
    return _placeholders.contains(v.toLowerCase()) ? '' : v;
  }

  static const _placeholders = {
    'to be filled by o.e.m.',
    'system manufacturer',
    'system product name',
    'default string',
    'not applicable',
  };

  /// `11 25H2 (26200.6899)`. Windows 11 still calls itself 10.0 — its
  /// builds from 22000 on are 11 (Microsoft's own line between the two).
  static String? windowsVersion({
    required String? build,
    String? release,
    int? update,
  }) {
    final number = int.tryParse(build ?? '');
    if (number == null) return null;
    final major = number >= 22000 ? '11' : '10';
    final named = release == null || release.isEmpty ? '' : ' $release';
    final full = update == null ? '$number' : '$number.$update';
    return '$major$named ($full)';
  }

  /// `PRETTY_NAME` from an `/etc/os-release` [text], quotes taken off.
  static String? prettyNameIn(String text) {
    for (final line in text.split('\n')) {
      if (!line.startsWith('PRETTY_NAME=')) continue;
      final value = line.substring('PRETTY_NAME='.length).trim();
      return value.replaceAll(RegExp(r'^"|"$'), '');
    }
    return null;
  }

  static String? _registryString(String key, String value) => _registry(
    key,
    value,
    _rrfRtRegSz,
    (data) => data.cast<Utf16>().toDartString(),
  );

  static int? _registryNumber(String key, String value) => _registry(
    key,
    value,
    _rrfRtRegDword,
    (data) => data.cast<Uint32>().value,
  );

  /// [value] under [key] in `HKEY_LOCAL_MACHINE`, of the type [flag] asks
  /// for, as [read] takes it out of the bytes; null where there is none.
  static R? _registry<R>(
    String key,
    String value,
    int flag,
    R Function(Pointer<Uint8>) read,
  ) {
    final size = calloc<Uint32>()..value = _registryBytes;
    final data = calloc<Uint8>(_registryBytes);
    final k = key.toNativeUtf16();
    final v = value.toNativeUtf16();
    try {
      final status = _regGetValue(_hklm, k, v, flag, nullptr, data.cast(),
          size);
      return status == 0 ? read(data) : null;
    } finally {
      calloc
        ..free(size)
        ..free(data)
        ..free(k)
        ..free(v);
    }
  }

  static const int _registryBytes = 512;

  static String? _systemProperty(String name) {
    final key = name.toNativeUtf8();
    final value = calloc<Uint8>(_propValueMax);
    try {
      final length = _systemPropertyGet(key, value.cast());
      return length > 0 ? value.cast<Utf8>().toDartString() : null;
    } finally {
      calloc
        ..free(key)
        ..free(value);
    }
  }

  static String? _sysctl(String name) {
    final key = name.toNativeUtf8();
    final size = calloc<Size>();
    try {
      if (_sysctlByName(key, nullptr, size, nullptr, 0) != 0) return null;
      final value = calloc<Uint8>(size.value + 1);
      try {
        if (_sysctlByName(key, value.cast(), size, nullptr, 0) != 0) {
          return null;
        }
        return value.cast<Utf8>().toDartString();
      } finally {
        calloc.free(value);
      }
    } finally {
      calloc
        ..free(key)
        ..free(size);
    }
  }

  /// `HKEY_LOCAL_MACHINE`: `(HKEY)(LONG)0x80000002`, sign-extended to the
  /// handle's width as the C headers have it. 🧪The zero-extended handle
  /// reads the same on the main PC (a surviving mutant, 2026-10-28) — the
  /// headers' spelling is kept, not because the other fails.
  static final _hklm = Pointer<Void>.fromAddress(0x80000002 - 0x100000000);
  static const int _rrfRtRegSz = 0x2;
  static const int _rrfRtRegDword = 0x10;

  /// `PROP_VALUE_MAX` (sys/system_properties.h).
  static const int _propValueMax = 92;

  static final _regGetValue = DynamicLibrary.open('advapi32.dll')
      .lookupFunction<
        Int32 Function(
          Pointer<Void>,
          Pointer<Utf16>,
          Pointer<Utf16>,
          Uint32,
          Pointer<Uint32>,
          Pointer<Void>,
          Pointer<Uint32>,
        ),
        int Function(
          Pointer<Void>,
          Pointer<Utf16>,
          Pointer<Utf16>,
          int,
          Pointer<Uint32>,
          Pointer<Void>,
          Pointer<Uint32>,
        )
      >('RegGetValueW');

  static final _systemPropertyGet = DynamicLibrary.open('libc.so')
      .lookupFunction<
        Int32 Function(Pointer<Utf8>, Pointer<Utf8>),
        int Function(Pointer<Utf8>, Pointer<Utf8>)
      >('__system_property_get');

  static final _sysctlByName = DynamicLibrary.process()
      .lookupFunction<
        Int32 Function(Pointer<Utf8>, Pointer<Void>, Pointer<Size>,
            Pointer<Void>, Size),
        int Function(Pointer<Utf8>, Pointer<Void>, Pointer<Size>,
            Pointer<Void>, int)
      >('sysctlbyname');
}
