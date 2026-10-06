# Porting word2pdf to macOS and Windows

Status: Linux and macOS (Apple Silicon) are built and tested. On Windows the build environment
works (on ARM64); word2pdf itself is not ported yet, the plan for that is below.

## What is portable

* `slim/` (the executable, the asset embedding, the component selection) is platform
  independent C++/Python/make. The fontconfig setup depends on `USE_HEADLESS_CODE` (VCL renders
  with FreeType and fontconfig), the embedded file layout on LibreOffice's per-platform folder
  names (`LIBO_SHARE_FOLDER` etc.: `share/` is `Resources/` on macOS).
* `embed_files.py` emits `.incbin` for ELF and Mach-O and plain byte arrays otherwise (MSVC).
* The static linking machinery (`--disable-dynamic-loading`,
  `--enable-customtarget-components`, `slim/constructors.list`) is the same one LibreOffice uses
  for iOS (Mach-O, clang) and WebAssembly.
* The embedded file tree lives in `sal/osl/unx`, which macOS shares with Linux.

## macOS (done)

LibreOffice's macOS port renders through Quartz/CoreText (`vcl/osx`, `vcl/quartz`), but
configure already has `--enable-headless` for Darwin, which keeps the `svp` headless backend
with FreeType, fontconfig and cairo. word2pdf uses that, so it renders exactly like on Linux,
with the same embedded `fonts.conf` rules and the macOS font directories. (The alternative,
`svp` with CoreText text as `vcl/ios/iosinst.cxx` does, would follow macOS's own font matching
more closely but needs new code.)

What it took (patches 0008, 0012 and 0013, `scripts/build-macos.sh`):

* configure: `--disable-gui` without X11 when the headless backend is used; no OpenGL without a
  GUI; external hyphenation directories on Darwin; pkgconf 3's virtual packages in the "bogus
  pkg-config" check.
* gbuild's macOS platform had no static mode: libraries become `.a` archives, executables link
  them with `-l`, `--gc-sections` is `-dead_strip`, and frameworks are passed as one word each
  (static builds deduplicate the collected link flags, which split `-framework X` pairs).
* VCL: the headless component implementations and no `vclplug_osx`/Cocoa objects without a GUI;
  `SvpSalInstance` skips the AppKit startup workaround. sfx2: no Dock menu (AppKit).
* Bundled libraries: cairo, pixman, ICU, liblangtag, libxslt and redland rename the install
  names of their dylibs on macOS, which a static build does not have; cairo without Quartz; the
  ICU data filter runs the build platform's `icupkg` with `DYLD_LIBRARY_PATH`. libxml2 and
  libxslt are the bundled ones (configure picks the SDK's on Darwin otherwise).
* sal's macOS startup closes inherited regular files by `fstat`-ing every possible descriptor,
  up to the open-file limit; it lists the open ones with `proc_pidinfo` instead.
* VCL's duplicate-font check copied two font patterns for every pair of faces of a family:
  0.5 s per conversion with the 2700 fonts of a Mac, where the named instances of the variable
  system fonts make families of up to 380 faces.
* The build runs natively with Xcode; GNU make, gperf, ninja, cmake, autoconf, automake and
  pkg-config come from Homebrew, linked into a directory that is the only non-system entry on
  the `PATH` (configure rejects a pkg-config that would find Homebrew's libraries).

Not done: Intel Macs (should only need building there), universal binaries, and a
path-independent build like the container one.

## Windows

### Build environment (done)

`scripts/setup-windows.ps1` installs it and `scripts/build-windows.sh` builds from Git Bash.
Tried on Windows 11 on ARM64 (a UTM virtual machine on a Mac, 6 cores, 8 GB): the slim tree
configures as a (dynamic) Windows build, and gbuild compiles and links native ARM64 executables
with Visual Studio 2022's ARM64-hosted compiler.

It follows LibreOffice's own Windows setup (its `.config/*.winget`): autogen.sh and configure
run in WSL, the build runs natively with GNU make and MSVC, and bison, flex and gperf come from
WSL. What differs, and why:

* WSL1, imported from Ubuntu's image: WSL2 needs nested virtualisation, which VMs on a Mac do
  not have, and `wsl --install` then reports success having installed nothing.
* make 4.4.1, a 64-bit build (`dev-www.libreoffice.org/extern/make-4.4.1-msvc.exe`), not the
  32-bit make 4.2.1: Windows redirects System32 for 32-bit programs, so that one cannot start
  `wsl.exe`.
* The .NET Framework 4.8.1 SDK: 4.8 has no ARM64 `mscoree.lib`, which configure requires.
* The build's Python is the installed Windows one (`PYTHON=` for configure); configure would
  otherwise pick WSL's, which the native build cannot run.
* autogen.sh recognises Git Bash on ARM64 (`clangarm64` on the `PATH`) like configure does
  (patch 0015); otherwise a separate build directory gets module makefiles with WSL paths.
* extract.sh takes executable bits from git, as NTFS has none, so `src/` is the same commit as
  on Linux and macOS.

### Port (not done)

configure stops at `--disable-gui` ("not suitable" without X11 or the headless plugin), and with
the GUI it refuses a static build ("Can't build --disable-dynamic-loading without --disable-gui
and a single VCL plugin"); `--with-system-dicts` is an error on Windows. A static Windows build
is a cross build in configure's eyes, as on macOS. Then the pieces:

1. **Embedded file tree**: `sal/osl/w32` has its own file layer (`file.cxx`,
   `file_dirvol.cxx`, `file_url.cxx`), so the hooks of patch 0001 need a Win32 counterpart
   (opening a memory "file", `GetFileAttributesEx`/`FindFirstFile` emulation for the embedded
   root). `rtl/bootstrap.cxx` already has the `#if !defined _WIN32` guard where the Windows
   variant would go.
2. **Static build with MSVC**: gbuild's static mode has only been used with clang/ELF and
   Mach-O; `com_MSC_class.mk` links every `Library` as a DLL with an import library and has no
   static mode yet. MSVC needs static `.lib` versions of everything and `__declspec(selectany)` where
   GCC uses weak symbols (patch 0005 already emits that for the svidl type maps), and the
   component constructor table has to survive the linker (`/OPT:REF` drops unreferenced
   objects; the table references the constructors, so this should hold). clang-cl is an
   alternative compiler that keeps more of the GCC/clang behaviour.
3. **Headless rendering**: LibreOffice on Windows renders through GDI/DirectWrite (`vcl/win`),
   with Skia on top. Either run that backend with hidden windows (what `soffice --headless`
   does on Windows; needs no fontconfig), or bring svp + fontconfig + cairo to Windows as on
   Linux. `vcl/win` already checks `Application::IsHeadlessModeEnabled()`.
4. **`word2pdf.cxx`**: the scratch directory (`mkdtemp`, the stale-directory check with
   `kill(pid, 0)`), the signal handlers, `setenv` and the fontconfig setup are POSIX.

Until then, the Linux binary runs on Windows in Docker Desktop or WSL2.

## Older Linux

The binary needs glibc >= 2.38 because it is built on Debian 13. Building in an older base image
(e.g. AlmaLinux 8 with a newer GCC toolset) lowers that; LibreOffice 26.2 needs GCC >= 12.
