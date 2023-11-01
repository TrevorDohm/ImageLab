import UIKit
import MetalKit

extension CIFaceFeature{
    var isBlinking: Bool{
        return self.leftEyeClosed && self.rightEyeClosed
    }
}

protocol VideoModelDelegate: AnyObject{
    func didDetectBlink(blinkCount: Int)
    func didProcessImage(_ processedImage: CIImage)
}

class VideoModel: NSObject {
    weak var delegate: VideoModelDelegate?
    weak var cameraView:MTKView?
    
    //MARK: Class Properties
    private var filters : [CIFilter]! = nil
    private lazy var videoManager:VisionAnalgesic! = {
        let tmpManager = VisionAnalgesic(view: cameraView!)
        tmpManager.setCameraPosition(position: .front)
        return tmpManager
    }()
    
    private lazy var detector:CIDetector! = {
        // create dictionary for face detection
        // HINT: you need to manipulate these properties for better face detection efficiency
        let optsDetector = [CIDetectorAccuracy:CIDetectorAccuracyHigh,
                               CIDetectorSmile:true,
                            CIDetectorEyeBlink:true,
                            CIDetectorTracking:false,
                      CIDetectorMinFeatureSize:0.1,
                     CIDetectorMaxFeatureCount:10,
                      CIDetectorNumberOfAngles:11] as [String : Any]
        
        // setup a face detector in swift
        let detector = CIDetector(ofType: CIDetectorTypeFace,
                                  context: self.videoManager.getCIContext(), // perform on the GPU is possible
            options: (optsDetector as [String : AnyObject]))
        return detector
        
    }()
    
    private var eyeStateHistory = [Bool]()
    
    var blinkCount = 0
    
    init(view:MTKView){
        super.init()
        
        cameraView = view
        
        self.videoManager.setCameraPosition(position: .front)
        self.videoManager.setProcessingBlock(newProcessBlock: self.processImage)
        
        if !videoManager.isRunning{
            videoManager.start()
        }
        
    }
    
    private var blinkCooldownFrames = 0
    
