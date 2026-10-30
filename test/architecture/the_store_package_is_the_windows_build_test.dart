import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 🗣️store-distribution-plan-Q2 (유저 2026-10-30 「MS 스토어도 지금 시작」):
/// the Microsoft Store package is the Windows release build, packed by
/// `tool/msix_pack.sh` with `windows/msix/AppxManifest.xml`. Only the
/// control tower's round runs that script, so what would fail first at
/// Partner Center is read here.
void main() {
  final manifest = File('windows/msix/AppxManifest.xml').readAsStringSync();
  final script = File('tool/msix_pack.sh').readAsStringSync();

  test('the manifest starts the executable the Windows build makes', () {
    final binary = RegExp(r'set\(BINARY_NAME "([^"]+)"\)')
        .firstMatch(File('windows/CMakeLists.txt').readAsStringSync())
        ?.group(1);
    expect(binary, isNotNull);
    expect(manifest, contains('Executable="$binary.exe"'));
  });

  test('every logo the manifest names is drawn at a scale the index picks',
      () {
    final names = RegExp(r'(?:Logo>|Logo=")Assets\\([A-Za-z0-9]+)\.png')
        .allMatches(manifest)
        .map((m) => m[1]!)
        .toSet();
    expect(names, {'StoreLogo', 'Square150x150Logo', 'Square44x44Logo'});
    final drawn = Directory('windows/msix/Assets')
        .listSync()
        .map((f) => f.uri.pathSegments.last)
        .toList();
    for (final name in names) {
      expect(
        drawn.where((f) => f.startsWith('$name.scale-')),
        isNotEmpty,
        reason: name,
      );
    }
  });

  test('the script fills every value the manifest leaves open', () {
    final open = RegExp(r'@([A-Z_]+)@')
        .allMatches(manifest)
        .map((m) => m[1]!)
        .toSet();
    expect(open, {'NAME', 'PUBLISHER', 'PUBLISHER_DISPLAY_NAME', 'VERSION'});
    for (final value in open) {
      expect(script, contains('s|@$value@|'), reason: value);
    }
  });

  test('the version is one the Store takes: four parts, the first not 0, '
      'the fourth 0', () {
    final version = RegExp(r'^version="([^"]+)"', multiLine: true)
        .firstMatch(script)
        ?.group(1);
    expect(version, isNotNull, reason: 'the script names it on one line');
    final parts = version!.split('.');
    expect(parts, hasLength(4));
    expect(parts.first, isNot('0'));
    expect(parts.last, '0');
  });
}
