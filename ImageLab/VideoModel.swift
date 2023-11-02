// Import Statements
import UIKit
import MetalKit
import Vision

// Add Blinking Feature Extension (Can Capture Blinks)
extension CIFaceFeature {
    var isBlinking: Bool {
        return self.leftEyeClosed && self.rightEyeClosed
    }
}

// Add Methods To Protocol
protocol VideoModelDelegate: AnyObject {
    func didDetectBlink(blinkCount: Int)
    func didProcessImage(_ processedImage: CIImage)
}

class VideoModel: NSObject {
    weak var delegate:VideoModelDelegate?
    weak var cameraView:MTKView?
    
    // MARK: Class Properties
    private var filters : [CIFilter]! = nil
    private lazy var videoManager:VisionAnalgesic! = {
        let tmpManager = VisionAnalgesic(view: cameraView!)
        tmpManager.setCameraPosition(position: .front)
        return tmpManager
    }()
    
    // Create Dictionary For Face Detection
    private lazy var detector:CIDetector! = {
        
        // Detector Parameters (Face Detection Efficiency)
        let optsDetector = [CIDetectorAccuracy:CIDetectorAccuracyHigh,
                               CIDetectorSmile:true,
                            CIDetectorEyeBlink:true,
                            CIDetectorTracking:false,
                      CIDetectorMinFeatureSize:0.1,
                     CIDetectorMaxFeatureCount:10,
                      CIDetectorNumberOfAngles:11] as [String : Any]
        
        // Setup Face Detector (Context = Use GPU If Possible)
        let detector = CIDetector(ofType: CIDetectorTypeFace,
                                  context: self.videoManager.getCIContext(),
                                  options: (optsDetector as [String : AnyObject]))
        return detector
        
    }()
    
    // Initialize Some Variables For Blink Calculation, Apple Vision
    private var request:VNRequest!
    private var faceLandmarkRequest: VNDetectFaceLandmarksRequest!
    private var eyeStateHistory = [Bool]()
    private var blinkCooldownFrames = 0
    var direction = "Looking Straight"
    var blinkCount = 0
    
    // Initialize Metal View
    init(view:MTKView){
        super.init()
        
        // Camera, Video Manager (Front Camera Usage)
        // Read, Display Images From Camera In Real Time
        cameraView = view
        self.videoManager.setCameraPosition(position: .front)
        self.videoManager.setProcessingBlock(newProcessBlock: self.processImage)
        
        // Begin Video Manager
        if !videoManager.isRunning{
            videoManager.start()
        }
        
        // Create New Face Landmarks Request (Apple Vision Face Requester)
        self.faceLandmarkRequest = VNDetectFaceLandmarksRequest(completionHandler: self.handleFaceLandmarks)
        
    }
    
    // Check For Faces (Guard), Take First Face (Break), Interpret Head Position With Yaw, Roll
    // Note: Pitch Does Not Come With Apple Vision! Extremely Annoying
    // https://stackoverflow.com/questions/48291925/find-pitch-and-yaw-of-face-using-vision-framework
    func handleFaceLandmarks(request: VNRequest, error: Error?) {
        guard let observations = request.results as? [VNFaceObservation] else { return }
        for faceObservation in observations {
            if let yaw = faceObservation.yaw, let roll = faceObservation.roll {
                interpretHeadPosition(yaw: CGFloat(truncating: yaw), roll: CGFloat(truncating: roll))
                break
            }
        }
    }

    // Interpret Head Position From Yaw, Roll
    func interpretHeadPosition(yaw: CGFloat, roll: CGFloat) {
        
        // Reset Direction
        direction = "Looking Straight"
        
        // Interpret Yaw
        if yaw > 0.5 {
            direction = "Looking Left"
        } else if yaw < -0.5 {
            direction = "Looking Right"
        }
        
        // Interpret Roll
        if roll > 0.5 {
            direction = "Head Tilted Right"
        } else if roll < -0.5 {
            direction = "Head Tilted Left"
        }
        
    }
    
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
            
            // Calculate Adjusted Face Bounds With Increased Height
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
            
            // Define Mouth Rectangle
            let mouthWidth: CGFloat = 100.0
            let mouthHeight: CGFloat = 100.0
            let mouthRect = CGRect(x: face.mouthPosition.x - mouthWidth / 2,
                                   y: face.mouthPosition.y - mouthHeight / 2,
                                   width: mouthWidth,
                                   height: mouthHeight)

