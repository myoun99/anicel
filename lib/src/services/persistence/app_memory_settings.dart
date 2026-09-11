import 'package:flutter/foundation.dart';

/// How much memory the app's caches may hold between them, when a person
/// has said so.
///
/// 🗣️유저 2026-09-11: 「앱이 사용하기로 허가된 메모리? 유저가 커스텀하는?
/// … 유저가 메모리 한계 설정할수있게」. Null is the automatic allowance —
/// every cache on its own device law, which is what the app did before
/// anyone could choose.
///
/// App state, not project state: a machine's memory must not travel inside
/// a `.anicel`.
@immutable
class AppMemorySettings {
  const AppMemorySettings({this.allowanceBytes});

  /// The allowance a person chose, or null for the automatic one.
  final int? allowanceBytes;

  static const Object _unset = Object();

  AppMemorySettings copyWith({Object? allowanceBytes = _unset}) =>
      AppMemorySettings(
        allowanceBytes: identical(allowanceBytes, _unset)
            ? this.allowanceBytes
            : allowanceBytes as int?,
      );

  Map<String, dynamic> toJson() => {'allowanceBytes': allowanceBytes};

  /// A stored allowance is a stranger's number: anything that is not a
  /// positive whole number of bytes reads as the automatic one.
  static AppMemorySettings fromJson(Map<String, dynamic> json) {
    final bytes = json['allowanceBytes'];
    return AppMemorySettings(
      allowanceBytes: bytes is int && bytes > 0 ? bytes : null,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is AppMemorySettings && other.allowanceBytes == allowanceBytes;

  @override
  int get hashCode => allowanceBytes.hashCode;
}

/// The app-wide memory settings, on the same idiom as [AppSave.settings].
abstract final class AppMemory {
  static final ValueNotifier<AppMemorySettings> settings =
      ValueNotifier<AppMemorySettings>(const AppMemorySettings());
}
