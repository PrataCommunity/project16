$ErrorActionPreference = 'Stop'
$repoRoot = $PSScriptRoot

if (-not (Test-Path (Join-Path $repoRoot '.git'))) {
    Write-Host 'ERROR: This script is not inside the root of your cloned project16 repository.' -ForegroundColor Red
    Write-Host 'Move this script and APPLY_WEB_PORT_STAGE1.bat into the project16 folder, beside the README.md file.'
    Read-Host 'Press Enter to close'
    exit 1
}

$relativeFiles = @(
    'Rendering/GfxCore/GL/HeadersGL.h',
    'Rendering/GfxCore/GL/DeviceGL.cpp',
    'Rendering/GfxCore/GL/TextureGL.cpp',
    'Rendering/GfxCore/GL/GeometryGL.cpp'
)
$contents = @{}
foreach ($relative in $relativeFiles) {
    $full = Join-Path $repoRoot $relative
    if (-not (Test-Path $full)) { throw "Required source file not found: $relative" }
    $contents[$relative] = ([System.IO.File]::ReadAllText($full) -replace "`r`n", "`n" -replace "`r", "`n")
}

function Replace-ExactlyOnce([string]$source, [string]$oldText, [string]$newText, [string]$label) {
    $first = $source.IndexOf($oldText, [System.StringComparison]::Ordinal)
    if ($first -lt 0) { throw "Could not find expected source section: $label. No files have been changed." }
    $second = $source.IndexOf($oldText, $first + $oldText.Length, [System.StringComparison]::Ordinal)
    if ($second -ge 0) { throw "Found more than one match for: $label. No files have been changed." }
    return $source.Substring(0, $first) + $newText + $source.Substring($first + $oldText.Length)
}

function Wrap-FunctionForWeb([string]$source, [string]$signature, [string]$nextSignature, [string]$webBody, [string]$label) {
    $start = $source.IndexOf($signature, [System.StringComparison]::Ordinal)
    if ($start -lt 0) { throw "Could not find function: $label. No files have been changed." }
    $end = $source.IndexOf($nextSignature, $start + $signature.Length, [System.StringComparison]::Ordinal)
    if ($end -lt 0) { throw "Could not find the end of function: $label. No files have been changed." }
    $fn = $source.Substring($start, $end - $start)
    $open = $fn.IndexOf('{')
    $close = $fn.LastIndexOf('}')
    if ($open -lt 0 -or $close -le $open) { throw "Could not parse function body: $label. No files have been changed." }
    $wrapped = $fn.Substring(0, $open + 1) + "`n#ifdef __EMSCRIPTEN__`n" + $webBody + "`n#else`n" + $fn.Substring($open + 1, $close - $open - 1) + "`n#endif`n" + $fn.Substring($close)
    return $source.Substring(0, $start) + $wrapped + $source.Substring($end)
}

# HeadersGL.h: select Emscripten's GLES headers and provide the same sync typedefs used by Android.
$p = 'Rendering/GfxCore/GL/HeadersGL.h'
$s = $contents[$p]
$s = Replace-ExactlyOnce $s "#pragma once`n" "#pragma once`n`n#include <stdint.h>`n" 'HeadersGL integer types'
$s = Replace-ExactlyOnce $s "#elif defined(__ANDROID__)`n    #include <GLES2/gl2.h>`n    #include <GLES2/gl2ext.h>`n`n    #define GLES`n#else" "#elif defined(__ANDROID__) || defined(__EMSCRIPTEN__)`n    #include <GLES2/gl2.h>`n    #include <GLES2/gl2ext.h>`n`n    #define GLES`n#else" 'HeadersGL Emscripten GLES headers'
$s = Replace-ExactlyOnce $s "#ifdef __ANDROID__`ntypedef struct __GLsync *GLsync;`ntypedef uint64_t GLuint64;`n#endif" "#if defined(__ANDROID__) || defined(__EMSCRIPTEN__)`ntypedef struct __GLsync *GLsync;`ntypedef uint64_t GLuint64;`n#endif" 'HeadersGL sync typedefs'
$contents[$p] = $s