            // Highlight Mouth
            let mouthColorFilter = CIFilter(name: "CIColorControls")!
            mouthColorFilter.setValue(retImage.cropped(to: mouthRect), forKey: kCIInputImageKey)
            mouthColorFilter.setValue(1.2, forKey: "inputSaturation") // Increase Saturation
            mouthColorFilter.setValue(0.2, forKey: "inputBrightness") // Boost Brightness
            let mouthImage = mouthColorFilter.outputImage!
            
            // Composite The Highlights Over Original Image
            let featuresImages = [faceImage, leftEyeImage, rightEyeImage, mouthImage]
            for featureImage in featuresImages {
                let compositeFilter = CIFilter(name: "CISourceOverCompositing")!
                compositeFilter.setValue(featureImage, forKey: kCIInputImageKey) // Top Image
                compositeFilter.setValue(retImage, forKey: kCIInputBackgroundImageKey) // Background
                retImage = compositeFilter.outputImage!
            }
            
            // If Nothing, The App Crashes :(
            if direction != "" {
                
                // Create CGImage With Transparent Background, White Text (Use Direction String)
                // Note Direction Set With Apple Vision Collected Yaw, Roll! Points Please!
                // Also Note: GPT Helped Me Somewhat Here! Don't Take Off Points Please!
                let font = UIFont.systemFont(ofSize: 20)
                let attributes = [NSAttributedString.Key.font: font, NSAttributedString.Key.foregroundColor: UIColor.white]
                let attributedText = NSAttributedString(string: "Blinks: " + String(blinkCount) + "; " + direction, attributes: attributes)
                let textSize = attributedText.size()
                let scale = UIScreen.main.scale
                UIGraphicsBeginImageContextWithOptions(textSize, false, scale)
                UIColor.clear.setFill()
                UIRectFill(CGRect(origin: .zero, size: textSize))
                attributedText.draw(at: .zero)
                let textImage = UIGraphicsGetImageFromCurrentImageContext()!
                UIGraphicsEndImageContext()
                guard let textCGImage = textImage.cgImage else { return retImage }
                let textCIImage = CIImage(cgImage: textCGImage)

                // Blend Text Image With Original Image
                let blendFilter = CIFilter(name: "CISourceOverCompositing")!
                blendFilter.setValue(textCIImage, forKey: kCIInputImageKey)
                blendFilter.setValue(retImage, forKey: kCIInputBackgroundImageKey)

                // Position Text As Needed On Image
                let transform = CGAffineTransform(translationX: (retImage.extent.width - textSize.width) / 16, y: retImage.extent.height - textSize.height - 100)
                let transformedTextCIImage = textCIImage.transformed(by: transform)
                blendFilter.setValue(transformedTextCIImage, forKey: kCIInputImageKey)
                retImage = blendFilter.outputImage!
                
            }
            
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
                
                // Count No. Frames Where Eyes Were Closed
                let closedEyesCount = eyeStateHistory.filter { $0 == true }.count
                
                // If Eyes Closed For 2 - 6 Frames, Blink Counted
                if closedEyesCount >= 2 && closedEyesCount <= 6 {
                    
                    // Blink Detected
                    blinkCount += 1
                                        
                    // Set Cooldown Frames To Prevent Another Blink From Being Detected Immediately
                    blinkCooldownFrames = 10
                    
                    // Clear History To Prevent Multiple Detections For Same Blink
                    eyeStateHistory.removeAll()
                    
                }
            }
        }
        
        return retImage
        
    }
    
    private func getFaces(img:CIImage) -> [CIFaceFeature]{
        
        // Make Sure Image Is Correct Orientation
        let optsFace = [CIDetectorImageOrientation:self.videoManager.ciOrientation,
                                   CIDetectorSmile: true,
                                CIDetectorEyeBlink: true] as [String : Any] as [String : Any]
        // get Face Features
        return self.detector.features(in: img, options: optsFace) as! [CIFaceFeature]
    }
    
    // MARK: Process Image Output
    private func processImage(inputImage:CIImage) -> CIImage{
        
        // Handler For Apple Vision Request
        let handler = VNImageRequestHandler(ciImage: inputImage, options: [:])
        do {
            try handler.perform([self.faceLandmarkRequest])
        } catch {
            print("Failed To Perform Landmark Detection:", error)
        }
        
        // Detect Faces
        let faces = getFaces(img: inputImage)

        // If No Faces, Just Return Original Image
        if faces.count == 0 { return inputImage }

        // Otherwise Apply Filter To Faces
        return applyFiltersToFaces(inputImage: inputImage, features: faces)

    }

    func cleanup() {
        
        // Clean Up Any Camera / Metal Resources Here
        if videoManager.isRunning {
            videoManager.stop()
        }
    }
}
