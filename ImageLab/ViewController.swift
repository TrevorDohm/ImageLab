//
//  ViewController.swift
//  ImageLab
//
//  Created by Eric Larson
//  Copyright © Eric Larson. All rights reserved.
// This code was forked off the Flipped Module Branch. The code in this ViewController and OpenCVBridge are based off Eric Larson's ImageLab Repo.

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
    //set up videoManager
    override func viewDidLoad() {
        super.viewDidLoad()
        
        self.view.backgroundColor = nil
        graph?.addGraph(withName: "bpm",
            shouldNormalizeForFFT: false,
                        numPointsInGraph: Int(self.bridge.getBufferSize()))

        // setup the OpenCV bridge nose detector, from file
        self.videoManager = VisionAnalgesic(view: self.cameraView)
        self.videoManager.setCameraPosition(position: AVCaptureDevice.Position.back)
        
        //Not sure if necessary but set framerate of phone here, iPhone X was used in video
        self.videoManager.setFPS(desiredFrameRate: 30)
        // create dictionary for face detection
    
        self.videoManager.setProcessingBlock(newProcessBlock: self.processImageSwift)
        
        //timer for updating the bpm
        bpmTimer = Timer.scheduledTimer(timeInterval: 1, target: self, selector: #selector(self.bpmUpdater), userInfo: nil, repeats: true)
        
        if !videoManager.isRunning{
            videoManager.start()
        }
        
        //timer for updating bpm graph
        Timer.scheduledTimer(withTimeInterval: 1/30.0, repeats: true) { _ in
            self.updateGraphView()
        }
            
    }
    
    func cleanup(){
         if videoManager.isRunning {
             videoManager.stop()
         }
     }
    //If view is exited during exection this will reset the buffers and current Index
     override func viewWillDisappear(_ animated: Bool) {
         super.viewWillDisappear(animated)
         self.cleanup()
         self.bridge.resetBuffer()
     }
    
    @objc func updateGraphView() {
        var theArray:[Float] = []
        for i in 0...Int(self.bridge.getBufferSize()){
            theArray.append(Float(self.bridge.ppg[i]))
        }

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
