//
// Copyright (c) 2015 The ANGLE Project Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.
//

// WindowSurfaceCGL.cpp: CGL implementation of egl::Surface for windows

#include "libANGLE/renderer/gl/cgl/WindowSurfaceCGL.h"

#import  <Cocoa/Cocoa.h>
#import <QuartzCore/QuartzCore.h>
#include <OpenGL/OpenGL.h>

#include "common/debug.h"
#include "libANGLE/renderer/gl/cgl/DisplayCGL.h"
#include "libANGLE/renderer/gl/FramebufferGL.h"
#include "libANGLE/renderer/gl/RendererGL.h"
#include "libANGLE/renderer/gl/StateManagerGL.h"

#define GL_TEXTURE_RECTANGLE_ARB 0x84F5

namespace rx
{

WindowSurfaceCGL::WindowSurfaceCGL(DisplayCGL *display, CALayer *layer, const FunctionsGL *functions)
    : SurfaceGL(display->getRenderer()),
      mWidth(0),
      mHeight(0),
      mDisplay(display),
      mLayer(layer),
      mFunctions(functions),
      mStateManager(mDisplay->getRenderer()->getStateManager()),
      mCurrentSurface(0),
      mFramebuffer(0)
{
  for (size_t i = 0; i < 2; i++)
  {
      mSurfaces[i].texture = 0;
      mSurfaces[i].ioSurface = nil;
  }
}

WindowSurfaceCGL::~WindowSurfaceCGL()
{
    if (mFramebuffer != 0)
    {
        mFunctions->deleteFramebuffers(1, &mFramebuffer);
        mFramebuffer = 0;
    }

    for (size_t i = 0; i < 2; i++)
    {
        Surface& surface = mSurfaces[i];
        if (surface.texture != 0)
        {
            mFunctions->deleteTextures(1, &surface.texture);
            surface.texture = 0;
        }
        if (surface.ioSurface != nil)
        {
            CFRelease(surface.ioSurface);
            surface.ioSurface = nil;
        }
    }
}

egl::Error WindowSurfaceCGL::initialize()
{
    unsigned width = getWidth();
    unsigned height = getHeight();

    CFDictionaryRef ioSurfaceOptions = nil;
    {
        unsigned pixelFormat = 'BGRA';
        const unsigned kBytesPerElement = 4;
        size_t bytesPerRow = IOSurfaceAlignProperty(kIOSurfaceBytesPerRow, width * kBytesPerElement);
        size_t totalBytes = IOSurfaceAlignProperty(kIOSurfaceAllocSize, height * bytesPerRow);

        NSDictionary *options = @{
            (id)kIOSurfaceWidth: @(width),
            (id)kIOSurfaceHeight: @(height),
            (id)kIOSurfacePixelFormat: @(pixelFormat),
            (id)kIOSurfaceBytesPerElement: @(kBytesPerElement),
            (id)kIOSurfaceBytesPerRow: @(bytesPerRow),
            (id)kIOSurfaceAllocSize: @(totalBytes),
        };
        ioSurfaceOptions = reinterpret_cast<CFDictionaryRef>(options);
    }

    for (size_t i = 0; i < 2; i++)
    {
        Surface& surface = mSurfaces[i];
        surface.ioSurface = IOSurfaceCreate(ioSurfaceOptions);

        mFunctions->genTextures(1, &surface.texture);
        mFunctions->bindTexture(GL_TEXTURE_RECTANGLE_ARB, surface.texture);

        CGLError error = CGLTexImageIOSurface2D(
                CGLGetCurrentContext(),
                GL_TEXTURE_RECTANGLE_ARB,
                GL_RGBA,
                width,
                height,
                GL_BGRA,
                GL_UNSIGNED_INT_8_8_8_8_REV,
                surface.ioSurface,
                0);

        if (error != kCGLNoError)
        {
            std::string errorMessage = "Could not create the IOSurfaces: " + std::string(CGLErrorString(error));
            return egl::Error(EGL_BAD_NATIVE_WINDOW, errorMessage.c_str());
        }
    }

    mFunctions->genFramebuffers(1, &mFramebuffer);
    mStateManager->bindFramebuffer(GL_FRAMEBUFFER, mFramebuffer);
    mFunctions->framebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_RECTANGLE_ARB, mSurfaces[0].texture, 0);