    // MARK: Apply Filters, Feature Detectors
    private func applyFiltersToFaces(inputImage:CIImage, features:[CIFaceFeature]) -> CIImage{
        
        // Initialize Image, Face Center, Radius
        var retImage = inputImage
        var filterCenter = CGPoint()
        var radius = 100
        
        // For Each Face ( < CIDetectorMaxFeatureCount:10 )
        for face in features {
            
            // Set Where To Apply Filters, Radius Fix
            filterCenter.x = face.bounds.midX
            filterCenter.y = face.bounds.midY
            radius = Int(face.bounds.width / 2)
            
            // Calculate adjusted face bounds with increased height
            let heightIncrease: CGFloat = 300.0
            let adjustedFaceBounds = CGRect(x: face.bounds.origin.x,
                                            y: face.bounds.origin.y - heightIncrease / 10,
                                            width: face.bounds.width,
                                            height: face.bounds.height + heightIncrease)

            // Highlight Entire Face With Adjusted Bounds
            let faceHighlight = CIFilter(name: "CIHueAdjust")!
            faceHighlight.setValue(retImage.cropped(to: adjustedFaceBounds), forKey: kCIInputImageKey)
            faceHighlight.setValue(2.1, forKey: "inputAngle")
            let faceImage = faceHighlight.outputImage!
            
            // Highlight Left Eye
            let leftEyeHighlight = CIFilter(name: "CIRadialGradient")!
            let leftEyeCenter = CIVector(x: face.leftEyePosition.x, y: face.leftEyePosition.y)
            leftEyeHighlight.setValue(leftEyeCenter, forKey: "inputCenter")
            leftEyeHighlight.setValue(10, forKey: "inputRadius0") // Inner Circle Radius
            leftEyeHighlight.setValue(20, forKey: "inputRadius1") // Outer Circle Radius
            leftEyeHighlight.setValue(CIColor(red: 1.0, green: 0.0, blue: 0.0, alpha: 1.0), forKey: "inputColor0") // Solid Red Color For Inner Circle
            leftEyeHighlight.setValue(CIColor(red: 1.0, green: 0.0, blue: 0.0, alpha: 0.0), forKey: "inputColor1") // Transparent Red Color For Outer Circle
            let leftEyeImage = leftEyeHighlight.outputImage!

            // Highlight Right Eye
            let rightEyeHighlight = CIFilter(name: "CIRadialGradient")!
            let rightEyeCenter = CIVector(x: face.rightEyePosition.x, y: face.rightEyePosition.y)
            rightEyeHighlight.setValue(rightEyeCenter, forKey: "inputCenter")
            rightEyeHighlight.setValue(10, forKey: "inputRadius0") // Inner Circle Radius
            rightEyeHighlight.setValue(20, forKey: "inputRadius1") // Outer Circle Radius
            rightEyeHighlight.setValue(CIColor(red: 1.0, green: 0.0, blue: 0.0, alpha: 1.0), forKey: "inputColor0") // Solid Red Color for Inner Circle
            rightEyeHighlight.setValue(CIColor(red: 1.0, green: 0.0, blue: 0.0, alpha: 0.0), forKey: "inputColor1") // Transparent Red Color For Outer Circle
            let rightEyeImage = rightEyeHighlight.outputImage!

            // Highlight Mouth
            // Define a mouth rect (you may need to adjust the width and height values to best fit the mouth area)
            
            let mouthWidth: CGFloat = 100.0
            let mouthHeight: CGFloat = 100.0
            let mouthRect = CGRect(x: face.mouthPosition.x - mouthWidth / 2,
                                   y: face.mouthPosition.y - mouthHeight / 2,
                                   width: mouthWidth,
                                   height: mouthHeight)

            // Apply a color adjustment to the mouth area
            let mouthColorFilter = CIFilter(name: "CIColorControls")!
            mouthColorFilter.setValue(retImage.cropped(to: mouthRect), forKey: kCIInputImageKey)
            mouthColorFilter.setValue(1.2, forKey: "inputSaturation") // Increase Saturation
            mouthColorFilter.setValue(0.2, forKey: "inputBrightness") // Boost Brightness
            let mouthImage = mouthColorFilter.outputImage!
            
            // Composite the highlights over the original image
            let featuresImages = [faceImage, leftEyeImage, rightEyeImage, mouthImage]
            for featureImage in featuresImages {
                let compositeFilter = CIFilter(name: "CISourceOverCompositing")!
                compositeFilter.setValue(featureImage, forKey: kCIInputImageKey) // Top Image
                compositeFilter.setValue(retImage, forKey: kCIInputBackgroundImageKey) // Background
                retImage = compositeFilter.outputImage!
            }
            
//            if let face = features.first {
//                let faceAngle = face.faceAngle
//                if abs(faceAngle) < Float(Double.pi) / 4 {
//                            // Face is approximately straight (not rotated much)
//                            if faceAngle > 0 {
//                                // Face is looking to the right
//                                print("looking Right")
//                            } else {
//                                // Face is looking to the left
//                                print("looking left")
//                            }
//                        } else {
//                            // Face is rotated significantly
//                            if faceAngle > 0 {
//                                print("looking up")
//                                // Face is looking up
//                            } else {
//                                print("looking down")
//                                // Face is looking down
//                            }
//                        }
//                print(faceAngle)
                //                    let rollAngle = face.rollAngle
                //                    let pitchAngle = face.pitchAngle
                //                    let yawAngle = face.yawAngle
                //print(faceAngle)
                //print("Roll:\(rollAngle) , Pitch:\(pitchAngle), Yaw:\(yawAngle) ")
//            }

            // Apply Pinch Filter Only When Smiling
            if face.hasSmile {
                
                // Pinch Filter Image
                let pinchFilter = CIFilter(name:"CIBumpDistortion")!
                pinchFilter.setValue(-1.0, forKey: "inputScale")
                pinchFilter.setValue(radius, forKey: "inputRadius")
                pinchFilter.setValue(CIVector(cgPoint: filterCenter), forKey: "inputCenter")
                pinchFilter.setValue(retImage.cropped(to: adjustedFaceBounds), forKey: kCIInputImageKey)
                let pinchImage = pinchFilter.outputImage!
                
                // Compositing
                let compositeFilter = CIFilter(name: "CISourceOverCompositing")!
                compositeFilter.setValue(pinchImage, forKey: kCIInputImageKey) // Top Image
                compositeFilter.setValue(retImage, forKey: kCIInputBackgroundImageKey) // Background
                retImage = compositeFilter.outputImage!
                
            }
            
            // If Cooldown, Decrement Cooldown, Skip Blink Detection
            if blinkCooldownFrames > 0 {
                blinkCooldownFrames -= 1
                return retImage
            }
            
            // Add Latest Eye State To History
            eyeStateHistory.append(face.isBlinking)
            
            // Limit History To Last 20 Frames
            if eyeStateHistory.count > 10 {
                eyeStateHistory.removeFirst()
            }

            // Check For Blink Pattern
            if eyeStateHistory.count == 10 {

                // Count the number of frames where the eyes were closed
                let closedEyesCount = eyeStateHistory.filter { $0 == true }.count
                
                // If eyes were closed for 3 to 5 frames (which is a typical blink duration) amidst a 20-frame sequence,
                // we consider it a blink. These numbers can be tweaked.
                if closedEyesCount >= 3 && closedEyesCount <= 7 {
                    
                    // Blink Detected
                    blinkCount += 1
                    delegate?.didDetectBlink(blinkCount: blinkCount)
                    
                    // Set the cooldown frames to prevent another blink from being detected immediately
                    blinkCooldownFrames = 10
                    
                    // Clear the history to prevent multiple detections for the same blink
                    eyeStateHistory.removeAll()
                    
                }
            }
        }
        
        return retImage
        
    }
    
