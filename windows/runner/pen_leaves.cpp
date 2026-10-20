#include "pen_leaves.h"

#include <set>

namespace {

// The pointer ids of the pens the view heard and has not heard leave.
std::set<UINT32>& Pens() {
  static std::set<UINT32> pens;
  return pens;
}

bool IsPointerMessage(UINT message) {
  return message == WM_POINTERENTER || message == WM_POINTERDOWN ||
         message == WM_POINTERUPDATE || message == WM_POINTERUP ||
         message == WM_POINTERLEAVE;
}

}  // namespace

void NotePenPointer(UINT message, WPARAM wparam) {
  if (!IsPointerMessage(message)) {
    return;
  }
  const UINT32 id = GET_POINTERID_WPARAM(wparam);
  if (message == WM_POINTERLEAVE) {
    Pens().erase(id);
    return;
  }
  POINTER_INPUT_TYPE type;
  if (::GetPointerType(id, &type) && type == PT_PEN) {
    Pens().insert(id);
  }
}

void LetPensGo(HWND view) {
  // A copy: each leave passes the view's subclass, which notes it.
  const std::set<UINT32> pens = Pens();
  for (const UINT32 id : pens) {
    POINTER_INFO info;
    if (!::GetPointerInfo(id, &info)) {
      // The engine reads the same and would send nothing.
      Pens().erase(id);
      continue;
    }
    ::SendMessage(view, WM_POINTERLEAVE, MAKEWPARAM(id, 0),
                  MAKELPARAM(info.ptPixelLocation.x, info.ptPixelLocation.y));
  }
}
