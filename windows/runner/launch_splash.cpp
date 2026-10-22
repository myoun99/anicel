#include "launch_splash.h"

#include <d2d1.h>
#include <dwrite_3.h>
#include <wincodec.h>
#include <wrl/client.h>

#include <algorithm>
#include <fstream>
#include <future>
#include <iterator>
#include <memory>
#include <sstream>

#include "resource.h"

using Microsoft::WRL::ComPtr;

namespace {

constexpr const wchar_t kSplashClassName[] = L"ANICEL_LAUNCH_SPLASH";

// I-106-Q6 (user, 2026-10-20): the splash stands half as tall as its
// monitor's short side — 「짧은 변의 50%로하면 가로일땐 높이의 50%」 — so a
// turned monitor gets the same picture. Spelled again in
// MainFlutterWindow.swift and linux/runner/launch_splash.cc.
constexpr LONG kShortSideShare = 2;

// The stage's line, close under the name, small and faint (user,
// 2026-10-21: 「Anicel 아래에 어느정도 붙고, 글자크기도 좀 작게 … 있는듯
// 없는듯한 느낌으로」): its middle and its type size as shares of the
// picture's height (tool/app_art/render_app_art_test.dart,
// kSplashStageCenter and kSplashStageSize over kSplashHeight), and its ink.
// Spelled again in MainFlutterWindow.swift and
// linux/runner/launch_splash.cc.
constexpr float kStageCenter = 210.0f / 232.0f;
constexpr float kStageSize = 8.0f / 232.0f;

// 「1초마다 .을 붙이고 초기화하고」 (user, 2026-10-21): one, two, three
// dots, a second each, and round again.
constexpr UINT kDotTurnMs = 1000;
constexpr int kMostDots = 3;

constexpr UINT kStageMessage = WM_APP + 1;
constexpr UINT kCloseMessage = WM_APP + 2;
constexpr UINT_PTR kDotTimer = 1;

// What lib/src/native/launch_splash.dart leaves for the next launch:
// LaunchSplash.labelsFileName under appSupportFilePath's base.
constexpr const wchar_t kLabelsPath[] = L"\\anicel\\launch-labels.txt";

struct Stage {
  std::string face_files;
  std::string name;
};

std::wstring Widen(const std::string& utf8) {
  if (utf8.empty()) return std::wstring();
  const int length = ::MultiByteToWideChar(
      CP_UTF8, 0, utf8.data(), static_cast<int>(utf8.size()), nullptr, 0);
  std::wstring wide(static_cast<size_t>(length), L'\0');
  ::MultiByteToWideChar(CP_UTF8, 0, utf8.data(),
                        static_cast<int>(utf8.size()), wide.data(), length);
  return wide;
}

std::vector<std::string> SplitOn(const std::string& text, char separator) {
  std::vector<std::string> parts;
  std::stringstream stream(text);
  std::string part;
  while (std::getline(stream, part, separator)) {
    if (!part.empty() && part.back() == '\r') part.pop_back();
    if (!part.empty()) parts.push_back(part);
  }
  return parts;
}

// The folder the engine reads its assets from, beside the executable.
std::wstring AssetsFolder() {
  wchar_t path[MAX_PATH];
  const DWORD length = ::GetModuleFileName(nullptr, path, MAX_PATH);
  std::wstring folder(path, length);
  folder.resize(folder.find_last_of(L'\\') + 1);
  return folder + L"data\\flutter_assets\\";
}

// The picture as a WIC source scaled to |target_height| (its width by its
// own proportion), premultiplied BGRA. Null when any step fails.
ComPtr<IWICFormatConverter> DecodePicture(UINT target_height, UINT* width,
                                          UINT* height) {
  HMODULE module = ::GetModuleHandle(nullptr);
  HRSRC resource = ::FindResource(module, MAKEINTRESOURCE(IDR_LAUNCH_SPLASH),
                                  RT_RCDATA);
  if (!resource) return nullptr;
  HGLOBAL loaded = ::LoadResource(module, resource);
  DWORD size = ::SizeofResource(module, resource);
  void* bytes = loaded ? ::LockResource(loaded) : nullptr;
  if (!bytes || size == 0) return nullptr;

  ComPtr<IWICImagingFactory> factory;
  ComPtr<IWICStream> stream;
  ComPtr<IWICBitmapDecoder> decoder;
  ComPtr<IWICBitmapFrameDecode> frame;
  if (FAILED(::CoCreateInstance(CLSID_WICImagingFactory, nullptr,
                                CLSCTX_INPROC_SERVER,
                                IID_PPV_ARGS(&factory))) ||
      FAILED(factory->CreateStream(&stream)) ||
      FAILED(stream->InitializeFromMemory(static_cast<BYTE*>(bytes), size)) ||
      FAILED(factory->CreateDecoderFromStream(
          stream.Get(), nullptr, WICDecodeMetadataCacheOnLoad, &decoder)) ||
      FAILED(decoder->GetFrame(0, &frame))) {
    return nullptr;
  }
  UINT source_width = 0;
  UINT source_height = 0;
  frame->GetSize(&source_width, &source_height);
  if (source_height == 0 || target_height == 0) return nullptr;
  *height = target_height;
  *width = source_width * target_height / source_height;

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
    return nullptr;
  }
  return converter;
}

