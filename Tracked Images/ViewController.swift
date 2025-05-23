import UIKit
import SceneKit
import ARKit
import AVFoundation

class ViewController: UIViewController, ARSCNViewDelegate, ARSessionDelegate {
    
    @IBOutlet var sceneView: ARSCNView!
    @IBOutlet weak var magicSwitch: UISwitch!
    
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
        let id: Int
        let name: String
        let image: String
        let video: String
        let isRemoved: Bool
    }

    struct MediaItem {
        let name: String
        let image: UIImage
        let videoUrl: URL
    }

    var mediaItems: [MediaItem] = []
    var videoPlayers: [String: AVPlayer] = [:]

    override func viewDidLoad() {
        super.viewDidLoad()
        
        sceneView.delegate = self
        sceneView.session.delegate = self
        magicSwitch.setOn(false, animated: false)
        
        UIApplication.shared.isIdleTimerDisabled = true
        
        fetchMediaItemsFromAPI()
    }

    func fetchMediaItemsFromAPI() {
        guard let url = URL(string: "https://club.mamakschool.ir/club.backend/ClubAdmin/GetAllImageARGuest") else { return }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"

        let boundary = UUID().uuidString
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()
        let params = [
            "clubId": "0",
            "adminId": "1"
        ]

        for (key, value) in params {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"\(key)\"\r\n\r\n".data(using: .utf8)!)
            body.append("\(value)\r\n".data(using: .utf8)!)
        }

        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        request.httpBody = body

        URLSession.shared.dataTask(with: request) { data, response, error in
            guard let data = data else { return }

            do {
                let decoded = try JSONDecoder().decode(MediaResponse.self, from: data)
                self.prepareReferenceImages(from: decoded.data.dataContent)
            } catch {
                print("JSON decode error:", error)
            }
        }.resume()
    }

    func prepareReferenceImages(from rawItems: [MediaItemRaw]) {
        let group = DispatchGroup()

        for item in rawItems where !item.isRemoved && !item.image.isEmpty && !item.video.isEmpty {
            guard let imageUrl = URL(string: item.image),
                  let videoUrl = URL(string: item.video) else { continue }

            group.enter()

            URLSession.shared.dataTask(with: imageUrl) { data, _, error in
                defer { group.leave() }

                guard let data = data, let image = UIImage(data: data) else {
                    print("Failed to load image for \(item.name)")
                    return
                }

                let mediaItem = MediaItem(name: item.name, image: image, videoUrl: videoUrl)
                self.mediaItems.append(mediaItem)
            }.resume()
        }

        group.notify(queue: .main) {
            self.setupARReferenceImages()
        }
    }

    func setupARReferenceImages() {
        var referenceImages = Set<ARReferenceImage>()
        for item in mediaItems {
            guard let cgImage = item.image.cgImage else { continue }
            let arImage = ARReferenceImage(cgImage, orientation: .up, physicalWidth: 0.2)
            arImage.name = item.name
            referenceImages.insert(arImage)
        }

        let configuration = ARImageTrackingConfiguration()
        configuration.trackingImages = referenceImages
        configuration.maximumNumberOfTrackedImages = referenceImages.count
        sceneView.session.run(configuration, options: [.resetTracking, .removeExistingAnchors])
    }

    public func renderer(_ renderer: SCNSceneRenderer, nodeFor anchor: ARAnchor) -> SCNNode? {
        let node = SCNNode()

        guard let imageAnchor = anchor as? ARImageAnchor,
              let imageName = imageAnchor.referenceImage.name,
              let mediaItem = mediaItems.first(where: { $0.name == imageName }) else {
            return node
        }

        let videoPlayer: AVPlayer
        if let existingPlayer = videoPlayers[mediaItem.name] {
            videoPlayer = existingPlayer
        } else {
            videoPlayer = AVPlayer(url: mediaItem.videoUrl)
            videoPlayer.volume = 0.6
            videoPlayers[mediaItem.name] = videoPlayer
        }

        let plane = SCNPlane(width: imageAnchor.referenceImage.physicalSize.width,
                             height: imageAnchor.referenceImage.physicalSize.height)
        plane.firstMaterial?.diffuse.contents = videoPlayer
        plane.firstMaterial?.isDoubleSided = true

        let planeNode = SCNNode(geometry: plane)
        planeNode.eulerAngles.x = -.pi / 2
        node.addChildNode(planeNode)

        videoPlayer.play()

        return node
    }
}
