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