// The family a font file carries, as DirectWrite matches it.
std::wstring FamilyOf(IDWriteFontSet* set) {
  BOOL exists = FALSE;
  ComPtr<IDWriteLocalizedStrings> names;
  if (!set || set->GetFontCount() == 0 ||
      FAILED(set->GetPropertyValues(0, DWRITE_FONT_PROPERTY_ID_FAMILY_NAME,
                                    &exists, &names)) ||
      !exists) {
    return std::wstring();
  }
  UINT32 length = 0;
  names->GetStringLength(0, &length);
  std::wstring name(length + 1, L'\0');
  names->GetString(0, name.data(), length + 1);
  name.resize(length);
  return name;
}

// Draws the splash: the picture, and under the name the stage with its
// dots. Lives on the splash thread.
class SplashPainter {
 public:
  bool Start(HWND window, UINT width, UINT height,
             IWICFormatConverter* picture) {
    window_ = window;
    width_ = width;
    height_ = height;
    screen_dc_ = ::GetDC(nullptr);
    memory_dc_ = ::CreateCompatibleDC(screen_dc_);
    BITMAPINFO info = {};
    info.bmiHeader.biSize = sizeof(BITMAPINFOHEADER);
    info.bmiHeader.biWidth = static_cast<LONG>(width);
    info.bmiHeader.biHeight = -static_cast<LONG>(height);
    info.bmiHeader.biPlanes = 1;
    info.bmiHeader.biBitCount = 32;
    info.bmiHeader.biCompression = BI_RGB;
    void* pixels = nullptr;
    dib_ = ::CreateDIBSection(memory_dc_, &info, DIB_RGB_COLORS, &pixels,
                              nullptr, 0);
    if (!dib_) return false;
    previous_ = ::SelectObject(memory_dc_, dib_);

    ComPtr<ID2D1Factory> factory;
    const D2D1_RENDER_TARGET_PROPERTIES properties =
        D2D1::RenderTargetProperties(
            D2D1_RENDER_TARGET_TYPE_DEFAULT,
            D2D1::PixelFormat(DXGI_FORMAT_B8G8R8A8_UNORM,
                              D2D1_ALPHA_MODE_PREMULTIPLIED),
            96.0f, 96.0f);
    RECT bounds = {0, 0, static_cast<LONG>(width), static_cast<LONG>(height)};
    if (FAILED(::D2D1CreateFactory(D2D1_FACTORY_TYPE_SINGLE_THREADED,
                                   factory.GetAddressOf())) ||
        FAILED(factory->CreateDCRenderTarget(&properties, &target_)) ||
        FAILED(target_->BindDC(memory_dc_, &bounds)) ||
        FAILED(target_->CreateBitmapFromWicBitmap(picture, &picture_))) {
      return false;
    }
    // Text on a target with alpha takes grayscale smoothing only.
    target_->SetTextAntialiasMode(D2D1_TEXT_ANTIALIAS_MODE_GRAYSCALE);
    target_->CreateSolidColorBrush(D2D1::ColorF(1.0f, 1.0f, 1.0f, 0.6f),
                                   &ink_);
    target_->CreateSolidColorBrush(D2D1::ColorF(0.0f, 0.0f, 0.0f, 0.3f),
                                   &shadow_);
    return true;
  }

