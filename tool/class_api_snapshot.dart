// Dumps one class's member declarations, so a MOVE refactor can be checked
// for "public API diff = 0".
//
// Why this exists: a refactor that only relocates code passes the whole suite
// by construction, so "the tests are green" says nothing about whether the
// class still offers what it offered. Snapshot before, snapshot after, diff.
//
// It is an instrument, so here is what it looks like when it lies:
//   - a continuation line counted as its own member -> entries that are not
//     declarations (`({`, `expr;`) and an inflated count
//   - a member swallowed into the previous one      -> the count drops
// The count is printed first on purpose, and every entry should read like a
// declaration.
//
//   dart tool/class_api_snapshot.dart <file.dart> <ClassName> [--names]
//
// `--names` reduces each declaration to its member NAME (getters and setters
// keep the keyword). Use it to answer "did a public member vanish?" without
// eyeballing declaration text that a move legitimately rewrites — a body
// becoming an arrow, or a field becoming a getter over the same object, is
// not an API change, and only the name list says so plainly.
import 'dart:io';

void main(List<String> args) {
  final positional = args.where((a) => !a.startsWith('--')).toList();
  if (positional.length < 2) {
    stderr.writeln(
      'usage: class_api_snapshot.dart <file.dart> <ClassName> [--names]',
    );
    exit(2);
  }
  final members = _members(
    File(positional[0]).readAsLinesSync(),
    positional[1],
  );

  if (args.contains('--names')) {
    final names = members.map(_nameOf).whereType<String>().toSet().toList()
      ..sort();
    stdout.writeln('NAMES: ${names.length}');
    names.forEach(stdout.writeln);
    return;
  }
  stdout.writeln('MEMBERS: ${members.length}');
  members.forEach(stdout.writeln);
}

/// Every member declaration of [className], sorted, bodies omitted.
List<String> _members(List<String> lines, String className) {
  var i = lines.indexWhere(
    (l) =>
        l.startsWith('class $className ') ||
        l.startsWith('class $className<') ||
        l.startsWith('abstract class $className ') ||
        l.startsWith('mixin $className '),
  );
  if (i < 0) {
    stderr.writeln('class $className not found');
    exit(3);
  }

  var brace = 0;
  var paren = 0;
  var inBlockComment = false;
  final members = <String>[];
  String? sig; // signature collected so far (null = between members)
  var sigDone = false; // terminator seen; now waiting for the member's end
  var blockBodied = false; // ended at `{`, so the member ends at its `}`

  for (; i < lines.length; i++) {
    final line = lines[i];
    final trimmed = line.trim();
    final isCode =
        trimmed.isNotEmpty &&
        !trimmed.startsWith('//') &&
        !trimmed.startsWith('/*') &&
        !trimmed.startsWith('*');
    if (sig == null && isCode && brace == 1 && paren == 0 && !inBlockComment) {
      sig = '';
      sigDone = false;
      blockBodied = false;
    }

    final buf = StringBuffer();
    var ended = false;
    for (var c = 0; c < line.length; c++) {
      final ch = line[c];
      final next = c + 1 < line.length ? line[c + 1] : '';
      if (inBlockComment) {
        if (ch == '*' && next == '/') {
          inBlockComment = false;
          c++;
        }
        continue;
      }
      if (ch == '/' && next == '/') break; // line comment: prose, not code
      if (ch == '/' && next == '*') {
        inBlockComment = true;
        c++;
        continue;
      }
      if (ch == "'" || ch == '"') {
        // Skip the literal whole: braces inside it are not code braces.
        final quote = ch;
        final triple = line.startsWith(quote * 3, c) ? quote * 3 : null;
        if (sig != null && !sigDone) buf.write(ch);
        c += triple != null ? 3 : 1;
        while (c < line.length) {
          if (line[c] == r'\') {
            c += 2;
            continue;
          }
          if (triple != null && line.startsWith(triple, c)) {
            c += 2;
            break;
          }
          if (triple == null && line[c] == quote) break;
          c++;
        }
        if (sig != null && !sigDone) buf.write(quote);
        continue;
      }

      if (ch == '{') brace++;
      if (ch == '}') brace--;
      if (ch == '(') paren++;
      if (ch == ')') paren--;

      if (sig == null) continue;

      if (!sigDone) {
        buf.write(ch);
        // A named-parameter `{` sits inside the parens — only a `{` at paren
        // depth 0 opens the body. Without this the signature is cut off at
        // `({` and every parameter list vanishes from the diff.
        if (ch == '{' && paren == 0) {
          sigDone = true;
          blockBodied = true;
        } else if (ch == ';') {
          sigDone = true;
          ended = brace == 1 && paren == 0;
        } else if (ch == '>' && c > 0 && line[c - 1] == '=') {
          sigDone = true;
        }
        continue;
      }

      if (brace == 1 && paren == 0) {
        if (ch == ';' && !blockBodied) ended = true;
        if (ch == '}' && blockBodied) ended = true;
      }
    }

    if (sig != null) {
      sig = '$sig ${buf.toString().trim()}';
      if (ended) {
        members.add(sig.replaceAll(RegExp(r'\s+'), ' ').trim());
        sig = null;
      }
    }

    if (brace == 0 && members.isNotEmpty) break; // class closed
  }

  members.sort();
  return members;
}

/// The member name a declaration introduces, or null when nothing parses.
String? _nameOf(String declaration) {
  var text = declaration.replaceAll(RegExp(r'^@\w+\s+'), '');
  final accessor = RegExp(
    r'\b(get|set)\s+([A-Za-z_][A-Za-z0-9_]*)',
  ).firstMatch(text);
  if (accessor != null) {
    return '${accessor.group(1)} ${accessor.group(2)}';
  }
  // Otherwise: the identifier just before the first '(' (a method), or the
  // one before the '=' / ';' that ends a field.
  var cut = text.length;
  for (final i in [text.indexOf('('), text.indexOf('='), text.indexOf(';')]) {
    if (i >= 0 && i < cut) cut = i;
  }
  final ids = RegExp(
    r'[A-Za-z_][A-Za-z0-9_]*',
  ).allMatches(text.substring(0, cut)).toList();
  return ids.isEmpty ? null : ids.last.group(0);
}
