/// The two sides of a timesheet page's memo band, each a memo of its own.
///
/// 🗣️F-542 (유저 2026-11-02): 「타임시트 메모란, 텍스트 공간 왼쪽 오른쪽 두개로
/// 나누자. 좌우로 긴데 지금처럼하면 한 줄이라서 너무 공간활용이 애매해」 ·
/// F-542-Q1: 「둘 다 동일한 메모고, 고정텍스트는 왼쪽 메모란부터 위에서 공간
/// 쓰다가 부족하면 오른쪽 메모란 위에서부터 쓰기시작」.
enum SheetMemoSide { left, right }
