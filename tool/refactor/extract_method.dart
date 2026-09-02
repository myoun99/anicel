// The audit's Extract Method driver (2026-09-02). It asks the analysis
// server — the refactoring IDEs run — to carve a named step out of a long
// function, so the analyzer computes the parameters and the return value
// and REFUSES a selection it cannot extract. The audit's own rules ride
// on top: leading decision comments travel with the code, a lambda's
// whole body lifts with its early returns intact, a void block that
// always leaves keeps the caller's `return;`, an added import follows the
// repo's relative style, and a static caller gets a static method.
//
//   dart run tool/refactor/extract_method.dart <projectRoot> <jobs.json> [<analysisRoot>]
//
// Pass `<projectRoot>/lib` as the analysis root: the whole tree takes
// minutes to crawl, lib alone a dozen seconds.
// jobs.json is a list; each job:
//   {"file": "lib/x.dart",            // relative to the root
//    "startText": "final a = ...",     // unique text on the FIRST line
//    "endText": "...;",                // unique text on the LAST line
//    "name": "_stepName",
//    "expr": false,                    // true: extract the expression from
//                                      //   startText's start to endText's end
//    "occurrence": 1}                  // which hit of startText (1-based)
// Statements: the selection runs from the first non-blank character of the
// start line to the end of the end line. Jobs run in order on the live file,
// so later anchors are found in the text the earlier jobs produced.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:analyzer/dart/analysis/features.dart';
import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';

late Process _server;
final _pending = <String, Completer<Map<String, Object?>>>{};
final _status = StreamController<bool>.broadcast();
int _nextId = 1;

Future<Map<String, Object?>> _request(
  String method,
  Map<String, Object?> params,
) {
  final id = '${_nextId++}';
  final completer = Completer<Map<String, Object?>>();
  _pending[id] = completer;
  _server.stdin.writeln(jsonEncode({'id': id, 'method': method, 'params': params}));
  return completer.future;
}

void _listen() {
  _server.stdout
      .transform(utf8.decoder)
      .transform(const LineSplitter())
      .listen((line) {
    if (!line.startsWith('{')) return;
    final msg = jsonDecode(line) as Map<String, Object?>;
    final id = msg['id'];
    if (id is String && _pending.containsKey(id)) {
      _pending.remove(id)!.complete(msg);
      return;
    }
    if (msg['event'] == 'server.status') {
      final params = msg['params']! as Map<String, Object?>;
      final analysis = params['analysis'] as Map<String, Object?>?;
      if (analysis != null) _status.add(analysis['isAnalyzing'] == true);
    }
    if (msg['event'] == 'server.error') {
      stderr.writeln('SERVER ERROR: $line');
    }
  });
  _server.stderr.transform(utf8.decoder).listen(stderr.write);
}

int _offsetOf(String src, String text, int occurrence, String what) {
  var from = 0;
  var found = -1;
  for (var i = 0; i < occurrence; i++) {
    found = src.indexOf(text, from);
    if (found < 0) {
      throw StateError('$what not found (occurrence $occurrence): "$text"');
    }
    from = found + 1;
  }
  return found;
}

int _lineStartNonBlank(String src, int offset) {
  final lineStart = src.lastIndexOf('\n', offset - 1) + 1;
  var i = lineStart;
  while (i < src.length && (src[i] == ' ' || src[i] == '\t')) {
    i++;
  }
  return i;
}

int _lineEnd(String src, int offset) {
  var end = src.indexOf('\n', offset);
  if (end < 0) end = src.length;
  if (end > 0 && src[end - 1] == '\r') end--;
  return end;
}

String _problems(Map<String, Object?> result) {
  final out = <String>[];
  for (final key in ['initialProblems', 'optionsProblems', 'finalProblems']) {
    final list = (result[key] as List?) ?? const [];
    for (final p in list) {
      final m = p as Map<String, Object?>;
      out.add('$key ${m['severity']}: ${m['message']}');
    }
  }
  return out.join('\n');
}

