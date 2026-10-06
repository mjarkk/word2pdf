/* -*- Mode: C++; tab-width: 4; indent-tabs-mode: nil; c-basic-offset: 4 -*- */
/*
 * This file is part of the LibreOffice project.
 *
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/.
 */

// word2pdf: convert one text document (docx, doc, rtf, odt, ...) to PDF in a single
// short-lived process: start, load, export, exit. Everything LibreOffice normally reads
// from its installation (configuration, UNO type and service registries) is compiled
// into the executable; see lo_embeddedfs_register.

#include <sal/config.h>
#include <config_folders.h>
#include <config_vclplug.h>
#include <config_version.h>

#include <algorithm>
#include <cctype>
#include <cerrno>
#include <chrono>
#include <csignal>
#include <condition_variable>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <mutex>
#include <string>
#include <string_view>
#include <thread>
#include <vector>

#ifdef _WIN32
#include <fcntl.h>
#include <io.h>
#include <process.h>
#include <prewin.h>
#include <postwin.h>
#else
#include <fcntl.h>
#include <signal.h>
#include <unistd.h>
#endif

#if USE_HEADLESS_CODE
#include <fontconfig/fontconfig.h>
#ifdef __linux__
#include <sys/mman.h>
#endif
#endif

#include <com/sun/star/beans/PropertyValue.hpp>
#include <com/sun/star/document/BrokenPackageRequest.hpp>
#include <com/sun/star/document/MacroExecMode.hpp>
#include <com/sun/star/document/UpdateDocMode.hpp>
#include <com/sun/star/frame/Desktop.hpp>
#include <com/sun/star/frame/XStorable.hpp>
#include <com/sun/star/lang/XMultiServiceFactory.hpp>
#include <com/sun/star/lang/XServiceInfo.hpp>
#include <com/sun/star/task/DocumentPasswordRequest.hpp>
#include <com/sun/star/task/DocumentPasswordRequest2.hpp>
#include <com/sun/star/task/DocumentMSPasswordRequest.hpp>
#include <com/sun/star/task/DocumentMSPasswordRequest2.hpp>
#include <com/sun/star/task/ErrorCodeRequest.hpp>
#include <com/sun/star/task/XInteractionAbort.hpp>
#include <com/sun/star/task/XInteractionApprove.hpp>
#include <com/sun/star/task/XInteractionHandler.hpp>
#include <com/sun/star/ucb/UniversalContentBroker.hpp>
#include <com/sun/star/uno/XComponentContext.hpp>
#include <com/sun/star/util/XCloseable.hpp>
#include <comphelper/configuration.hxx>
#include <comphelper/processfactory.hxx>
#include <comphelper/propertyvalue.hxx>
#include <comphelper/sequence.hxx>
#include <cppuhelper/bootstrap.hxx>
#include <cppuhelper/implbase.hxx>
#include <i18nlangtag/languagetag.hxx>
#include <libxml/xmlIO.h>
#include <officecfg/Setup.hxx>
#include <osl/detail/embeddedfs.h>
#include <osl/file.hxx>
#include <osl/process.h>
#include <osl/signal.h>
#include <rtl/bootstrap.hxx>
#include <rtl/ref.hxx>
#include <sal/main.h>
#include <sfx2/app.hxx>
#include <unotools/tempfile.hxx>
#include <vcl/font.hxx>
#include <vcl/svapp.hxx>
#include <vcl/weld.hxx>

extern "C" const lo_embedded_file slim_assets[];
extern "C" const size_t slim_assets_count;

// sfx2 calls this special character dialog of cui directly in static builds; there are no
// dialogs here.
extern "C" bool GetSpecialCharsForEdit(weld::Widget*, const vcl::Font&, OUString&) { return false; }

// Entry points of libraries that only code which never runs during a conversion refers to.
// Defining them here keeps those static libraries, and their data, out of the executable.
// zxcvbn-c (1.6 MB of dictionaries): the password strength meter of password dialogs.
extern "C" double ZxcvbnMatch(const char*, const char*[], void**) { return 0; }
// md4c: Writer's Markdown import.
extern "C" int md_parse(const char*, unsigned, const void*, void*) { return -1; }

