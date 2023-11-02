///
//  OpenCVBridge.m
//  LookinLive
//
//  Created by Eric Larson.
//  Copyright (c) Eric Larson. All rights reserved.
//

#import "OpenCVBridge.hh"


using namespace cv;

@interface OpenCVBridge()
@property (nonatomic) cv::Mat image;
@property (strong,nonatomic) CIImage* frameInput;
@property (nonatomic) CGRect bounds;
@property (nonatomic) CGAffineTransform transform;
@property (nonatomic) CGAffineTransform inverseTransform;
@property (atomic) cv::CascadeClassifier classifier;
@property (atomic) int frameDelay;
@end

@implementation OpenCVBridge

// Global Variables (For Processing Finger Circularly)

const uint fps = 30;
const uint secondsToFillBuffer = 30;
const uint bufferSize = fps * secondsToFillBuffer;
bool bufferIsFull = false;

//double avgPixelIntensityRed[bufferSize];
float avgPixelIntensityGreen[bufferSize];
float avgPixelIntensityBlue[bufferSize];

size_t currentIndex = 0;
bool flash = false;
int flashCooldownCounter = 60; // 2 Seconds (30 FPS Default)

// Text Information
char text[100];
double fontScale = 3.5;
int thickness = 2;
int baseline = 0;
cv::Size textSize = cv::getTextSize(text, FONT_HERSHEY_PLAIN, fontScale, thickness, &baseline);
//double redAvgs[60 * 30];
#pragma mark === Write Your Code Here ===
-(bool)processFinger{
    std::cout << "CurrIndex: " <<currentIndex <<std::endl;
    // Corrected Color Conversion
    cv::Mat image_copy;
    Scalar avgPixelIntensity;
    cvtColor(_image, image_copy, CV_RGBA2BGR);
    avgPixelIntensity = cv::mean( image_copy );
    
    
    // Calculate Starting Position (BL Corner) For Centering
    cv::Point textOrg((image_copy.cols - textSize.width) / 16, (image_copy.rows + textSize.height) / 16);
    
    // Overlay Text Onto Image
    cv::putText(_image, text, textOrg, FONT_HERSHEY_PLAIN, fontScale, Scalar::all(255), thickness, 2);
    
    // Cooldown Counter Check
    if (flashCooldownCounter == 0) {
        
        // Empirically Tested Finger Thresholds
        if (flash) {
            if (avgPixelIntensity.val[2] < 160) {
                flash = false;
            }
        }
        else {
            if (avgPixelIntensity.val[0] < 20 and
                avgPixelIntensity.val[1] < 20 and
                avgPixelIntensity.val[2] > 20) {
                flash = true;
            }
        }
        
        // Reset Cooldown
        flashCooldownCounter = 30;

    }
        
    // Cooldown Decrement
    if (flashCooldownCounter > 0) {
        flashCooldownCounter--;
    }
    if (self.frameDelay > 0) {
        self.frameDelay --;
    }
    // Execute Only When Finger Over Camera
    if (flash && self.frameDelay <= 0) {
        // Save Average Blue, Green, Red Values
        avgPixelIntensityBlue[currentIndex] = avgPixelIntensity.val[0];
        avgPixelIntensityGreen[currentIndex] = avgPixelIntensity.val[1];
        self.avgPixelIntensityRed[currentIndex] = avgPixelIntensity.val[2];
        //self.ppg[currentIndex] = (avgPixelIntensity.val[2] / 128) - 1;
        // Increment Index
        currentIndex++;
        if (currentIndex >= bufferSize) { //make sure we dont go out of bounds, will handle circular later
            currentIndex = 0;
            bufferIsFull = true;
            
        }
        
    }
    
    // Return Flash
    return flash;
    
}


-(bool) isBPMReady {
    return bufferIsFull;
}


-(int) getBufferSize {
    return bufferSize;
}