bool _hasError(Map<String, Object?> result) {
  for (final key in ['initialProblems', 'optionsProblems', 'finalProblems']) {
    final list = (result[key] as List?) ?? const [];
    for (final p in list) {
      final m = p as Map<String, Object?>;
      if (m['severity'] == 'FATAL' || m['severity'] == 'ERROR') return true;
    }
  }
  return false;
}

Future<bool> _runJob(String root, Map<String, Object?> job) async {
  if (job['lambdaBody'] == true) return _liftLambdaBody(root, job);
  final rel = job['file']! as String;
  final path = '$root/$rel'.replaceAll('\\', '/');
  final file = File(path);
  var src = file.readAsStringSync();
  final name = job['name']! as String;

  final srcBefore = src;
  final (start, end) = _selection(src, job);
  final leadingComment = job['expr'] == true ? '' : _leadingComment(src, job);
  final length = end - start;

  final serverPath = path.replaceAll('/', Platform.pathSeparator);
  final probe = await _request('edit.getRefactoring', {
    'kind': 'EXTRACT_METHOD',
    'file': serverPath,
    'offset': start,
    'length': length,
    'validateOnly': true,
  });
  final probeResult = probe['result'] as Map<String, Object?>?;
  if (probeResult == null) {
    stdout.writeln('REFUSED $name: ${probe['error']}');
    return false;
  }
  if (_hasError(probeResult)) {
    stdout.writeln('REFUSED $name:\n${_problems(probeResult)}');
    stdout.writeln('  head: ${_show(src.substring(start, start + 70 > end ? end : start + 70))}');
    stdout.writeln('  tail: ${_show(src.substring(end - 70 < start ? start : end - 70, end))}');
    return false;
  }
  final feedback = probeResult['feedback']! as Map<String, Object?>;
  final options = {
    'returnType': feedback['returnType'],
    'createGetter': false,
    'name': name,
    'parameters': feedback['parameters'],
    'extractAll': false,
  };
  final response = await _request('edit.getRefactoring', {
    'kind': 'EXTRACT_METHOD',
    'file': serverPath,
    'offset': start,
    'length': length,
    'validateOnly': false,
    'options': options,
  });
  final result = response['result'] as Map<String, Object?>?;
  if (result == null) {
    stdout.writeln('REFUSED $name: ${response['error']}');
    return false;
  }
  if (_hasError(result)) {
    stdout.writeln('REFUSED $name:\n${_problems(result)}');
    return false;
  }
  final change = result['change'] as Map<String, Object?>?;
  if (change == null) {
    stdout.writeln('REFUSED $name: no change');
    return false;
  }
  final fileEdits = change['edits']! as List;
  for (final fe in fileEdits) {
    final m = fe as Map<String, Object?>;
    final editedPath = (m['file']! as String).replaceAll('\\', '/');
    if (editedPath.toLowerCase() != path.toLowerCase()) {
      stdout.writeln('REFUSED $name: edit outside the file: $editedPath');
      return false;
    }
    final edits = (m['edits']! as List)
        .map((e) => e as Map<String, Object?>)
        .toList()
      ..sort((a, b) => (b['offset']! as int).compareTo(a['offset']! as int));
    // A void block whose every path ended in `return;` extracts cleanly,
    // but the analyzer leaves a bare call behind: the caller must still
    // leave. Put the `return;` back after the call.
    final leaves = job['expr'] != true &&
        feedback['returnType'] == 'void' &&
        srcBefore.substring(start, end).trimRight().endsWith('return;');
    for (final e in edits) {
      final offset = e['offset']! as int;
      final len = e['length']! as int;
      var replacement = e['replacement']! as String;
      if (leaves && offset == start) {
        final eol = src.contains('\r\n') ? '\r\n' : '\n';
        replacement += '$eol${' ' * _column(srcBefore, start)}return;';
        stdout.writeln('  (the caller leaves after the call: `return;` kept)');
      }
      src = src.replaceRange(offset, offset + len, replacement);
    }
  }
  if (leadingComment.isNotEmpty) {
    src = _carryComment(src, leadingComment, name);
  }
  if (job['expr'] == true) {
    src = _reindentExpressionBody(src, name, _column(srcBefore, start));
  }
  src = _tearOffs(src, name);
  src = _normaliseAddedImports(srcBefore, src, rel);
  if (_inStaticContext(srcBefore, start)) {
    src = _makeStatic(src, name);
  }
  file.writeAsStringSync(src);
  final params = feedback['parameters'] as List? ?? const [];
  final paramText = params
      .map((p) => '${(p as Map)['type']} ${p['name']}')
      .join(', ');
  stdout.writeln(
    'EXTRACTED $name($paramText) -> ${feedback['returnType']}  '
    '[$rel: $length chars]',
  );
  final warnings = _problems(result);
  if (warnings.isNotEmpty) stdout.writeln('  $warnings');
  await _request('analysis.updateContent', {
    'files': {
      serverPath: {'type': 'add', 'content': src},
    },
  });
  // No idle wait: the next request waits for this file on its own.
  return true;
}

