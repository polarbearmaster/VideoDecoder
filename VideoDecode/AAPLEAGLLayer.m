//
//  AAPLEAGLLayer.m
//  VideoDecode
//
//  Created by kenny on 07/03/2017.
//  Copyright © 2017 yuneec. All rights reserved.
//

/*
 This file is based on the original Apple CAEAGLLayer subclass which is to demonstrates how to draw a CVPixelBufferRef using OpenGLES and display the timecode assciated with that pixel buffer in the top right corner
 See https://developer.apple.com/library/prerelease/ios/samplecode/VideoTimeline/Introduction/Intro.html
 */

#import "AAPLEAGLLayer.h"

#import <mach/mach_time.h>
@import AVFoundation;
@import OpenGLES;
@import UIKit;

// Uniform index.
enum
{
    UNIFORM_Y,
    UNIFORM_UV,
    UNIFORM_ROTATION_ANGLE,
    UNIFORM_COLOR_CONVERSION_MATRIX,
    NUM_UNIFORMS
};
GLint uniforms[NUM_UNIFORMS];

// Attribute index
enum
{
    ATTRIB_VERTEX,
    ATTRIB_TEXCOORD,
    NUM_ATTRIBUTES
};

// Color Conversion Constants (YUV to RGB) including adjustment from 16-235/16-240 (video range)

// BT.601, which is the standard for SDTV
static const GLfloat kColorConversion601[] = {
    1.164, 1.164, 1.164,
    0.0, -0.392, 2.017,
    1.596, -0.813, 0.0,
}; // 别问我这些数字怎么来的

// BT. 709, which is the standatd for HDTV.
static const GLfloat kColorConversion709[] = {
    1.164, 1.164, 1.164,
    0.0, -0.213, 2.112,
    1.793, -0.533, 0.0
}; // 别问我这些数字怎么来的

@interface AAPLEAGLLayer ()
{
    // The pixel dimensions of the CAEAGLLayer
    GLint _backingWidth;
    GLint _backingHeight;
    
    EAGLContext *_context;
    CVOpenGLESTextureRef _lumaTexture;
    CVOpenGLESTextureRef _chromaTexture;
    
    GLuint _frameBufferHandle;
    GLuint _colorBufferHandle;
    
    const GLfloat *_preferredConversion;
}
@property GLuint program;

@end
@implementation AAPLEAGLLayer
@synthesize pixelBuffer = _pixelBuffer;

- (CVPixelBufferRef)pixelBuffer {
    return _pixelBuffer;
}

- (void)setPixelBuffer:(CVPixelBufferRef)pbc {
    if (_pixelBuffer) {
        CVPixelBufferRelease(_pixelBuffer);
    }
    _pixelBuffer = CVPixelBufferRetain(pbc);
    
    [self displayPixelBuffer:_pixelBuffer];
}

- (instancetype)initWithFrame:(CGRect)frame {
    if (self = [super init]) {
        self.contentsScale = [UIScreen mainScreen].scale;
        
        self.opaque = TRUE;
        self.drawableProperties = @{ kEAGLDrawablePropertyRetainedBacking:[NSNumber numberWithBool:YES] };
        
        [self setFrame:frame];
        
        // Set the context into which the frames will be drawn.
        _context = [[EAGLContext alloc] initWithAPI:kEAGLRenderingAPIOpenGLES2];
        
        if (!_context || ![EAGLContext setCurrentContext:_context]) {
            return nil;
        }
        
        // Set the default conversion to BT.709, which is the standard for HDTV.
        _preferredConversion = kColorConversion709;
        
        [self setupGL];
    }
    
    return self;
}

