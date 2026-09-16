import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/ui/editor_workspace.dart';
import 'package:anicel/src/ui/home_page.dart';
import 'package:anicel/src/ui/media/media_viewer_tab_host.dart';

/// F-103, the SECOND report (유저 2026-09-16): 「같은띠에서 뷰어패널이랑
/// 컬러패널 연 상태에서, 컬러패널을 닫으면 뷰어패널이 리빌드되는건지
/// 뷰어패널쪽이 파일 열렸습니다라는 반짝반짝 ui와 함께 내용물이 흰색됬다가
/// 돌아옴 … 패널 공통적으로 패널 닫고 여는게 리빌드시키는거라면 해결」.
///
/// The first round fixed one remount (a panel body changed tree shape when
/// the dock crossed the panel's floor). This is the other one, and it is a
/// rail-level identity question rather than a body-level one: the rail lays
/// its open groups out as a run of positioned children, so a group opening
/// or closing ABOVE another moves every group below it by one slot. Matched
/// by position, the panel below is handed its neighbour's element — same
/// widget types, different dock — and the panel inside is built again. For
/// the viewer that means reading its file again: the silhouette, and the
/// white.
///
/// ⚠️It is asked of the VIEWER because the viewer is what the user saw, but
/// nothing here is the viewer's: the answer is one key in the rail, so it
/// holds for every panel that has a State worth keeping.
void main() {
  Future<void> tapRailGroup(WidgetTester tester, String railId) async {
    await tester.tap(find.byKey(ValueKey<String>('rail-group-$railId')));
    await tester.pumpAndSettle();
  }

  /// The colour group sits at the top of the right rail and the sub viewer's
  /// group below it — the user's own arrangement.
  Future<State> openTheUsersRail(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1600, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const MaterialApp(home: HomePage()));
    await tester.pumpAndSettle();
    await tapRailGroup(tester, EditorWorkspace.rightGroupId);
    await tapRailGroup(
      tester,
      EditorWorkspace.railGroupId(right: true, slot: 5),
    );
    expect(
      find.byType(MediaViewerTabHost),
      findsOneWidget,
      reason: 'fixture: the sub viewer is open',
    );
    return tester.state<State>(find.byType(MediaViewerTabHost));
  }

  testWidgets('closing the rail group ABOVE a panel leaves that panel '
      'mounted — its State, not a new one', (tester) async {
    final before = await openTheUsersRail(tester);

    await tapRailGroup(tester, EditorWorkspace.rightGroupId);

    expect(find.byType(MediaViewerTabHost), findsOneWidget);
    expect(
      identical(tester.state<State>(find.byType(MediaViewerTabHost)), before),
      isTrue,
      reason: 'a neighbour closing must not rebuild the panel below it',
    );
  });

  testWidgets('and OPENING one above it is the same question — the panel '
      'below keeps its State', (tester) async {
    // Closing was what the user hit; opening moves the same panels by the
    // same slot, so a fix that only answered one of them would be a fix for
    // the report rather than for the defect.
    await openTheUsersRail(tester);
    await tapRailGroup(tester, EditorWorkspace.rightGroupId);
    final before = tester.state<State>(find.byType(MediaViewerTabHost));

    await tapRailGroup(tester, EditorWorkspace.rightGroupId);

    expect(
      identical(tester.state<State>(find.byType(MediaViewerTabHost)), before),
      isTrue,
      reason: 'a neighbour opening must not rebuild the panel below it',
    );
  });
}