-(int) getBetsPerMinute {
    if(!bufferIsFull) {
        return -1;
    }
    const size_t WINDOW_LOOK_SIZE = 15; // NOTE THIS MEANS TO LOOK THAT MANY LEFT AND THAT MANY RIGHT
    //IE. 3 means total window size of 7, the value, 3 to the left, and 3 to the right
    
    vector<double> buf(bufferSize);
    for(int i=0; i < bufferSize; i ++) {
        size_t idx =(currentIndex + i + 1) % bufferSize;
        buf[i] = self.avgPixelIntensityRed[idx];
    }
    
    
    size_t prevPeak = 0, peakDistSum = 0,numPeaks = 0;
    for(size_t i = WINDOW_LOOK_SIZE; i < bufferSize - WINDOW_LOOK_SIZE; i ++) {
        double _max = buf[i];
        //Calculating max in window without vDSP because im too lazy to move accelerate in here
        for(size_t j = i - WINDOW_LOOK_SIZE; j < i +WINDOW_LOOK_SIZE; j++) {
            if(buf[j] > _max){
                _max = buf[j];
            }
        }
        if(_max == buf[i]) {// if the max is in the middle of window then we found a peak
            peakDistSum += i - prevPeak;
            prevPeak = i;
            numPeaks += 1;
            //TODO Maybe take the average peak dist and use that instead of num peaks
            self.ppg[i] = (buf[i]/128) - 0.5;
            
        } else {
            self.ppg[i] = (buf[i]/128) - 1;
        }
    }
    int bpm = int(numPeaks * 60 /secondsToFillBuffer);
    return bpm;
}

-(void)resetBuffer{
    for(int i = 0; i< bufferSize; i++){
        avgPixelIntensityBlue[i] = 0;
        self.avgPixelIntensityRed[i] = 0;
        avgPixelIntensityGreen[i] = 0;
    }
    currentIndex = 0;
}

#pragma mark ====Do Not Manipulate Code below this line!====
-(void)setTransforms:(CGAffineTransform)trans{
    self.inverseTransform = trans;
    self.transform = CGAffineTransformInvert(trans);
}

-(void)loadHaarCascadeWithFilename:(NSString*)filename{
    NSString *filePath = [[NSBundle mainBundle] pathForResource:filename ofType:@"xml"];
    self.classifier = cv::CascadeClassifier([filePath UTF8String]);
}

-(void)resetFrameDelay {
    self.frameDelay = fps * 10;
}

-(instancetype)init{
    self = [super init];
    
    if(self != nil){
        //self.transform = CGAffineTransformMakeRotation(M_PI_2);
        //self.transform = CGAffineTransformScale(self.transform, -1.0, 1.0);
        self.avgPixelIntensityRed = new double[bufferSize];
        //self.inverseTransform = CGAffineTransformMakeScale(-1.0,1.0);
        //self.inverseTransform = CGAffineTransformRotate(self.inverseTransform, -M_PI_2);
        self.transform = CGAffineTransformIdentity;
        self.inverseTransform = CGAffineTransformIdentity;
        self.ppg = new double[bufferSize];
        self.frameDelay = fps * 10;
    }
    return self;
}

-(void)dealloc{
    delete[] self.avgPixelIntensityRed; //No memory Leaks
    delete[] self.ppg;
}
#pragma mark Bridging OpenCV/CI Functions
// code manipulated from
// http://stackoverflow.com/questions/30867351/best-way-to-create-a-mat-from-a-ciimage
// http://stackoverflow.com/questions/10254141/how-to-convert-from-cvmat-to-uiimage-in-objective-c


-(void) setImage:(CIImage*)ciFrameImage
      withBounds:(CGRect)faceRectIn
      andContext:(CIContext*)context{
    
    CGRect faceRect = CGRect(faceRectIn);
    faceRect = CGRectApplyAffineTransform(faceRect, self.transform);
    ciFrameImage = [ciFrameImage imageByApplyingTransform:self.transform];
    
    
    
    //get face bounds and copy over smaller face image as CIImage
    //CGRect faceRect = faceFeature.bounds;
    _frameInput = ciFrameImage; // save this for later
    _bounds = faceRect;
    CIImage *faceImage = [ciFrameImage imageByCroppingToRect:faceRect];
    CGImageRef faceImageCG = [context createCGImage:faceImage fromRect:faceRect];
    
    // setup the OPenCV mat fro copying into
    CGColorSpaceRef colorSpace = CGImageGetColorSpace(faceImageCG);
    CGFloat cols = faceRect.size.width;
    CGFloat rows = faceRect.size.height;
    cv::Mat cvMat(rows, cols, CV_8UC4); // 8 bits per component, 4 channels
    _image = cvMat;
    
    // setup the copy buffer (to copy from the GPU)
    CGContextRef contextRef = CGBitmapContextCreate(cvMat.data,                // Pointer to backing data
                                                    cols,                      // Width of bitmap
                                                    rows,                      // Height of bitmap
                                                    8,                         // Bits per component
                                                    cvMat.step[0],             // Bytes per row
                                                    colorSpace,                // Colorspace
                                                    kCGImageAlphaNoneSkipLast |
                                                    //kCGImageAlphaLast |
                                                    kCGBitmapByteOrderDefault); // Bitmap info flags
    // do the copy
    CGContextDrawImage(contextRef, CGRectMake(0, 0, cols, rows), faceImageCG);
    
    // release intermediary buffer objects
    CGContextRelease(contextRef);
    CGImageRelease(faceImageCG);
    
    
}


