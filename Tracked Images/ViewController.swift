//
//  ViewController.swift
//  DynamicImageTracking
//
//  Created by Ashen on 23/05/2025.
//

import UIKit
import SceneKit
import ARKit
import AVFoundation

// MARK: - API Models -----------------------------------------------------------

struct MediaResponse: Codable {
    let status: Int
    let data: MediaData
    let message: String
}

struct MediaData: Codable {
    let state: Int
    let dataContent: [MediaItemRaw]
}

struct MediaItemRaw: Codable {
    let clubId: Int
    let adminId: Int
    let name: String
    let video: String          // video URL
    let object: String
    let mapLa: String
    let mapLo: String
    let card: String?
    let image: String          // image URL
    let isRemoved: Bool
    let isPassword: Bool
    let type: String
    let fullName: String
    let instagram: String
    let facebook: String
    let twitter: String
    let email: String
    let phone: String
    let avatar: String
    let description: String
    let latitude: String
    let longitude: String
    let addressSite: String
    let ytb: String
    let seen: Int
    let id: Int
    let insertTime: String
    let updateTime: String?
}

// MARK: - ViewController -------------------------------------------------------

final class ViewController: UIViewController, ARSCNViewDelegate {
    
    // MARK: IBOutlets
    @IBOutlet weak var sceneView: ARSCNView!
    @IBOutlet weak var magicSwitch: UISwitch!
    @IBOutlet weak var blurView: UIVisualEffectView!
    
    // MARK: Private State
     var videoURLMap: [String: URL] = [:]          // image name → video URL
     var playerMap:   [String: AVPlayer] = [:]     // image name → AVPlayer
     var dynamicReferenceImages = Set<ARReferenceImage>()
     var isSessionRunning = false
     var isRestartAvailable = true
     let updateQueue = DispatchQueue(label: "\(Bundle.main.bundleIdentifier!).serialSceneKitQueue")
    static let ReferencePhysicalWidth: CGFloat = 0.20     // metres
    
    // status UI (already on storyboard)
     lazy var statusViewController: StatusViewController = {
        children.lazy.compactMap { $0 as? StatusViewController }.first!
    }()
    
    // MARK: Lifecycle -----------------------------------------------------------
    override func viewDidLoad() {
        super.viewDidLoad()
        
        sceneView.delegate = self
        sceneView.session.delegate = self
        magicSwitch.isOn = false
        blurView.isHidden = true
        
        fetchMediaFromAPI()
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        UIApplication.shared.isIdleTimerDisabled = true
        resetTracking()
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        sceneView.session.pause()
    }
    
    // MARK: Session helpers -----------------------------------------------------
    
     func resetTracking() {
        let configuration = ARImageTrackingConfiguration()
        sceneView.session.run(configuration, options: [.resetTracking, .removeExistingAnchors])
    }
    
    @IBAction private func switchOnMagic(_ sender: UISwitch) {
        if sender.isOn {
            configureAndRunSession()
        } else {
            sceneView.session.pause()
            isSessionRunning = false
        }
    }
    
    private func configureAndRunSession() {
        guard !dynamicReferenceImages.isEmpty else {
            print("⚠️ No reference images yet – wait for API")
            return
        }
        let configuration = ARImageTrackingConfiguration()
        configuration.trackingImages = dynamicReferenceImages
        configuration.maximumNumberOfTrackedImages = dynamicReferenceImages.count
        sceneView.session.run(configuration, options: [.resetTracking, .removeExistingAnchors])
        isSessionRunning = true
        print("🟢 AR session running with \(dynamicReferenceImages.count) images")
        statusViewController.showMessage("AR session running with \(dynamicReferenceImages.count) images")
    }
    
    // MARK: API Call & Parsing --------------------------------------------------
    
