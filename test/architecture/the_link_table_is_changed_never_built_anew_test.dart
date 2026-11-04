import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../helpers/dart_sources.dart';

/// 🚨A LINK TABLE IS CHANGED, NEVER BUILT ANEW FROM ITS GROUPS.
///
/// The table holds the 동기컷 beside the linked rows (`LayerLinkRegistry
/// .syncs`, I-150-Q3: 「겸용컷이면서 추가로 타임라인까지 완벽동기화된 실질
/// 같은컷」), so a step that writes its groups into `LayerLinkRegistry(groups:
/// …)` drops every sync in the project without a word — twelve steps did,
/// the day the syncs came in. They change it with `copyWith`.
///
/// ⛔A behaviour test would have to run each of the twelve on a synced cut;
/// this scan is what stops the thirteenth.
void main() {
  const theModel = 'lib/src/models/layer_link_registry.dart';

  /// An imported file's table, made with the project it comes in: there is
  /// no sync in it to drop.
  const aNewProjectsTable = 'lib/src/services/import/clip_import_planner.dart';
  const construction = 'LayerLinkRegistry(';

  List<String> buildersIn(File file) => [
    for (final line in file.readAsLinesSync())
      if (!line.trimLeft().startsWith('//') && line.contains(construction))
        line.trim(),
  ];

  final builders = <String, List<String>>{
    for (final file in dartFilesUnder('lib'))
      if (libPath(file) != theModel)
        if (buildersIn(file) case final found when found.isNotEmpty)
          libPath(file): found,
  };

  test('premise: the scan sees the new project\'s table made', () {
    expect(
      builders.keys,
      contains(aNewProjectsTable),
      reason: 'an empty scan must not pass for nothing',
    );
  });

  test('no step builds the table anew — each changes the one it has', () {
    expect(
      builders.keys.toList(),
      [aNewProjectsTable],
      reason: 'LayerLinkRegistry(groups: …) drops the syncs; '
          'registry.copyWith(groups: …) keeps them',
    );
  });
}
