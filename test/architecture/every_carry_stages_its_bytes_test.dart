import 'package:flutter_test/flutter_test.dart';
import '../helpers/dart_sources.dart';

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

  test('the premise: it sees a carry decided by a VALUE, not only `true`', () {
    expect(
      _declaresCarried(
        'final a = importedMediaAsset(\n  carried: copyIntoProject,\n);',
      ),
      isTrue,
    );
    expect(
      _declaresCarried(
        'final a = MediaAsset(\n'
        '  carried: settings.mode == ImportFileMode.keepInside,\n'
        ');',
      ),
      isTrue,
    );
    expect(
      _declaresCarried('final a = MediaAsset(\n  carried: false,\n);'),
      isFalse,
    );
    expect(
      _declaresCarried('final lift = DragLift(carried: carried);'),
      isFalse,
      reason: 'a drag\'s layers, in a file that builds no asset',
    );
    expect(
      _declaresCarried('asset.copyWith(carriedAs: mintMediaCarry())'),
      isTrue,
      reason: 'a carry MADE here — the mint is the moment of carrying',
    );
    expect(
      _declaresCarried('final a = MediaAsset(\n  carriedAs: carry.token,\n);'),
      isTrue,
      reason: 'a carry handed to a new asset',
    );
    expect(
      _declaresCarried('final a = MediaAsset(\n  carriedAs: null,\n);'),
      isFalse,
    );
    expect(
      _stagesBytes('// hands it to stageCarriedBytes\nrecord(asset);'),
      isFalse,
      reason: 'a comment naming the funnel holds nothing',
    );
    expect(_stagesBytes('await _pool.holdCarriedBytes(assets);'), isTrue);
  });

  test('every place an asset becomes carried also stages its bytes', () {
    for (final entity in dartFilesUnder('lib')) {
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
      if (!_stagesBytes(source)) {
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
          'what gets saved. Call `stageCarriedBytes` (or the pool\'s '
          '`holdCarriedBytes`) before the pool records the asset, or add '
          'the file to _allowedFiles above with the reason it does not '
          'need to.',
    );
  });
}

/// Whether [source] holds bytes, or hands the job to what does — in CODE.
///
/// 🪦A comment naming the funnel used to count: a door that had stopped
/// calling it kept its doc paragraph about it, and the scan passed it.
bool _stagesBytes(String source) => _codeLines(source).any(
  (line) =>
      line.contains('stageCarriedBytes') || line.contains('holdCarriedBytes'),
);

/// [source]'s lines that are not comments.
Iterable<String> _codeLines(String source) => source
    .split('\n')
    .map((line) => line.trimLeft())
    .where((line) => !line.startsWith('//'));

/// Whether [source] decides an asset carries, rather than merely passing a
/// flag along: `carried: true` anywhere, `copyWith(carried:`, or — in a
/// file that builds a [MediaAsset] — `carried:` given any VALUE but
/// `false`.
///
/// 🪦Until 2026-09-23 it saw only the literal `true`, while the doc above
/// already promised 「or a variable that decides it」 — and every door a
/// placement goes through decides carrying from the window's answer
/// (`carried: copyIntoProject`). Five entrances recorded assets carried
/// without holding a byte, from the day staging landed, and this scan
/// passed them all.
///
/// ⚠️The value half needs the file to build an asset because `carried:`
/// also names a drag's lifted layers and a paint pass's scroll flag, and a
/// collection after it is the save's own set of carried paths.
///
/// 🆕A carry has a NAME now ([MediaAsset.carriedAs]), minted where it is
/// made (`mintMediaCarry`) — so the mint, or a name handed to an asset, is
/// the surest sign of all (card `recarry-after-remove-reads-the-old`).
bool _declaresCarried(String source) {
  final buildsAssets = source.contains('MediaAsset(');
  for (final trimmed in _codeLines(source)) {
    if (trimmed.contains('carried: true') ||
        trimmed.contains('mintMediaCarry(') ||
        (buildsAssets && _decidesCarried.hasMatch(trimmed)) ||
        _namesACarry.hasMatch(trimmed)) {
      return true;
    }
  }
  return false;
}

/// `carried:` followed by a value that decides it — a name or an
/// expression, never `false`, never a collection.
final _decidesCarried = RegExp(r'\bcarried:\s*(?!false\b)[A-Za-z_]');

/// `carriedAs:` given a carry — anything but `null`.
final _namesACarry = RegExp(r'\bcarriedAs:\s*(?!null\b)[A-Za-z_]');

/// Files that name `carried` without being an entrance, with the reason.
const Set<String> _allowedFiles = {
  // The flag's own definition and its copyWith — the model does not
  // decide anything, it records what it was told.
  'lib/src/models/media_asset.dart',
  // The planner BUILDS assets from the caller's answer; the session that
  // calls it is the entrance and stages there. Splitting the staging into
  // the planner would put a disk write inside a pure plan.
  'lib/src/services/import/media_import_planner.dart',
  // A relink by hand is a new carry ([RelinkMediaAssetCommand.carriedAs]),
  // minted and staged by the pool's relink — the entrance; the coordinator
  // and the command only hand it to the asset inside the undo step, the way
  // the planner hands over an import's.
  'lib/src/services/commands/cut_command_coordinator.dart',
  'lib/src/services/commands/relink_media_asset_command.dart',
};