    private func fetchMediaFromAPI() {
        guard let url = URL(string: "https://club.mamakschool.ir/club.backend/ClubAdmin/GetAllImageARGuest") else { return }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        
        let boundary = UUID().uuidString
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        
        var body = Data()
        let params = ["clubId": "0", "adminId": "1"]
        for (key, value) in params {
            body.append("--\(boundary)\r\n".utf8)
            body.append("Content-Disposition: form-data; name=\"\(key)\"\r\n\r\n".utf8)
            body.append("\(value)\r\n".utf8)
        }
        body.append("--\(boundary)--\r\n".utf8)
        request.httpBody = body
        
        URLSession.shared.dataTask(with: request) { [weak self] data, _, error in
            guard let self else { return }
            if let error {
                print("❌ API error:", error)
                statusViewController.showMessage("❌ API error:")
                return
            }
            guard let data else { return }
            do {
                let decoded = try JSONDecoder().decode(MediaResponse.self, from: data)
                let validItems = decoded.data.dataContent.filter {
                    !$0.isRemoved && !$0.name.isEmpty && !$0.image.isEmpty && !$0.video.isEmpty
                }
                self.prepareTracking(with: validItems)
            } catch {
                print("❌ JSON decode error:", error)
                statusViewController.showMessage("❌ JSON decode error:")
            }
        }.resume()
    }
    
    // MARK: Build Reference Images ---------------------------------------------
    
    private func prepareTracking(with items: [MediaItemRaw]) {
        var refs = [ARReferenceImage]()
        let group = DispatchGroup()
        
        for item in items {
            guard let imgURL = URL(string: item.image),
                  let vidURL = URL(string: item.video) else { continue }
            
            videoURLMap[item.name] = vidURL
            
            group.enter()
            URLSession.shared.dataTask(with: imgURL) { data, _, _ in
                defer { group.leave() }
                guard let data,
                      let uiImage = UIImage(data: data),
                      let cg = uiImage.cgImage else { return }
                
                let refImage = ARReferenceImage(cg, orientation: .up, physicalWidth: Self.ReferencePhysicalWidth)
                refImage.name = item.name
                refs.append(refImage)
            }.resume()
        }
        
        group.notify(queue: .main) {
            self.dynamicReferenceImages = Set(refs)
            print("✅ Prepared \(refs.count) dynamic reference images")
            self.configureAndRunSession()
        }
    }
    
    // MARK: ARSCNViewDelegate ---------------------------------------------------
    
    /// Called when a new anchor appears.
    func renderer(_ renderer: SCNSceneRenderer, nodeFor anchor: ARAnchor) -> SCNNode? {
        guard let imageAnchor = anchor as? ARImageAnchor else { return nil }
        let imageName = imageAnchor.referenceImage.name ?? ""
        guard let videoURL = videoURLMap[imageName] else {
            print("⚠️ No video mapped for «\(imageName)»")
            statusViewController.showMessage("No video mapped for «\(imageName)»")
            return nil
        }
        
        // Player
        let player = AVPlayer(url: videoURL)
        player.actionAtItemEnd = .none      // allow looping
        
        // Loop observer
        NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: player.currentItem,
            queue: .main) { [weak player] _ in
                player?.seek(to: .zero)
                player?.play()
            }
        
        playerMap[imageName] = player       // keep strong ref
        
        // Plane
        let plane = SCNPlane(width: imageAnchor.referenceImage.physicalSize.width,
                             height: imageAnchor.referenceImage.physicalSize.height)
        plane.firstMaterial?.diffuse.contents = player
        plane.firstMaterial?.isDoubleSided = true
        
        let planeNode = SCNNode(geometry: plane)
        planeNode.eulerAngles.x = -.pi / 2
        
        let parent = SCNNode()
        parent.addChildNode(planeNode)
        
        player.play()
        print("🎬 Playing video for «\(imageName)»")
        return parent
    }
    
    /// Called continuously while an anchor is tracked / lost.
    func renderer(_ renderer: SCNSceneRenderer, didUpdate node: SCNNode, for anchor: ARAnchor) {
        guard let imageAnchor = anchor as? ARImageAnchor else { return }
        let imageName = imageAnchor.referenceImage.name ?? ""
        guard let player = playerMap[imageName] else { return }
        
        if imageAnchor.isTracked {
            // back in view → resume
            if player.timeControlStatus != .playing {
                player.play()
                print("▶️ Resume «\(imageName)»")
            }
        } else {
            // lost tracking → pause
            if player.timeControlStatus == .playing {
                player.pause()
                print("⏸️ Pause «\(imageName)»")
            }
        }
    }
}

// MARK: - Convenience ----------------------------------------------------------

private extension Data {
    mutating func append(_ string: String.UTF8View) { append(Data(string)) }
}
