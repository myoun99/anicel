import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../services/persistence/folder_grant.dart';
import '../services/persistence/provider_documents.dart';

/// 🗣️open-door-windows-open-with-Q1 (유저 2026-10-22: 「떠 있는 창의 새
/// 탭으로」): a file opened with Anicel while one runs opens in that one.
/// Windows starts another Anicel for it, which hands the paths to the running
/// window and ends (`windows/runner/main.cpp`); the window says them here
/// ([openMethod]), and they go where the files a launch was handed go.
///
/// `open-door-android-share` (F-282-Q5, 유저 2026-10-09: 「최대한
/// 통일하고싶음」): Android says here what another app opened Anicel with or
/// shared with it — the file that started the app as well as one that
/// reached it running (`MainActivity.hand`).
abstract final class HandedFiles {
  /// The platforms' channel and its method, spelled again in
  /// `flutter_window.cpp` and `MainActivity.kt`;
  /// `a_file_opened_again_joins_the_running_window_test` and
  /// `a_file_another_app_hands_goes_through_the_door_test` read them.
  static const channel = MethodChannel('anicel/handed_files');
  static const openMethod = 'open';

  /// Hands [open] each batch of files the platform says — and with null,
  /// hears nothing any more.
  static void listen(ValueSetter<List<FolderGrant>>? open) {
    if (open == null) {
      channel.setMethodCallHandler(null);
      return;
    }
    channel.setMethodCallHandler((call) async {
      final handed = call.arguments;
      if (call.method == openMethod && handed is List) {
        open(_grantsOf(handed));
      }
      return null;
    });
  }

  /// What the platform said, as the door takes it — one entry per file,
  /// said two ways: the Windows runner says a PATH, as a drop or a launch
  /// argument is one ([handedPath]); Android says an ITEM, as its picker
  /// answers one ([FolderPicker.itemGrant]) — a path, or a document with no
  /// path behind it (PICK-7) — and a file, since neither 「다음으로 열기」
  /// nor 「공유」 hands a folder. A document is remembered by its own name,
  /// as a pick's is: every step after has only its URI. What names neither
  /// is dropped.
  static List<FolderGrant> _grantsOf(List<Object?> handed) {
    final grants = <FolderGrant>[];
    for (final file in handed) {
      final grant = file is String
          ? handedPath(file)
          : FolderPicker.itemGrant(file, GrantKind.file);
      if (grant == null) {
        continue;
      }
      if (grant.document case final document?) {
        ProviderDocuments.remember(document);
      }
      grants.add(grant);
    }
    return grants;
  }
}
