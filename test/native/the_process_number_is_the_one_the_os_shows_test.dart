import 'dart:io';
import 'dart:typed_data';

import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/native/qa_engine_abi.dart';
import 'package:anicel/src/native/qa_native_engine.dart';
import 'package:anicel/src/ui/diagnostics/memory_census.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/native_engine_path.dart';

/// 🚨THE PANEL'S BIG NUMBER MUST BE THE ONE THE USER IS LOOKING AT.
///
/// 유저 2026-09-10: 「같은수로 하고싶은데 다른 멀티플랫폼도 같아지는건가?」 —
/// the memory readout used to print `ProcessInfo.currentRss`, which is
/// `WorkingSet64` and counts pages SHARED with other processes, so it read
/// 194.8MB where 작업 관리자 said 139.3MB on the same instant. Every platform
/// has a private-footprint number instead, and each is what that OS's own
/// task manager shows.
///
/// ⛔A BEHAVIOUR TEST CANNOT SEE THIS. The census would happily report RSS
/// forever: the fallback is real and returns a plausible number. What has
/// to be pinned is that the ENGINE answers on the platform running this —
/// so this suite lives beside the other native ones and needs the binary.
///
/// 🧪The differential is the part that says WHICH number it is: touch N
/// bytes of private memory and the reading must move by about N. RSS moves
/// too, so that alone would not separate them; the Windows arm adds the
/// separation directly, where a mapped DLL is always in the working set
/// and never in the private one.
void main() {
  // The census reads `PaintingBinding.instance.imageCache`, so the binding
  // has to exist before it can be collected.
  TestWidgetsFlutterBinding.ensureInitialized();
  final libraryPath = nativeEngineLibraryPathOrNull();
  if (libraryPath == null) {
    test(
      'the process footprint answers here',
      () {},
      skip: nativeEngineMissingSkipReason,
    );
    return;
  }

  late QaNativeEngine engine;

  setUpAll(() {
    debugQaEngineLibraryPathOverride = libraryPath;
    QaNativeEngine.debugResetForTests();
    final loaded = QaNativeEngine.instance;
    expect(
      loaded,
      isNotNull,
      reason:
          'the engine at $libraryPath did not load — an ABI mismatch '
          'after a bump is the usual cause; rebuild the standalone binary',
    );
    engine = loaded!;
  });

  tearDownAll(() {
    debugQaEngineLibraryPathOverride = null;
    QaNativeEngine.debugResetForTests();
  });

  test('this platform answers the process footprint at all', () {
    expect(
      engine.processFootprintBytes,
      isNotNull,
      reason:
          'null means the arm for ${Platform.operatingSystem} still returns '
          '0, and the readout silently falls back to RSS — the exact state '
          'this replaced',
    );
    expect(engine.processFootprintBytes, greaterThan(0));
  });

  test('the reading follows the private bytes we touch', () {
    const megabytes = 64;
    const ballastBytes = megabytes * 1024 * 1024;
    final before = engine.processFootprintBytes!;
    final ballast = Uint8List(ballastBytes);
    // One byte per page: allocating is not enough, the pages have to be
    // resident before a working-set number can see them.
    for (var offset = 0; offset < ballast.length; offset += 4096) {
      ballast[offset] = 1;
    }
    final after = engine.processFootprintBytes!;
    expect(
      after - before,
      greaterThan(ballastBytes ~/ 2),
      reason:
          'a counter that ignored $megabytes MB of freshly touched private '
          'pages is not measuring this process',
    );
    // Keeps the ballast alive across the second reading.
    expect(ballast[0], 1);
  });

  test('on Windows it is the PRIVATE working set, not the resident one', () {
    // ⛔Windows only, deliberately. Apple's `phys_footprint` counts
    // compressed pages and can sit ABOVE the resident set, so "below RSS"
    // is not a law that holds everywhere. Windows is the one platform
    // where every mapped DLL is guaranteed to be IN the working set and
    // OUT of the private one, which is what separates the two numbers.
    //
    // 🚨A BARE `lessThan` DID NOT SEPARATE THEM — the mutant that returned
    // WorkingSetSize instead of PrivateWorkingSetSize passed it. The two
    // readings are taken microseconds apart, so a working set that is
    // still growing makes the earlier number the smaller one and the
    // assertion true for the wrong reason. The SIZE of the gap is the
    // evidence: 20.1MB in a bare Dart process (measured 2026-09-10), and
    // a test host loads more DLLs, not fewer.
    //
    // Resident is read FIRST so any drift between the two shrinks the gap
    // rather than inventing one.
    final resident = ProcessInfo.currentRss;
    final private = engine.processFootprintBytes!;
    const mappedFloor = 8 * 1024 * 1024;
    expect(
      resident - private,
      greaterThan(mappedFloor),
      reason:
          'the shared pages of the loaded DLLs are worth far more than '
          '${mappedFloor ~/ (1024 * 1024)}MB; a gap this small means the '
          'resident set came back under a private name',
    );
  }, skip: Platform.isWindows ? null : 'Windows-only separation');

  test('the CENSUS reads the engine, not the Dart VM', () {
    // 🚨THE ONE THAT PINS THE WIRING. The engine can answer perfectly and
    // the panel still print RSS -- that was the state this round started
    // in, and no behaviour test could see it because the RSS fallback is
    // real and returns a plausible number. With a binary loaded, the two
    // are far enough apart to tell which one arrived.
    final session = EditorSessionManager(initialProject: createDefaultProject());
    addTearDown(session.dispose);
    final resident = ProcessInfo.currentRss;
    final census = collectMemoryCensus(session);
    expect(
      census.footprintBytes,
      isNot(resident),
      reason: 'the census handed back the Dart VM number, not the engine',
    );
    expect(
      resident - census.footprintBytes,
      greaterThan(8 * 1024 * 1024),
      reason:
          'the census total must be the private footprint, which sits a '
          'whole DLL set below the resident one',
    );
  }, skip: Platform.isWindows ? null : 'Windows-only separation');
}
