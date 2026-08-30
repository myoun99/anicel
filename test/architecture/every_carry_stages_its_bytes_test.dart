import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 🚨★★★**EVERY WAY AN ASSET BECOMES CARRIED MUST HOLD ITS BYTES.**
///
/// Carrying means the project has the file from the moment the choice is
/// made — 유저 2026-08-30: 「품은 순간 데이터를 가지고있고 **불변**이었
/// 으면좋겠어서」. There are four ways to make that choice, and when the
/// staging was built only ONE of them learned to hold anything:
///
/// • the import window's Keep inside
/// • a folder import
/// • promoting a reference from the pool row, afterwards
/// • recording a voice take
///
/// The other three set the flag and left the bytes on the user's disk,
/// which is the exact behaviour the staging replaced. They were found by
/// grepping for `carried: true` — after two rounds of this work — so this
/// scans the SOURCE for the same thing rather than trusting the next
/// reader to remember.
///
/// ⛔A behaviour test cannot cover this: it would pass with a fifth
/// entrance nobody wrote a test for, which is precisely the failure.
void main() {
  /// Where an asset is declared carried, other than the flag's own
  /// definition and the plumbing that copies it.
  ///
  /// ⚠️Deliberately crude. It is looking for the SHAPE `carried: true` (or
  /// a variable that decides it) in a file that creates or rewrites a
  /// [MediaAsset], and every hit is either an entrance or a line that has
  /// to explain itself in [_allowed].
  final entrances = <String>[];

  test('every place an asset becomes carried also stages its bytes', () {
    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) {
        continue;
      }
      final path = entity.path.replaceAll(r'\', '/');
      final relative = path.substring(path.indexOf('lib/'));
      if (_allowedFiles.contains(relative)) {
        continue;
      }
      final source = entity.readAsStringSync();
      if (!_declaresCarried(source)) {
        continue;
      }
      // The law: a file that decides an asset carries must also be the
      // one that holds the bytes, or hand the job to something that does.
      if (!source.contains('stageCarriedBytes')) {
        entrances.add(relative);
      }
    }

    expect(
      entrances,
      isEmpty,
      reason:
          'these decide that an asset is CARRIED without staging its bytes '
          '— which leaves the promise to be kept at save time, so deleting '
          'or editing the original in between quietly changes or empties '
          'what gets saved. Call `stageCarriedBytes` before the pool '
          'records the asset, or add the file to _allowedFiles above with '
          'the reason it does not need to.',
    );
  });
}

/// Whether [source] decides an asset carries, rather than merely passing a
/// flag along.
bool _declaresCarried(String source) {
  for (final line in source.split('\n')) {
    final trimmed = line.trimLeft();
    if (trimmed.startsWith('//') || trimmed.startsWith('///')) {
      continue;
    }
    if (trimmed.contains('carried: true') ||
        trimmed.contains('copyWith(carried:')) {
      return true;
    }
  }
  return false;
}

/// Files that name `carried` without being an entrance, with the reason.
const Set<String> _allowedFiles = {
  // The flag's own definition and its copyWith — the model does not
  // decide anything, it records what it was told.
  'lib/src/models/media_asset.dart',
  // The planner BUILDS assets from the caller's answer; the session that
  // calls it is the entrance and stages there. Splitting the staging into
  // the planner would put a disk write inside a pure plan.
  'lib/src/services/import/media_import_planner.dart',
};
