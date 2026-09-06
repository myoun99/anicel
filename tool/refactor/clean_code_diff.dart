// ignore_for_file: avoid_print
// Which offenders a change ADDED (round 8, G0-2). The ratchets in
// test/architecture say a number grew; this says WHICH rows are new, by
// scanning two trees and subtracting.
//
//   dart run tool/refactor/clean_code_diff.dart <beforeLibDir> <afterLibDir>
//
// ⚠️It compares by FILE + MEMBER with a leading `_` stripped off the class
// name: this round made 38 private collaborator classes public, so a
// name-for-name diff would call every one of them both gone and added.

import 'clean_code_scan.dart';

String _key(CleanCodeFinding f) {
  final parts = f.where.trim().split(RegExp('[ \t]+'));
  final where = parts.first;
  final name = parts.length > 1 ? parts.last : '';
  final file = where.split('/').last.split(':').first;
  return '$file ${name.replaceFirst('_', '')}';
}

void main(List<String> args) {
  final before = scanCleanCode(args[0]);
  final after = scanCleanCode(args[1]);
  void diff(String what, List<CleanCodeFinding> a, List<CleanCodeFinding> b) {
    final was = {for (final f in a) _key(f)};
    final now = {for (final f in b) _key(f)};
    print('$what: ${a.length} -> ${b.length}');
    for (final n in now.difference(was)) {
      print('  ADDED $n');
    }
    for (final n in was.difference(now)) {
      print('  GONE  $n');
    }
  }

  diff('wide', before.wideSignatures, after.wideSignatures);
  diff('bodies', before.longBodies, after.longBodies);
  diff('classes', before.longClasses, after.longClasses);
}