Future<void> main(List<String> args) async {
  final root = args[0].replaceAll('\\', '/');
  final jobs = (jsonDecode(File(args[1]).readAsStringSync()) as List)
      .map((j) => j as Map<String, Object?>)
      .toList();
  _server = await Process.start(
    'dart',
    ['language-server', '--protocol=analyzer'],
    workingDirectory: root,
    runInShell: true,
  );
  _listen();
  await _request('server.setSubscriptions', {
    'subscriptions': ['STATUS'],
  });
  final started = DateTime.now();
  await _request('analysis.setAnalysisRoots', {
    'included': [(args.length > 2 ? args[2] : root).replaceAll('/', Platform.pathSeparator)],
    'excluded': <String>[],
  });
  stdout.writeln('roots set (${args.length > 2 ? args[2] : root})');

  var done = 0;
  for (final job in jobs) {
    final t0 = DateTime.now();
    if (await _runJob(root, job)) done++;
    stdout.writeln('  (${DateTime.now().difference(t0).inSeconds}s, ${DateTime.now().difference(started).inSeconds}s total)');
  }
  stdout.writeln('DONE $done/${jobs.length}');
  await _request('server.shutdown', {});
  _server.kill();
  exit(done == jobs.length ? 0 : 1);
}
int _lineExact(String src, String lineText, int from) {
  var at = from;
  while (true) {
    final hit = src.indexOf('\n$lineText', at);
    if (hit < 0) return -1;
    final after = hit + 1 + lineText.length;
    if (after >= src.length || src[after] == '\n' || src[after] == '\r') {
      return hit + 1;
    }
    at = hit + 1;
  }
}

