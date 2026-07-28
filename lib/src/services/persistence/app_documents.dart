import 'dart:io';

import 'package:flutter/services.dart' show MethodChannel;

import 'app_save_settings.dart';

/// SAVE-1: the app's USER-VISIBLE project home — the default location
/// every save/open surface starts in (the initial-save window, Save As,
/// Open). Deliberately a folder ordinary file managers show:
///
/// - Windows: `%USERPROFILE%/Documents/Anicel`
/// - macOS/Linux: `$HOME/Documents/Anicel`
/// - Android: the PUBLIC Documents folder ("내 파일" shows it) via the
///   qa_storage channel (SAVE-1c)
/// - iOS: the sandbox Documents dir, Files-app visible (SAVE-1d flags)
String appDocumentsDirectory() {
  final fromChannel = AppStorage.channelDocumentsPath;
  if (fromChannel != null && fromChannel.isNotEmpty) {
    return fromChannel;
  }
  final environment = Platform.environment;
  final home = environment['USERPROFILE'] ?? environment['HOME'];
  if (home != null && home.isNotEmpty) {
    final normalized = home.replaceAll('\\', '/');
    return '$normalized/Documents/Anicel';
  }
  // Environment-less platforms before the channel answers: the system
  // temp keeps dev/test harmless.
  return '${Directory.systemTemp.path.replaceAll('\\', '/')}/Anicel';
}

/// REC1-B2: the take shelf — where a never-saved project's voice takes
/// land. A folder ordinary file managers show (`Recordings` under the
/// app documents home, the DAW convention), NOT the hidden OS temp: a
/// discarded session leaves its takes findable. The first real save
/// moves a project's referenced takes into its `Media/`; a custom shelf
/// is a desktop-only setting.
String appRecordingsDirectory() {
  final custom = AppSave.settings.value.recordingsDirectory;
  if (custom != null && custom.isNotEmpty) {
    return custom.replaceAll('\\', '/');
  }
  return '${appDocumentsDirectory()}/Recordings';
}

/// [appDocumentsDirectory], created if missing.
Future<String> ensuredAppDocumentsDirectory() async {
  final path = appDocumentsDirectory();
  await Directory(path).create(recursive: true);
  return path;
}

/// The sync twin — for dialog-internal navigation (sync dart:io works
/// under the widget-test clock; async never completes there).
String ensuredAppDocumentsDirectorySync() {
  final path = appDocumentsDirectory();
  Directory(path).createSync(recursive: true);
  return path;
}

/// SAVE-1c: the platform storage glue over the `qa_storage` channel —
/// the Android real-path model's grants and the mobile app-documents
/// home. Desktop needs none of it (env paths + full FS access).
abstract final class AppStorage {
  static const MethodChannel _channel = MethodChannel('qa_storage');

  /// The platform-provided app documents home (mobile); null until
  /// [ensureInitialized] resolves it (or on desktop, always).
  static String? channelDocumentsPath;

  /// Test hook: forces the all-files-access answer.
  static bool? debugAllFilesAccessOverride;

  /// Resolves the mobile documents home once at startup (main()).
  static Future<void> ensureInitialized() async {
    if (!Platform.isAndroid && !Platform.isIOS) {
      return;
    }
    try {
      channelDocumentsPath = await _channel.invokeMethod<String>(
        'appDocumentsPath',
      );
    } on Object {
      channelDocumentsPath = null;
    }
  }

  /// Whether shared-storage paths are writable (Android's All-Files
  /// grant; everywhere else the answer is yes).
  static Future<bool> isAllFilesAccessGranted() async {
    final override = debugAllFilesAccessOverride;
    if (override != null) {
      return override;
    }
    if (!Platform.isAndroid) {
      return true;
    }
    try {
      return await _channel.invokeMethod<bool>('isAllFilesAccessGranted') ??
          false;
    } on Object {
      return false;
    }
  }

  /// Whether the microphone may be captured (AUDIO-PRO R5). Android asks
  /// its runtime RECORD_AUDIO grant through the channel — the Future
  /// completes AFTER the user answers the system dialog. Everywhere else
  /// the OS gates the device open itself (macOS/iOS prompt on first use;
  /// desktop Windows/Linux have no app-level grant), so the answer is yes
  /// and a refusal surfaces as the capture failing to open.
  static Future<bool> ensureMicrophoneAccess() async {
    if (!Platform.isAndroid) {
      return true;
    }
    try {
      return await _channel.invokeMethod<bool>('requestMicrophone') ?? false;
    } on Object {
      return false;
    }
  }

  /// Opens the system grant surface (Android settings toggle).
  static Future<void> requestAllFilesAccess() async {
    if (!Platform.isAndroid) {
      return;
    }
    try {
      await _channel.invokeMethod<void>('requestAllFilesAccess');
    } on Object {
      // The settings screen failing to open leaves the notice visible.
    }
  }
}
