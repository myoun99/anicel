import '../../tool/source_brackets.dart';
import 'dart_sources.dart';

/// Every menu row written under [dir] — a `PanelFlyoutItem(…)` call — as
/// 「file | its key as written」, and whether it names an action
/// (`shortcuts:`).
///
/// ⚠️A row is known by its FILE and its KEY EXPRESSION, never by its line:
/// a ledger keyed by line numbers is rewritten by every edit above it. A
/// row with no key of its own is known by its place among the keyless rows
/// of its file.
///
/// ⚠️The caller names the folder, `'lib/src/ui'` spelled out in the test:
/// the affected-tests selector finds a source scan by the path the TEST
/// names. The walk is the one every source scan takes ([dartFilesUnder]).
({Set<String> named, Set<String> silent}) menuRowsUnder(String dir) =>
    callsNamingAnActionUnder(dir, const {'PanelFlyoutItem'}, what: 'row');

/// [menuRowsUnder]'s scan, for every call of any of [callees] — a widget's
/// constructor, or a private method that builds one on its owner's behalf
/// (`_bar._barIconButton(…)`). A call is known by its key, or by its NAME
/// where the widget takes one instead ([Named] — the rail's buttons, I-57)
/// — the first one written in it, so a pill is known by its name cell's;
/// a call with neither is 「keyless [what] N」 among the keyless calls of
/// its file.
({Set<String> named, Set<String> silent}) callsNamingAnActionUnder(
  String dir,
  Set<String> callees, {
  required String what,
}) {
  final named = <String>{};
  final silent = <String>{};
  final root = '${dir.replaceAll(r'\', '/')}/';
  for (final file in dartFilesUnder(dir)) {
    final text = file.readAsStringSync().replaceAll('\r\n', '\n');
    final path = file.path.replaceAll(r'\', '/').split(root).last;
    var keyless = 0;
    for (final callee in callees) {
      for (final call in _callsOf(callee, text)) {
        final open = callee.length;
        final key =
            namedArgumentWithin(call, open, 'keyValue') ??
            namedArgumentWithin(call, open, 'name');
        final id = '$path | ${key ?? 'keyless $what ${++keyless}'}';
        (call.contains('shortcuts:') ? named : silent).add(id);
      }
    }
  }
  return (named: named, silent: silent);
}

/// The text of every call of [callee] in [text], parentheses and all — not
/// its own declaration, and not a mention in a comment.
Iterable<String> _callsOf(String callee, String text) sync* {
  // A longer name that ends in this one is another widget. A private method
  // is called on its owner (`_bar._barIconButton(`), so a dot may lead it.
  final joined = RegExp(callee.startsWith('_') ? '[A-Za-z0-9_]' : r'[\w.]');
  var from = 0;
  while (true) {
    final at = text.indexOf('$callee(', from);
    if (at < 0) return;
    from = at + callee.length + 1;
    if (at > 0 && joined.hasMatch(text[at - 1])) continue;
    final lead = text.substring(text.lastIndexOf('\n', at) + 1, at);
    if (lead.trimLeft().startsWith('//')) continue;
    final end = matchingClose(text, at + callee.length);
    if (end == null) return;
    final call = text.substring(at, end + 1);
    // `const PanelFlyoutItem({…})` is the class saying what a row takes,
    // and `PanelFlyoutItem(:final action) =>` a switch asking what it has.
    if (call.startsWith('$callee({')) continue;
    if (text.substring(end + 1).trimLeft().startsWith('=>')) continue;
    yield call;
  }
}
