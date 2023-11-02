//
//  ModuleAViewController.swift
//  ImageLab
//
//  Created by William Landin on 10/30/23.
//  Copyright © 2023 Eric Larson. All rights reserved.
//

import UIKit
import MetalKit

class ModuleAViewController: UIViewController, VideoModelDelegate {
    
    var videoModel:VideoModel? = nil
    
    @IBOutlet weak var cameraView: MTKView!
    @IBOutlet weak var blinkLabel: UILabel!
    
    //MARK: ViewController Hierarchy
    override func viewDidLoad() {
        super.viewDidLoad()
        videoModel = VideoModel(view: self.cameraView)
        videoModel?.delegate = self
        
//        blinkUpdateTimer = Timer.scheduledTimer(timeInterval: 1.0, target: self,
//            selector: #selector(self.updateBlinkLabel),
//            userInfo: nil, repeats: true)
    }
    
    func updateBlinkLabel(){
        let numBlinks = max(videoModel!.blinkCount, 0)
        blinkLabel.text = "You have blinked: \(numBlinks)"
    }
    
    func didDetectBlink(blinkCount: Int) {
        DispatchQueue.main.async {
            self.blinkLabel.text = "You have blinked: \(blinkCount)"
        }
        print("updated label")
    }
    
    func didProcessImage(_ processedImage: CIImage){
        DispatchQueue.main.async {
            //return processedImage
        }
    }
    
    deinit {
        videoModel?.delegate = nil
        print("ModuleAViewController Dealloc")
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        videoModel?.cleanup()
    }

    /*
    // MARK: - Navigation

    // In a storyboard-based application, you will often want to do a little preparation before navigation
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        // Get the new view controller using segue.destination.
        // Pass the selected object to the new view controller.
    }
    */

    
}