-(CIImage*)getImage{
    
    // convert back
    // setup NS byte buffer using the data from the cvMat to show
    NSData *data = [NSData dataWithBytes:_image.data
                                  length:_image.elemSize() * _image.total()];
    
    CGColorSpaceRef colorSpace;
    if (_image.elemSize() == 1) {
        colorSpace = CGColorSpaceCreateDeviceGray();
    } else {
        colorSpace = CGColorSpaceCreateDeviceRGB();
    }
    
    // setup buffering object
    CGDataProviderRef provider = CGDataProviderCreateWithCFData((__bridge CFDataRef)data);
    
    // setup the copy to go from CPU to GPU
    CGImageRef imageRef = CGImageCreate(_image.cols,                                     // Width
                                        _image.rows,                                     // Height
                                        8,                                              // Bits per component
                                        8 * _image.elemSize(),                           // Bits per pixel
                                        _image.step[0],                                  // Bytes per row
                                        colorSpace,                                     // Colorspace
                                        //kCGImageAlphaLast |
                                        kCGBitmapByteOrderDefault,  // Bitmap info flags
                                        provider,                                       // CGDataProviderRef
                                        NULL,                                           // Decode
                                        false,                                          // Should interpolate
                                        kCGRenderingIntentDefault);                     // Intent
    
    // do the copy inside of the object instantiation for retImage
    CIImage* retImage = [[CIImage alloc]initWithCGImage:imageRef];
    CGAffineTransform transform = CGAffineTransformMakeTranslation(self.bounds.origin.x, self.bounds.origin.y);
    retImage = [retImage imageByApplyingTransform:transform];
    retImage = [retImage imageByApplyingTransform:self.inverseTransform];
    
    // clean up
    CGImageRelease(imageRef);
    CGDataProviderRelease(provider);
    CGColorSpaceRelease(colorSpace);
    
    return retImage;
}

-(CIImage*)getImageComposite{
    
    // convert back
    // setup NS byte buffer using the data from the cvMat to show
    NSData *data = [NSData dataWithBytes:_image.data
                                  length:_image.elemSize() * _image.total()];
    
    CGColorSpaceRef colorSpace;
    if (_image.elemSize() == 1) {
        colorSpace = CGColorSpaceCreateDeviceGray();
    } else {
        colorSpace = CGColorSpaceCreateDeviceRGB();
    }
    
    // setup buffering object
    CGDataProviderRef provider = CGDataProviderCreateWithCFData((__bridge CFDataRef)data);
    
    // setup the copy to go from CPU to GPU
    CGImageRef imageRef = CGImageCreate(_image.cols,                                     // Width
                                        _image.rows,                                     // Height
                                        8,                                              // Bits per component
                                        8 * _image.elemSize(),                           // Bits per pixel
                                        _image.step[0],                                  // Bytes per row
                                        colorSpace,                                     // Colorspace
                                        kCGImageAlphaNoneSkipLast,
                                        //kCGImageAlphaLast |
                                        //kCGBitmapByteOrderDefault,  // Bitmap info flags
                                        provider,                                       // CGDataProviderRef
                                        NULL,                                           // Decode
                                        false,                                          // Should interpolate
                                        kCGRenderingIntentDefault);                     // Intent
    
    // do the copy inside of the object instantiation for retImage
    CIImage* retImage = [[CIImage alloc]initWithCGImage:imageRef];
    // now apply transforms to get what the original image would be inside the Core Image frame
    CGAffineTransform transform = CGAffineTransformMakeTranslation(self.bounds.origin.x, self.bounds.origin.y);
    retImage = [retImage imageByApplyingTransform:transform];
    CIFilter* filt = [CIFilter filterWithName:@"CISourceAtopCompositing"
                          withInputParameters:@{@"inputImage":retImage,@"inputBackgroundImage":self.frameInput}];
    retImage = filt.outputImage;
    
    // clean up
    CGImageRelease(imageRef);
    CGDataProviderRelease(provider);
    CGColorSpaceRelease(colorSpace);
    
    retImage = [retImage imageByApplyingTransform:self.inverseTransform];
    
    return retImage;
}




@end
