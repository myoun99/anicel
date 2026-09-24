import 'dart:io';

/// Why a save did not reach its file — the part a person can act on, read
/// off the error the platform gave.
///
/// 🗣️유저 2026-09-23 (whole-write-temp-beside-the-file Q2): 「왜
/// 실패했는지(파일을 잡고있어서)같은것들 정확하게 알기쉽게 명시」. The
/// notice used to print the exception — `PathAccessException: Cannot rename
/// file … errno = 5` — which names a system call, not a reason.
enum SaveFailureCause {
  /// Another program holds the file — a sync client, a scanner, another
  /// app with it open.
  fileInUse,

  /// The file or its folder refuses writing — read-only, or no permission.
  readOnly,

  /// No room left where the file lives.
  diskFull,

  /// The place is not there any more — the drive went, the network
  /// dropped, the folder was removed.
  locationGone,

  /// The platform's file provider refused to take the new file in place
  /// (the coordinated replace answered no — Apple, Android).
  replaceRefused,

  /// Anything else: the error's own words are all there is.
  unknown,
}

/// What [error] says about why a save of [projectPath] failed.
///
/// 🔬**Measured on Windows, 2026-09-23**, not assumed: a rename onto a file
/// ANOTHER PROCESS holds answers 5 (access denied) — not 32 — and so does a
/// rename onto a read-only file; an append onto a held file answers 32. So
/// 5 alone cannot tell 「someone has it open」 from 「it is read-only」, and
/// the file's own write bits do: Dart reports a read-only file as mode 444.
///
/// [onWindows] is the platform the codes are read in — the test's lever,
/// since the same number means different things on the two families.
SaveFailureCause saveFailureCauseOf(
  Object error, {
  required String projectPath,
  bool? onWindows,
}) {
  if (error is SaveNotSwappedIn && error.refusedByProvider) {
    return SaveFailureCause.replaceRefused;
  }
  if (error is! FileSystemException) {
    return SaveFailureCause.unknown;
  }
  final code = error.osError?.errorCode;
  if (code == null) {
    return SaveFailureCause.unknown;
  }
  return (onWindows ?? Platform.isWindows)
      ? _windowsCause(code, projectPath)
      : _posixCause(code);
}

SaveFailureCause _windowsCause(int code, String projectPath) =>
    switch (code) {
      // ERROR_SHARING_VIOLATION, ERROR_LOCK_VIOLATION.
      32 || 33 => SaveFailureCause.fileInUse,
      // ERROR_ACCESS_DENIED — see [saveFailureCauseOf].
      5 => _writable(projectPath)
          ? SaveFailureCause.fileInUse
          : SaveFailureCause.readOnly,
      // ERROR_WRITE_PROTECT.
      19 => SaveFailureCause.readOnly,
      // ERROR_HANDLE_DISK_FULL, ERROR_DISK_FULL.
      39 || 112 => SaveFailureCause.diskFull,
      // Not found, no path, no drive, drive not ready, and the network's
      // own ways of being gone.
      2 || 3 || 15 || 21 || 53 || 64 || 67 || 1167 || 1231 =>
        SaveFailureCause.locationGone,
      _ => SaveFailureCause.unknown,
    };

/// Whether [path] is a file whose write bits are set. A file that is not
/// there cannot be held by anyone, so access denied means its folder
/// refused.
bool _writable(String path) {
  try {
    final stat = File(path).statSync();
    if (stat.type == FileSystemEntityType.notFound) {
      return false;
    }
    return stat.mode & 0x92 != 0;
  } on FileSystemException {
    return false;
  }
}

SaveFailureCause _posixCause(int code) => switch (code) {
  // EBUSY, ETXTBSY.
  16 || 26 => SaveFailureCause.fileInUse,
  // EPERM, EACCES, EROFS.
  1 || 13 || 30 => SaveFailureCause.readOnly,
  // ENOSPC; EDQUOT is 122 on Linux and 69 on Apple.
  28 || 122 || 69 => SaveFailureCause.diskFull,
  // ENOENT, ENXIO, ENODEV.
  2 || 6 || 19 => SaveFailureCause.locationGone,
  _ => SaveFailureCause.unknown,
};

/// A save that wrote its whole archive and could not put it in the file's
/// place: [archive] is where that archive is now.
///
/// ⚠️A [FileSystemException] so every road that already answers a refusal
/// still answers this one — Android falls back to the staging road on
/// exactly that type.
final class SaveNotSwappedIn extends FileSystemException {
  SaveNotSwappedIn({
    required this.archive,
    required FileSystemException error,
    this.refusedByProvider = false,
  }) : super(error.message, error.path, error.osError);

  final String archive;

  /// Whether the platform's file provider was the one that said no (a
  /// coordinated replace), rather than the file system.
  final bool refusedByProvider;
}

/// A save that did not reach its file, as the person is told it: WHY —
/// [cause], read off [error] — and where the work went instead.
///
/// 🗣️유저 2026-09-23 (whole-write-temp-beside-the-file): the work goes to
/// this run's FAILED COPY (실패본) — [failedCopy] — and the notice says so
/// at that moment, and that it disappears when the program closes. Null
/// when even the failed copy could not be written ([copyError]).
final class SaveFailure implements Exception {
  const SaveFailure({
    required this.cause,
    required this.error,
    this.failedCopy,
    this.copyError,
  });

  final SaveFailureCause cause;
  final Object error;
  final String? failedCopy;
  final Object? copyError;

  @override
  String toString() =>
      'The save did not reach its file (${cause.name}): $error'
      '${failedCopy == null ? '' : ' — the work is kept at $failedCopy'}';
}