- (void)displayPixelBuffer:(CVPixelBufferRef)pixelBuffer {
    if (pixelBuffer == NULL) {
        NSLog(@"Pixel Buffer is null");
        return;
    }
    
    CVReturn err;
    int frameWidth = (int)CVPixelBufferGetWidth(pixelBuffer);
    int frameHeight = (int)CVPixelBufferGetHeight(pixelBuffer);
    
    size_t planeCount = CVPixelBufferGetPlaneCount(pixelBuffer);
    
    /*
     Use the color attachment of the pixel buffer to determine the appropriate color conversion matrix.
     */
    CFTypeRef colorAttachments = CVBufferGetAttachment(pixelBuffer, kCVImageBufferYCbCrMatrixKey, NULL);
    
    if (colorAttachments == kCVImageBufferYCbCrMatrix_ITU_R_601_4) {
        _preferredConversion = kColorConversion601;
    } else {
        _preferredConversion = kColorConversion709;
    }
    
    /*
     CVOpenGLESTextureCacheCreateTextureFromIamge will create GLES texture optimally from CVPixelBufferRef
     */
    
    /*
     Create Y and UV textures from the pixel buffer. These textures will be drawn on the frame buffer Y-plane.
     */
    
    CVOpenGLESTextureCacheRef _videoTextureCache;
    // Create CVOpenGLESTextureCacheRef for optimal CVPixelBufferRef to GLES texture converison.
    
    err = CVOpenGLESTextureCacheCreate(kCFAllocatorDefault, NULL, _context, NULL, &_videoTextureCache);
    if (err != noErr) {
        NSLog(@"Error at CVOpenGLESTextureCacheCreate %d", err);
        return;
    }
    glActiveTexture(GL_TEXTURE0);
    
    err = CVOpenGLESTextureCacheCreateTextureFromImage(kCFAllocatorDefault, _videoTextureCache, pixelBuffer, NULL, GL_TEXTURE_2D, GL_RED_EXT, frameWidth, frameHeight, GL_RED_EXT, GL_UNSIGNED_BYTE, 0, &_lumaTexture);
    
    if (err) {
        NSLog(@"Error at CVOPENGLESTextureCacheCreateTextureFromImage %d", err);
    }
    
    glBindTexture(CVOpenGLESTextureGetTarget(_lumaTexture), CVOpenGLESTextureGetName(_lumaTexture));
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
    glTexParameterf(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
    glTexParameterf(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
    
    // UV-plane.
    if (planeCount == 2) {
        glActiveTexture(GL_TEXTURE1);
        err = CVOpenGLESTextureCacheCreateTextureFromImage(kCFAllocatorDefault, _videoTextureCache, pixelBuffer, NULL, GL_TEXTURE_2D, GL_RG_EXT, frameWidth / 2, frameHeight / 2, GL_RG_EXT, GL_UNSIGNED_BYTE, 1, &_chromaTexture);
        
        if (err) {
            NSLog(@"Error at CVOpenGLESTextureCacheCreateTextureFromImage %d", err);
        }
        
        glBindTexture(CVOpenGLESTextureGetTarget(_chromaTexture), CVOpenGLESTextureGetName(_chromaTexture));
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
        glTexParameterf(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
        glTexParameterf(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
    }
    
    glBindFramebuffer(GL_FRAMEBUFFER, _frameBufferHandle);
    
    // Set the view port to the entire view
    glViewport(0, 0, _backingWidth, _backingHeight);
    
    glClearColor(0.0f, 0.0f, 0.0f, 1.0f);
    glClear(GL_COLOR_BUFFER_BIT);
    
    // Use shader program
    glUseProgram(self.program);
    
    glUniform1f(uniforms[UNIFORM_ROTATION_ANGLE], 0);
    glUniformMatrix3fv(uniforms[UNIFORM_COLOR_CONVERSION_MATRIX], 1, GL_FALSE, _preferredConversion);
    
    // Set up the quad vertices with respect to the orientation and aspect ratio of the video
    CGRect vertexSamplingRect = AVMakeRectWithAspectRatioInsideRect(CGSizeMake(frameWidth, frameHeight), self.bounds);
    
    // Compute normalized quad coordinates to draw the frame into
    CGSize normalizedSamplingSize = CGSizeMake(0.0, 0.0);
    CGSize cropScaleAmount = CGSizeMake(vertexSamplingRect.size.width/self.bounds.size.width, vertexSamplingRect.size.height/self.bounds.size.height);
    
    // Normalize the quad vertices.
    if (cropScaleAmount.width > cropScaleAmount.height) {
        normalizedSamplingSize.width = 1.0;
        normalizedSamplingSize.height = cropScaleAmount.height/cropScaleAmount.width;
    } else {
        normalizedSamplingSize.width = cropScaleAmount.width/cropScaleAmount.height;
        normalizedSamplingSize.height = 1.0;
    }
    
    /*
     The quad vertex data defines the region of 2D plane onto which we draw our pixel buffers.
     Vertex data formed using (-1,-1) and (1,1) as the bottom left and top coordinates respectively, covers the entire screen.
     */
    GLfloat quadVertexData [] = {
        -1 * normalizedSamplingSize.width, -1 * normalizedSamplingSize.height,
        normalizedSamplingSize.width, -1 * normalizedSamplingSize.height,
        -1 * normalizedSamplingSize.width, normalizedSamplingSize.height,
        normalizedSamplingSize.width, normalizedSamplingSize.height,
    };
    
    // Update attribute values
    glVertexAttribPointer(ATTRIB_VERTEX, 2, GL_FLOAT, 0, 0, quadVertexData);
    glEnableVertexAttribArray(ATTRIB_VERTEX);
    
    /*
     The texture vertices are set up such that we flip the texture vertically. This is so that out top left origin buffer match OpenGL's bottom left texture coordinate system.
     */
    CGRect textureSamplingRect = CGRectMake(0, 0, 1, 1);
    GLfloat quadTextureData [] = {
        CGRectGetMinX(textureSamplingRect), CGRectGetMaxY(textureSamplingRect),
        CGRectGetMaxX(textureSamplingRect), CGRectGetMaxY(textureSamplingRect),
        CGRectGetMinX(textureSamplingRect), CGRectGetMinY(textureSamplingRect),
        CGRectGetMaxX(textureSamplingRect), CGRectGetMinY(textureSamplingRect)
    };
    
    glVertexAttribPointer(ATTRIB_TEXCOORD, 2, GL_FLOAT, 0, 0, quadTextureData);
    glEnableVertexAttribArray(ATTRIB_TEXCOORD);
    
    glDrawArrays(GL_TRIANGLE_STRIP, 0, 4);
    
    glBindRenderbuffer(GL_RENDERBUFFER, _colorBufferHandle);
    [_context presentRenderbuffer:GL_RENDERBUFFER];
    
    [self cleanUpTextures];
    
    // Periodic texture cache flush every frame
    CVOpenGLESTextureCacheFlush(_videoTextureCache, 0);
    
    if (_videoTextureCache) {
        CFRelease(_videoTextureCache);
    }
}

// MARK: OpenGL setup
- (void)setupGL {
    [EAGLContext setCurrentContext: _context];
    [self setupBuffers];
    [self loadShaders];
    
    glUseProgram(self.program);
    
    // 0 and 1 are the texture IDs of _lumaTexture and _chromaTexture respectively
    glUniform1i(uniforms[UNIFORM_Y], 0);
    glUniform1i(uniforms[UNIFORM_UV], 1);
    glUniform1f(uniforms[UNIFORM_ROTATION_ANGLE], 0);
    glUniformMatrix3fv(uniforms[UNIFORM_COLOR_CONVERSION_MATRIX], 1, GL_FALSE, _preferredConversion);
    
//    // Create CVOpenGLESTextureCacheRef for optimal CVPixelBufferRef to GLES texture converison.
//    if (_videoTextureCache) {
//        CVReturn err = CVOpenGLESTextureCacheCreate(kCFAllocatorDefault, NULL, _context, NULL, &_videoTextureCache);
//        if (err != noErr) {
//            NSLog(@"Error at CVOpenGLESTextureCacheCreate %d", err);
//            return;
//        }
//    }
}

// MARK: Utilities
- (void)setupBuffers {
    glDisable(GL_DEPTH_TEST);
    
    glEnableVertexAttribArray(ATTRIB_VERTEX);
    glVertexAttribPointer(ATTRIB_VERTEX, 2, GL_FLOAT, GL_FALSE, 2 * sizeof(GLfloat), 0);
    
    glEnableVertexAttribArray(ATTRIB_TEXCOORD);
    glVertexAttribPointer(ATTRIB_TEXCOORD, 2, GL_FLOAT, GL_FALSE, 2 * sizeof(GLfloat), 0);
    
    glGenFramebuffers(1, &_frameBufferHandle);
    glBindFramebuffer(GL_FRAMEBUFFER, _frameBufferHandle);
    
    glGenRenderbuffers(1, &_colorBufferHandle);
    glBindRenderbuffer(GL_RENDERBUFFER, _colorBufferHandle);
    
    [_context renderbufferStorage:GL_RENDERBUFFER fromDrawable:self];
    glGetRenderbufferParameteriv(GL_RENDERBUFFER, GL_RENDERBUFFER_WIDTH, &_backingWidth);
    glGetRenderbufferParameteriv(GL_RENDERBUFFER, GL_RENDERBUFFER_HEIGHT, &_backingHeight);
    
    glFramebufferRenderbuffer(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_RENDERBUFFER, _colorBufferHandle);
    if (glCheckFramebufferStatus(GL_FRAMEBUFFER) != GL_FRAMEBUFFER_COMPLETE) {
        NSLog(@"Failed to make complete framebuffer object %x", glCheckFramebufferStatus(GL_FRAMEBUFFER));
    }
}

- (void)cleanUpTextures {
    if (_lumaTexture) {
        CFRelease(_lumaTexture);
        _lumaTexture = NULL;
    }
    
    if (_chromaTexture) {
        CFRelease(_chromaTexture);
        _chromaTexture = NULL;
    }
}

// MARK: OpenGL ES 2 shader compilation
const GLchar *shader_fsh = (const GLchar*)"varying highp vec2 texCoordVarying;"
"precision mediump float;"
"uniform sampler2D SamplerY;"
"uniform sampler2D SamplerUV;"
"uniform mat3 colorConversionMatrix;"
"void main()"
"{"
"    mediump vec3 yuv;"
"    lowp vec3 rgb;"
//   Subtract constants to map the video range start at 0
"    yuv.x = (texture2D(SamplerY, texCoordVarying).r - (16.0/255.0));"
"    yuv.yz = (texture2D(SamplerUV, texCoordVarying).rg - vec2(0.5, 0.5));"
"    rgb = colorConversionMatrix * yuv;"
"    gl_FragColor = vec4(rgb, 1);"
"}";

const GLchar *shader_vsh = (const GLchar*)"attribute vec4 position;"
"attribute vec2 texCoord;"
"uniform float preferredRotation;"
"varying vec2 texCoordVarying;"
"void main()"
"{"
"    mat4 rotationMatrix = mat4(cos(preferredRotation), -sin(preferredRotation), 0.0, 0.0,"
"                               sin(preferredRotation),  cos(preferredRotation), 0.0, 0.0,"
"                               0.0,					    0.0, 1.0, 0.0,"
"                               0.0,					    0.0, 0.0, 1.0);"
"    gl_Position = position * rotationMatrix;"
"    texCoordVarying = texCoord;"
"}";

- (BOOL)loadShaders {
    GLuint vertShader, fragShader;
    
    // Create the shader program.
    
    // Create and compile the vertex shader.
    if (![self compileShader:&vertShader type:GL_VERTEX_SHADER string:shader_vsh]) {
        NSLog(@"Failed to compile vertex shader");
        return NO;
    }
    
    if (![self compileShader:&fragShader type:GL_FRAGMENT_SHADER string:shader_fsh]) {
        NSLog(@"Failed to compile fragment shader");
        return NO;
    }
    
    // Attach vertex shader to program
    glAttachShader(self.program, vertShader);
    
    // Attach fragment shader to program
    glAttachShader(self.program, fragShader);
    
    // Bind attribute locations. This needs to be done prior to linking
    glBindAttribLocation(self.program, ATTRIB_VERTEX, "position");
    glBindAttribLocation(self.program, ATTRIB_TEXCOORD, "texCoord");
    
    // Link the program
    if (![self linkProgram:self.program]) {
        NSLog(@"Failed to link program: %d", self.program);
        
        if (vertShader) {
            glDeleteShader(vertShader);
            vertShader = 0;
        }
        
        if (fragShader) {
            glDeleteShader(fragShader);
            fragShader = 0;
        }
        
        if (self.program) {
            glDeleteProgram(self.program);
            self.program = 0;
        }
        
        return NO;
    }
    
    // Get uniform locations.
    uniforms[UNIFORM_Y] = glGetUniformLocation(self.program, "SamplerY");
    uniforms[UNIFORM_UV] = glGetUniformLocation(self.program, "SamplerUV");
    uniforms[UNIFORM_ROTATION_ANGLE] = glGetUniformLocation(self.program, "preferredRotation");
    uniforms[UNIFORM_COLOR_CONVERSION_MATRIX] = glGetUniformLocation(self.program, "colorConversionMatrix");
    
    // Release vertex and fragment shaders.
    if (vertShader) {
        glDetachShader(self.program, vertShader);
        glDeleteShader(vertShader);
    }
    if (fragShader) {
        glDetachShader(self.program, fragShader);
        glDeleteShader(fragShader);
    }
    
    return YES;
}


- (BOOL)compileShader:(GLuint *)shader type:(GLenum)type string:(const GLchar *)string {
    *shader = glCreateShader(type);
    glShaderSource(*shader, 1, &string, NULL);
    glCompileShader(*shader);
    
#if defined(DEBUG)
    GLint logLength;
    glGetShaderiv(*shader, GL_INFO_LOG_LENGTH, &logLength);
    if (logLength > 0) {
        GLchar *log = (GLchar *)malloc(logLength);
        glGetShaderInfoLog(*shader, logLength, &logLength, log);
        NSLog(@"Shader compile log:\n%s", log);
        free(log);
    }
#endif
    
    GLint status;
    glGetShaderiv(*shader, GL_COMPILE_STATUS, &status);
    if (status == 0) {
        glDeleteShader(*shader);
        return NO;
    }
    
    return YES;
}

- (BOOL)linkProgram:(GLuint)prog {
    GLint status;
    glLinkProgram(prog);
    
#if defined(DEBUG)
    GLint logLength;
    glGetProgramiv(prog, GL_INFO_LOG_LENGTH, &logLength);
    if (logLength) {
        GLchar *log = (GLchar *)malloc(logLength);
        glGetProgramInfoLog(prog, logLength, &logLength, log);
        NSLog(@"Program link log:\n%s", log);
        free(log);
    }
#endif
    
    glGetProgramiv(prog, GL_LINK_STATUS, &status);
    if (status == 0) {
        return NO;
    }
    
    return YES;
}

- (void)dealloc {
    [self cleanUpTextures];
    
    if (_pixelBuffer) {
        CVPixelBufferRelease(_pixelBuffer);
    }
    
    if (self.program) {
        glDeleteProgram(self.program);
        self.program = 0;
    }
    
    if (_context) {
        _context = nil;
    }
}


@end
