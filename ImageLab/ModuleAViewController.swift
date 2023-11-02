import UIKit
import MetalKit

class ModuleAViewController: UIViewController {
    
    var videoModel:VideoModel? = nil
    @IBOutlet weak var cameraView: MTKView!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        videoModel = VideoModel(view: self.cameraView)
    }
    
    // deallocate the video Model if exiting the view
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        videoModel?.cleanup()
    }

}

