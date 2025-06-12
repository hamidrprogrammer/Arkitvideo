//
//  ViewController.swift
//  DynamicImageTracking
//
//  Updated: 12 June 2025 – Changed action priority and added length checks
//

import UIKit
import SceneKit
import ARKit
import AVFoundation
import MapKit
import CoreLocation

// MARK: - API Models -----------------------------------------------

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
    let video: String
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
    let ytb: String?
    let seen: Int
    let id: Int
    let insertTime: String
    let updateTime: String?
}

// MARK: - ViewController -------------------------------------------------------

final class ViewController: UIViewController, ARSCNViewDelegate {
    
    // MARK: - IBOutlets
    @IBOutlet weak var sceneView: ARSCNView!
    @IBOutlet weak var magicSwitch: UISwitch!
    @IBOutlet weak var blurView: UIVisualEffectView!
    
    // MARK: - AR Action Definition
    
    enum ARAction {
        case playVideo(URL)
        case openMap(CLLocationCoordinate2D)
        case openYouTube(URL)
    }
    
    // MARK: - Private State
    
    var actionMap: [String: ARAction] = [:]
    var playerMap: [String: AVPlayer] = [:]
    var openedForImage = Set<String>()
    var dynamicReferenceImages = Set<ARReferenceImage>()
    
    var isSessionRunning = false
    var isRestartAvailable = true
    let updateQueue = DispatchQueue(label: "\(Bundle.main.bundleIdentifier!).serialSceneKitQueue")
    
    static let ReferencePhysicalWidth: CGFloat = 0.20
    
    lazy var statusViewController: StatusViewController = {
        children.lazy.compactMap { $0 as? StatusViewController }.first!
    }()
    
    // MARK: - Lifecycle
    
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
    
    // MARK: - Session Helpers
    
    func resetTracking() {
        openedForImage.removeAll()
        
        let configuration = ARImageTrackingConfiguration()
        sceneView.session.run(configuration, options: [.resetTracking, .removeExistingAnchors])
        
        if magicSwitch.isOn {
            configureAndRunSession()
        }
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
    
    // MARK: - API Call & Parsing
    
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
                DispatchQueue.main.async { self.statusViewController.showMessage("❌ API error") }
                return
            }
            guard let data else { return }
            do {
                let decoded = try JSONDecoder().decode(MediaResponse.self, from: data)
                let validItems = decoded.data.dataContent.filter {
                    !$0.isRemoved && !$0.name.isEmpty && !$0.image.isEmpty
                }
                self.prepareTracking(with: validItems)
            } catch {
                print("❌ JSON decode error:", error)
                DispatchQueue.main.async { self.statusViewController.showMessage("❌ JSON decode error") }
            }
        }.resume()
    }
    
    // MARK: - Build Reference Images & Actions
    
    private func prepareTracking(with items: [MediaItemRaw]) {
        var refs = [ARReferenceImage]()
        let group = DispatchGroup()
        
        for item in items {
            
            // ⬅️ START OF CHANGES: New priority and length checks
            // Priority: Video > YouTube > Map
            
            // 1. Check for Video first
            if let vidURL = URL(string: item.video) {
                actionMap[item.name] = .playVideo(vidURL)
            
            // 2. Else, check for YouTube with length > 5
            } else if let ytbString = item.ytb, ytbString.count > 5, let url = URL(string: ytbString) {
                actionMap[item.name] = .openYouTube(url)

            // 3. Else, check for Map with length > 5
            } else {
                let latString = item.mapLa.isEmpty ? item.latitude : item.mapLa
                let lonString = item.mapLo.isEmpty ? item.longitude : item.mapLo
                
                if latString.count > 5 && lonString.count > 5,
                   let lat = Double(latString),
                   let lon = Double(lonString),
                   (lat != 0 || lon != 0) {
                    let coord = CLLocationCoordinate2D(latitude: lat, longitude: lon)
                    actionMap[item.name] = .openMap(coord)
                }
            }
            // ⬅️ END OF CHANGES
            
            guard let imgURL = URL(string: item.image) else { continue }
            
            group.enter()
            URLSession.shared.dataTask(with: imgURL) { data, _, _ in
                defer { group.leave() }
                guard let data,
                      let uiImage = UIImage(data: data),
                      let cg = uiImage.cgImage else {
                    print("Could not download or process image for \(item.name)")
                    return
                }
                
                let refImage = ARReferenceImage(cg, orientation: .up, physicalWidth: Self.ReferencePhysicalWidth)
                refImage.name = item.name
                refs.append(refImage)
            }.resume()
        }
        
        group.notify(queue: .main) {
            self.dynamicReferenceImages = Set(refs)
            print("✅ Prepared \(refs.count) dynamic reference images")
            
            if self.magicSwitch.isOn {
                self.configureAndRunSession()
            }
        }
    }
    
    // MARK: - ARSCNViewDelegate (No changes below this line)
    
    func renderer(_ renderer: SCNSceneRenderer, nodeFor anchor: ARAnchor) -> SCNNode? {
        guard let imageAnchor = anchor as? ARImageAnchor, isSessionRunning else { return nil }
        let imageName = imageAnchor.referenceImage.name ?? ""
        
        guard let action = actionMap[imageName] else {
            print("🤷 No action defined for image «\(imageName)»")
            return nil
        }
        
        if case .playVideo = action {
            // No need to check openedForImage for videos
        } else {
            if openedForImage.contains(imageName) { return nil }
        }
        
        switch action {
        case .openYouTube(let url):
            openedForImage.insert(imageName)
            DispatchQueue.main.async {
                print("▶️ Opening YouTube for «\(imageName)»")
                self.statusViewController.showMessage("Opening YouTube for «\(imageName)»")
                UIApplication.shared.open(url, options: [:])
            }
            return SCNNode()

        case .openMap(let coord):
            openedForImage.insert(imageName)
            let url = URL(string: "http://maps.apple.com/?ll=\(coord.latitude),\(coord.longitude)")!
            DispatchQueue.main.async {
                print("🗺️ Opening map for «\(imageName)»")
                self.statusViewController.showMessage("Opening map for «\(imageName)»")
                UIApplication.shared.open(url, options: [:], completionHandler: nil)
            }
            return SCNNode()

        case .playVideo(let videoURL):
            guard playerMap[imageName] == nil else { return nil }
            
            let player = AVPlayer(url: videoURL)
            player.actionAtItemEnd = .none
            
            NotificationCenter.default.addObserver(
                forName: .AVPlayerItemDidPlayToEndTime,
                object: player.currentItem,
                queue: .main) { [weak player] _ in
                    player?.seek(to: .zero)
                    player?.play()
                }
            
            playerMap[imageName] = player
            
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
    }
    
    func renderer(_ renderer: SCNSceneRenderer, didUpdate node: SCNNode, for anchor: ARAnchor) {
        guard let imageAnchor = anchor as? ARImageAnchor else { return }
        let imageName = imageAnchor.referenceImage.name ?? ""
        
        guard let action = actionMap[imageName], case .playVideo = action else { return }
        guard let player = playerMap[imageName] else { return }
        
        if imageAnchor.isTracked {
            if player.timeControlStatus != .playing {
                player.play()
                print("▶️ Resume «\(imageName)»")
            }
        } else {
            if player.timeControlStatus == .playing {
                player.pause()
                print("⏸️ Pause «\(imageName)»")
            }
        }
    }
}

// MARK: - Convenience

private extension Data {
    mutating func append(_ string: String.UTF8View) { append(Data(string)) }
}
