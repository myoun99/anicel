/// RELINK-2: matching missing media against a folder the user points at.
///
/// Pure — no `dart:io` — because the rule is the part that can be wrong in
/// ways a file system cannot demonstrate. The walk that produces the
/// candidate list belongs to the caller.
///
/// 🚨The trap this exists to avoid: **a file name is not unique on a real
/// production drive.** `A1.png` and `A2.png` repeat in every cut folder, so
/// matching by name alone would relink dozens of assets to pictures from
/// the wrong cut — silently, and with one undo step to notice it in.
///
/// So the rule is: gather by name, then SPLIT BY TAIL. A candidate is only
/// accepted when the decision is forced — either the name is unique under
/// the chosen folder, or a suffix of the original path (`C-045/A1.png`)
/// picks exactly one of the candidates. Anything still ambiguous is left
/// out and reported, because the alternative is choosing arbitrarily on the
/// user's behalf and being wrong at scale.
library;

/// What a relink pass decided.
class MediaRelinkPlan {
  const MediaRelinkPlan({required this.matched, required this.unmatched});

  /// Old path → new path, for the assets whose destination was forced.
  final Map<String, String> matched;

  /// The ones left alone: no candidate, or more than one and nothing to
  /// tell them apart. Kept so the preview can say "M of N".
  final List<String> unmatched;

  bool get isEmpty => matched.isEmpty;
}

/// Matches [missingPaths] against [candidatePaths].
///
/// [candidatePaths] is every file found under the folder the user chose
/// (recursively — a production folder splits by cut, so the file being
/// hunted is almost never at the top).
MediaRelinkPlan planMediaRelink({
  required Iterable<String> missingPaths,
  required Iterable<String> candidatePaths,
}) {
  final byName = <String, List<String>>{};
  for (final raw in candidatePaths) {
    final candidate = _normalize(raw);
    final name = _fileName(candidate);
    if (name.isEmpty) {
      continue;
    }
    (byName[name.toLowerCase()] ??= <String>[]).add(candidate);
  }

  final matched = <String, String>{};
  final unmatched = <String>[];
  // Destination → the old paths that want it. Two assets landing on one
  // file is not a relink, it is a collision, and it is resolved by
  // dropping BOTH rather than by letting insertion order decide.
  final claimed = <String, List<String>>{};

  for (final raw in missingPaths) {
    final missing = _normalize(raw);
    final candidates = byName[_fileName(missing).toLowerCase()] ?? const [];
    // The extension has to survive: a `.png` and a `.psd` of the same name
    // are different files, and swapping one for the other would decode to
    // a failure much later and somewhere else.
    final sameKind = [
      for (final candidate in candidates)
        if (_extension(candidate) == _extension(missing)) candidate,
    ];
    final chosen = _chooseByTail(missing, sameKind);
    if (chosen == null) {
      unmatched.add(missing);
      continue;
    }
    (claimed[chosen] ??= <String>[]).add(missing);
  }

  for (final entry in claimed.entries) {
    if (entry.value.length == 1) {
      matched[entry.value.single] = entry.key;
    } else {
      unmatched.addAll(entry.value);
    }
  }

  // Stable order so a preview reads the same way twice.
  unmatched.sort();
  return MediaRelinkPlan(matched: matched, unmatched: unmatched);
}

/// The one candidate a suffix of [missing] forces, or null when nothing
/// does.
///
/// Walks the original path from the file name outwards — `A1.png`, then
/// `C-045/A1.png`, then `cuts/C-045/A1.png` — and stops the moment exactly
/// one candidate still ends with it. That IS the "tail match first" rule:
/// when the name is already unique the loop settles on the first step and
/// never looks at the folders, and when it is not, the folders are what
/// decide.
String? _chooseByTail(String missing, List<String> candidates) {
  if (candidates.isEmpty) {
    return null;
  }
  if (candidates.length == 1) {
    return candidates.single;
  }
  final segments = missing.split('/');
  var remaining = candidates;
  for (var take = 1; take <= segments.length; take++) {
    final tail = segments.sublist(segments.length - take).join('/');
    final suffix = '/$tail';
    final next = [
      for (final candidate in remaining)
        if (candidate == tail || candidate.endsWith(suffix)) candidate,
    ];
    if (next.length == 1) {
      return next.single;
    }
    if (next.isEmpty) {
      // A longer tail cannot match where a shorter one already failed —
      // the previous round's survivors are the best this can do, and they
      // are still ambiguous.
      return null;
    }
    remaining = next;
  }
  return null;
}

String _normalize(String path) => path.replaceAll('\\', '/');

String _fileName(String path) {
  final slash = path.lastIndexOf('/');
  return slash < 0 ? path : path.substring(slash + 1);
}

/// Lowercased, including the dot; empty when there is none. Compared rather
/// than parsed, so `.tar.gz`-style names simply compare their last part on
/// both sides.
String _extension(String path) {
  final name = _fileName(path);
  final dot = name.lastIndexOf('.');
  return dot <= 0 ? '' : name.substring(dot).toLowerCase();
}
