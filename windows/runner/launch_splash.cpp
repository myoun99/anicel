#include "launch_splash.h"

#include <wincodec.h>
#include <wrl/client.h>

#include <algorithm>

#include "resource.h"

using Microsoft::WRL::ComPtr;

namespace {

constexpr const wchar_t kSplashClassName[] = L"ANICEL_LAUNCH_SPLASH";

// I-106-Q6 (user, 2026-10-20): the splash stands half as tall as its
// monitor's short side — 「짧은 변의 50%로하면 가로일땐 높이의 50%」 — so a
// turned monitor gets the same picture. Spelled again in
// MainFlutterWindow.swift and linux/runner/launch_splash.cc.
constexpr LONG kShortSideShare = 2;

// The picture, decoded and scaled to |target_height| (its width by its own
// proportion) as premultiplied BGRA into a new |bitmap| of |width| x
// |height|. False when any step fails.
bool DecodePicture(UINT target_height, UINT* width, UINT* height,
                   HBITMAP* bitmap, HDC memory_dc) {
  HMODULE module = ::GetModuleHandle(nullptr);
  HRSRC resource = ::FindResource(module, MAKEINTRESOURCE(IDR_LAUNCH_SPLASH),
                                  RT_RCDATA);
  if (!resource) return false;
  HGLOBAL loaded = ::LoadResource(module, resource);
  DWORD size = ::SizeofResource(module, resource);
  void* bytes = loaded ? ::LockResource(loaded) : nullptr;
  if (!bytes || size == 0) return false;

  ComPtr<IWICImagingFactory> factory;
  if (FAILED(::CoCreateInstance(CLSID_WICImagingFactory, nullptr,
                                CLSCTX_INPROC_SERVER,
                                IID_PPV_ARGS(&factory)))) {
    return false;
  }
  ComPtr<IWICStream> stream;
  if (FAILED(factory->CreateStream(&stream)) ||
      FAILED(stream->InitializeFromMemory(static_cast<BYTE*>(bytes), size))) {
    return false;
  }
  ComPtr<IWICBitmapDecoder> decoder;
  ComPtr<IWICBitmapFrameDecode> frame;
  if (FAILED(factory->CreateDecoderFromStream(
          stream.Get(), nullptr, WICDecodeMetadataCacheOnLoad, &decoder)) ||
      FAILED(decoder->GetFrame(0, &frame))) {
    return false;
  }
  UINT source_width = 0;
  UINT source_height = 0;
  frame->GetSize(&source_width, &source_height);
  if (source_height == 0) return false;
  *height = target_height;
  *width = source_width * target_height / source_height;
  if (*width == 0 || *height == 0) return false;

  ComPtr<IWICBitmapScaler> scaler;
  ComPtr<IWICFormatConverter> converter;
  if (FAILED(factory->CreateBitmapScaler(&scaler)) ||
      FAILED(scaler->Initialize(frame.Get(), *width, *height,
                                WICBitmapInterpolationModeFant)) ||
      FAILED(factory->CreateFormatConverter(&converter)) ||
      FAILED(converter->Initialize(scaler.Get(),
                                   GUID_WICPixelFormat32bppPBGRA,
                                   WICBitmapDitherTypeNone, nullptr, 0.0,
                                   WICBitmapPaletteTypeCustom))) {
    return false;
  }

  BITMAPINFO info = {};
  info.bmiHeader.biSize = sizeof(BITMAPINFOHEADER);
  info.bmiHeader.biWidth = static_cast<LONG>(*width);
  // Negative: rows top-down, as WIC writes them.
  info.bmiHeader.biHeight = -static_cast<LONG>(*height);
  info.bmiHeader.biPlanes = 1;
  info.bmiHeader.biBitCount = 32;
  info.bmiHeader.biCompression = BI_RGB;
  void* pixels = nullptr;
  *bitmap = ::CreateDIBSection(memory_dc, &info, DIB_RGB_COLORS, &pixels,
                               nullptr, 0);
  if (!*bitmap) return false;
  const UINT stride = *width * 4;
  if (FAILED(converter->CopyPixels(nullptr, stride, stride * *height,
                                   static_cast<BYTE*>(pixels)))) {
    ::DeleteObject(*bitmap);
    *bitmap = nullptr;
    return false;
  }
  return true;
}

void RegisterSplashClass() {
  static bool registered = false;
  if (registered) return;
  WNDCLASS window_class = {};
  window_class.hCursor = ::LoadCursor(nullptr, IDC_APPSTARTING);
  window_class.lpszClassName = kSplashClassName;
  window_class.hInstance = ::GetModuleHandle(nullptr);
  window_class.lpfnWndProc = ::DefWindowProc;
  ::RegisterClass(&window_class);
  registered = true;
}

}  // namespace

LaunchSplash::~LaunchSplash() { Close(); }

void LaunchSplash::Show(HMONITOR monitor) {
  if (window_) return;
  MONITORINFO monitor_info = {sizeof(MONITORINFO)};
  if (!::GetMonitorInfo(monitor, &monitor_info)) return;
  const RECT& work = monitor_info.rcWork;
  const LONG short_side =
      (std::min)(work.right - work.left, work.bottom - work.top);

  HDC screen_dc = ::GetDC(nullptr);
  HDC memory_dc = ::CreateCompatibleDC(screen_dc);
  UINT width = 0;
  UINT height = 0;
  HBITMAP bitmap = nullptr;
  if (DecodePicture(static_cast<UINT>(short_side / kShortSideShare), &width,
                    &height, &bitmap, memory_dc)) {
    RegisterSplashClass();
    POINT origin = {
        work.left + (work.right - work.left - static_cast<LONG>(width)) / 2,
        work.top + (work.bottom - work.top - static_cast<LONG>(height)) / 2};
    SIZE extent = {static_cast<LONG>(width), static_cast<LONG>(height)};
    // A tool window: no taskbar button for a picture that lives a second.
    window_ = ::CreateWindowEx(
        WS_EX_LAYERED | WS_EX_TOOLWINDOW, kSplashClassName, L"Anicel",
        WS_POPUP, origin.x, origin.y, extent.cx, extent.cy, nullptr, nullptr,
        ::GetModuleHandle(nullptr), nullptr);
    if (window_) {
      HGDIOBJ previous = ::SelectObject(memory_dc, bitmap);
      POINT source = {0, 0};
      BLENDFUNCTION blend = {AC_SRC_OVER, 0, 255, AC_SRC_ALPHA};
      ::UpdateLayeredWindow(window_, screen_dc, &origin, &extent, memory_dc,
                            &source, 0, &blend, ULW_ALPHA);
      ::SelectObject(memory_dc, previous);
      ::ShowWindow(window_, SW_SHOWNORMAL);
    }
    ::DeleteObject(bitmap);
  }
  ::DeleteDC(memory_dc);
  ::ReleaseDC(nullptr, screen_dc);
}

void LaunchSplash::Close() {
  if (!window_) return;
  ::DestroyWindow(window_);
  window_ = nullptr;
}
