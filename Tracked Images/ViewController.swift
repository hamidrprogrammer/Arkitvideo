//
//  ViewController.swift
//  Tracked Images
//
//  Created by Tony Morales on 6/13/18.
//  Modified by Ashen – 19 May 2025
//

import UIKit
import SceneKit
import ARKit
import AVFoundation

// MARK: - کوچک‌ترین نسخه‌ی StatusViewController برای پیام‌های وضعیت
final class StatusViewController: UIViewController {
    
    private let label = UILabel()
    private var timer: Timer?
    
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        label.textColor = .white
        label.font = .systemFont(ofSize: 15, weight: .medium)
        label.textAlignment = .center
        label.numberOfLines = 0
        label.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            label.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            label.topAnchor.constraint(equalTo: view.topAnchor),
            label.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }
    
    /// نشان دادن یک پیام که پس از ۳ ثانیه پاک می‌شود
    func showMessage(_ text: String) {
        DispatchQueue.main.async {
            self.label.text = text
            self.timer?.invalidate()
            self.timer = Timer.scheduledTimer(withTimeInterval: 3, repeats: false) { _ in
                self.label.text = ""
            }
        }
    }
    
    /// لغو تمام پیام‌های زمان‌بندی‌شده
    func cancelAllScheduledMessages() {
        timer?.invalidate()
        timer = nil
        label.text = ""
    }
}

class ViewController: UIViewController, ARSCNViewDelegate, ARSessionDelegate {
    
    // MARK: - UI
    
    private var sceneView: ARSCNView!
    private var magicSwitch: UISwitch!
    private var blurView: UIVisualEffectView!
    private let statusViewController = StatusViewController()
    
    // MARK: - ویدیو پلیرها
    
    private let isaVideoPlayer: AVPlayer = {
        guard let url = Bundle.main.url(forResource: "isa video",
                                        withExtension: "mp4",
                                        subdirectory: "art.scnassets") else { return AVPlayer() }
        return AVPlayer(url: url)
    }()
    
    private let pragueVideoPlayer: AVPlayer = {
        guard let url = Bundle.main.url(forResource: "prague video",
                                        withExtension: "mp4",
                                        subdirectory: "art.scnassets") else { return AVPlayer() }
        return AVPlayer(url: url)
    }()
    
    private let fightClubVideoPlayer: AVPlayer = {
        guard let url = Bundle.main.url(forResource: "fight club video",
                                        withExtension: "mov",
                                        subdirectory: "art.scnassets") else { return AVPlayer() }
        return AVPlayer(url: url)
    }()
    
    private let homerVideoPlayer: AVPlayer = {
        guard let url = Bundle.main.url(forResource: "homer video",
                                        withExtension: "mov",
                                        subdirectory: "art.scnassets") else { return AVPlayer() }
        return AVPlayer(url: url)
    }()
    
    // MARK: - Session helpers
    
    private let updateQueue = DispatchQueue(label: Bundle.main.bundleIdentifier! + ".serialSceneKitQueue")
    private var session: ARSession { sceneView.session }
    private var isRestartAvailable = true
    
    // MARK: - Life‑cycle
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        // ARSCNView
        sceneView = ARSCNView(frame: view.bounds)
        sceneView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        sceneView.delegate = self
        sceneView.session.delegate = self
        view.addSubview(sceneView)
        
        // Blur overlay (برای هماهنگی با کد extension قدیمی)
        blurView = UIVisualEffectView(effect: UIBlurEffect(style: .dark))
        blurView.frame = view.bounds
        blurView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        blurView.alpha = 0
        view.addSubview(blurView)
        
        // Magic switch
        magicSwitch = UISwitch()
        magicSwitch.translatesAutoresizingMaskIntoConstraints = false
        magicSwitch.addTarget(self, action: #selector(switchOnMagic(_:)), for: .valueChanged)
        view.addSubview(magicSwitch)
        
        // Show‑images button
        let listButton = UIButton(type: .system)
        listButton.translatesAutoresizingMaskIntoConstraints = false
        listButton.setImage(UIImage(systemName: "photo.on.rectangle.angled"), for: .normal)
        listButton.tintColor = .white
        listButton.backgroundColor = UIColor.black.withAlphaComponent(0.5)
        listButton.layer.cornerRadius = 22
        listButton.addTarget(self, action: #selector(showImageList), for: .touchUpInside)
        view.addSubview(listButton)
        
        // Status vc (پایین صفحه)
        addChild(statusViewController)
        statusViewController.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(statusViewController.view)
        statusViewController.didMove(toParent: self)
        
        // Constraints
        NSLayoutConstraint.activate([
            magicSwitch.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 16),
            magicSwitch.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 16),
            
            listButton.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -16),
            listButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 16),
            listButton.widthAnchor.constraint(equalToConstant: 44),
            listButton.heightAnchor.constraint(equalToConstant: 44),
            
            statusViewController.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            statusViewController.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            statusViewController.view.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
            statusViewController.view.heightAnchor.constraint(equalToConstant: 50)
        ])
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
    
    // MARK: - AR configuration
    
    @objc private func switchOnMagic(_ sender: Any) {
        let configuration = ARImageTrackingConfiguration()
        guard let trackingImages = ARReferenceImage.referenceImages(inGroupNamed: "AR Resources", bundle: nil) else {
            print("Could not load images")
            return
        }
        configuration.trackingImages = trackingImages
        configuration.maximumNumberOfTrackedImages = 4
        session.run(configuration, options: [.resetTracking, .removeExistingAnchors])
    }
    
    private func resetTracking() {
        let configuration = ARImageTrackingConfiguration()
        session.run(configuration, options: [.resetTracking, .removeExistingAnchors])
    }
    
    /// برای extension قدیمی
    func restartExperience() { resetTracking() }
    
    // MARK: - Pop‑up list
    
    @objc private func showImageList() {
        let alert = UIAlertController(title: "Available Videos", message: nil, preferredStyle: .actionSheet)
        ["isa video", "prague video", "fight club video", "homer video"].forEach { name in
            alert.addAction(UIAlertAction(title: name, style: .default))
        }
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        if let pop = alert.popoverPresentationController {
            pop.sourceView = view
            pop.sourceRect = CGRect(x: view.bounds.width - 60, y: 60, width: 1, height: 1)
        }
        present(alert, animated: true)
    }
    
    // MARK: - ARSCNViewDelegate
    
    func renderer(_ renderer: SCNSceneRenderer, nodeFor anchor: ARAnchor) -> SCNNode? {
        let node = SCNNode()
        guard let imageAnchor = anchor as? ARImageAnchor else { return node }
        
        let plane = SCNPlane(width: imageAnchor.referenceImage.physicalSize.width,
                             height: imageAnchor.referenceImage.physicalSize.height)
        
        switch imageAnchor.referenceImage.name {
        case "prague image":
            plane.firstMaterial?.diffuse.contents = pragueVideoPlayer
            pragueVideoPlayer.play()
            pragueVideoPlayer.volume = 0.4
        case "fight club image":
            plane.firstMaterial?.diffuse.contents = fightClubVideoPlayer
            fightClubVideoPlayer.play()
        case "homer image":
            plane.firstMaterial?.diffuse.contents = homerVideoPlayer
            homerVideoPlayer.play()
        default:
            plane.firstMaterial?.diffuse.contents = isaVideoPlayer
            isaVideoPlayer.play()
            isaVideoPlayer.isMuted = true
        }
        
        let planeNode = SCNNode(geometry: plane)
        planeNode.eulerAngles.x = -.pi / 2
        node.addChildNode(planeNode)
        return node
    }
}

