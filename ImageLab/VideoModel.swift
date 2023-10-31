import UIKit
import MetalKit

extension CIFaceFeature{
    var isBlinking: Bool{
        return self.leftEyeClosed && self.rightEyeClosed
    }
}

protocol VideoModelDelegate: AnyObject{
    func didDetectBlink(blinkCount: Int)
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
                     CIDetectorMaxFeatureCount:5,
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
        
        self.setupFilters()
        
        self.videoManager.setCameraPosition(position: .front)
        self.videoManager.setProcessingBlock(newProcessBlock: self.processImage)
        
        if !videoManager.isRunning{
            videoManager.start()
        }
        
    }
    
    //MARK: Setup filtering
    private func setupFilters(){
        filters = []
    }
    
    //MARK: Apply filters and apply feature detectors
    private func applyFiltersToFaces(inputImage:CIImage,features:[CIFaceFeature])->CIImage{
        var retImage = inputImage
        var filterCenter = CGPoint() // for saving the center of face
        var radius = 75
        
        for face in features { // for each face
            //set where to apply filter
            filterCenter.x = face.bounds.midX
            filterCenter.y = face.bounds.midY
            radius = Int(face.bounds.width/2) // for setting the radius of the bump
            
            if face.hasSmile {
                print("Smiling detected!")
                // Apply the CICircularWrap filter only when smiling
                let circularWrapFilter = CIFilter(name: "CICircularWrap")!
                circularWrapFilter.setValue(retImage, forKey: kCIInputImageKey)
                circularWrapFilter.setValue(CIVector(cgPoint: filterCenter), forKey: "inputCenter")
                circularWrapFilter.setValue(radius, forKey: "inputRadius")
                retImage = circularWrapFilter.outputImage!
            }
            
            eyeStateHistory.append(face.isBlinking)
            if eyeStateHistory.count > 3 && eyeStateHistory[eyeStateHistory.count-2] == true && eyeStateHistory.last == false{
                print("You just blinked")
                blinkCount += 1
                // Notify the ModAViewController about the blink
                delegate?.didDetectBlink(blinkCount: blinkCount)

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
    
    //MARK: Process image output
    private func processImage(inputImage:CIImage) -> CIImage{
        
        // detect faces
        let faces = getFaces(img: inputImage)
        
        // if no faces, just return original image
        if faces.count == 0 { return inputImage }
        
        //otherwise apply the filters to the faces
        return applyFiltersToFaces(inputImage: inputImage, features: faces)
        
    }

}
