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
///
/// When the folders cannot force it either, the CONTENT is asked — length
/// first because a `stat` settles most of it, and a recorded CRC only when
/// one is both available and still needed.
library;

import '../../models/media_identity.dart';

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
  /// What the PROJECT recorded about a missing asset's content, or null
  /// when it recorded nothing. Free to call — it reads a map.
  MediaIdentity? Function(String missingPath)? recordedIdentity,

  /// What a candidate ON DISK is, given what is being looked for.
  ///
  /// 🚨 This one costs. It is called ONLY for candidates that survived the
  /// tail walk and still tie, which on a production drive is a handful out
  /// of thousands. [wanted] is passed so the reader can stop early: a
  /// length that already differs is decisive without opening the file, and
  /// a [wanted] with no CRC means reading the candidate's bytes cannot
  /// change any answer.
  MediaIdentity? Function(String candidatePath, MediaIdentity wanted)?
  candidateIdentity,
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
    final chosen =
        _chooseByTail(missing, sameKind) ??
        _chooseByContent(
          missing,
          sameKind,
          recordedIdentity: recordedIdentity,
          candidateIdentity: candidateIdentity,
        );
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

/// The one candidate whose CONTENT forces it, or null.
///
/// Runs only where the tail walk gave up — the folders could not tell these
/// apart, so the bytes are asked instead. Two steps, cheap one first:
///
/// 1. **Length.** A candidate whose size differs is provably not the file,
///    and saying so costs a `stat`. This alone settles the common shape of
///    the problem, because two different drawings that happen to share the
///    name `A1.png` almost never weigh the same. When it leaves exactly one
///    standing, no file is ever opened.
/// 2. **CRC**, and only when the project recorded one AND more than one
///    candidate survived step 1. Without a recorded fingerprint there is
///    nothing to compare against, and reading every candidate to build one
///    would be paying the price for an answer that cannot arrive.
///
/// ⛔ Still refuses to guess. `unknown` is not a match, ties are not broken
/// arbitrarily, and two survivors mean the caller reports rather than picks
/// — the rule the whole file is built on does not bend because a new kind
/// of evidence arrived.
String? _chooseByContent(
  String missing,
  List<String> candidates, {
  MediaIdentity? Function(String missingPath)? recordedIdentity,
  MediaIdentity? Function(String candidatePath, MediaIdentity wanted)?
  candidateIdentity,
}) {
  if (candidates.length < 2 ||
      recordedIdentity == null ||
      candidateIdentity == null) {
    return null;
  }
  final wanted = recordedIdentity(missing);
  if (wanted == null) {
    return null;
  }
  final proven = <String>[];
  final possible = <String>[];
  for (final candidate in candidates) {
    final found = candidateIdentity(candidate, wanted);
    if (found == null) {
      continue;
    }
    switch (wanted.compare(found)) {
      case MediaIdentityMatch.same:
        proven.add(candidate);
      case MediaIdentityMatch.unknown:
        possible.add(candidate);
      case MediaIdentityMatch.different:
        break;
    }
  }
  // ⛔ Every candidate is walked before deciding, and two proven matches
  // are refused rather than resolved by whichever came first. Byte-identical
  // copies of one drawing DO sit in a production folder — the same cel
  // handed to two cuts — and either would render correctly, but the path
  // written down is not the same path, and choosing it for the user is the
  // thing this file exists to not do.
  if (proven.isNotEmpty) {
    return proven.length == 1 ? proven.single : null;
  }
  // Nothing proven: the length alone may still have forced it, by leaving
  // exactly one candidate that could be the file at all.
  return possible.length == 1 ? possible.single : null;
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