namespace
{
#ifdef _WIN32
// Only a name: osl serves everything below it from memory, nothing there is read from disk.
constexpr char EMBEDDED_ROOT[] = "C:\\lo-embedded";
constexpr char DEFAULT_TMP_DIR[] = "%TEMP%";
#else
constexpr char EMBEDDED_ROOT[] = "/lo-embedded";
constexpr char DEFAULT_TMP_DIR[] = "$TMPDIR or /tmp";
#endif

enum ExitCode
{
    EXIT_OK = 0,
    EXIT_USAGE = 1,
    EXIT_FAILED = 2,
    EXIT_TIMEOUT = 3,
    EXIT_CRASHED = 4,
    EXIT_TERMINATED = 5,
};

struct Options
{
    std::string input;
    std::string output;
    std::vector<std::string> fontDirs;
    std::string tmpDir;
    std::string locale;
    unsigned timeout = 120;
    bool taggedPdf = false;
    bool formFields = false;
    bool verbose = false;
    bool updateFontCache = false;
    std::vector<css::beans::PropertyValue> pdfOptions;
};

void usage(std::ostream& rOut)
{
    rOut << "Usage: word2pdf [options] INPUT OUTPUT.pdf\n"
            "Convert a text document (docx, doc, rtf, odt, ...) to PDF.\n"
            "INPUT and OUTPUT may be '-' for stdin and stdout.\n"
            "\n"
            "Options:\n"
            "  --timeout SECONDS        give up after SECONDS (default 120, 0 = never)\n"
            "  --font-dir DIR           also use the fonts in DIR (repeatable)\n"
            "  --tmp-dir DIR            directory for scratch files (default "
         << DEFAULT_TMP_DIR << ")\n"
            "  --locale TAG             locale for number formats, default paper size etc.\n"
            "                           (BCP 47, default en-US)\n"
            "  --tagged-pdf             write a tagged PDF (default off)\n"
            "  --form-fields            export form fields (default off)\n"
            "  --pdf-option NAME=VALUE  extra writer_pdf_Export filter option; VALUE is\n"
            "                           true, false, an integer or a string\n"
            "  --verbose                report progress on stderr\n"
            "  --update-font-cache      scan the fonts, write fontconfig caches where possible\n"
            "                           and exit (run once when building a container image;\n"
            "                           without caches every conversion rescans all fonts)\n"
            "  --version                show the LibreOffice version\n"
            "  --help                   show this help\n"
            "\n"
            "Exit status: 0 success, 1 usage error, 2 conversion failed, 3 timed out,\n"
            "4 crashed, 5 terminated by a signal.\n";
}

css::uno::Any parseOptionValue(std::string_view value)
{
    if (value == "true")
        return css::uno::Any(true);
    if (value == "false")
        return css::uno::Any(false);
    if (!value.empty() && value.find_first_not_of("-0123456789") == std::string_view::npos)
        return css::uno::Any(sal_Int32(std::stol(std::string(value))));
    return css::uno::Any(OUString::fromUtf8(value));
}

bool parseArgs(int argc, char** argv, Options& rOptions)
{
    std::vector<std::string> positional;
    for (int i = 1; i < argc; ++i)
    {
        std::string_view arg(argv[i]);
        auto value = [&]() -> const char* {
            if (i + 1 >= argc)
                throw std::runtime_error(std::string(arg) + " needs a value");
            return argv[++i];
        };
        if (arg == "--help" || arg == "-h")
        {
            usage(std::cout);
            std::exit(EXIT_OK);
        }
        else if (arg == "--version")
        {
            std::cout << "word2pdf, LibreOffice " LIBO_VERSION_DOTTED "\n";
            std::exit(EXIT_OK);
        }
        else if (arg == "--timeout")
            rOptions.timeout = std::stoul(value());
        else if (arg == "--font-dir")
            rOptions.fontDirs.emplace_back(value());
        else if (arg == "--tmp-dir")
            rOptions.tmpDir = value();
        else if (arg == "--locale")
            rOptions.locale = value();
        else if (arg == "--tagged-pdf")
            rOptions.taggedPdf = true;
        else if (arg == "--form-fields")
            rOptions.formFields = true;
        else if (arg == "--verbose")
            rOptions.verbose = true;
        else if (arg == "--update-font-cache")
            rOptions.updateFontCache = true;
        else if (arg == "--pdf-option")
        {
            std::string_view option(value());
            size_t eq = option.find('=');
            if (eq == std::string_view::npos || eq == 0)
                throw std::runtime_error("--pdf-option wants NAME=VALUE");
            rOptions.pdfOptions.push_back(comphelper::makePropertyValue(
                OUString::fromUtf8(option.substr(0, eq)), parseOptionValue(option.substr(eq + 1))));
        }
        else if (arg.size() > 1 && arg.starts_with("-"))
            throw std::runtime_error("unknown option " + std::string(arg));
        else
            positional.emplace_back(arg);
    }
    if (rOptions.updateFontCache)
        return positional.empty();
    if (positional.size() != 2)
        return false;
    rOptions.input = positional[0];
    rOptions.output = positional[1];
    return true;
}

// Options and messages are UTF-8; on Windows, std::string paths would be in the ANSI code page.
std::filesystem::path toPath(std::string_view aUtf8)
{
    return std::filesystem::path(std::u8string(aUtf8.begin(), aUtf8.end()));
}

std::string toUtf8(const std::filesystem::path& rPath)
{
    std::u8string aUtf8 = rPath.u8string();
    return std::string(aUtf8.begin(), aUtf8.end());
}

OUString toFileUrl(const std::filesystem::path& rPath)
{
    OUString aUrl;
    OUString aSystemPath = OUString::fromUtf8(toUtf8(std::filesystem::absolute(rPath)));
    if (osl::FileBase::getFileURLFromSystemPath(aSystemPath, aUrl) != osl::FileBase::E_None)
        throw std::runtime_error("bad path " + toUtf8(rPath));
    return aUrl;
}

void removeFile(const std::string& rPath)
{
    std::error_code ec;
    std::filesystem::remove(toPath(rPath), ec);
}

long processId()
{
#ifdef _WIN32
    return _getpid();
#else
    return getpid();
#endif
}

bool processExists(long nPid)
{
#ifdef _WIN32
    HANDLE hProcess = OpenProcess(SYNCHRONIZE, FALSE, static_cast<DWORD>(nPid));
    if (!hProcess)
        return GetLastError() != ERROR_INVALID_PARAMETER;
    // a process that has ended stays signalled while someone holds a handle to it
    bool bRunning = WaitForSingleObject(hProcess, 0) == WAIT_TIMEOUT;
    CloseHandle(hProcess);
    return bRunning;
#else
    return !(kill(static_cast<pid_t>(nPid), 0) == -1 && errno == ESRCH);
#endif
}

class Scratch;

// What to remove when the process dies from a signal (crash, SIGTERM).
Scratch* g_pScratch = nullptr;
std::string g_aPartialOutput;

// Holds the per-process scratch directory (user profile and temp files) and removes it on exit,
// also when the watchdog fires.
class Scratch
{
public:
    explicit Scratch(const std::string& rBase)
    {
        std::filesystem::path aBase = rBase.empty() ? defaultBase() : toPath(rBase);
        removeStale(aBase);
#ifdef _WIN32
        // it gets the permissions of the (per-user) temp directory it is in
        for (int n = 0; m_aPath.empty(); ++n)
        {
            std::filesystem::path aPath
                = aBase / ("word2pdf-" + std::to_string(processId()) + "-" + std::to_string(n));
            std::error_code ec;
            if (std::filesystem::create_directory(aPath, ec))
                m_aPath = aPath;
            else if (ec || n == 100)
                throw std::runtime_error("cannot create scratch directory in " + toUtf8(aBase));
        }
#else
        std::string aTemplate = toUtf8(aBase) + "/word2pdf-" + std::to_string(getpid()) + "-XXXXXX";
        if (!mkdtemp(aTemplate.data()))
            throw std::runtime_error("cannot create scratch directory in " + toUtf8(aBase));
        m_aPath = aTemplate;
#endif
        std::filesystem::create_directory(m_aPath / "tmp");
    }
    ~Scratch()
    {
        if (g_pScratch == this)
            g_pScratch = nullptr;
        remove();
    }

