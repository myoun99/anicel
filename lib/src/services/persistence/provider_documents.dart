/// PICK-7: projects in a document provider with no filesystem path behind
/// them — Google Drive and its kind on Android.
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../../core/path_names.dart';
import 'app_documents.dart';
import 'session_scratch.dart';

/// A document the OS handed over with no filesystem path behind it: the
/// provider answers to [uri] and reads and writes it; [name] is what it is
/// called there, [length] its size when the provider says.
@immutable
class ProviderDocument {
  const ProviderDocument({required this.uri, required this.name, this.length});

  final String uri;
  final String name;
  final int? length;

  @override
  bool operator ==(Object other) =>
      other is ProviderDocument &&
      other.uri == uri &&
      other.name == name &&
      other.length == length;

  @override
  int get hashCode => Object.hash(uri, name, length);

  @override
  String toString() => 'ProviderDocument($name, $uri)';
}

/// A provider that did not take — or did not give — the bytes asked of it.
class ProviderDocumentRefused implements Exception {
  const ProviderDocumentRefused(this.document, this.reason);

  final ProviderDocument document;
  final String reason;

  @override
  String toString() => '${document.name}: $reason';
}

/// One document on its way into its working copy ([ProviderDocuments.copyIn]).
class ProviderCopy {
  ProviderCopy._(this.destination, this.done);

  /// Where the working copy stands once [done] answers true.
  final String destination;

  /// True once the whole document stands at [destination]; false when the
  /// provider refused it or the copy was stopped.
  final Future<bool> done;

  /// How many bytes have come so far.
  Future<int> moved() => ProviderDocuments._moved(destination);

  /// Stops the copy; what came so far goes with it.
  void stop() => unawaited(
    ProviderDocuments._call('cancelDocumentCopy', {
      'destinationPath': destination,
    }),
  );
}

/// 🗣️유저 2026-09-27 ([[android-cloud-project-open-Q1]]): 「드라이브 파일을
/// 그대로 읽고, 저장은 통째로 다시 쓴다」 — then 「통째로 다시쓸수밖에
/// 없는건가? 증분저장못하고, 일단진행해줘」.
///
/// 🚨★★★**A WORKING COPY, BECAUSE THE ARCHIVE IS READ WHERE IT LIES.** A
/// saved cel is `{path, offset, length}` into the project file and is read
/// back on demand; carried media reach the native decoders as a path and a
/// span. None of that goes through a provider's stream: the descriptor a
/// provider hands out cannot be reopened by path when it is another app's
/// private cache, a provider that streams through a pipe cannot be read at
/// an offset at all, and a save has to read the old file while it writes
/// the new one, which a document being rewritten cannot give it. So the
/// project is copied into this run's room once, when it opens
/// ([SessionScratch.openedFolder]); saved THERE like any local file —
/// incrementally; and handed back WHOLE after every save ([publish]). The
/// answer carried this road as its own fallback (「안 되면 「작업본」으로
/// 가야 한다」). The provider uploads a whole file either way.
///
/// ⚠️A file on the device's own storage is never one of these: the native
/// side finds its real path first, whichever tab of the picker it came
/// through, so it is read and saved in place with no copy at all.
abstract final class ProviderDocuments {
  /// Test seam for the native half — the channel is unreachable from a
  /// Dart test, as every picker's is.
  /// ⚠️Reset in `test/flutter_test_config.dart` ([debugReset]).
  @visibleForTesting
  static Future<Map<Object?, Object?>?> Function(
    String method,
    Map<String, Object?> arguments,
  )?
  debugChannel;

  /// Forgets every document and working copy, and the seam.
  @visibleForTesting
  static void debugReset() {
    debugChannel = null;
    _known.clear();
    _workingCopies.clear();
  }

  /// Every document this run has been handed, by URI.
  static final Map<String, ProviderDocument> _known = {};

  /// The working copy each document is worked on in, by URI — the latest
  /// one, when a document was opened again after its tab closed.
  static final Map<String, String> _workingCopies = {};

  /// Whether [path] names a provider document rather than a file.
  static bool isDocumentUri(String path) => path.startsWith('content://');

  /// Keeps [document]'s name for the steps after the pick that only have
  /// its URI.
  static void remember(ProviderDocument document) {
    _known[document.uri] = document;
  }

  /// The document [uri] names, when this run has been handed it.
  static ProviderDocument? known(String uri) => _known[uri];

  /// What [pathOrUri] is called: the provider's own name for a document,
  /// the file name for anything else.
  static String nameOf(String pathOrUri) =>
      _known[pathOrUri]?.name ?? fileNameOfPath(pathOrUri);