/// Where the job's selection starts and ends in [src].
///
/// `startText` is found by `occurrence` (1-based), or relative to `near`
/// (a unique text): the last hit at or before it, or the first at or after
/// it with `nearAfter`. Statements run from the first non-blank character
/// of the start line to the end of the end line; `endText` is the first
/// hit after the start (`endPlus` extends that by N lines). Expressions run
/// from the start hit; with `balanced` the end is the bracket matching the
/// one `endText` (or `startText`) ends with, otherwise `endText`'s end.
(int, int) _selection(String src, Map<String, Object?> job) {
  final expr = job['expr'] == true;
  final balanced = job['balanced'] == true;
  final startText = job['startText']! as String;
  final endText = job['endText'] as String?;
  final near = job['near'] as String?;
  int startHit;
  if (near != null) {
    final nearHit = _offsetOf(src, near, 1, 'near');
    if (src.indexOf(near, nearHit + 1) >= 0) {
      throw StateError('near is not unique: "$near"');
    }
    startHit = job['nearAfter'] == true
        ? src.indexOf(startText, nearHit)
        : src.lastIndexOf(startText, nearHit);
    if (startHit < 0) throw StateError('startText not found near: "$startText"');
  } else {
    startHit = _offsetOf(src, startText, (job['occurrence'] as int?) ?? 1, 'startText');
  }
  final start = expr ? startHit : _codeStart(src, startHit);
  if (balanced) {
    // The bracket to balance: endText's last character, else startText's
    // last — or its FIRST with `openAtStart` (a multi-line anchor that
    // begins with the bracket).
    final openAt = endText != null
        ? src.indexOf(endText, startHit) + endText.length - 1
        : job['openAtStart'] == true
        ? startHit
        : startHit + startText.length - 1;
    if (openAt < startHit) throw StateError('endText not found: "$endText"');
    final close = _matchingClose(src, openAt);
    final end = expr ? close + 1 : _lineEnd(src, close);
    return (start, end);
  }
  if (endText == null) throw StateError('endText required');
  // `endNear`: the end anchor is the LAST hit of endText before that
  // (unique) text — for a block whose last statement repeats earlier in it.
  final endNear = job['endNear'] as String?;
  final int endHit;
  if (endNear != null) {
    final endNearHit = _offsetOf(src, endNear, 1, 'endNear');
    if (src.indexOf(endNear, endNearHit + 1) >= 0) {
      throw StateError('endNear is not unique: "$endNear"');
    }
    endHit = src.lastIndexOf(endText, endNearHit);
  } else {
    endHit = expr ? src.indexOf(endText, startHit) : _lineExact(src, endText, startHit);
  }
  final endHitLoose = endHit < 0 ? src.indexOf(endText, startHit) : endHit;
  if (endHitLoose < 0) throw StateError('endText not found after start: "$endText"');
  var end = expr ? endHitLoose + endText.length : _lineEnd(src, endHitLoose);
  for (var i = 0; i < ((job['endPlus'] as int?) ?? 0); i++) {
    end = _lineEnd(src, src.indexOf('\n', end) + 1);
  }
  return (start, end);
}

/// The index of the bracket closing the one at [openAt], skipping strings
/// and comments.
int _matchingClose(String src, int openAt) {
  final open = src[openAt];
  final close = switch (open) {
    '(' => ')',
    '[' => ']',
    '{' => '}',
    _ => throw StateError('not a bracket at $openAt: "$open"'),
  };
  var depth = 0;
  var i = openAt;
  while (i < src.length) {
    final c = src[i];
    if (c == '/' && i + 1 < src.length && src[i + 1] == '/') {
      i = src.indexOf('\n', i);
      if (i < 0) break;
      continue;
    }
    if (c == '/' && i + 1 < src.length && src[i + 1] == '*') {
      i = src.indexOf('*/', i) + 2;
      continue;
    }
    if (c == "'" || c == '"') {
      i = _skipString(src, i);
      continue;
    }
    if (c == open) depth++;
    if (c == close) {
      depth--;
      if (depth == 0) return i;
    }
    i++;
  }
  throw StateError('no matching $close for the $open at $openAt');
}

int _skipString(String src, int at) {
  final quote = src[at];
  final triple = src.startsWith(quote * 3, at);
  var i = at + (triple ? 3 : 1);
  while (i < src.length) {
    final c = src[i];
    if (c == r'\') {
      i += 2;
      continue;
    }
    if (triple ? src.startsWith(quote * 3, i) : c == quote) {
      return i + (triple ? 3 : 1);
    }
    i++;
  }
  return src.length;
}

/// The first non-blank, non-comment character at or after the line of
/// [anchor] — a selection may not begin inside a comment.
int _codeStart(String src, int anchor) {
  var at = _lineStartNonBlank(src, anchor);
  while (at < src.length && (src.startsWith('//', at) || src[at] == '\r' || src[at] == '\n')) {
    final nl = src.indexOf('\n', at);
    if (nl < 0) return src.length;
    at = _lineStartNonBlank(src, nl + 1);
  }
  return at;
}