  ~SplashPainter() {
    if (memory_dc_) {
      if (previous_) ::SelectObject(memory_dc_, previous_);
      ::DeleteDC(memory_dc_);
    }
    if (dib_) ::DeleteObject(dib_);
    if (screen_dc_) ::ReleaseDC(nullptr, screen_dc_);
  }

  void Say(const Stage& stage) {
    if (!format_ || stage.face_files != face_files_) {
      face_files_ = stage.face_files;
      format_ = MakeFormat();
    }
    name_ = Widen(stage.name);
    dots_ = 1;
  }

  void TurnDots() { dots_ = dots_ % kMostDots + 1; }

  void Paint() {
    target_->BeginDraw();
    target_->Clear(D2D1::ColorF(0.0f, 0.0f, 0.0f, 0.0f));
    target_->DrawBitmap(picture_.Get(),
                        D2D1::RectF(0, 0, static_cast<float>(width_),
                                    static_cast<float>(height_)));
    if (format_ && !name_.empty()) PaintStage();
    target_->EndDraw();
    POINT origin = {0, 0};
    RECT frame;
    ::GetWindowRect(window_, &frame);
    origin.x = frame.left;
    origin.y = frame.top;
    SIZE extent = {static_cast<LONG>(width_), static_cast<LONG>(height_)};
    POINT source = {0, 0};
    BLENDFUNCTION blend = {AC_SRC_OVER, 0, 255, AC_SRC_ALPHA};
    ::UpdateLayeredWindow(window_, screen_dc_, &origin, &extent, memory_dc_,
                          &source, 0, &blend, ULW_ALPHA);
  }

 private:
  // The stage's type: the face's files in order — the first speaks, the
  // rest fill in what it lacks, then the OS — or the OS's own face when
  // there are none.
  ComPtr<IDWriteTextFormat> MakeFormat() {
    // Made at the first stage, not before the picture is up.
    if (!write_ &&
        FAILED(::DWriteCreateFactory(
            DWRITE_FACTORY_TYPE_SHARED, __uuidof(IDWriteFactory5),
            reinterpret_cast<IUnknown**>(write_.GetAddressOf())))) {
      return nullptr;
    }
    const float size = static_cast<float>(height_) * kStageSize;
    std::vector<std::wstring> families;
    ComPtr<IDWriteFontSetBuilder1> builder;
    write_->CreateFontSetBuilder(&builder);
    const std::wstring assets = AssetsFolder();
    for (const std::string& file : SplitOn(face_files_, '\t')) {
      std::wstring path = assets + Widen(file);
      std::replace(path.begin(), path.end(), L'/', L'\\');
      ComPtr<IDWriteFontFile> font_file;
      ComPtr<IDWriteFontSetBuilder1> one;
      ComPtr<IDWriteFontSet> one_set;
      if (FAILED(write_->CreateFontFileReference(path.c_str(), nullptr,
                                                 &font_file)) ||
          FAILED(builder->AddFontFile(font_file.Get())) ||
          FAILED(write_->CreateFontSetBuilder(&one)) ||
          FAILED(one->AddFontFile(font_file.Get())) ||
          FAILED(one->CreateFontSet(&one_set))) {
        continue;
      }
      const std::wstring family = FamilyOf(one_set.Get());
      if (!family.empty()) families.push_back(family);
    }

    ComPtr<IDWriteTextFormat> format;
    if (families.empty()) {
      NONCLIENTMETRICS metrics = {sizeof(NONCLIENTMETRICS)};
      ::SystemParametersInfo(SPI_GETNONCLIENTMETRICS, sizeof(metrics),
                             &metrics, 0);
      write_->CreateTextFormat(metrics.lfMessageFont.lfFaceName, nullptr,
                               DWRITE_FONT_WEIGHT_NORMAL,
                               DWRITE_FONT_STYLE_NORMAL,
                               DWRITE_FONT_STRETCH_NORMAL, size, L"", &format);
      return format;
    }
    ComPtr<IDWriteFontSet> set;
    ComPtr<IDWriteFontCollection1> collection;
    ComPtr<IDWriteFontFallbackBuilder> fallback_builder;
    ComPtr<IDWriteFontFallback> system_fallback;
    ComPtr<IDWriteFontFallback> fallback;
    ComPtr<IDWriteTextFormat1> format1;
    if (FAILED(builder->CreateFontSet(&set)) ||
        FAILED(write_->CreateFontCollectionFromFontSet(set.Get(),
                                                       &collection)) ||
        FAILED(write_->CreateTextFormat(
            families.front().c_str(), collection.Get(),
            DWRITE_FONT_WEIGHT_NORMAL, DWRITE_FONT_STYLE_NORMAL,
            DWRITE_FONT_STRETCH_NORMAL, size, L"", &format)) ||
        FAILED(write_->CreateFontFallbackBuilder(&fallback_builder)) ||
        FAILED(write_->GetSystemFontFallback(&system_fallback))) {
      return format;
    }
    const DWRITE_UNICODE_RANGE everything = {0x0, 0x10FFFF};
    for (size_t i = 1; i < families.size(); ++i) {
      const wchar_t* name = families[i].c_str();
      fallback_builder->AddMapping(&everything, 1, &name, 1,
                                   collection.Get(), nullptr, nullptr, 1.0f);
    }
    fallback_builder->AddMappings(system_fallback.Get());
    if (SUCCEEDED(fallback_builder->CreateFontFallback(&fallback)) &&
        SUCCEEDED(format.As(&format1))) {
      format1->SetFontFallback(fallback.Get());
    }
    return format;
  }

