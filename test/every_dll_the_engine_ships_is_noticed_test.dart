import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

/// Every DLL the GPU engine's build hook ships beside the engine on Windows
/// is NOTICED (관제 2026-11-07, connection-round-checklist A 📜): listed in
/// THIRD_PARTY.md, and shown in the app's About ▸ licenses screen under
/// every licence text of the pinned zip it comes from. The texts are held to
/// the digests packages/gpu_engine/rust/build.rs checks the zip's against,
/// so a newer zip turns the build red, and the build's new digests turn this
/// red until the texts are bundled again.
///
/// Every path is a literal, so a change under any of them runs this.
void main() {
  final hook = File('packages/gpu_engine/hook/build.dart').readAsStringSync();
  final build = File('packages/gpu_engine/rust/build.rs').readAsStringSync();
  final shipped = {
    for (final match in RegExp(r"'([\w-]+\.dll)'").allMatches(hook))
      match[1]!,
  };

  test('every DLL the hook ships is pinned and listed', () {
    final pinned = {
      for (final match in RegExp(
        r'"bin/\w+/([\w-]+\.dll)"',
      ).allMatches(build))
        match[1]!,
    };
    final thirdParty = File('THIRD_PARTY.md').readAsStringSync();
    expect(shipped, isNotEmpty);
    for (final dll in shipped) {
      expect(pinned, contains(dll), reason: '$dll ships from no pinned zip');
      expect(thirdParty, contains('`$dll`'), reason: '$dll ships unlisted');
    }
  });

  // ⛔The app asks no one to agree to the Microsoft terms in the zip
  // because the user reads them as the closed-source dxil.dll's, which it
  // does not ship (유저 2026-11-07, gpu-engine-feasibility-Q6; 관제 21:46).
  // Shipping it is that question asked again, not a DLL to notice.
  test('the hook ships no dxil.dll, whose terms the app asks no one to '
      'agree to', () {
    expect(shipped, isNotEmpty);
    expect(
      shipped,
      isNot(contains('dxil.dll')),
      reason: 'ask the user gpu-engine-feasibility-Q6 again before it ships',
    );
  });

  test('the app bundles every licence text of the pinned zip', () {
    final pinned = {
      for (final match in RegExp(
        r'\("[\w.-]+\.txt", "([0-9a-f]{64})"\)',
      ).allMatches(build))
        match[1]!,
    };
    // The text as git keeps it: without carriage returns, as build.rs
    // digests the zip's.
    final bundled = {
      for (final file in Directory('assets/licenses').listSync())
        if (file is File &&
            file.uri.pathSegments.last.startsWith('LICENSE-DXC-'))
          sha256.convert([
            for (final byte in file.readAsBytesSync())
              if (byte != 13) byte,
          ]).toString(),
    };
    expect(pinned, isNotEmpty);
    expect(bundled, pinned);
  });
}
