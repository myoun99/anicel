import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gpu_engine/gpu_engine.dart';

import 'package:anicel/src/native/app_gpu_engine.dart';
import 'package:anicel/src/services/persistence/app_support_path.dart';

import '../../tool/machine_cache.dart';
import '../helpers/temp_dir.dart';

/// 🚨A TEST RUN'S ENGINE KEEPS ITS SHADERS WHERE THE NEXT RUN FINDS THEM:
/// the config names one folder of the machine's for every run
/// (flutter_test_config.dart, which says what was measured), and every
/// opening of the app's engine names the folder it is to keep them in — the
/// one a test makes by asking for [appGpuEngine] too.
///
/// ⚠️One process, and the order is the tests': the first reads what the
/// config named before the second names a folder of its own, and the second
/// is this file's first asking for the engine.
void main() {
  // What the config named, before a test here names another.
  final named = debugAppShaderFolder;

  String spelled(String path) => path.replaceAll('\\', '/').toLowerCase();

  test('the runs of a machine name one folder of the machine\'s — not in the '
      'run\'s own temp, which goes with the run, and not in the app\'s '
      'container', () {
    final machine = machineCacheFolder(Platform.environment);
    expect(machine, isNotNull, reason: '⛔premise: this machine names one');
    expect(named, isNotNull, reason: 'the config names one');
    // The temp this process was given: the run's own is a folder in it
    // (`giveTheRunItsOwnTemp`), and the line empties the whole of it as
    // each run ends (tool/test_queue.dart, `RunTemp`).
    final given = Directory.systemTemp.parent.path;
    expect(
      spelled(named!),
      isNot(startsWith(spelled(given))),
      reason: 'what is kept in the temp goes with the run',
    );
    expect(
      spelled(named),
      isNot(startsWith(spelled(appSupportFilePath('')))),
      reason: 'a test writes nothing among the user\'s files',
    );
    expect(named, '$machine/test_shaders', reason: 'beside the line\'s own');
    expect(appShaderFolder(), named, reason: 'what the app\'s engines keep in');
  });

  test(
    'an engine a test opens by asking for it keeps what it compiles in the '
    'folder named',
    () {
      final own = Directory.systemTemp.createTempSync('qa_shaders_');
      addTearDown(() => deleteTempQuietly(own));
      debugAppShaderFolder = own.path;
      addTearDown(() => debugAppShaderFolder = named);

      final grid = GpuGrid(appGpuEngine);
      addTearDown(grid.free);

      expect(own.listSync().whereType<File>(), isNotEmpty);
    },
    skip: Platform.isWindows ? false : 'what is kept is what DXC made',
  );
}