/// The comment lines between the start anchor's line and the code the
/// selection begins with — whole lines, indentation included.
String _leadingComment(String src, Map<String, Object?> job) {
  final expr = job['expr'] == true;
  if (expr) return '';
  final (start, _) = _selection(src, job);
  final anchorHit = _anchorHit(src, job);
  final anchorLine = src.lastIndexOf('\n', anchorHit - 1) + 1;
  final codeLine = src.lastIndexOf('\n', start - 1) + 1;
  if (codeLine <= anchorLine) return '';
  return src.substring(anchorLine, codeLine);
}

int _anchorHit(String src, Map<String, Object?> job) {
  final startText = job['startText']! as String;
  final near = job['near'] as String?;
  if (near != null) {
    final nearHit = _offsetOf(src, near, 1, 'near');
    return job['nearAfter'] == true
        ? src.indexOf(startText, nearHit)
        : src.lastIndexOf(startText, nearHit);
  }
  return _offsetOf(src, startText, (job['occurrence'] as int?) ?? 1, 'startText');
}

/// Moves [comment] (whole lines, still sitting above the call) to the top
/// of the body of the method [name] the analyzer just declared.
String _carryComment(String src, String comment, String name) {
  final at = src.indexOf(comment);
  if (at < 0) return src;
  src = src.replaceRange(at, at + comment.length, '');
  final decl = RegExp(
    '^[ \t]+[A-Za-z_][A-Za-z0-9_<>,? ]*[ \t]+${RegExp.escape(name)}\\(',
    multiLine: true,
  );
  final m = decl.firstMatch(src);
  if (m == null) {
    stderr.writeln('  (comment not carried: declaration of $name not found)');
    return src;
  }
  final brace = _bodyBrace(src, m.end - 1);
  final bodyLine = src.indexOf('\n', brace) + 1;
  final indentEnd = _lineStartNonBlank(src, bodyLine);
  final indent = src.substring(bodyLine, indentEnd);
  final eol = src.contains('\r\n') ? '\r\n' : '\n';
  final lines = comment.split('\n').where((l) => l.trim().isNotEmpty);
  final moved = lines.map((l) => '$indent${l.trim()}$eol').join();
  return src.replaceRange(bodyLine, bodyLine, moved);
}

String _show(String text) => text.replaceAll('\r', '').replaceAll('\n', '⏎');

/// The `{` opening a declaration's body: the one after the parameter
/// list's matching `)` — a record-typed parameter has braces of its own.
int _bodyBrace(String src, int paramsOpen) =>
    src.indexOf('{', _matchingClose(src, paramsOpen));

/// Whether [offset] sits in a static method or a factory constructor —
/// the analyzer declares the extracted method as an instance member
/// either way, which such a caller cannot reach.
bool _inStaticContext(String src, int offset) {
  final member = _enclosingMember(src, offset);
  return switch (member) {
    MethodDeclaration(isStatic: true) => true,
    ConstructorDeclaration(factoryKeyword: != null) => true,
    _ => false,
  };
}

/// Prefixes the declaration of [name] with `static`.
String _makeStatic(String src, String name) {
  final decl = RegExp(
    '^([ \\t]+)([A-Za-z_][A-Za-z0-9_<>,? ]*[ \\t]+${RegExp.escape(name)}\\()',
    multiLine: true,
  );
  final m = decl.firstMatch(src);
  if (m == null) return src;
  stdout.writeln('  (declared static: the caller is a static context)');
  return src.replaceRange(m.start, m.end, '${m.group(1)}static ${m.group(2)}');
}

ClassMember? _enclosingMember(String src, int offset) {
  final unit = parseString(
    content: src,
    featureSet: FeatureSet.latestLanguageVersion(),
    throwIfDiagnostics: false,
  ).unit;
  for (final declaration in unit.declarations) {
    if (declaration is! ClassDeclaration) continue;
    for (final member in declaration.body.members) {
      if (member.offset <= offset && offset < member.end) return member;
    }
  }
  return null;
}