    const std::filesystem::path& path() const { return m_aPath; }

    void remove()
    {
        std::error_code ec;
        std::filesystem::remove_all(m_aPath, ec);
    }

private:
    static std::filesystem::path defaultBase()
    {
#ifdef _WIN32
        return std::filesystem::temp_directory_path();
#else
        const char* pTmp = std::getenv("TMPDIR");
        return pTmp && *pTmp ? pTmp : "/tmp";
#endif
    }

    // A run killed with SIGKILL cannot clean up after itself; the next run does it.
    static void removeStale(const std::filesystem::path& rBase)
    {
        std::error_code ec;
        for (const auto& rEntry : std::filesystem::directory_iterator(rBase, ec))
        {
            std::string aName = toUtf8(rEntry.path().filename());
            if (!aName.starts_with("word2pdf-"))
                continue;
            long nPid = std::atol(aName.c_str() + sizeof("word2pdf-") - 1);
            if (nPid > 0 && !processExists(nPid))
                std::filesystem::remove_all(rEntry.path(), ec);
        }
    }

    std::filesystem::path m_aPath;
};

// Kills the process if the conversion does not finish in time; LibreOffice can loop forever
// on some broken documents and the caller must never be left with a hung process.
class Watchdog
{
public:
    Watchdog(unsigned nSeconds, Scratch& rScratch, std::string aPartialOutput)
    {
        if (nSeconds == 0)
            return;
        m_aThread = std::thread([this, nSeconds, &rScratch, aPartialOutput] {
            std::unique_lock lock(m_aMutex);
            if (m_aCondition.wait_for(lock, std::chrono::seconds(nSeconds), [this] { return m_bDone; }))
                return;
            std::cerr << "word2pdf: timed out after " << nSeconds << " seconds\n";
            rScratch.remove();
            if (!aPartialOutput.empty())
                removeFile(aPartialOutput);
            _exit(EXIT_TIMEOUT);
        });
    }
    ~Watchdog()
    {
        if (!m_aThread.joinable())
            return;
        {
            std::scoped_lock lock(m_aMutex);
            m_bDone = true;
        }
        m_aCondition.notify_one();
        m_aThread.join();
    }

private:
    std::mutex m_aMutex;
    std::condition_variable m_aCondition;
    bool m_bDone = false;
    std::thread m_aThread;
};

// Not async-signal-safe, but the process is going away and a stale scratch directory per
// crash would pile up on a busy server.
[[noreturn]] void cleanUpAndExit(int nCode)
{
    static const char aCrashed[] = "word2pdf: crashed\n";
    static const char aTerminated[] = "word2pdf: terminated\n";
    const char* pMessage = nCode == EXIT_CRASHED ? aCrashed : aTerminated;
#ifdef _WIN32
    (void)_write(2, pMessage, static_cast<unsigned>(std::strlen(pMessage)));
#else
    (void)!write(2, pMessage, std::strlen(pMessage));
#endif
    if (g_pScratch)
        g_pScratch->remove();
    if (!g_aPartialOutput.empty())
        removeFile(g_aPartialOutput);
    _exit(nCode);
}

// For the signals sal handles itself (it only takes over SIGSEGV and SIGILL in soffice).
oslSignalAction onSalSignal(void*, oslSignalInfo* pInfo)
{
    switch (pInfo->Signal)
    {
        case osl_Signal_AccessViolation:
        case osl_Signal_IntegerDivideByZero:
        case osl_Signal_FloatDivideByZero:
            cleanUpAndExit(EXIT_CRASHED);
        case osl_Signal_Terminate:
            cleanUpAndExit(EXIT_TERMINATED);
        default:
            return osl_Signal_ActCallNextHdl;
    }
}

void installSignalHandlers()
{
#ifdef _WIN32
    // Crashes and Ctrl+C reach onSalSignal (sal's exception filter and console handler);
    // nothing may wait for someone to close an error dialog.
    SetErrorMode(SEM_FAILCRITICALERRORS | SEM_NOGPFAULTERRORBOX | SEM_NOOPENFILEERRORBOX);
    _set_abort_behavior(0, _WRITE_ABORT_MSG | _CALL_REPORTFAULT);
    std::signal(SIGABRT, [](int) { cleanUpAndExit(EXIT_CRASHED); });
#else
    struct sigaction aAction = {};
    sigemptyset(&aAction.sa_mask);
    aAction.sa_handler = [](int) { cleanUpAndExit(EXIT_CRASHED); };
    for (int nSignal : { SIGSEGV, SIGBUS, SIGILL, SIGFPE, SIGABRT })
        sigaction(nSignal, &aAction, nullptr);
    aAction.sa_handler = [](int) { cleanUpAndExit(EXIT_TERMINATED); };
    for (int nSignal : { SIGTERM, SIGINT, SIGQUIT })
        sigaction(nSignal, &aAction, nullptr);
#endif
    // sal installs its own handlers for some of these later and calls this one from them
    osl_addSignalHandler(onSalSignal, nullptr);
}

const lo_embedded_file* findAsset(std::string_view path)
{
    for (size_t i = 0; i < slim_assets_count; ++i)
        if (path == slim_assets[i].path)
            return &slim_assets[i];
    return nullptr;
}

// Serves embedded files to libxml2, for libraries that parse their data files themselves
// (liblangtag) instead of going through osl.
const lo_embedded_file* findEmbeddedXml(const char* pUri)
{
    std::string aNormalized(pUri ? pUri : "");
    std::string aRoot(EMBEDDED_ROOT);
#ifdef _WIN32
    // a file URL (file:///C:/...) or a system path with either separator, in any case
    for (std::string* pString : { &aNormalized, &aRoot })
        std::transform(pString->begin(), pString->end(), pString->begin(),
                       [](char c) { return c == '\\' ? '/' : std::tolower(static_cast<unsigned char>(c)); });
    std::string_view aUri(aNormalized);
    if (aUri.starts_with("file:///"))
        aUri.remove_prefix(8);
#else
    std::string_view aUri(aNormalized);
    if (aUri.starts_with("file://"))
        aUri.remove_prefix(7);
#endif
    if (!aUri.starts_with(aRoot))
        return nullptr;
    aUri.remove_prefix(aRoot.size());
    // normalize "//", "." and ".." (paths are built as ${ORIGIN}/../share/...)
    std::vector<std::string_view> aSegments;
    while (!aUri.empty())
    {
        size_t n = aUri.find('/');
        std::string_view aSegment = aUri.substr(0, n);
        aUri.remove_prefix(n == std::string_view::npos ? aUri.size() : n + 1);
        if (aSegment == "..")
        {
            if (!aSegments.empty())
                aSegments.pop_back();
        }
        else if (!aSegment.empty() && aSegment != ".")
            aSegments.push_back(aSegment);
    }
    std::string aPath;
    for (std::string_view aSegment : aSegments)
        (aPath += aPath.empty() ? "" : "/") += aSegment;
    return findAsset(aPath);
}

struct EmbeddedXmlInput
{
    const lo_embedded_file* pFile;
    size_t nPos;
};

void registerEmbeddedXmlInput()
{
    xmlRegisterInputCallbacks(
        [](const char* pUri) -> int { return findEmbeddedXml(pUri) != nullptr; },
        [](const char* pUri) -> void* { return new EmbeddedXmlInput{ findEmbeddedXml(pUri), 0 }; },
        [](void* pContext, char* pBuffer, int nLen) -> int {
            auto* pInput = static_cast<EmbeddedXmlInput*>(pContext);
            size_t n = std::min<size_t>(nLen, pInput->pFile->size - pInput->nPos);
            std::memcpy(pBuffer, pInput->pFile->data + pInput->nPos, n);
            pInput->nPos += n;
            return static_cast<int>(n);
        },
        [](void* pContext) -> int {
            delete static_cast<EmbeddedXmlInput*>(pContext);
            return 0;
        });
}

// Records why loading failed instead of showing a dialog; repairs broken packages like the
// interactive "repair the document?" question would, and refuses passwords.
class InteractionHandler : public cppu::WeakImplHelper<css::task::XInteractionHandler>
{
public:
    void SAL_CALL handle(const css::uno::Reference<css::task::XInteractionRequest>& xRequest) override
    {
        const css::uno::Any aRequest = xRequest->getRequest();
        bool bApprove = false;
        if (aRequest.isExtractableTo(cppu::UnoType<css::task::DocumentPasswordRequest>::get())
            || aRequest.isExtractableTo(cppu::UnoType<css::task::DocumentPasswordRequest2>::get())
            || aRequest.isExtractableTo(cppu::UnoType<css::task::DocumentMSPasswordRequest>::get())
            || aRequest.isExtractableTo(cppu::UnoType<css::task::DocumentMSPasswordRequest2>::get()))
            m_aError = "the document is password protected";
        else if (css::document::BrokenPackageRequest aBroken; aRequest >>= aBroken)
        {
            std::cerr << "word2pdf: warning: the document is damaged, repairing it\n";
            bApprove = true;
        }
        else if (css::task::ErrorCodeRequest aError; aRequest >>= aError)
            m_aError = "LibreOffice error code 0x" + toHex(aError.ErrCode);
        else if (aRequest.getValueTypeName() == "com.sun.star.document.NoSuchFilterRequest")
            m_aError = "not a supported document format";
        else if (css::uno::Exception aException; aRequest >>= aException)
            m_aError = aRequest.getValueTypeName().toUtf8().getStr() + std::string(": ")
                       + aException.Message.toUtf8().getStr();
        else
            m_aError = "unexpected request " + std::string(aRequest.getValueTypeName().toUtf8());

        for (const auto& xContinuation : xRequest->getContinuations())
        {
            if (bApprove
                    ? css::uno::Reference<css::task::XInteractionApprove>(xContinuation, css::uno::UNO_QUERY).is()
                    : css::uno::Reference<css::task::XInteractionAbort>(xContinuation, css::uno::UNO_QUERY).is())
            {
                xContinuation->select();
                return;
            }
        }
    }

