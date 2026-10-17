// Where a bracket in source text closes — and so what in it is code: a
// bracket inside a string or a comment is not one.
//
// 🚨ONE READING (2026-10-18, source-scans-count-brackets-by-hand). The
// scans under `test/` that read a body, a call's arguments or one argument
// out of source text each counted brackets their own way — eleven of them
// — and so did two tools; all but `tool/refactor/extract_method.dart`, whose
// reading this is, counted the brackets inside strings and comments too.
// `test/architecture/brackets_are_read_one_way_test.dart` keeps it to this
// file.
//
// By the characters, not a parse: the scans read Kotlin, Swift, C, C++ and
// GLSL as well as Dart, and a Dart parser reads none of those. What it
// knows of them is what they share — `//` and `/* */` comments, strings in
// `'` or `"` (tripled for many lines), `\` escaping one character — and
// Dart's own: a raw string's `r`, and the code inside `${…}`, read as code,
// strings in it and all (`'${on ? '(' : ''}'` holds no bracket).
//
// ⚠️A string in one quote never runs past its line, in any of these
// languages, so a misreading stops at the line's end instead of reading
// the rest of the file as a string.

/// The index just past what is NOT code that starts at [at] — a comment or
/// a string — or [at] itself when code starts there.
int pastNonCode(String source, int at) {
  if (source.startsWith('//', at)) {
    final end = source.indexOf('\n', at);
    return end < 0 ? source.length : end;
  }
  if (source.startsWith('/*', at)) {
    final end = source.indexOf('*/', at + 2);
    return end < 0 ? source.length : end + 2;
  }
  final quote = source[at];
  return quote == "'" || quote == '"' ? _pastString(source, at) : at;
}

/// The index just past the string that opens at [at].
int _pastString(String source, int at) {
  final quote = source[at];
  final raw = at > 0 && source[at - 1] == 'r';
  final closer = source.startsWith(quote * 3, at) ? quote * 3 : quote;
  var i = at + closer.length;
  while (i < source.length) {
    if (source.startsWith(closer, i)) {
      return i + closer.length;
    }
    if (closer.length == 1 && source[i] == '\n') {
      return i;
    }
    if (!raw && source[i] == r'\') {
      i += 2;
    } else if (!raw && source.startsWith(r'${', i)) {
      i = (matchingClose(source, i + 1) ?? source.length - 1) + 1;
    } else {
      i += 1;
    }
  }
  return source.length;
}

/// The index of the bracket closing the `(`, `[` or `{` at [openAt],
/// counted outside strings and comments — or null when [source] ends
/// first.
int? matchingClose(String source, int openAt) {
  final open = source[openAt];
  final close = switch (open) {
    '(' => ')',
    '[' => ']',
    '{' => '}',
    _ => throw ArgumentError.value(open, 'source[openAt]', 'not a bracket'),
  };
  var depth = 0;
  var i = openAt;
  while (i < source.length) {
    final past = pastNonCode(source, i);
    if (past > i) {
      i = past;
      continue;
    }
    if (source[i] == open) {
      depth += 1;
    } else if (source[i] == close) {
      depth -= 1;
      if (depth == 0) {
        return i;
      }
    }
    i += 1;
  }
  return null;
}

/// The arguments of the call whose `(` is at [openAt], each as written: cut
/// at the call's own commas — never at one inside a nested bracket, a
/// string or a comment — and a trailing comma makes none. Null when
/// [source] ends first.
List<String>? callArguments(String source, int openAt) {
  final arguments = <String>[];
  var depth = 0;
  var from = openAt + 1;
  var i = openAt;
  while (i < source.length) {
    final past = pastNonCode(source, i);
    if (past > i) {
      i = past;
      continue;
    }
    final char = source[i];
    if (_opens.contains(char)) {
      depth += 1;
    } else if (_closes.contains(char)) {
      depth -= 1;
      if (depth == 0) {
        final last = source.substring(from, i);
        if (withoutComments(last).trim().isNotEmpty) {
          arguments.add(last);
        }
        return arguments;
      }
    } else if (char == ',' && depth == 1) {
      arguments.add(source.substring(from, i));
      from = i + 1;
    }
    i += 1;
  }
  return null;
}

const _opens = '([{';
const _closes = ')]}';

/// Every argument of the call whose `(` is at [openAt] and of every bracket
/// written inside it — each list's own, as [callArguments] cuts them — in
/// the order they are written.
Iterable<String> argumentsWithin(String source, int openAt) sync* {
  for (final argument in callArguments(source, openAt) ?? const <String>[]) {
    yield argument;
    var i = 0;
    while (i < argument.length) {
      final past = pastNonCode(argument, i);
      if (past > i) {
        i = past;
      } else if (_opens.contains(argument[i])) {
        yield* argumentsWithin(argument, i);
        i = (matchingClose(argument, i) ?? argument.length - 1) + 1;
      } else {
        i += 1;
      }
    }
  }
}

/// What the call whose `(` is at [openAt] passes as [name] — one of its own
/// arguments, never one nested inside another, and not one whose name only
/// ends in it — on one line; or null.
String? namedArgument(String source, int openAt, String name) =>
    _valueNamed(callArguments(source, openAt) ?? const <String>[], name);

/// The first argument named [name] written in the call whose `(` is at
/// [openAt] — its own, or one of a call written inside it — on one line;
/// or null. For a scan that knows a call by what it holds: a pill by its
/// name cell's key.
String? namedArgumentWithin(String source, int openAt, String name) =>
    _valueNamed(argumentsWithin(source, openAt), name);

String? _valueNamed(Iterable<String> arguments, String name) {
  for (final argument in arguments) {
    final code = withoutComments(argument).trim();
    if (code.startsWith('$name:')) {
      return code
          .substring(name.length + 1)
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();
    }
  }
  return null;
}

/// The body of the declaration that starts with [signature] in [source] —
/// from the first `{` after it to the one that closes it, both kept — or
/// null when there is no such signature, or its body never closes.
///
/// From the signature's END: one that runs through a named parameter list
/// would otherwise be read from that list's brace.
String? bodyOf(String source, Pattern signature) {
  final head = signature.allMatches(source).firstOrNull;
  if (head == null) {
    return null;
  }
  var open = head.end;
  while (open < source.length) {
    final past = pastNonCode(source, open);
    if (past > open) {
      open = past;
    } else if (source[open] == '{') {
      final close = matchingClose(source, open);
      return close == null ? null : source.substring(open, close + 1);
    } else {
      open += 1;
    }
  }
  return null;
}

/// [source] with its comments taken out, and its strings kept whole — a
/// `//` inside one stays.
String withoutComments(String source) {
  final code = StringBuffer();
  var i = 0;
  while (i < source.length) {
    final past = pastNonCode(source, i);
    if (past == i) {
      code.write(source[i]);
      i += 1;
      continue;
    }
    if (source[i] != '/') {
      code.write(source.substring(i, past));
    }
    i = past;
  }
  return code.toString();
}
