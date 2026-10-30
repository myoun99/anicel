import 'package:flutter_test/flutter_test.dart';

import '../../helpers/dart_sources.dart';

/// 🚨F-409 (유저 2026-10-19): 「세로 스크롤바를 프레임 영역. 즉 제일 오른쪽으로
/// 이동. 초+코마 버튼 위치도 그에맞춰서 이동. 타임라인/콘티패널 동일함. 법
/// 통일」. Where they stand moved again — F-459 (유저 2026-10-23): 「예전처럼
/// 역시 레이어영역이랑 프레임 사이에 … 위치는 현재 레이어영역 스플리터의
/// 오른쪽」 — and the law that they stand in one place stayed.
///
/// The timeline and the conte panel each wrote the grid's three rows out by
/// hand, so a law about where the bar and the corner stand was two laws
/// that agreed. They are laid by `timeline_grid_frame.dart` now; a panel
/// that builds the corner itself is writing the header row again.
///
/// The x-sheet stands its grid up and lays its own strip — the one other
/// place the corner is built.
void main() {
  test('only the frame and the x-sheet build the corner', () {
    final builders = <String>[
      for (final file in dartFilesUnder('lib'))
        if (file.readAsStringSync() case final source
            when source.contains('TimelineRulerViewCorner(') &&
                // Its own constructor's declaration.
                !source.contains('class TimelineRulerViewCorner '))
          libPath(file),
    ]..sort();
    expect(builders, [
      'lib/src/ui/timeline/timeline_grid_frame.dart',
      'lib/src/ui/timeline/xsheet_timeline_grid.dart',
    ]);
  });
}