    return egl::Error(EGL_SUCCESS);
}

egl::Error WindowSurfaceCGL::makeCurrent()
{
    // TODO(cwallez) if it is the first makeCurrent set the viewport and scissor?

    return egl::Error(EGL_SUCCESS);
}

egl::Error WindowSurfaceCGL::swap()
{
    // A flush is needed for the IOSurface to get the result of the GL operations
    // as specified in the documentation of CGLTexImageIOSurface2D
    mFunctions->flush();

    if(mLayer) {
        // Put the IOSurface as the content of the layer
        [CATransaction begin];
        [mLayer setContents: (id) mSurfaces[mCurrentSurface].ioSurface];
        [CATransaction commit];

        mCurrentSurface = (mCurrentSurface + 1) % 2;
        IOSurfaceRef surface = mSurfaces[mCurrentSurface].ioSurface;

        // Wait for the compositor to have finished using the IOSurface before
        // rendering to it again.
        // TODO(cwallez) this doesn't seem to work when dragging the window on
        // the top of the screen, figure out a better way to do it?
        if (IOSurfaceIsInUse(surface))
        {
            IOSurfaceLock(surface, kIOSurfaceLockReadOnly, nullptr);
            IOSurfaceUnlock(surface, kIOSurfaceLockReadOnly, nullptr);
        }
    }

    mStateManager->bindFramebuffer(GL_FRAMEBUFFER, mFramebuffer);
    mFunctions->framebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_RECTANGLE_ARB, mSurfaces[mCurrentSurface].texture, 0);

    return egl::Error(EGL_SUCCESS);
}

egl::Error WindowSurfaceCGL::postSubBuffer(EGLint x, EGLint y, EGLint width, EGLint height)
{
    UNIMPLEMENTED();
    return egl::Error(EGL_SUCCESS);
}

egl::Error WindowSurfaceCGL::querySurfacePointerANGLE(EGLint attribute, void **value)
{
    UNIMPLEMENTED();
    return egl::Error(EGL_SUCCESS);
}

egl::Error WindowSurfaceCGL::bindTexImage(EGLint buffer)
{
    UNIMPLEMENTED();
    return egl::Error(EGL_SUCCESS);
}

egl::Error WindowSurfaceCGL::releaseTexImage(EGLint buffer)
{
    UNIMPLEMENTED();
    return egl::Error(EGL_SUCCESS);
}

void WindowSurfaceCGL::setSwapInterval(EGLint interval)
{
    // TODO
    //UNIMPLEMENTED();
}

void WindowSurfaceCGL::setShape(EGLint width, EGLint height)
{
    mWidth = width;
    mHeight = height;
}

EGLint WindowSurfaceCGL::getWidth() const
{
    if(mLayer) {
      return CGRectGetWidth([mLayer frame]);
    }
    return mWidth;
}

EGLint WindowSurfaceCGL::getHeight() const
{
    if(mLayer) {
      return CGRectGetHeight([mLayer frame]);
    }
    return mHeight;
}

EGLint WindowSurfaceCGL::isPostSubBufferSupported() const
{
    UNIMPLEMENTED();
    return EGL_FALSE;
}

EGLint WindowSurfaceCGL::getSwapBehavior() const
{
    return EGL_BUFFER_DESTROYED;
}

FramebufferImpl *WindowSurfaceCGL::createDefaultFramebuffer(const gl::Framebuffer::Data &data)
{
    //TODO(cwallez) assert it happens only once?
    return new FramebufferGL(mFramebuffer, data, mFunctions, mStateManager);
}

}
