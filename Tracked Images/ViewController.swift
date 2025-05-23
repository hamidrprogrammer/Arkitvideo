//
//  ViewController.swift
//  Tracked Images – Dynamic Video
//
//  © 2025 – production-ready single-file version
//

import UIKit
import SceneKit
import ARKit
import AVFoundation

// MARK: - API Models ----------------------------------------------------------

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
    let name: String          // **Must exactly match image name in asset catalog**
    let video: String         // Remote video URL
    let object: String
    let mapLa: String
    let mapLo: String
    let card: String?
    let image: String
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

// MARK: - View Controller -----------------------------------------------------

final class ViewController: UIViewController, ARSCNViewDelegate, ARSessionDelegate {
    
    // MARK: IBOutlets
    @IBOutlet private weak var sceneView: ARSCNView!
    @IBOutlet private weak var magicSwitch: UISwitch!
    @IBOutlet private weak var blurView: UIVisualEffectView!   // shows while session is interrupted
    
    // MARK: Private State
    private var videoURLMap: [String: URL] = [:]   // imageName → videoURL
    private let updateQueue = DispatchQueue(label: "\(Bundle.main.bundleIdentifier!).serialSceneKitQueue")
    private var isRestartAvailable = true
    
    // MARK: - Lifecycle
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        sceneView.delegate = self
        sceneView.session.delegate = self
        magicSwitch.isOn = false
        blurView.isHidden = true
        
        fetchMediaFromAPI()          // Build the imageName→videoURL map
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        UIApplication.shared.isIdleTimerDisabled = true   // keep screen awake
        resetTracking()                                   // start AR session
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        sceneView.session.pause()
    }
    
    // MARK: - AR Session Configuration
    
    @IBAction private func switchOnMagic(_ sender: Any) {
        let configuration = ARImageTrackingConfiguration()
        guard let trackingImages = ARReferenceImage.referenceImages(inGroupNamed: "AR Resources", bundle: nil) else {
            print("❌ Could not load tracking images")
            return
        }
        configuration.trackingImages = trackingImages
        configuration.maximumNumberOfTrackedImages = 4
        sceneView.session.run(configuration, options: [.resetTracking, .removeExistingAnchors])
    }
    
    /// Restarts the AR session with an empty configuration.
    func resetTracking() {
        let configuration = ARImageTrackingConfiguration()
        sceneView.session.run(configuration, options: [.resetTracking, .removeExistingAnchors])
    }
    
    // MARK: - Remote API -------------------------------------------------------
    
    private func fetchMediaFromAPI() {
        guard let url = URL(string: "https://club.mamakschool.ir/club.backend/ClubAdmin/GetAllImageARGuest") else { return }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        
        let boundary = UUID().uuidString
        request.setValue("multipart/form-data; boundary=\(boundary)",
                         forHTTPHeaderField: "Content-Type")
        
        var body = Data()
        let params = [
            "clubId": "0",
            "adminId": "1"
        ]
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
                return
            }
            guard let data else { return }
            do {
                let decoded = try JSONDecoder().decode(MediaResponse.self, from: data)
                DispatchQueue.main.async { self.buildVideoMap(from: decoded.data.dataContent) }
            } catch {
                print("❌ JSON decode error:", error)
            }
        }.resume()
    }
    
    private func buildVideoMap(from items: [MediaItemRaw]) {
        for item in items {
            if let url = URL(string: item.video) {
                videoURLMap[item.name] = url
            }
        }
        print("✅ videoURLMap ready with \(videoURLMap.count) entries")
    }
    
    // MARK: - ARSCNViewDelegate -------------------------------------------------
    
    func renderer(_ renderer: SCNSceneRenderer,
                  nodeFor anchor: ARAnchor) -> SCNNode? {
        
        guard let imageAnchor = anchor as? ARImageAnchor else { return nil }
        let imageName = imageAnchor.referenceImage.name ?? ""
        
        // Lookup video URL for this image
        guard let videoURL = videoURLMap[imageName] else {
            print("⚠️ No video URL mapped for image «\(imageName)»")
            return nil
        }
        
        // Create player
        let player = AVPlayer(url: videoURL)
        player.volume = 1.0
        
        // Plane matching physical size of the image
        let plane = SCNPlane(width: imageAnchor.referenceImage.physicalSize.width,
                             height: imageAnchor.referenceImage.physicalSize.height)
        plane.firstMaterial?.diffuse.contents = player
        plane.firstMaterial?.isDoubleSided = true
        
        let planeNode = SCNNode(geometry: plane)
        planeNode.eulerAngles.x = -.pi / 2    // lay flat on image
        
        // Parent node
        let parent = SCNNode()
        parent.addChildNode(planeNode)
        
        player.play()
        return parent
    }
    
    // MARK: - ARSessionDelegate -------------------------------------------------
    
    func session(_ session: ARSession, cameraDidChangeTrackingState camera: ARCamera) {
        switch camera.trackingState {
        case .normal:             print("🟢 Tracking normal")
        case .notAvailable:       print("🔴 Tracking not available")
        case .limited(let reason):print("🟡 Tracking limited:", reason)
        @unknown default:         print("⚠️ Unknown tracking state")
        }
    }
    
    func session(_ session: ARSession, didFailWithError error: Error) {
        print("💥 ARSession error:", error.localizedDescription)
    }
    
    func sessionWasInterrupted(_ session: ARSession) {
        print("⏸️ Session interrupted")
        DispatchQueue.main.async { self.blurView.isHidden = false }
    }
    
    func sessionInterruptionEnded(_ session: ARSession) {
        print("▶️ Session interruption ended – resetting tracking")
        DispatchQueue.main.async { self.blurView.isHidden = true }
        resetTracking()
    }
}

// MARK: - Convenience Data extension ------------------------------------------

private extension Data {
    mutating func append(_ string: String.UTF8View) {
        self.append(Data(string))
    }
}
