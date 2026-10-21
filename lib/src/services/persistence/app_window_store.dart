import 'app_support_path.dart';
import 'versioned_settings_file.dart';

/// Where the window stood and how big it was, in its runner's own numbers
/// (I-116, 유저 2026-10-21: 「닫고 열때 마지막크기/위치로 열고싶음」) — the
/// normal frame, the one a maximized window comes back to, and whether it
/// was maximized. Only the runner that wrote it reads it; the app keeps it.
typedef WindowFrame = ({
  double left,
  double top,
  double width,
  double height,
  bool maximized,
});

/// Loads and saves how the app's window stands — whether it is full screen
/// (I-103-Q2, 유저 2026-10-16: on the desktops, remembered for the next
/// run) and where it stands ([WindowFrame], I-116). Editor/app state, not
/// project data — an app-support JSON file beside the UI scale.
///
/// ⚠️Its own file, not the workspace layout's: 「작업공간 배치 초기화」
/// resets the layout, and full screen is the window, not the layout.
///
/// ONE document for both, so a save of one keeps the other: the store holds
/// what it last read or wrote, and every save writes it whole. `main()`
/// reads both before the runner says anything.
class AppWindowStore {
  AppWindowStore({String? filePath})
    : filePath = filePath ?? defaultFilePath();

  final String filePath;

  static String defaultFilePath() => appSettingsFilePath('window.json');

  static const int version = 1;

  Map<String, Object?> _document = const {};

  /// Whether the last run left the window full screen, or null when there
  /// is nothing usable on disk.
  Future<bool?> loadFullScreen() async {
    final on = (await _load())['fullScreen'];
    return on is bool ? on : null;
  }

  /// Where the last run left the window, or null when there is nothing
  /// usable on disk.
  Future<WindowFrame?> loadFrame() async =>
      windowFrameFromJson((await _load())['frame']);

  Future<void> saveFullScreen(bool on) => _save('fullScreen', on);

  Future<void> saveFrame(WindowFrame frame) =>
      _save('frame', windowFrameToJson(frame));

  Future<Map<String, Object?>> _load() async => _document =
      await loadVersionedSettings(
        filePath: filePath,
        version: version,
        fromJson: (json) => Map<String, Object?>.of(json)..remove('version'),
      ) ??
      const {};

  Future<void> _save(String key, Object value) {
    _document = {..._document, key: value};
    return saveVersionedSettings(
      filePath: filePath,
      version: version,
      json: _document,
    );
  }
}

/// [frame] as the runners send it and the file keeps it.
Map<String, Object> windowFrameToJson(WindowFrame frame) => {
  'left': frame.left,
  'top': frame.top,
  'width': frame.width,
  'height': frame.height,
  'maximized': frame.maximized,
};

/// The frame [json] holds — from a runner or the file — or null when it is
/// no frame: a number missing, a size not above zero.
WindowFrame? windowFrameFromJson(Object? json) {
  if (json case {
    'left': final num left,
    'top': final num top,
    'width': final num width,
    'height': final num height,
    'maximized': final bool maximized,
  } when width > 0 && height > 0) {
    return (
      left: left.toDouble(),
      top: top.toDouble(),
      width: width.toDouble(),
      height: height.toDouble(),
      maximized: maximized,
    );
  }
  return null;
}