/// The end offset of the class member that contains [offset], parsed.
int _enclosingMemberEnd(String src, int offset) {
  final unit = parseString(
    content: src,
    featureSet: FeatureSet.latestLanguageVersion(),
    throwIfDiagnostics: false,
  ).unit;
  for (final declaration in unit.declarations) {
    if (declaration is! ClassDeclaration) continue;
    for (final member in declaration.body.members) {
      if (member.offset <= offset && offset < member.end) return member.end;
    }
  }
  throw StateError('no class member encloses offset $offset');
}

int _column(String src, int offset) => offset - (src.lastIndexOf('\n', offset - 1) + 1);

/// The extracted method's body is `return <expr>` with the expression's
/// continuation lines still at the call site's column [startColumn];
/// shift them so the expression's own first line is the reference (it
/// now sits after `return ` at the body indent of 4).
String _reindentExpressionBody(String src, String name, int startColumn) {
  final decl = RegExp(
    '^[ \t]+[A-Za-z_][A-Za-z0-9_<>,? ]*[ \t]+${RegExp.escape(name)}\\(',
    multiLine: true,
  );
  final m = decl.firstMatch(src);
  if (m == null) return src;
  final brace = _bodyBrace(src, m.end - 1);
  final close = _matchingClose(src, brace);
  final bodyStart = src.indexOf('\n', brace) + 1;
  if (close < bodyStart) {
    stderr.writeln(
      'reindent $name: matched "${_show(src.substring(m.start, m.end))}" '
      'brace $brace close $close bodyStart $bodyStart — left as is',
    );
    return src;
  }
  final body = src.substring(bodyStart, close);
  final eol = body.contains('\r\n') ? '\r\n' : '\n';
  final lines = body.split(eol);
  var last = lines.length - 1;
  while (last > 0 && lines[last].trim().isEmpty) {
    last--;
  }
  var lastLead = 0;
  while (lastLead < lines[last].length && lines[last][lastLead] == ' ') {
    lastLead++;
  }
  final shift = 4 - lastLead;
  if (shift >= 0 || last == 0) return src;
  final out = <String>[];
  for (var i = 0; i < lines.length; i++) {
    final line = lines[i];
    if (i == 0 || line.trim().isEmpty) {
      out.add(line);
      continue;
    }
    var lead = 0;
    while (lead < line.length && line[lead] == ' ') {
      lead++;
    }
    final cut = lead + shift < 0 ? lead : -shift;
    out.add(line.substring(cut));
  }
  return src.replaceRange(bodyStart, close, out.join(eol));
}

/// `(x) { _name(x); }` — the shape the analyzer leaves when a lambda's
/// whole body was extracted — becomes the tear-off `_name`.
String _tearOffs(String src, String name) {
  final re = RegExp(r'\(\s*(\w+)\s*\)\s*\{\s*' + RegExp.escape(name) + r'\(\s*\1\s*\);\s*\}');
  return src.replaceAllMapped(re, (_) => name);
}