  void PaintStage() {
    const float width = static_cast<float>(width_);
    const float height = static_cast<float>(height_);
    ComPtr<IDWriteTextLayout> name;
    ComPtr<IDWriteTextLayout> dots;
    const std::wstring dot_text(static_cast<size_t>(dots_), L'.');
    if (FAILED(write_->CreateTextLayout(
            name_.c_str(), static_cast<UINT32>(name_.size()), format_.Get(),
            width, height, &name)) ||
        FAILED(write_->CreateTextLayout(
            dot_text.c_str(), static_cast<UINT32>(dot_text.size()),
            format_.Get(), width, height, &dots))) {
      return;
    }
    DWRITE_TEXT_METRICS metrics;
    name->GetMetrics(&metrics);
    // The name stands still; the dots grow to its right.
    const float left = (width - metrics.width) / 2;
    const float top = height * kStageCenter - metrics.height / 2;
    const float shadow = height / 232.0f;
    for (int pass = 0; pass < 2; ++pass) {
      ID2D1SolidColorBrush* brush = pass == 0 ? shadow_.Get() : ink_.Get();
      const float lift = pass == 0 ? shadow : 0.0f;
      target_->DrawTextLayout(D2D1::Point2F(left, top + lift), name.Get(),
                              brush);
      target_->DrawTextLayout(D2D1::Point2F(left + metrics.width, top + lift),
                              dots.Get(), brush);
    }
  }

  HWND window_ = nullptr;
  UINT width_ = 0;
  UINT height_ = 0;
  HDC screen_dc_ = nullptr;
  HDC memory_dc_ = nullptr;
  HBITMAP dib_ = nullptr;
  HGDIOBJ previous_ = nullptr;
  ComPtr<ID2D1DCRenderTarget> target_;
  ComPtr<ID2D1Bitmap> picture_;
  ComPtr<ID2D1SolidColorBrush> ink_;
  ComPtr<ID2D1SolidColorBrush> shadow_;
  ComPtr<IDWriteFactory5> write_;
  ComPtr<IDWriteTextFormat> format_;
  std::string face_files_;
  std::wstring name_;
  int dots_ = 1;
};

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

