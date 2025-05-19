//
//  ViewController.swift
//  Tracked Images
//
//  Created by Tony Morales on 6/13/18.
//  Copyright © 2018 Tony Morales. All rights reserved.
//

import UIKit
import SceneKit
import ARKit
import AVFoundation

class ViewController: UIViewController, ARSCNViewDelegate, ARSessionDelegate, UICollectionViewDataSource, UICollectionViewDelegate {

    @IBOutlet var sceneView: ARSCNView!
    @IBOutlet weak var magicSwitch: UISwitch!
    @IBOutlet weak var blurView: UIVisualEffectView!
    
    // Video Players
    let isaVideoPlayer: AVPlayer = {
        guard let url = Bundle.main.url(forResource: "isa video", withExtension: "mp4", subdirectory: "art.scnassets") else {
            print("Could not find video file")
            return AVPlayer()
        }
        return AVPlayer(url: url)
    }()
    
    let pragueVideoPlayer: AVPlayer = {
        guard let url = Bundle.main.url(forResource: "prague video", withExtension: "mp4", subdirectory: "art.scnassets") else {
            print("Could not find video file")
            return AVPlayer()
        }
        return AVPlayer(url: url)
    }()
    
    let fightClubVideoPlayer: AVPlayer = {
        guard let url = Bundle.main.url(forResource: "fight club video", withExtension: "mov", subdirectory: "art.scnassets") else {
            print("Could not find video file")
            return AVPlayer()
        }
        return AVPlayer(url: url)
    }()
    
    let homerVideoPlayer: AVPlayer = {
        guard let url = Bundle.main.url(forResource: "homer video", withExtension: "mov", subdirectory: "art.scnassets") else {
            print("Could not find video file")
            return AVPlayer()
        }
        return AVPlayer(url: url)
    }()
    
    // UI Components
    private let imagesButton = UIButton(type: .system)
    private let popupView = UIView()
    private let collectionView: UICollectionView = {
        let layout = UICollectionViewFlowLayout()
        layout.itemSize = CGSize(width: 120, height: 40)
        layout.minimumInteritemSpacing = 10
        let cv = UICollectionView(frame: .zero, collectionViewLayout: layout)
        return cv
    }()
    
    private let imageList = [
        "isa video",
        "prague video", 
        "fight club video",
        "homer video"
    ]
    
    // Status View Controller
    lazy var statusViewController: StatusViewController = {
        return children.lazy.compactMap({ $0 as? StatusViewController }).first!
    }()
    
    let updateQueue = DispatchQueue(label: Bundle.main.bundleIdentifier! + ".serialSceneKitQueue")
    
    var session: ARSession {
        return sceneView.session
    }
    
    // MARK: - Lifecycle
    override func viewDidLoad() {
        super.viewDidLoad()
        
        sceneView.delegate = self
        sceneView.session.delegate = self
        magicSwitch.setOn(false, animated: false)
        
        setupUI()
        setupPopup()
        
        statusViewController.restartExperienceHandler = { [unowned self] in
            self.restartExperience()
        }
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
    
    // MARK: - UI Setup
    private func setupUI() {
        // Images Button
        imagesButton.setTitle("Images", for: .normal)
        imagesButton.backgroundColor = .white.withAlphaComponent(0.9)
        imagesButton.layer.cornerRadius = 8
        imagesButton.addTarget(self, action: #selector(togglePopup), for: .touchUpInside)
        
        view.addSubview(imagesButton)
        imagesButton.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            imagesButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 16),
            imagesButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            imagesButton.widthAnchor.constraint(equalToConstant: 80),
            imagesButton.heightAnchor.constraint(equalToConstant: 40)
        ])
    }
    
    private func setupPopup() {
        // Popup View
        popupView.backgroundColor = UIColor.black.withAlphaComponent(0.7)
        popupView.layer.cornerRadius = 12
        popupView.isHidden = true
        
        // Collection View
        collectionView.backgroundColor = .white
        collectionView.layer.cornerRadius = 8
        collectionView.register(UICollectionViewCell.self, forCellWithReuseIdentifier: "cell")
        collectionView.dataSource = self
        collectionView.delegate = self
        
        // Tap Gesture for Dismiss
        let tap = UITapGestureRecognizer(target: self, action: #selector(dismissPopup))
        tap.delegate = self
        popupView.addGestureRecognizer(tap)
        
        view.addSubview(popupView)
        popupView.addSubview(collectionView)
        
        popupView.translatesAutoresizingMaskIntoConstraints = false
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        
        NSLayoutConstraint.activate([
            popupView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            popupView.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            popupView.widthAnchor.constraint(equalTo: view.widthAnchor, multiplier: 0.8),
            popupView.heightAnchor.constraint(equalTo: view.heightAnchor, multiplier: 0.6),
            
            collectionView.topAnchor.constraint(equalTo: popupView.topAnchor, constant: 20),
            collectionView.leadingAnchor.constraint(equalTo: popupView.leadingAnchor, constant: 20),
            collectionView.trailingAnchor.constraint(equalTo: popupView.trailingAnchor, constant: -20),
            collectionView.bottomAnchor.constraint(equalTo: popupView.bottomAnchor, constant: -20)
        ])
    }
    
    // MARK: - Button Actions
    @IBAction func switchOnMagic(_ sender: Any) {
        let configuration = ARImageTrackingConfiguration()
        
        guard let trackingImages = ARReferenceImage.referenceImages(inGroupNamed: "AR Resources", bundle: nil) else {
            print("Could not load images")
            return
        }
        
        configuration.trackingImages = trackingImages
        configuration.maximumNumberOfTrackedImages = 4
        session.run(configuration, options: [.resetTracking, .removeExistingAnchors])
    }
    
    @objc private func togglePopup() {
        popupView.isHidden = !popupView.isHidden
    }
    
    @objc private func dismissPopup() {
        popupView.isHidden = true
    }
    
    // MARK: - CollectionView DataSource
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return imageList.count
    }
    
    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "cell", for: indexPath)
        cell.backgroundColor = .lightGray
        
        let label = UILabel(frame: cell.contentView.bounds)
        label.text = imageList[indexPath.row]
        label.textAlignment = .center
        label.numberOfLines = 0
        cell.contentView.addSubview(label)
        
        return cell
    }
    
    // MARK: - ARSession Management
    func resetTracking() {
        let configuration = ARImageTrackingConfiguration()
        session.run(configuration, options: [.resetTracking, .removeExistingAnchors])
    }
    
    // MARK: - ARSCNViewDelegate
    func renderer(_ renderer: SCNSceneRenderer, nodeFor anchor: ARAnchor) -> SCNNode? {
        let node = SCNNode()
        
        if let imageAnchor = anchor as? ARImageAnchor {
            let plane = SCNPlane(
                width: imageAnchor.referenceImage.physicalSize.width,
                height: imageAnchor.referenceImage.physicalSize.height
            )
            
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
        }
        
        return node
    }
}

// MARK: - UIGestureRecognizerDelegate
extension ViewController: UIGestureRecognizerDelegate {
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        return touch.view == popupView
    }
}