/// A lambda's WHOLE body becomes a method and the lambda its tear-off —
/// done here, not by the server, because the refactoring refuses a
/// selection with early returns even when it is an entire body (where a
/// `return` keeps its meaning). The parameter's type is the job's
/// `paramType` — `flutter analyze` is what checks it.
///
///   {"lambdaBody": true, "startText": "onPointerDown: (event) {",
///    "near": "...", "nearAfter": true, "paramType": "PointerDownEvent",
///    "name": "_toolTapDown"}
Future<bool> _liftLambdaBody(String root, Map<String, Object?> job) async {
  final rel = job['file']! as String;
  final path = '$root/$rel'.replaceAll('\\', '/');
  final file = File(path);
  var src = file.readAsStringSync();
  final name = job['name']! as String;
  // One positional parameter is typed by `paramType`; anything richer is
  // spelled whole by `paramList` (e.g. "double delta, {required bool snap}").
  final paramType = job['paramType'] as String?;
  final paramList = job['paramList'] as String?;
  final anchor = _anchorHit(src, job);
  final startText = job['startText']! as String;
  final lambdaAt = src.indexOf('(', anchor + startText.indexOf('('));
  final paramClose = src.indexOf(')', lambdaAt);
  final param = src.substring(lambdaAt + 1, paramClose).trim();
  final brace = src.indexOf('{', paramClose);
  final close = _matchingClose(src, brace);
  final eol = src.contains('\r\n') ? '\r\n' : '\n';
  // The body: the lines between the braces, re-indented to a method body.
  final bodyStart = src.indexOf('\n', brace) + 1;
  final bodyLines = src.substring(bodyStart, close).split(eol);
  while (bodyLines.isNotEmpty && bodyLines.last.trim().isEmpty) {
    bodyLines.removeLast();
  }
  var minLead = 1 << 20;
  for (final line in bodyLines) {
    if (line.trim().isEmpty) continue;
    var lead = 0;
    while (lead < line.length && line[lead] == ' ') {
      lead++;
    }
    if (lead < minLead) minLead = lead;
  }
  final body = bodyLines
      .map((l) => l.trim().isEmpty ? '' : '    ${l.substring(minLead)}')
      .join(eol);
  // The enclosing class member, from the AST: the new method goes right
  // after it. Inserted BEFORE the lambda is replaced, so the insertion
  // point (below the lambda) needs no offset arithmetic.
  final memberEnd = _enclosingMemberEnd(src, anchor);
  final signature = paramList ?? '$paramType $param';
  final method = '$eol  void $name($signature) {$eol$body$eol  }$eol';
  final insertAt = src.indexOf('\n', memberEnd) + 1;
  src = src.replaceRange(insertAt, insertAt, method);
  src = src.replaceRange(lambdaAt, close + 1, name);
  file.writeAsStringSync(src);
  stdout.writeln('LIFTED $name($signature)  [$rel: ${bodyLines.length} lines]');
  return true;
}

/// The analyzer imports a type it needs by `package:` URI; this repo
/// imports its own files relatively. Rewrite an added import to the
/// relative form, and drop it when that form is already there.
String _normaliseAddedImports(String before, String after, String rel) {
  final re = RegExp(
    r"^import 'package:anicel/([^']+)';[ \t]*\r?\n",
    multiLine: true,
  );
  final fileDir = rel.substring(0, rel.lastIndexOf('/')).split('/');
  final widen = <String>[];
  var out = after.replaceAllMapped(re, (m) {
    final whole = m.group(0)!;
    if (before.contains(whole)) return whole;
    final target = 'lib/${m.group(1)!}'.split('/');
    var common = 0;
    while (common < fileDir.length &&
        common < target.length - 1 &&
        fileDir[common] == target[common]) {
      common++;
    }
    final up = List.filled(fileDir.length - common, '..');
    final relative = [...up, ...target.sublist(common)].join('/');
    final line = "import '$relative';";
    if (before.contains(line)) {
      stdout.writeln('  (added import dropped: already imported as $relative)');
      return '';
    }
    // The same file imported with a `show` list: the analyzer needed a name
    // the list hides, so the list is widened away — the reader keeps the
    // file's own import line.
    final shown = RegExp(
      "^import '${RegExp.escape(relative)}'\\s+show [^;]+;",
      multiLine: true,
    );
    if (shown.hasMatch(after)) {
      stdout.writeln('  (added import folded into the existing `show` import of $relative)');
      widen.add(relative);
      return '';
    }
    stdout.writeln('  (added import made relative: $relative)');
    final eol = whole.endsWith('\r\n') ? '\r\n' : '\n';
    return '$line$eol';
  });
  for (final relative in widen) {
    final shown = RegExp(
      "^import '${RegExp.escape(relative)}'\\s+show [^;]+;",
      multiLine: true,
    );
    out = out.replaceFirst(shown, "import '$relative';");
  }
  return out;
}
