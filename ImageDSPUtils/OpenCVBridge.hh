//
//  OpenCVBridge.h
//  LookinLive
//
//  Created by Eric Larson.
//  Copyright (c) Eric Larson. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <CoreImage/CoreImage.h>
#import "AVFoundation/AVFoundation.h"

#import "PrefixHeader.pch"
@interface OpenCVBridge : NSObject

@property (nonatomic) NSInteger processType;
@property (atomic) double *avgPixelIntensityRed;
@property (atomic) double *ppg;
// set the image for processing later
-(void) setImage:(CIImage*)ciFrameImage
      withBounds:(CGRect)rect
      andContext:(CIContext*)context;

-(int) getBufferSize;
//-(NSMutableArray) getColorBuffer;
//get the image raw opencv
-(CIImage*)getImage;

//get the image inside the original bounds
-(CIImage*)getImageComposite;

//Returns the value of the red color channel

-(bool) isBPMReady;

//Returns an estimate of your Heart Rate (+/- 2 BPM)
-(int) getBetsPerMinute;

// call this to perfrom processing (user controlled for better transparency)
-(void)processImage;

// for the video manager transformations
-(void)setTransforms:(CGAffineTransform)trans;

// sets buffer to 0 if you leave the view
-(void) resetBuffer;

-(void)loadHaarCascadeWithFilename:(NSString*)filename;

// Process Finger Header Declaration
-(bool)processFinger;


@end
