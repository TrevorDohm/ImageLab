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
    
// MARK: ViewController Hierarchy
    override func viewDidLoad() {
        super.viewDidLoad()
        
        self.view.backgroundColor = nil
        
        self.bridge.loadHaarCascade(withFilename: "nose")
        
        self.videoManager = VisionAnalgesic(view: self.cameraView)
        self.videoManager.setCameraPosition(position: AVCaptureDevice.Position.back)
        
        let optsDetector = [CIDetectorAccuracy: CIDetectorAccuracyHigh,
                            CIDetectorNumberOfAngles: 11,
                            CIDetectorTracking: false] as [String: Any]
        
        self.detector = CIDetector(ofType: CIDetectorTypeFace,
                                   context: self.videoManager.getCIContext(),
                                   options: (optsDetector as [String: AnyObject]))
        
        self.videoManager.setProcessingBlock(newProcessBlock: self.processImageSwift)
        
        if !videoManager.isRunning {
            videoManager.start()
        }
        
        startUpdatingBPM()
    }
    
    func startUpdatingBPM() {
        Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { timer in
            let bpm = self.bridge.getBetsPerMinute()
            self.bpmLabel.text = "BPM: \(bpm)"
        }
    }
    
    func processImageSwift(inputImage: CIImage) -> CIImage {
        
        var retImage = inputImage
        
        self.bridge.setImage(inputImage,
                             withBounds: inputImage.extent,
                             andContext: self.videoManager.getCIContext())
        
        let isFingerDetected = self.bridge.processFinger()
        let redValue = self.bridge.getRedValue()

        DispatchQueue.main.async {
            if isFingerDetected {
                self.stageLabel.text = String(format: "Red Value: %.2f", redValue)
            } else {
                self.stageLabel.text = "Finger not detected"
            }
        }

        if isFingerDetected {
            _ = self.videoManager.turnOnFlashwithLevel(1.0)
        } else {
            self.videoManager.turnOffFlash()
        }
        
        retImage = self.bridge.getImageComposite()
        
        return retImage
    }
    
    func getFaces(img: CIImage) -> [CIFaceFeature] {
        let optsFace = [CIDetectorImageOrientation: self.videoManager.ciOrientation]
        return self.detector.features(in: img, options: optsFace) as! [CIFaceFeature]
    }
    
    @IBAction func swipeRecognized(_ sender: UISwipeGestureRecognizer) {
        switch sender.direction {
        case .left:
            if self.bridge.processType <= 10 {
                self.bridge.processType += 1
            }
        case .right:
            if self.bridge.processType >= 1 {
                self.bridge.processType -= 1
            }
        default:
            break
        }
        stageLabel.text = "Stage: \(self.bridge.processType)"
    }
    
    @IBAction func flash(_ sender: AnyObject) {
        print("Flash button tapped, but no action is implemented.")
    }

    @IBAction func switchCamera(_ sender: AnyObject) {
        print("Camera toggle button tapped, but no action is implemented.")
    }

    @IBAction func setFlashLevel(_ sender: UISlider) {
        print("Flash slider value changed to \(sender.value), but no action is implemented.")
    }
}



