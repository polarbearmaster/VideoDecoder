//
//  AAPLEAGLLayer.h
//  VideoDecode
//
//  Created by kenny on 07/03/2017.
//  Copyright © 2017 yuneec. All rights reserved.
//

/*
 This file is based on the original Apple CAEAGLLayer subclass which is to demonstrates how to draw a CVPixelBufferRef using OpenGLES and display the timecode assciated with that pixel buffer in the top right corner
 See https://developer.apple.com/library/prerelease/ios/samplecode/VideoTimeline/Introduction/Intro.html
 */

@import QuartzCore;
@import CoreVideo;

@interface AAPLEAGLLayer : CAEAGLLayer
@property CVPixelBufferRef pixelBuffer;

- (instancetype)initWithFrame:(CGRect)frame;
@end
