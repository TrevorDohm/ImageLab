//
//  ViewController.swift
//  ImageLab
//
//  Created by Eric Larson
//  Copyright © Eric Larson. All rights reserved.
//

import UIKit
import AVFoundation
import MetalKit

class ViewController: UIViewController   {

    // MARK: Class Properties
    var filters : [CIFilter]! = nil
    var videoManager:VisionAnalgesic! = nil
    let pinchFilterIndex = 2
    var detector:CIDetector! = nil
    let bridge = OpenCVBridge()
    var isFlashManuallyControlled:Bool = false

    
    // MARK: View Outlets
    @IBOutlet weak var flashSlider: UISlider!
    @IBOutlet weak var stageLabel: UILabel!
    @IBOutlet weak var cameraView: MTKView!
    @IBOutlet weak var torchToggleButton: UIButton!
    @IBOutlet weak var cameraToggleButton: UIButton!
    @IBOutlet weak var bpmLabel: UILabel!
    
    var bpmTimer: Timer?
    var currBpm:Int32 = -1
    
    // MARK: ViewController Hierarchy
    override func viewDidLoad() {
        super.viewDidLoad()
        
        self.view.backgroundColor = nil
        
        // setup the OpenCV bridge nose detector, from file
        self.bridge.loadHaarCascade(withFilename: "nose")
        
        self.videoManager = VisionAnalgesic(view: self.cameraView)
        self.videoManager.setCameraPosition(position: AVCaptureDevice.Position.back)
        self.videoManager.setFPS(desiredFrameRate: 30)
        // create dictionary for face detection
        // HINT: you need to manipulate these properties for better face detection efficiency
        let optsDetector = [CIDetectorAccuracy:CIDetectorAccuracyHigh,
                      CIDetectorNumberOfAngles:11,
                      CIDetectorTracking:false] as [String : Any]
        
        // setup a face detector in swift
        self.detector = CIDetector(ofType: CIDetectorTypeFace,
                                  context: self.videoManager.getCIContext(), // perform on the GPU is possible
            options: (optsDetector as [String : AnyObject]))
        
        self.videoManager.setProcessingBlock(newProcessBlock: self.processImageSwift)
        
        bpmTimer = Timer.scheduledTimer(timeInterval: 1, target: self, selector: #selector(self.bpmUpdater), userInfo: nil, repeats: true)
        if !videoManager.isRunning{
            videoManager.start()
        }
        
//        startUpdatingBPM()
    
    }
    @objc func bpmUpdater() {
        self.currBpm = self.bridge.getBetsPerMinute()
    }
    // MARK: Process Image Output
//    func processFace(inputImage:CIImage) -> CIImage{
//         //detect faces
//        let f = getFaces(img: inputImage)
//
//         //if no faces, just return original image
//        if f.count == 0 { return inputImage }
//
//        var retImage = inputImage
//
//        self.bridge.setImage(retImage,
//                             withBounds: f[0].bounds, // the first face bounds
//                             andContext: self.videoManager.getCIContext())
//
//        self.bridge.processImage()
//        retImage = self.bridge.getImageComposite() // get back opencv processed part of the image (overlayed on original)
//
//        return retImage
//    }
    
    // This shows
    ///Removed because I dont think a timer is correct. Should be in the VideoProcessor no?
//    func startUpdatingBPM() {
//        Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { timer in
//            let bpm = self.bridge.getBetsPerMinute() //calculates bpm in bridge
//            self.bpmLabel.text = "BPM: \(bpm)"
//        }
//    }

    
    func processImageSwift(inputImage:CIImage) -> CIImage{
        
        // detect faces
//        let f = getFaces(img: inputImage)
        
        // if no faces, just return original image
//        if f.count == 0 { return inputImage }
        
//        var retImage = inputImage
        
        //-------------------Example 1----------------------------------
        // if you just want to process on separate queue use this code
        // this is a NON BLOCKING CALL, but any changes to the image in OpenCV cannot be displayed real time
        /*
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0)) { () -> Void in
            self.bridge.setImage(retImage, withBounds: retImage.extent, andContext: self.videoManager.getCIContext())
            self.bridge.processImage()
        }
         */
        
        //-------------------Example 2----------------------------------
        // use this code if you are using OpenCV and want to overwrite the displayed image via OpenCV
        // this is a BLOCKING CALL
        /*
        // FOR FLIPPED ASSIGNMENT, YOU MAY BE INTERESTED IN THIS EXAMPLE
        
        self.bridge.setImage(retImage, withBounds: retImage.extent, andContext: self.videoManager.getCIContext())
        self.bridge.processImage()
        retImage = self.bridge.getImage()
         */
        
        //-------------------Example 3----------------------------------
        //You can also send in the bounds of the face to ONLY process the face in OpenCV
        // or any bounds to only process a certain bounding region in OpenCV
        
        // Initializer
        var retImage = inputImage
        
        // Set Current Image
        self.bridge.setImage(inputImage,
                             withBounds: inputImage.extent,
                             andContext: self.videoManager.getCIContext())
        
        // Process Finger
        let isFingerDetected = self.bridge.processFinger()
        
        
        // Based On Return Value, Enable / Disable Buttons
//        DispatchQueue.main.async {
            self.torchToggleButton.isEnabled = !isFingerDetected
            self.cameraToggleButton.isEnabled = !isFingerDetected
            if currBpm != -1 {
                self.bpmLabel.text = "BPM: \(self.currBpm)"
                
            } else {
                if !isFingerDetected{
                    self.stageLabel.text = "Finger not detected"
                    self.bpmLabel.text = "Please Place Finger Over Camera and Flash!"
                } else {
                    //TODO make a loading bar
                    self.bpmLabel.text = "Hold finger..."
                }
                
            }
//        }

        // Toggle Flash Depending On Return
        // Note: Only Change If Not Already Controlled
        if !isFlashManuallyControlled {
            if isFingerDetected {
                _ = self.videoManager.turnOnFlashwithLevel(1.0)
            }
            else {
                self.videoManager.turnOffFlash()
            }
        }
        
        // Get Back OpenCV Processed Part Of Image
        retImage = self.bridge.getImageComposite()
        
        // Return Augmented Image
        return retImage
        
    }
    
    // MARK: Setup Face Detection
    
    func getFaces(img:CIImage) -> [CIFaceFeature]{
        // this ungodly mess makes sure the image is the correct orientation
        let optsFace = [CIDetectorImageOrientation:self.videoManager.ciOrientation]
        // get Face Features
        return self.detector.features(in: img, options: optsFace) as! [CIFaceFeature]
        
    }
    
    // change the type of processing done in OpenCV
    @IBAction func swipeRecognized(_ sender: UISwipeGestureRecognizer) {
        switch sender.direction {
        case .left:
            if self.bridge.processType <= 10 {
                self.bridge.processType += 1
            }
        case .right:
            if self.bridge.processType >= 1{
                self.bridge.processType -= 1
            }
        default:
            break
            
        }
        
        stageLabel.text = "Stage: \(self.bridge.processType)"

    }
    
    // MARK: Convenience Methods For UI Flash, Camera Toggle
    @IBAction func flash(_ sender: AnyObject) {
        
         // Toggle Flash. If Overheated, Toggle Will Not Change State
         if (!self.videoManager.toggleFlash()) {
             isFlashManuallyControlled.toggle()
         }
         
         // Update Slider Value
         self.flashSlider.value = isFlashManuallyControlled ? 1.0 : 0.0
         
    }
    
    @IBAction func switchCamera(_ sender: AnyObject) {
        self.videoManager.toggleCameraPosition()
    }
    
    @IBAction func setFlashLevel(_ sender: UISlider) {
        if (sender.value > 0.0) {
            isFlashManuallyControlled = true
            let val = self.videoManager.turnOnFlashwithLevel(sender.value)
            if val {
                print("Flash Return, No Errors")
            }
        }
        else if (sender.value == 0.0) {
            isFlashManuallyControlled = false
            self.videoManager.turnOffFlash()
        }
    }
}
