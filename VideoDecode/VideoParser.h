//
//  VideoParser.h
//  VideoDecode
//
//  Created by kenny on 07/03/2017.
//  Copyright © 2017 yuneec. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface VideoPacket : NSObject

@property uint8_t *buffer;
@property NSInteger size;

@end

@interface VideoParser : NSObject

- (BOOL)open:(NSString *)fileName;
- (VideoPacket *)nextPacket;
- (void)close;
@end
