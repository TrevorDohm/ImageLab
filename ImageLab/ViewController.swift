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
import Accelerate

class ViewController: UIViewController   {

    // MARK: Class Properties
    var filters : [CIFilter]! = nil
    var videoManager:VisionAnalgesic! = nil
    let pinchFilterIndex = 2
    var detector:CIDetector! = nil
    let bridge = OpenCVBridge()
    var isFlashManuallyControlled:Bool = false

    @IBOutlet weak var graphView: UIView!
    lazy var graph:MetalGraph? = {
        return MetalGraph(userView: self.graphView)
    }()
    
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
        graph?.addGraph(withName: "bpm",
            shouldNormalizeForFFT: false,
                        numPointsInGraph: Int(self.bridge.getBufferSize()))

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
        Timer.scheduledTimer(withTimeInterval: 1/30.0, repeats: true) { _ in
            self.updateGraphView()
        }
        
//        startUpdatingBPM()
    
    }
    func logC(val: Double, forBase base: Double) -> Double {
        return log(val)/log(base)
    }
    
    @objc func updateGraphView() {
//        var theArray:[Float] = Array.init(repeating: 0.0, count: Int(self.bridge.getBufferSize()))
        var theArray:[Float] = []
        for i in 0...Int(self.bridge.getBufferSize()){
            theArray.append(Float(self.bridge.ppg[i]))
        }
//        memcpy(&theArray, self.bridge.ppg, Int(self.bridge.getBufferSize() * 4))
//        vDSP_vdpsp(self.bridge.ppg, 1, &theArray, 1, vDSP_Length(Int(self.bridge.getBufferSize())))
        
        self.graph?.updateGraph(
            data: theArray,
            forKey: "bpm"
        )
    }
        
    @objc func bpmUpdater() {
        self.currBpm = self.bridge.getBetsPerMinute()
    }
    
    func processImageSwift(inputImage:CIImage) -> CIImage{
        var retImage = inputImage
        
        // Set Current Image
        self.bridge.setImage(inputImage,
                             withBounds: inputImage.extent,
                             andContext: self.videoManager.getCIContext())
        
        // Process Finger
        let isFingerDetected = self.bridge.processFinger()
        
        
        // Based On Return Value, Enable / Disable Buttons
        
            self.torchToggleButton.isEnabled = !isFingerDetected
            self.cameraToggleButton.isEnabled = !isFingerDetected
            if self.currBpm != -1 {
                self.bpmLabel.text = "BPM: \(self.currBpm)"
                
            } else {
                if !isFingerDetected{
                    self.stageLabel.text = "Finger not detected"
                    self.bpmLabel.text = "Please Place Finger Over Camera and Flash!"
                } else {
                    //TODO make a loading bar
                    self.bpmLabel.text = "Hold finger..."
                    self.stageLabel.text = "Finger is present"
                }
                
            }
        

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