  /// The working copy [uri] is being worked on in this run, if any.
  static String? workingCopyOf(String uri) => _workingCopies[uri];

  /// The document [path] is the working copy of — or null for every other
  /// file, which is to say nearly always.
  static ProviderDocument? documentBehind(String path) {
    final spelled = path.replaceAll(r'\', '/');
    for (final MapEntry(key: uri, value: copy) in _workingCopies.entries) {
      if (copy == spelled) {
        return _known[uri] ?? ProviderDocument(uri: uri, name: nameOf(copy));
      }
    }
    return null;
  }

  /// Starts bringing [uri] into a fresh working copy.
  static ProviderCopy copyIn(String uri) {
    final destination = _freshWorkingCopy(nameOf(uri));
    final done = _call('copyDocument', {
      'uri': uri,
      'destinationPath': destination,
    }).then((answer) {
      if (answer?['status'] != 'granted') {
        return false;
      }
      _workingCopies[uri] = destination;
      return true;
    });
    return ProviderCopy._(destination, done);
  }

  /// [staged] — a whole project the picker has just poured into [document]
  /// — becomes that document's working copy: MOVED into the room, not
  /// copied, so the one file on this device is the one the saves carry on
  /// in. Answers where it stands now.
  static String adoptAsWorkingCopy(ProviderDocument document, String staged) {
    final destination = _freshWorkingCopy(document.name);
    try {
      File(staged).renameSync(destination);
    } on FileSystemException {
      // Another volume: the room and the staging folder need not share one.
      File(staged).copySync(destination);
      File(staged).deleteSync();
    }
    remember(document);
    _workingCopies[document.uri] = destination;
    return destination;
  }

  /// Hands [workingCopy] back to the document it was opened from, whole —
  /// how every save of such a project ends. Nothing to do for any other
  /// file. Throws [ProviderDocumentRefused] when the provider does not take
  /// it.
  static Future<void> publish(
    String workingCopy, {
    void Function(double)? onProgress,
  }) async {
    final document = documentBehind(workingCopy);
    if (document == null) {
      return;
    }
    final length = File(workingCopy).lengthSync();
    var finished = false;
    final writing = _call('writeDocument', {
      'uri': document.uri,
      'sourcePath': workingCopy,
    }).whenComplete(() => finished = true);
    if (onProgress != null && length > 0) {
      while (!finished) {
        await Future.any<void>([
          writing.then<void>((_) {}),
          Future<void>.delayed(_progressEvery),
        ]);
        if (!finished) {
          onProgress((await _moved(workingCopy) / length).clamp(0.0, 1.0));
        }
      }
    }
    final answer = await writing;
    if (answer?['status'] != 'granted') {
      throw ProviderDocumentRefused(
        document,
        '${answer?['error'] ?? answer?['status'] ?? 'unavailable'}',
      );
    }
    onProgress?.call(1);
  }

  static const Duration _progressEvery = Duration(milliseconds: 250);

  /// A folder of its own in this run's room, holding a file under the
  /// document's own name — the name the session, its tab and a backup show.
  static String _freshWorkingCopy(String name) {
    final folder =
        '${SessionScratch.openedFolder().replaceAll(r'\', '/')}/'
        '${DateTime.now().microsecondsSinceEpoch}';
    Directory(folder).createSync(recursive: true);
    return '$folder/${_fileNameFor(name)}';
  }

  /// [name] as a file name: a provider's name may hold what a path cannot.
  static String _fileNameFor(String name) {
    final safe = name.replaceAll(RegExp(r'[/\\:*?"<>|\x00-\x1f]'), '_').trim();
    return safe.isEmpty ? 'project' : safe;
  }

  static Future<int> _moved(String path) async {
    final answer = await _invokeValue('documentTransferred', {'path': path});
    return answer is int ? answer : 0;
  }

  /// A native answer, or null when the channel is missing or threw.
  static Future<Map<Object?, Object?>?> _call(
    String method,
    Map<String, Object?> arguments,
  ) async {
    final override = debugChannel;
    if (override != null) {
      return override(method, arguments);
    }
    try {
      return await AppStorage.channel.invokeMapMethod<Object?, Object?>(
        method,
        arguments,
      );
    } on Object {
      return null;
    }
  }

  static Future<Object?> _invokeValue(
    String method,
    Map<String, Object?> arguments,
  ) async {
    final override = debugChannel;
    if (override != null) {
      return (await override(method, arguments))?['value'];
    }
    try {
      return await AppStorage.channel.invokeMethod<Object?>(method, arguments);
    } on Object {
      return null;
    }
  }
}
