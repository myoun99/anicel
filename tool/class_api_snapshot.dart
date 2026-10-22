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

import 'source_brackets.dart';

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
///
/// What is code is read the one way (`tool/source_brackets.dart`): a string
/// or a comment is skipped whole, however many lines it runs over — braces
/// inside it are not code braces. ↩️It was read a line at a time, and a
/// string over many lines had its later lines read as code.
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

  final text = lines.join('\n');
  final starts = <int>[];
  var offset = 0;
  for (final line in lines) {
    starts.add(offset);
    offset += line.length + 1;
  }

  var brace = 0;
  var paren = 0;
  final members = <String>[];
  String? sig; // signature collected so far (null = between members)
  var sigDone = false; // terminator seen; now waiting for the member's end
  var blockBodied = false; // ended at `{`, so the member ends at its `}`

  var at = starts[i];
  while (i < lines.length) {
    final lineEnd = starts[i] + lines[i].length;
    // A member starts on a line of its own — not one a string or a comment
    // ran on to.
    final trimmed = lines[i].trim();
    final isCode =
        trimmed.isNotEmpty &&
        !trimmed.startsWith('//') &&
        !trimmed.startsWith('/*') &&
        !trimmed.startsWith('*');
    if (at == starts[i] && sig == null && isCode && brace == 1 && paren == 0) {
      sig = '';
      sigDone = false;
      blockBodied = false;
    }

    final buf = StringBuffer();
    var ended = false;
    while (at < lineEnd) {
      final past = pastNonCode(text, at);
      if (past > at) {
        // A literal is kept as its quotes alone; a comment is prose.
        final quote = text[at];
        if (quote != '/' && sig != null && !sigDone) buf.write(quote * 2);
        at = past;
        continue;
      }
      final ch = text[at];
      at += 1;

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
        } else if (ch == '>' && at >= 2 && text[at - 2] == '=') {
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

    // On to the next line — past the ones a string or a comment ran over.
    while (i < lines.length && at >= starts[i] + lines[i].length) {
      i += 1;
    }
    if (i < lines.length && at < starts[i]) at = starts[i];
  }

  members.sort();
  return members;
}

/// The member name a declaration introduces, or null when nothing parses.
String? _nameOf(String declaration) {
  final text = declaration.replaceAll(RegExp(r'^@\w+\s+'), '');
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
    '[A-Za-z_][A-Za-z0-9_]*',
  ).allMatches(text.substring(0, cut)).toList();
  return ids.isEmpty ? null : ids.last.group(0);
}
