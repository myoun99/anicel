import 'dart:io';

/// Every menu row written under [root] — a `PanelFlyoutItem(…)` call — as
/// 「file | its key as written」, and whether it names an action
/// (`shortcuts:`).
///
/// ⚠️A row is known by its FILE and its KEY EXPRESSION, never by its line:
/// a ledger keyed by line numbers is rewritten by every edit above it. A
/// row with no key of its own is known by its place among the keyless rows
/// of its file.
///
/// ⚠️The caller reads the folder, `Directory('lib/src/ui')` spelled out in
/// the test: the affected-tests selector finds a source scan by the path
/// the TEST names.
({Set<String> named, Set<String> silent}) menuRowsUnder(Directory root) {
  final named = <String>{};
  final silent = <String>{};
  final files = root.listSync(recursive: true).whereType<File>().toList()
    ..sort((a, b) => a.path.compareTo(b.path));
  for (final file in files) {
    if (!file.path.endsWith('.dart')) continue;
    final text = file.readAsStringSync().replaceAll('\r\n', '\n');
    final path = file.path
        .replaceAll('\\', '/')
        .split('${root.path.replaceAll('\\', '/')}/')
        .last;
    var keyless = 0;
    for (final call in _callsOf('PanelFlyoutItem', text)) {
      final key = _argument('keyValue', call);
      final id = '$path | ${key ?? 'keyless row ${++keyless}'}';
      (call.contains('shortcuts:') ? named : silent).add(id);
    }
  }
  return (named: named, silent: silent);
}

/// The text of every call of [constructor] in [text], parentheses and all —
/// not the class's own constructor, and not a mention in a comment.
Iterable<String> _callsOf(String constructor, String text) sync* {
  var from = 0;
  while (true) {
    final at = text.indexOf('$constructor(', from);
    if (at < 0) return;
    from = at + constructor.length + 1;
    // A longer name that ends in this one is another widget.
    if (at > 0 && RegExp('[A-Za-z0-9_.]').hasMatch(text[at - 1])) continue;
    final lead = text.substring(text.lastIndexOf('\n', at) + 1, at);
    if (lead.trimLeft().startsWith('//')) continue;
    final end = _closing(text, at + constructor.length);
    if (end < 0) return;
    final call = text.substring(at, end + 1);
    // `const PanelFlyoutItem({…})` is the class saying what a row takes,
    // and `PanelFlyoutItem(:final action) =>` a switch asking what it has.
    if (call.startsWith('$constructor({')) continue;
    if (text.substring(end + 1).trimLeft().startsWith('=>')) continue;
    yield call;
  }
}

/// The index of the `)` that closes the `(` at [open], or -1.
int _closing(String text, int open) {
  var depth = 0;
  for (var i = open; i < text.length; i++) {
    final c = text[i];
    if (c == '(') depth++;
    if (c == ')' && --depth == 0) return i;
  }
  return -1;
}

/// What [call] passes as [name], as written and on one line — or null.
String? _argument(String name, String call) {
  final at = call.indexOf('$name:');
  if (at < 0) return null;
  var depth = 0;
  final from = at + name.length + 1;
  for (var i = from; i < call.length; i++) {
    final c = call[i];
    if (c == '(' || c == '[' || c == '{') depth++;
    if (c == ')' || c == ']' || c == '}') depth--;
    if ((c == ',' && depth == 0) || depth < 0) {
      return call.substring(from, i).replaceAll(RegExp(r'\s+'), ' ').trim();
    }
  }
  return null;
}