# DeviceGL.cpp: select the GLES 3 shader/capability path but disable APIs absent from WebGL 2.
$p = 'Rendering/GfxCore/GL/DeviceGL.cpp'
$s = $contents[$p]
$s = Replace-ExactlyOnce $s 'FASTFLAGVARIABLE(GraphicsGL3, false)' "#ifdef __EMSCRIPTEN__`nFASTFLAGVARIABLE(GraphicsGL3, true)`n#else`nFASTFLAGVARIABLE(GraphicsGL3, false)`n#endif" 'GraphicsGL3 web default'
$oldCaps = "    caps.extMapBuffer = version3 || extensions.count(`"GL_OES_mapbuffer`");`n    caps.extMapBufferRange = version3 || extensions.count(`"GL_EXT_map_buffer_range`");`n    caps.extTimerQuery = false;`n    caps.extDebugMarkers = extensions.count(`"GL_EXT_debug_marker`");`n    caps.extSync = version3;
"
$newCaps = "    caps.extMapBuffer = version3 || extensions.count(`"GL_OES_mapbuffer`");`n    caps.extMapBufferRange = version3 || extensions.count(`"GL_EXT_map_buffer_range`");`n    caps.extTimerQuery = false;`n    caps.extDebugMarkers = extensions.count(`"GL_EXT_debug_marker`");`n    caps.extSync = version3;`n`n#ifdef __EMSCRIPTEN__`n    // WebGL 2 has no native mapped-buffer or server-side wait-sync paths.`n    // GeometryGL uses CPU staging plus glBufferSubData; dynamic textures use direct uploads.`n    caps.extMapBuffer = false;`n    caps.extMapBufferRange = false;`n    caps.extSync = false;`n#endif`n"
$s = Replace-ExactlyOnce $s $oldCaps $newCaps 'WebGL capability overrides'
$s = Replace-ExactlyOnce $s "    if (FFlag::GraphicsGLReduceLatency && caps.extSync)`n    {" "#ifndef __EMSCRIPTEN__`n    if (FFlag::GraphicsGLReduceLatency && caps.extSync)`n    {" 'WebGL sync guard start'
$s = Replace-ExactlyOnce $s "    }`n`n`tif (vr && vrEnabled)`n`t{`n`t	vr->submitFrame(immediateContext.get());" "    }`n#endif`n`n`tif (vr && vrEnabled)`n`t{`n`t	vr->submitFrame(immediateContext.get());" 'WebGL sync guard end'
$contents[$p] = $s

# GeometryGL.cpp: use the existing CPU staging + glBufferSubData path on WebAssembly.
$p = 'Rendering/GfxCore/GL/GeometryGL.cpp'
$s = $contents[$p]
$s = Wrap-FunctionForWeb $s 'template <typename Base> void* GeometryBufferGL<Base>::lock(GeometryBuffer::LockMode mode)' 'template <typename Base> void GeometryBufferGL<Base>::unlock()' "    RBXASSERT(!locked);`n    unsigned int size = this->elementSize * this->elementCount;`n    locked = new char[size];`n    return locked;" 'GeometryBufferGL::lock'
$s = Wrap-FunctionForWeb $s 'template <typename Base> void GeometryBufferGL<Base>::unlock()' 'template <typename Base> void GeometryBufferGL<Base>::upload(unsigned int offset, const void* data, unsigned int size)' "    RBXASSERT(locked);`n    glBindBuffer(target, id);`n    glBufferSubData(target, 0, this->elementSize * this->elementCount, locked);`n    delete[] static_cast<char*>(locked);`n    locked = NULL;" 'GeometryBufferGL::unlock'
$contents[$p] = $s

# TextureGL.cpp: do not create a pixel-unpack scratch buffer on the WebGL backend.
$p = 'Rendering/GfxCore/GL/TextureGL.cpp'
$s = $contents[$p]
$s = Replace-ExactlyOnce $s 'if (FFlag::GraphicsTextureCommitChanges && usage == Usage_Dynamic && caps.ext3)' 'if (FFlag::GraphicsTextureCommitChanges && usage == Usage_Dynamic && caps.extMapBufferRange)' 'TextureGL scratch-buffer capability check'
$s = Wrap-FunctionForWeb $s 'Texture::LockResult TextureGL::lock(unsigned int index, unsigned int mip, const TextureRegion& region)' 'void TextureGL::unlock(unsigned int index, unsigned int mip)' "    Texture::LockResult result = {0, 0, 0};`n    return result;" 'TextureGL::lock'
$s = Wrap-FunctionForWeb $s 'void TextureGL::unlock(unsigned int index, unsigned int mip)' 'shared_ptr<Renderbuffer> TextureGL::getRenderbuffer' "    (void)index;`n    (void)mip;" 'TextureGL::unlock'
$contents[$p] = $s

# New WebGL 2 implementation of the engine's existing ContextGL interface.
$contextWeb = @'
#include "ContextGL.h"

#include "HeadersGL.h"

#include "rbx/Debug.h"

#include <emscripten/html5.h>

#include <algorithm>
#include <cmath>
#include <string>

namespace RBX
{
namespace Graphics
{

class ContextGLWeb: public ContextGL
{
public:
    explicit ContextGLWeb(void* windowHandle)
        : canvasSelector(windowHandle ? static_cast<const char*>(windowHandle) : "#game-canvas")
        , context(0)
        , framebufferWidth(0)
        , framebufferHeight(0)
        , pixelRatio(1.0)
    {
        EmscriptenWebGLContextAttributes attributes;
        emscripten_webgl_init_context_attributes(&attributes);

        attributes.alpha = EM_FALSE;
        attributes.depth = EM_TRUE;
        attributes.stencil = EM_TRUE;
        attributes.antialias = EM_TRUE;
        attributes.majorVersion = 2;
        attributes.minorVersion = 0;
        attributes.enableExtensionsByDefault = EM_TRUE;
        attributes.explicitSwapControl = EM_FALSE;

        context = emscripten_webgl_create_context(canvasSelector.c_str(), &attributes);
        if (!context)
            throw RBX::runtime_error("WebGL: failed to create WebGL 2 context for canvas %s", canvasSelector.c_str());

        EMSCRIPTEN_RESULT result = emscripten_webgl_make_context_current(context);
        if (result != EMSCRIPTEN_RESULT_SUCCESS)
        {
            emscripten_webgl_destroy_context(context);
            context = 0;
            throw RBX::runtime_error("WebGL: failed to make context current (%d)", static_cast<int>(result));
        }

        updateMainFramebuffer(0, 0);
    }

    virtual ~ContextGLWeb()
    {
        if (context)
            emscripten_webgl_destroy_context(context);
    }

    virtual void setCurrent()
    {
        EMSCRIPTEN_RESULT result = emscripten_webgl_make_context_current(context);
        RBXASSERT(result == EMSCRIPTEN_RESULT_SUCCESS);
    }

    virtual void swapBuffers()
    {
        // The browser presents the drawing buffer when control returns to its event loop.
        glFlush();
    }

    virtual unsigned int getMainFramebufferId()
    {
        return 0;
    }

    virtual bool isMainFramebufferRetina()
    {
        return pixelRatio > 1.0;
    }

    virtual std::pair<unsigned int, unsigned int> updateMainFramebuffer(unsigned int width, unsigned int height)
    {
        (void)width;
        (void)height;

        double cssWidth = 0.0;
        double cssHeight = 0.0;
        int currentWidth = 0;
        int currentHeight = 0;

        EMSCRIPTEN_RESULT cssResult = emscripten_get_element_css_size(canvasSelector.c_str(), &cssWidth, &cssHeight);
        EMSCRIPTEN_RESULT canvasResult = emscripten_get_canvas_element_size(canvasSelector.c_str(), &currentWidth, &currentHeight);

        if (cssResult == EMSCRIPTEN_RESULT_SUCCESS && cssWidth > 0.0 && cssHeight > 0.0)
        {
            pixelRatio = emscripten_get_device_pixel_ratio();
            if (!(pixelRatio > 0.0) || !std::isfinite(pixelRatio))
                pixelRatio = 1.0;

            const int targetWidth = std::max(1, static_cast<int>(std::ceil(cssWidth * pixelRatio)));
            const int targetHeight = std::max(1, static_cast<int>(std::ceil(cssHeight * pixelRatio)));

            if (canvasResult != EMSCRIPTEN_RESULT_SUCCESS || currentWidth != targetWidth || currentHeight != targetHeight)
            {
                EMSCRIPTEN_RESULT resizeResult = emscripten_set_canvas_element_size(canvasSelector.c_str(), targetWidth, targetHeight);
                if (resizeResult != EMSCRIPTEN_RESULT_SUCCESS)
                    throw RBX::runtime_error("WebGL: failed to resize canvas %s (%d)", canvasSelector.c_str(), static_cast<int>(resizeResult));

                currentWidth = targetWidth;
                currentHeight = targetHeight;
            }
        }
        else if (canvasResult != EMSCRIPTEN_RESULT_SUCCESS)
        {
            throw RBX::runtime_error("WebGL: canvas %s was not found or has no drawing buffer", canvasSelector.c_str());
        }

        framebufferWidth = static_cast<unsigned int>(std::max(1, currentWidth));
        framebufferHeight = static_cast<unsigned int>(std::max(1, currentHeight));
        return std::make_pair(framebufferWidth, framebufferHeight);
    }

private:
    std::string canvasSelector;
    EMSCRIPTEN_WEBGL_CONTEXT_HANDLE context;
    unsigned int framebufferWidth;
    unsigned int framebufferHeight;
    double pixelRatio;
};

ContextGL* ContextGL::create(void* windowHandle)
{
    return new ContextGLWeb(windowHandle);
}

}
}
'@

# Validate every transformation succeeded before touching any file on disk.
$newContextPath = Join-Path $repoRoot 'Rendering/GfxCore/GL/ContextGLWeb.cpp'
if (Test-Path $newContextPath) { throw 'ContextGLWeb.cpp already exists. No files have been changed.' }

$backupRoot = Join-Path $repoRoot '.web-port-stage1-backup'
if (Test-Path $backupRoot) { throw 'A .web-port-stage1-backup folder already exists. No files have been changed.' }
New-Item -ItemType Directory -Path $backupRoot | Out-Null
foreach ($relative in $relativeFiles) {
    $sourcePath = Join-Path $repoRoot $relative
    $backupPath = Join-Path $backupRoot $relative
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $backupPath) | Out-Null
    [System.IO.File]::Copy($sourcePath, $backupPath, $false)
}

$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
foreach ($relative in $relativeFiles) {
    $full = Join-Path $repoRoot $relative
    $windowsText = $contents[$relative] -replace "`n", "`r`n"
    [System.IO.File]::WriteAllText($full, $windowsText, $utf8NoBom)
}
[System.IO.File]::WriteAllText($newContextPath, ($contextWeb -replace "`n", "`r`n"), $utf8NoBom)

Write-Host ''
Write-Host 'Stage 1 source changes applied successfully.' -ForegroundColor Green
Write-Host 'Changed files:'
foreach ($relative in $relativeFiles) { Write-Host "  $relative" }
Write-Host '  Rendering/GfxCore/GL/ContextGLWeb.cpp'
Write-Host ''
Write-Host "Backups of the original four files are in: $backupRoot" -ForegroundColor Yellow
Write-Host 'Important: this is a renderer source milestone, not a complete/compiled browser client.' -ForegroundColor Yellow
Write-Host 'Next: open GitHub Desktop, commit the changes on web-port/stage-1-webgl-context, then Push origin.'
Read-Host 'Press Enter to close'