// The splash's thread: the window, its painter and its own message loop,
// so the dots turn while the runner's thread starts the engine.
void RunSplash(RECT work, std::promise<HWND> shown) {
  ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);
  {
    const LONG short_side =
        (std::min)(work.right - work.left, work.bottom - work.top);
    UINT width = 0;
    UINT height = 0;
    ComPtr<IWICFormatConverter> picture = DecodePicture(
        static_cast<UINT>(short_side / kShortSideShare), &width, &height);
    HWND window = nullptr;
    SplashPainter painter;
    if (picture) {
      RegisterSplashClass();
      // A tool window: no taskbar button for a picture that lives seconds.
      window = ::CreateWindowEx(
          WS_EX_LAYERED | WS_EX_TOOLWINDOW, kSplashClassName, L"Anicel",
          WS_POPUP,
          work.left + (work.right - work.left - static_cast<LONG>(width)) / 2,
          work.top + (work.bottom - work.top - static_cast<LONG>(height)) / 2,
          static_cast<int>(width), static_cast<int>(height), nullptr,
          nullptr, ::GetModuleHandle(nullptr), nullptr);
    }
    // Handed over as soon as it exists: the runner starts the engine while
    // this thread decodes and draws the picture (measured 2026-10-21 —
    // waiting for the drawing held the engine back about 0.45s). Stages
    // said meanwhile wait in this thread's queue.
    shown.set_value(window);
    if (window && painter.Start(window, width, height, picture.Get())) {
      painter.Paint();
      ::ShowWindow(window, SW_SHOWNORMAL);
      ::SetTimer(window, kDotTimer, kDotTurnMs, nullptr);
    } else if (window) {
      ::DestroyWindow(window);
      window = nullptr;
      // The stages said to a splash that never showed.
      MSG left;
      while (::PeekMessage(&left, nullptr, kStageMessage, kStageMessage,
                           PM_REMOVE)) {
        delete reinterpret_cast<Stage*>(left.lParam);
      }
    }

    MSG message;
    while (window && ::GetMessage(&message, nullptr, 0, 0) > 0) {
      if (message.message == kStageMessage) {
        std::unique_ptr<Stage> stage(reinterpret_cast<Stage*>(message.lParam));
        painter.Say(*stage);
        // A new stage starts its dots again from one.
        ::SetTimer(window, kDotTimer, kDotTurnMs, nullptr);
        painter.Paint();
      } else if (message.message == WM_TIMER &&
                 message.wParam == kDotTimer) {
        painter.TurnDots();
        painter.Paint();
      } else if (message.message == kCloseMessage) {
        ::DestroyWindow(window);
        window = nullptr;
      } else {
        ::DispatchMessage(&message);
      }
    }
  }
  ::CoUninitialize();
}

}  // namespace

LaunchSplash::~LaunchSplash() { Close(); }

void LaunchSplash::Show(HMONITOR monitor) {
  if (thread_.joinable()) return;
  MONITORINFO monitor_info = {sizeof(MONITORINFO)};
  if (!::GetMonitorInfo(monitor, &monitor_info)) return;

  wchar_t app_data[MAX_PATH];
  const DWORD length =
      ::GetEnvironmentVariable(L"APPDATA", app_data, MAX_PATH);
  if (length > 0 && length < MAX_PATH) {
    std::ifstream labels(std::wstring(app_data, length) + kLabelsPath,
                         std::ios::binary);
    std::string first;
    if (labels && std::getline(labels, first)) {
      if (!first.empty() && first.back() == '\r') first.pop_back();
      face_files_ = first;
      std::string rest((std::istreambuf_iterator<char>(labels)),
                       std::istreambuf_iterator<char>());
      stage_names_ = SplitOn(rest, '\n');
    }
  }

  std::promise<HWND> shown;
  std::future<HWND> window = shown.get_future();
  thread_ = std::thread(RunSplash, monitor_info.rcWork, std::move(shown));
  window_ = window.get();
}

void LaunchSplash::SayRunnerStage(size_t index) {
  // The first launch has no names yet: the line stays empty, its place
  // kept, until Dart speaks.
  if (index < stage_names_.size()) Post(face_files_, stage_names_[index]);
}

void LaunchSplash::SayStage(const std::string& face_files,
                            const std::string& name) {
  Post(face_files, name);
}

void LaunchSplash::Post(std::string face_files, std::string name) {
  if (!window_) return;
  auto* stage = new Stage{std::move(face_files), std::move(name)};
  if (!::PostMessage(window_, kStageMessage, 0,
                     reinterpret_cast<LPARAM>(stage))) {
    delete stage;
  }
}

void LaunchSplash::Close() {
  if (window_) {
    ::PostMessage(window_, kCloseMessage, 0, 0);
    window_ = nullptr;
  }
  if (thread_.joinable()) thread_.join();
}
