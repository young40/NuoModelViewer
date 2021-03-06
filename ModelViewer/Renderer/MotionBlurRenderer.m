//
//  MotionBlurRenderer.m
//  ModelViewer
//
//  Created by Dong on 11/11/17.
//  Copyright © 2017 middleware. All rights reserved.
//

#import "MotionBlurRenderer.h"
#import "NuoTextureAverageMesh.h"



@implementation MotionBlurRenderer
{
    id<MTLTexture> _latestSource;
    NuoTextureAverageMesh* _averageMesh;
}



- (instancetype)initWithDevice:(id<MTLDevice>)device
{
    if (self = [super initWithDevice:device
                     withPixelFormat:MTLPixelFormatBGRA8Unorm
                     withSampleCount:1])
    {
        [self resetResources];
    }
    
    return self;
}


- (void)resetResources
{
    _averageMesh = [[NuoTextureAverageMesh alloc] initWithDevice:self.device];
    [_averageMesh makePipelineAndSampler];
}



- (void)setSourceTexture:(id<MTLTexture>)sourceTexture
{
    if (_latestSource == sourceTexture)
        return;
    
    _latestSource = sourceTexture;
}


- (id<MTLTexture>)sourceTexture
{
    return _latestSource;
}


- (void)drawWithCommandBuffer:(id<MTLCommandBuffer>)commandBuffer
            withInFlightIndex:(unsigned int)inFlight
{
    self.renderTarget.clearColor = MTLClearColorMake(0.0, 0.0, 0.0, 0.0);
    [_averageMesh accumulateTexture:_latestSource onTarget:self.renderTarget
                       withInFlight:inFlight withCommandBuffer:commandBuffer];
}
    


@end