    const std::string& error() const { return m_aError; }

private:
    static std::string toHex(sal_uInt32 n)
    {
        char aBuf[16];
        std::snprintf(aBuf, sizeof(aBuf), "%08x", n);
        return aBuf;
    }

    std::string m_aError;
};

// Must run before VCL starts: once a configuration is current, VCL's FcInit() keeps it.
void setupFonts(const Options& rOptions)
{
#if USE_HEADLESS_CODE
    // FONTCONFIG_FILE explicitly selects a configuration on disk; otherwise use the
    // compiled-in one, which only reads the standard font and font cache directories.
    if (!std::getenv("FONTCONFIG_FILE"))
    {
        const lo_embedded_file* pConf = findAsset(LIBO_SHARE_FOLDER "/fontconfig/fonts.conf");
        if (!pConf)
            throw std::runtime_error("no embedded fontconfig configuration");
        FcConfig* pConfig = FcConfigCreate();
        if (!FcConfigParseAndLoadFromMemory(pConfig, pConf->data, FcTrue)
            || !FcConfigSetCurrent(pConfig))
            throw std::runtime_error("cannot load the fontconfig configuration");
        FcConfigDestroy(pConfig);
    }
    else if (!FcInit())
        throw std::runtime_error("cannot load the fontconfig configuration");
    for (const auto& rDir : rOptions.fontDirs)
    {
        std::string aDir = std::filesystem::absolute(rDir).string();
        if (!FcConfigAppFontAddDir(nullptr, reinterpret_cast<const FcChar8*>(aDir.c_str())))
            throw std::runtime_error("cannot add font directory " + rDir);
    }
#elif defined _WIN32
    // fonts for this process only; VCL lists them with the installed ones
    for (const auto& rDir : rOptions.fontDirs)
    {
        std::error_code ec;
        for (const auto& rEntry : std::filesystem::recursive_directory_iterator(toPath(rDir), ec))
            if (rEntry.is_regular_file())
                AddFontResourceExW(rEntry.path().c_str(), FR_PRIVATE, nullptr);
        if (ec)
            throw std::runtime_error("cannot add font directory " + rDir);
    }
#else
    (void)rOptions;
#endif
}

#if USE_HEADLESS_CODE
// A descriptor of an anonymous file holding rFile, which ends with the process.
int openMemoryFile(const lo_embedded_file& rFile, const Scratch& rScratch)
{
#ifdef __linux__
    (void)rScratch;
    int nFd = memfd_create("word2pdf-font", MFD_CLOEXEC);
#else
    std::string aPath = toUtf8(rScratch.path() / "font-XXXXXX");
    int nFd = mkostemp(aPath.data(), O_CLOEXEC);
    if (nFd != -1)
        unlink(aPath.c_str());
#endif
    if (nFd == -1)
        throw std::runtime_error(std::string("cannot load the embedded font ") + rFile.path);
    for (size_t nDone = 0; nDone < rFile.size;)
    {
        ssize_t n = write(nFd, rFile.data + nDone, rFile.size - nDone);
        if (n == -1 && errno == EINTR)
            continue;
        if (n <= 0)
            throw std::runtime_error(std::string("cannot load the embedded font ") + rFile.path);
        nDone += static_cast<size_t>(n);
    }
    return nFd;
}
#endif

// Only after setupFonts: without a current configuration fontconfig would load the system's.
// VCL prefers application fonts over installed ones of the same version, as it does
// LibreOffice's bundled fonts.
void addEmbeddedFonts(const Scratch& rScratch)
{
#if USE_HEADLESS_CODE
    constexpr std::string_view aFontDir = LIBO_SHARE_FOLDER "/fonts/truetype/";
    for (size_t i = 0; i < slim_assets_count; ++i)
    {
        if (!std::string_view(slim_assets[i].path).starts_with(aFontDir))
            continue;
        // LibreOffice's name for an open descriptor; its FreeType, cairo and font subsetting
        // read the font through it
        std::string aName = "/:FD:/" + std::to_string(openMemoryFile(slim_assets[i], rScratch));
        if (!FcConfigAppFontAddFile(nullptr, reinterpret_cast<const FcChar8*>(aName.c_str())))
            throw std::runtime_error(std::string("cannot load the embedded font ")
                                     + slim_assets[i].path);
    }
#else
    (void)rScratch;
#endif
}

void readAll(std::istream& rIn, const std::filesystem::path& rTo)
{
    std::ofstream aOut(rTo, std::ios::binary);
    aOut << rIn.rdbuf();
    aOut.close();
    if (!aOut)
        throw std::runtime_error("cannot write " + toUtf8(rTo));
}

void initOffice(const Options& rOptions, const Scratch& rScratch)
{
    // Profile and temp files go to the scratch directory; nothing outside it is written.
#ifdef _WIN32
    // what GetTempPathW returns, which osl takes the temp directory from
    _wputenv_s(L"TMP", (rScratch.path() / "tmp").c_str());
    _wputenv_s(L"TEMP", (rScratch.path() / "tmp").c_str());
#else
    setenv("TMPDIR", (rScratch.path() / "tmp").c_str(), 1);
#endif
    rtl::Bootstrap::set(u"UserInstallation"_ustr, toFileUrl(rScratch.path() / "user"));

    css::uno::Reference<css::uno::XComponentContext> xContext(
        cppu::defaultBootstrap_InitialComponentContext());
    css::uno::Reference<css::lang::XMultiServiceFactory> xFactory(xContext->getServiceManager(),
                                                                  css::uno::UNO_QUERY_THROW);
    comphelper::setProcessServiceFactory(xFactory);

    // The locale comes from the configuration (en-US unless --locale), not the environment.
    if (!rOptions.locale.empty())
    {
        std::shared_ptr<comphelper::ConfigurationChanges> xChanges(
            comphelper::ConfigurationChanges::create());
        officecfg::Setup::L10N::ooSetupSystemLocale::set(OUString::fromUtf8(rOptions.locale),
                                                         xChanges);
        xChanges->commit();
    }
    LanguageTag::setConfiguredSystemLanguage(LanguageTag::convertToLanguageType(
        officecfg::Setup::L10N::ooSetupSystemLocale::get()));
    if (!InitVCL())
        throw std::runtime_error("cannot initialize VCL");
    Application::EnableHeadlessMode(false);
    // soffice creates this during desktop startup; document loading relies on it.
    SfxApplication::GetOrCreate();

    css::ucb::UniversalContentBroker::create(xContext);
    utl::SetTempNameBaseDirectory(toFileUrl(rScratch.path() / "tmp"));
}

OUString pdfFilterFor(const css::uno::Reference<css::lang::XComponent>& xDocument)
{
    css::uno::Reference<css::lang::XServiceInfo> xInfo(xDocument, css::uno::UNO_QUERY);
    if (!xInfo.is())
        throw std::runtime_error("loaded component is not a document");
    if (xInfo->supportsService(u"com.sun.star.text.WebDocument"_ustr))
        return u"writer_web_pdf_Export"_ustr;
    if (xInfo->supportsService(u"com.sun.star.text.GlobalDocument"_ustr))
        return u"writer_globaldocument_pdf_Export"_ustr;
    if (xInfo->supportsService(u"com.sun.star.text.TextDocument"_ustr))
        return u"writer_pdf_Export"_ustr;
    throw std::runtime_error("input is not a text document");
}

void convert(const Options& rOptions, const std::filesystem::path& rInput,
             const std::filesystem::path& rOutput)
{
    css::uno::Reference<css::uno::XComponentContext> xContext(
        comphelper::getProcessComponentContext());
    css::uno::Reference<css::frame::XDesktop2> xDesktop = css::frame::Desktop::create(xContext);

    rtl::Reference<InteractionHandler> xHandler(new InteractionHandler);
    css::uno::Sequence<css::beans::PropertyValue> aLoadArgs{
        comphelper::makePropertyValue(u"InteractionHandler"_ustr,
                                      css::uno::Reference<css::task::XInteractionHandler>(xHandler)),
        comphelper::makePropertyValue(u"Hidden"_ustr, true),
        comphelper::makePropertyValue(u"ReadOnly"_ustr, true),
        comphelper::makePropertyValue(u"Silent"_ustr, true),
        comphelper::makePropertyValue(u"MacroExecutionMode"_ustr,
                                      css::document::MacroExecMode::NEVER_EXECUTE),
        comphelper::makePropertyValue(u"UpdateDocMode"_ustr,
                                      css::document::UpdateDocMode::NO_UPDATE),
    };
    if (rOptions.verbose)
        std::cerr << "word2pdf: loading " << rInput << "\n";
    css::uno::Reference<css::lang::XComponent> xDocument
        = xDesktop->loadComponentFromURL(toFileUrl(rInput), u"_blank"_ustr, 0, aLoadArgs);
    if (!xDocument.is())
        throw std::runtime_error("cannot load " + toUtf8(rInput)
                                 + (xHandler->error().empty() ? "" : ": " + xHandler->error()));

    std::vector<css::beans::PropertyValue> aFilterData{
        comphelper::makePropertyValue(u"UseTaggedPDF"_ustr, rOptions.taggedPdf),
        comphelper::makePropertyValue(u"ExportFormFields"_ustr, rOptions.formFields),
    };
    aFilterData.insert(aFilterData.end(), rOptions.pdfOptions.begin(), rOptions.pdfOptions.end());
    css::uno::Sequence<css::beans::PropertyValue> aStoreArgs{
        comphelper::makePropertyValue(u"FilterName"_ustr, pdfFilterFor(xDocument)),
        comphelper::makePropertyValue(u"FilterData"_ustr,
                                      comphelper::containerToSequence(aFilterData)),
    };
    if (rOptions.verbose)
        std::cerr << "word2pdf: exporting " << rOutput << "\n";
    css::uno::Reference<css::frame::XStorable> xStorable(xDocument, css::uno::UNO_QUERY_THROW);
    xStorable->storeToURL(toFileUrl(rOutput), aStoreArgs);

    css::uno::Reference<css::util::XCloseable> xCloseable(xDocument, css::uno::UNO_QUERY);
    if (xCloseable.is())
        xCloseable->close(true);
    else
        xDocument->dispose();
}

int run(int argc, char** argv)
{
    Options aOptions;
    try
    {
        if (!parseArgs(argc, argv, aOptions))
        {
            usage(std::cerr);
            return EXIT_USAGE;
        }
    }
    catch (const std::exception& e)
    {
        std::cerr << "word2pdf: " << e.what() << "\n";
        return EXIT_USAGE;
    }

    if (aOptions.updateFontCache)
    {
        try
        {
            setupFonts(aOptions);
        }
        catch (const std::exception& e)
        {
            std::cerr << "word2pdf: " << e.what() << "\n";
            return EXIT_FAILED;
        }
#if USE_HEADLESS_CODE
        // Loading the configuration scanned every font directory without a valid cache and
        // wrote a cache for it into the first writable cache directory.
        FcFontSet* pFonts = FcConfigGetFonts(nullptr, FcSetSystem);
        std::cout << "word2pdf: " << (pFonts ? pFonts->nfont : 0) << " fonts\n";
#endif
        return EXIT_OK;
    }

    const bool bToStdout = aOptions.output == "-";
    // Written next to the destination and renamed at the end, so a failed or killed run
    // never leaves a truncated PDF behind under the requested name.
    std::string aPartial = bToStdout ? std::string() : aOptions.output + ".part";

    try
    {
        Scratch aScratch(aOptions.tmpDir);
        g_pScratch = &aScratch;
        g_aPartialOutput = aPartial;
        installSignalHandlers();
        Watchdog aWatchdog(aOptions.timeout, aScratch, aPartial);

        std::filesystem::path aInput = toPath(aOptions.input);
        if (aOptions.input == "-")
        {
            aInput = aScratch.path() / "input";
            readAll(std::cin, aInput);
        }
        else if (!std::filesystem::is_regular_file(aInput))
            throw std::runtime_error("no such file " + aOptions.input);

        setupFonts(aOptions);
        addEmbeddedFonts(aScratch);
        initOffice(aOptions, aScratch);

        std::filesystem::path aPdf = aScratch.path() / "output.pdf";
        convert(aOptions, aInput, aPdf);

        if (bToStdout)
        {
            std::ifstream aIn(aPdf, std::ios::binary);
            std::cout << aIn.rdbuf();
            std::cout.flush();
            if (!std::cout)
                throw std::runtime_error("cannot write to stdout");
        }
        else
        {
            // Not copy_file: libstdc++ creates the copy write-only and then changes its mode,
            // which Docker Desktop's file sharing on macOS refuses.
            std::ifstream aIn(aPdf, std::ios::binary);
            readAll(aIn, toPath(aPartial));
            std::filesystem::rename(toPath(aPartial), toPath(aOptions.output));
        }
    }
    catch (const css::uno::Exception& e)
    {
        std::cerr << "word2pdf: conversion failed: " << e.Message << "\n";
        if (!aPartial.empty())
            removeFile(aPartial);
        return EXIT_FAILED;
    }
    catch (const std::exception& e)
    {
        std::cerr << "word2pdf: conversion failed: " << e.what() << "\n";
        if (!aPartial.empty())
            removeFile(aPartial);
        return EXIT_FAILED;
    }
    return EXIT_OK;
}
}

