//
//  ModuleAViewController.swift
//  ImageLab
//
//  Created by William Landin on 10/30/23.
//  Copyright © 2023 Eric Larson. All rights reserved.
//

import UIKit
import MetalKit

class ModuleAViewController: UIViewController {

    var videoModel:VideoModel? = nil
    
    @IBOutlet weak var cameraView: MTKView!
    
    
    //MARK: ViewController Hierarchy
    override func viewDidLoad() {
        super.viewDidLoad()
        videoModel = VideoModel(view: self.cameraView)
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

