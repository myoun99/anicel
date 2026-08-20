import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/services/persistence/app_ui_scale_store.dart';
import 'package:anicel/src/ui/ui_scale.dart';

void main() {
  late Directory directory;
  late AppUiScaleStore store;

  setUp(() {
    directory = Directory.systemTemp.createTempSync('ui_scale_store');
    store = AppUiScaleStore(filePath: '${directory.path}/ui_scale.json');
  });

  tearDown(() => directory.deleteSync(recursive: true));

  test('a missing file is not an error — it is the default', () async {
    expect(await store.load(), isNull);
  });

  test('round-trips a ladder stop', () async {
    for (final stop in AppUiScale.ladder) {
      await store.save(stop);
      expect(await store.load(), stop);
    }
  });

  test('an OFF-LADDER stored value is snapped on the way in', () async {
    // The normal way one arrives: a file written by a build whose ladder
    // had different stops. Handing it back unchanged would put a value in
    // the notifier that the settings row cannot show as selected.
    await File(store.filePath).writeAsString(
      jsonEncode({'version': 1, 'scale': 1.2}),
    );
    expect(await store.load(), 1.25);
  });

  test('a hostile scale never reaches the divisor', () async {
    for (final bad in <Object>['big', 0, -1.5, {}]) {
      await File(store.filePath).writeAsString(
        jsonEncode({'version': 1, 'scale': bad}),
      );
      expect(await store.load(), isNull, reason: 'scale=$bad');
    }
  });

  test('corrupt JSON, a directory, and a future version all yield null', () async {
    await File(store.filePath).writeAsString('{not json');
    expect(await store.load(), isNull);

    await File(store.filePath).writeAsString(
      jsonEncode({'version': AppUiScaleStore.version + 1, 'scale': 1.25}),
    );
    expect(await store.load(), isNull);
  });

  test('save creates the parent directory', () async {
    final nested = AppUiScaleStore(
      filePath: '${directory.path}/deep/deeper/ui_scale.json',
    );
    await nested.save(0.9);
    expect(await nested.load(), 0.9);
  });
}