SAL_IMPLEMENT_MAIN_WITH_ARGS(argc, argv)
{
    lo_embeddedfs_register(EMBEDDED_ROOT, slim_assets, slim_assets_count);
    registerEmbeddedXmlInput();
#ifdef _WIN32
    // documents and PDFs pass stdin and stdout unchanged, without newline translation
    _setmode(_fileno(stdin), _O_BINARY);
    _setmode(_fileno(stdout), _O_BINARY);
    // argv is in the ANSI code page; sal has the arguments as UTF-16
    std::vector<std::string> aArgs{ argv[0] };
    for (sal_uInt32 i = 0; i < osl_getCommandArgCount(); ++i)
    {
        OUString aArg;
        osl_getCommandArg(i, &aArg.pData);
        aArgs.push_back(aArg.toUtf8().getStr());
    }
    std::vector<char*> aArgv;
    for (std::string& rArg : aArgs)
        aArgv.push_back(rArg.data());
    int nRet = run(static_cast<int>(aArgv.size()), aArgv.data());
#else
    int nRet = run(argc, argv);
#endif
    std::fflush(stdout);
    std::fflush(stderr);
    // The document is written and closed; tearing down the office would only cost time.
    _exit(nRet);
}

/* vim:set shiftwidth=4 softtabstop=4 expandtab: */
