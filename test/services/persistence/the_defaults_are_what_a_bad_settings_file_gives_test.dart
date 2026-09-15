import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/services/persistence/versioned_settings_file.dart';

/// The law the audit pulled out of copies that no test named: a settings
/// file that cannot be read must not stop the app.
///
/// ↩️This file used to pin a second law beside it — a cut lead-edge drag
/// stated in cuts (`planCutLeadEdge`). That planner lost its last caller
/// when the lead edge became ONE rule over panels (I-21, 유저 2026-09-12:
/// the block in front keeps its head and trades frames across the boundary),
/// and it could not even say what the new rule does — it returned only the
/// dragged cut's length, while the cut in front now resizes too. Its two
/// cases pinning the retired rule kept master red from 2026-09-12 on. The
/// planner and its cases went together; the live rule is pinned where it
/// lives: `test/models/block_run_lead_edge_test.dart`,
/// `test/models/storyboard_panel_slots_test.dart` and
/// `test/ui/storyboard_lead_edge_is_one_law_test.dart`.
void main() {
  group('a settings file that cannot be read must not stop the app', () {
    late Directory directory;

    setUp(() async {
      directory = await Directory.systemTemp.createTemp('anicel-settings');
    });

    tearDown(() => directory.delete(recursive: true));

    String pathFor(String name) => '${directory.path}/$name';

    Map<String, dynamic>? asIs(Map<String, dynamic> json) => json;

    test('a round trip returns what was written, under its version', () async {
      final path = pathFor('a.json');
      await saveVersionedSettings(
        filePath: path,
        version: 3,
        json: {'lane': 'audio'},
      );

      expect(
        await loadVersionedSettings(filePath: path, version: 3, fromJson: asIs),
        {'version': 3, 'lane': 'audio'},
      );
    });

    test('the save CREATES the directory — a first run has none', () async {
      final path = pathFor('deep/and/deeper/b.json');
      await saveVersionedSettings(filePath: path, version: 1, json: const {});
      expect(File(path).existsSync(), isTrue);
    });

    test('a MISSING file is null', () async {
      expect(
        await loadVersionedSettings(
          filePath: pathFor('nothing.json'),
          version: 1,
          fromJson: asIs,
        ),
        isNull,
      );
    });

    test('🚨CORRUPT bytes are null, not a throw — the same situation as '
        'missing, on purpose', () async {
      final path = pathFor('torn.json');
      File(path).writeAsStringSync('{"lane": ');

      expect(
        await loadVersionedSettings(filePath: path, version: 1, fromJson: asIs),
        isNull,
      );
    });

    test('a file holding a JSON LIST is null too — the cast throws inside '
        'the same catch', () async {
      final path = pathFor('list.json');
      File(path).writeAsStringSync('[1, 2, 3]');

      expect(
        await loadVersionedSettings(filePath: path, version: 1, fromJson: asIs),
        isNull,
      );
    });

    test('a NEWER version is null — this build does not know it', () async {
      final path = pathFor('future.json');
      File(path).writeAsStringSync(jsonEncode({'version': 9, 'lane': 'x'}));

      expect(
        await loadVersionedSettings(filePath: path, version: 2, fromJson: asIs),
        isNull,
      );
    });

    test('an OLDER version still loads — fromJson is what migrates', () async {
      final path = pathFor('old.json');
      File(path).writeAsStringSync(jsonEncode({'version': 1, 'lane': 'x'}));

      expect(
        await loadVersionedSettings(filePath: path, version: 5, fromJson: asIs),
        isNotNull,
      );
    });

    test('a fromJson that THROWS is null as well — a decoder that cannot '
        'make sense of the document is the same as a torn one', () async {
      final path = pathFor('bad-shape.json');
      await saveVersionedSettings(filePath: path, version: 1, json: const {});

      expect(
        await loadVersionedSettings<String>(
          filePath: path,
          version: 1,
          fromJson: (_) => throw StateError('nope'),
        ),
        isNull,
      );
    });

    test('the SYNC reader answers identically, for the callers that cannot '
        'await (the export dialog, the launcher list)', () async {
      final missing = pathFor('none.json');
      final future = pathFor('future.json');
      final torn = pathFor('torn.json');
      final good = pathFor('good.json');
      File(future).writeAsStringSync(jsonEncode({'version': 9}));
      File(torn).writeAsStringSync('{');
      await saveVersionedSettings(
        filePath: good,
        version: 2,
        json: {'lane': 'audio'},
      );

      for (final path in [missing, future, torn]) {
        expect(
          loadVersionedSettingsSync(filePath: path, version: 2, fromJson: asIs),
          isNull,
          reason: path,
        );
      }
      expect(
        loadVersionedSettingsSync(filePath: good, version: 2, fromJson: asIs),
        {'version': 2, 'lane': 'audio'},
      );
    });
  });
}
