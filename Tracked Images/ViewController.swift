//
//  ViewController.swift
//  Tracked Images
//
//  Created by Tony Morales on 6/13/18.
//  Updated by Ashen on 5/19/2025.
//

import UIKit
import SceneKit
import ARKit
import AVFoundation

class ViewController: UIViewController, ARSCNViewDelegate {

    var sceneView: ARSCNView!
    var magicSwitch: UISwitch!
    var blurView: UIVisualEffectView!
    
    let isaVideoPlayer: AVPlayer = {
        guard let url = Bundle.main.url(forResource: "isa video", withExtension: "mp4", subdirectory: "art.scnassets") else {
            print("Could not find isa video file")
            return AVPlayer()
        }
        return AVPlayer(url: url)
    }()
    
    let pragueVideoPlayer: AVPlayer = {
        guard let url = Bundle.main.url(forResource: "prague video", withExtension: "mp4", subdirectory: "art.scnassets") else {
            print("Could not find prague video file")
            return AVPlayer()
        }
        return AVPlayer(url: url)
    }()
    
    let fightClubVideoPlayer: AVPlayer = {
        guard let url = Bundle.main.url(forResource: "fight club video", withExtension: "mov", subdirectory: "art.scnassets") else {
            print("Could not find fight club video file")
            return AVPlayer()
        }
        return AVPlayer(url: url)
    }()
    
    let homerVideoPlayer: AVPlayer = {
        guard let url = Bundle.main.url(forResource: "homer video", withExtension: "mov", subdirectory: "art.scnassets") else {
            print("Could not find homer video file")
            return AVPlayer()
        }
        return AVPlayer(url: url)
    }()
    
    let updateQueue = DispatchQueue(label: Bundle.main.bundleIdentifier! + ".serialSceneKitQueue")
    
    var session: ARSession {
        return sceneView.session
    }

    var isRestartAvailable = true
    
    override func viewDidLoad() {
        super.viewDidLoad()

        // Setup ARSCNView programmatically
        sceneView = ARSCNView(frame: view.bounds)
        sceneView.delegate = self
        sceneView.session.delegate = self
        view.addSubview(sceneView)
        
        // Add Magic Switch
        magicSwitch = UISwitch(frame: CGRect(x: 20, y: 40, width: 50, height: 30))
        magicSwitch.addTarget(self, action: #selector(switchOnMagic(_:)), for: .valueChanged)
        view.addSubview(magicSwitch)
        
        // Add Button to show image list
        let showListButton = UIButton(type: .system)
        showListButton.frame = CGRect(x: view.bounds.width - 120, y: 40, width: 100, height: 30)
        showListButton.setTitle("Show Images", for: .normal)
        showListButton.addTarget(self, action: #selector(showImageList), for: .touchUpInside)
        view.addSubview(showListButton)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        UIApplication.shared.isIdleTimerDisabled = true
        resetTracking()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        session.pause()
    }

    @objc func switchOnMagic(_ sender: Any) {
        let configuration = ARImageTrackingConfiguration()
        guard let trackingImages = ARReferenceImage.referenceImages(inGroupNamed: "AR Resources", bundle: nil) else {
            print("Could not load images")
            return
        }
        configuration.trackingImages = trackingImages
        configuration.maximumNumberOfTrackedImages = 4
        session.run(configuration, options: [.resetTracking, .removeExistingAnchors])
    }

    func resetTracking() {
        let configuration = ARImageTrackingConfiguration()
        session.run(configuration, options: [.resetTracking, .removeExistingAnchors])
    }

    public func renderer(_ renderer: SCNSceneRenderer, nodeFor anchor: ARAnchor) -> SCNNode? {
        let node = SCNNode()

        if let imageAnchor = anchor as? ARImageAnchor {
            let plane = SCNPlane(width: imageAnchor.referenceImage.physicalSize.width,
                                 height: imageAnchor.referenceImage.physicalSize.height)
            
            switch imageAnchor.referenceImage.name {
            case "prague image":
                plane.firstMaterial?.diffuse.contents = self.pragueVideoPlayer
                self.pragueVideoPlayer.play()
                self.pragueVideoPlayer.volume = 0.4
            case "fight club image":
                plane.firstMaterial?.diffuse.contents = self.fightClubVideoPlayer
                self.fightClubVideoPlayer.play()
            case "homer image":
                plane.firstMaterial?.diffuse.contents = self.homerVideoPlayer
                self.homerVideoPlayer.play()
            default:
                plane.firstMaterial?.diffuse.contents = self.isaVideoPlayer
                self.isaVideoPlayer.play()
                self.isaVideoPlayer.isMuted = true
            }
            
            let planeNode = SCNNode(geometry: plane)
            planeNode.eulerAngles.x = -.pi / 2
            node.addChildNode(planeNode)
        }

        return node
    }

    // MARK: - Show Pop-up List
    @objc func showImageList() {
        let alert = UIAlertController(title: "Available Videos", message: nil, preferredStyle: .actionSheet)
        let videos = [
            "isa video",
            "prague video",
            "fight club video",
            "homer video"
        ]
        
        for video in videos {
            alert.addAction(UIAlertAction(title: video, style: .default, handler: nil))
        }
        
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: nil))
        
        if let popover = alert.popoverPresentationController {
            popover.sourceView = self.view
            popover.sourceRect = CGRect(x: self.view.bounds.width - 60, y: 40, width: 1, height: 1)
        }
        
        present(alert, animated: true, completion: nil)
    }
}
