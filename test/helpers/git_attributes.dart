import 'dart:io';

/// The line ending git checks a path out with, by the `.gitattributes` at
/// [attributesPath]: the `eol=` of the last rule that matches the path, as
/// in git, and `unspecified` where none names one.
///
/// ⚠️IN-PROCESS, not by asking git: `tests_do_not_race_the_code_test` bans
/// spawning, so the rules are read from the file and matched with the part
/// of git's pattern rules that file uses ([_gitPattern]).
String Function(String path) eolRulesOf(String attributesPath) {
  final rules = <(RegExp, String)>[];
  for (final raw in File(attributesPath).readAsLinesSync()) {
    final line = raw.trim();
    if (line.isEmpty || line.startsWith('#')) {
      continue;
    }
    final fields = line.split(RegExp(r'\s+'));
    for (final attribute in fields.skip(1)) {
      if (attribute.startsWith('eol=')) {
        rules.add((_gitPattern(fields.first), attribute.substring(4)));
      }
    }
  }
  return (path) {
    var eol = 'unspecified';
    for (final (pattern, value) in rules) {
      if (pattern.hasMatch(path)) {
        eol = value; // The last rule that matches wins, as in git.
      }
    }
    return eol;
  };
}

/// git's pattern rules, as far as `.gitattributes` uses them: a pattern
/// with a slash is anchored at the repository root and one without matches
/// a file name at any depth; `**` crosses directories, `*` and `?` stay
/// inside one path segment.
RegExp _gitPattern(String pattern) {
  final relative = pattern.startsWith('/') ? pattern.substring(1) : pattern;
  final body = StringBuffer();
  for (var i = 0; i < relative.length; i += 1) {
    if (relative.startsWith('**', i)) {
      body.write('.*');
      i += 1;
    } else if (relative[i] == '*') {
      body.write('[^/]*');
    } else if (relative[i] == '?') {
      body.write('[^/]');
    } else {
      body.write(RegExp.escape(relative[i]));
    }
  }
  return RegExp(pattern.contains('/') ? '^$body\$' : '(^|/)$body\$');
}