    private func getFaces(img:CIImage) -> [CIFaceFeature]{
        // makes sure the image is the correct orientation
        let optsFace = [CIDetectorImageOrientation:self.videoManager.ciOrientation,
                                   CIDetectorSmile: true,
                                CIDetectorEyeBlink: true] as [String : Any] as [String : Any]
        // get Face Features
        return self.detector.features(in: img, options: optsFace) as! [CIFaceFeature]
    }
    
//    //MARK: Process image output
    private func processImage(inputImage:CIImage) -> CIImage{

        // detect faces
        let faces = getFaces(img: inputImage)

        // if no faces, just return original image
        if faces.count == 0 { return inputImage }

        //otherwise apply the filters to the faces
        return applyFiltersToFaces(inputImage: inputImage, features: faces)

    }
//    
//    private func processImage(inputImage: CIImage) -> CIImage {
//        // Perform the face detection and image processing in the background
//        DispatchQueue.global(qos: .userInitiated).async {
//            // Detect faces
//            let faces = self.getFaces(img: inputImage)
//
//            // If no faces, just return the original image
//            if faces.count == 0 {
//                // Notify the delegate that the image processing is complete (no changes)
//                self.delegate?.didProcessImage(inputImage)
//                return
//            }
//
//            // Apply the filters to the faces
//            let filteredImage = self.applyFiltersToFaces(inputImage: inputImage, features: faces)
//
//            // Notify the delegate with the processed image
//            //self.delegate?.didProcessImage(filteredImage)
//        }
//
//        // Return the original image immediately
//        return inputImage
//    }

    
    func cleanup() {
        // Clean up any camera or Metal resources here
        // For example, stop videoManager if it's running:
        if videoManager.isRunning {
            videoManager.stop()
        }
    }
}
