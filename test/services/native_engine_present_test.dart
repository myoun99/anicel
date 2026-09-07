import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/native/qa_cel_compressor.dart';

import '../helpers/native_engine_path.dart';

/// The guard that makes every OTHER parity suite trustworthy.
///
/// Byte-parity pins skip when no native binary is around, which is right
/// for a laptop without cmake — but in a CI summary a skipped suite and a
/// passing one look exactly the same. This project has been bitten by that
/// twice:
///
///  - #614: the pins hardcoded a Windows path, so on macOS and Linux they
///    could only ever skip. The first run that actually executed on Apple
///    silicon immediately found the engine rendering 182 where the
///    reference says 181.
///  - The Linux job built no engine at all — the gcc build lives in a
///    different job whose artifacts were never in that workspace — so every
///    pin had been skipping there since it was written.
///
/// Both were invisible because nothing asserted that the pins RAN. Every CI
/// job that builds a binary now sets `QA_REQUIRE_NATIVE=1`, and this test
/// turns a missing engine into a failure that names itself.
void main() {
  test('CI has a native engine, so the parity suites actually ran', () {
    final path = nativeEngineLibraryPathOrNull();
    expect(
      path,
      isNotNull,
      reason:
          'QA_REQUIRE_NATIVE=1 says this job builds a native engine, but no '
          'binary was found. Every byte-parity suite in this run therefore '
          'SKIPPED, and a skipped parity suite proves nothing. Check that '
          'the cmake build step ran and put its output where '
          'nativeEngineLibraryPathOrNull() looks.',
    );
  }, skip: nativeEngineRequired
      ? false
      : 'only enforced where CI builds an engine (QA_REQUIRE_NATIVE=1)');

  test('🚨 and PRODUCTION\'s resolver finds the same one this helper does',
      () {
    // ⛔**THE HOLE THE TEST ABOVE COULD NOT SEE** (2026-09-08).「Where is
    // the engine」had TWO answers. This helper looks under
    // `build/native_standalone`, so the suites that ask IT ran; the suites
    // gated on `QaCelCompressor.instance` ask `openQaEngineLibrary`, which
    // tries `QA_ENGINE_PATH` and then the bare library name beside the
    // executable — and `flutter test` has neither. So 27 pins over the zstd
    // block frames, the carried conform and the staged blob skipped
    // SILENTLY with the DLL sitting right there, and when the engine was
    // finally forced on, nine of them were RED.
    //
    // `flutter_test_config.dart` now points the production resolver at what
    // this helper finds. This is what says the two never drift apart again:
    // it asks the question in the direction that can fail — a build exists,
    // so production must see it.
    //
    // ⚠️Skips only when there is no engine at all, which is the laptop
    // case the corpus deliberately supports. It does NOT skip when the
    // wiring is missing, which is the bug.
    final built = nativeEngineLibraryPathOrNull();
    expect(
      QaCelCompressor.instance?.isSupported ?? false,
      isTrue,
      reason:
          'a native engine is built at $built, but the resolver production '
          'uses could not open one — the parity pins that gate on it are '
          'silently skipping. Check `debugQaEngineLibraryPathOverride` in '
          'test/flutter_test_config.dart.',
    );
  }, skip: nativeEngineLibraryPathOrNull() == null
      ? 'no engine built here — nothing for the two resolvers to disagree '
            'about'
      : false);
}
