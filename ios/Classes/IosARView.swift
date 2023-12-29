import Flutter
import UIKit
import Foundation
import ARKit
import Combine

class IosARView: NSObject, FlutterPlatformView, ARSCNViewDelegate, UIGestureRecognizerDelegate, ARSessionDelegate {
    let sceneView: ARSCNView
    let coachingView: ARCoachingOverlayView
    let sessionManagerChannel: FlutterMethodChannel
    let objectManagerChannel: FlutterMethodChannel
    let anchorManagerChannel: FlutterMethodChannel
    var showPlanes = false
    var customPlaneTexturePath: String? = nil
    private var trackedPlanes = [UUID: (SCNNode, SCNNode)]()
    let modelBuilder = ArModelBuilder()
    
    var cancellableCollection = Set<AnyCancellable>() //Used to store all cancellables in (needed for working with Futures)
    var anchorCollection = [String: ARAnchor]() //Used to bookkeep all anchors created by Flutter calls
    
    private var arcoreMode: Bool = false
    private var configuration: ARWorldTrackingConfiguration!
    private var tappedPlaneAnchorAlignment = ARPlaneAnchor.Alignment.horizontal // default alignment
    
    private var panStartLocation: CGPoint?
    private var panCurrentLocation: CGPoint?
    private var panCurrentVelocity: CGPoint?
    private var panCurrentTranslation: CGPoint?
    private var rotationStartLocation: CGPoint?
    private var rotation: CGFloat?
    private var rotationVelocity: CGFloat?
    private var panningNode: SCNNode?
    private var panningNodeCurrentWorldLocation: SCNVector3?
    
    private var pinchNode: SCNNode?
    private var pinchBeginScale: Float?
    private var pinchMinScale: Float = 0.5
    private var pinchMaxScale: Float = 4.0
    
    init(
        frame: CGRect,
        viewIdentifier viewId: Int64,
        arguments args: Any?,
        binaryMessenger messenger: FlutterBinaryMessenger
    ) {
        self.sceneView = ARSCNView(frame: frame)
        self.coachingView = ARCoachingOverlayView(frame: frame)
        
        self.sessionManagerChannel = FlutterMethodChannel(name: "arsession_\(viewId)", binaryMessenger: messenger)
        self.objectManagerChannel = FlutterMethodChannel(name: "arobjects_\(viewId)", binaryMessenger: messenger)
        self.anchorManagerChannel = FlutterMethodChannel(name: "aranchors_\(viewId)", binaryMessenger: messenger)
        super.init()
        
        let configuration = ARWorldTrackingConfiguration() // Create default configuration before initializeARView is called
        self.sceneView.delegate = self
        self.coachingView.delegate = self
        self.sceneView.session.run(configuration)
        self.sceneView.session.delegate = self
        
        self.sessionManagerChannel.setMethodCallHandler(self.onSessionMethodCalled)
        self.objectManagerChannel.setMethodCallHandler(self.onObjectMethodCalled)
        self.anchorManagerChannel.setMethodCallHandler(self.onAnchorMethodCalled)
    }
    
    func view() -> UIView {
        return self.sceneView
    }
    
    func onDispose(_ result:FlutterResult) {
        sceneView.session.pause()
        self.sessionManagerChannel.setMethodCallHandler(nil)
        self.objectManagerChannel.setMethodCallHandler(nil)
        self.anchorManagerChannel.setMethodCallHandler(nil)
        result(nil)
    }
    
    func onSessionMethodCalled(_ call :FlutterMethodCall, _ result:FlutterResult) {
        let arguments = call.arguments as? Dictionary<String, Any>
        
        switch call.method {
        case "init":
            //self.sessionManagerChannel.invokeMethod("onError", arguments: ["SessionTEST from iOS"])
            //result(nil)
            initializeARView(arguments: arguments!, result: result)
            break
        case "getCameraPose":
            if let cameraPose = sceneView.session.currentFrame?.camera.transform {
                result(serializeMatrix(cameraPose))
            } else {
                result(FlutterError())
            }
            break
        case "getAnchorPose":
            if let cameraPose = anchorCollection[arguments?["anchorId"] as! String]?.transform {
                result(serializeMatrix(cameraPose))
            } else {
                result(FlutterError())
            }
            break
        case "snapshot":
            // call the SCNView Snapshot method and return the Image
            let snapshotImage = sceneView.snapshot()
            if let bytes = snapshotImage.pngData() {
                let data = FlutterStandardTypedData(bytes:bytes)
                result(data)
            } else {
                result(nil)
            }
            break
        case "removeAnimatedGuide":
            self.removeAnimatedGuide()
            result(nil)
            break
        case "dispose":
            onDispose(result)
            result(nil)
            break
        default:
            result(FlutterMethodNotImplemented)
            break
        }
    }
    
    func onObjectMethodCalled(_ call :FlutterMethodCall, _ result: @escaping FlutterResult) {
        let arguments = call.arguments as? Dictionary<String, Any>
        
        switch call.method {
        case "init":
            self.objectManagerChannel.invokeMethod("onError", arguments: ["ObjectTEST from iOS"])
            result(nil)
            break
        case "addNode":
            addNode(dict_node: arguments!).sink(receiveCompletion: {completion in }, receiveValue: { val in
                result(val)
            }).store(in: &self.cancellableCollection)
            break
        case "addNodeToPlaneAnchor":
            let lightNode = SCNNode()
            let light = SCNLight()
            light.intensity = 50
            light.type = .omni
            light.color = UIColor.white
            // 设置其他光源属性
            lightNode.light = light
            lightNode.position = SCNVector3(x: 0, y: 5, z: 0) // 示例位置
            sceneView.scene.rootNode.addChildNode(lightNode)
            if let dict_node = arguments!["node"] as? Dictionary<String, Any>, let dict_anchor = arguments!["anchor"] as? Dictionary<String, Any> {
                addNode(dict_node: dict_node, dict_anchor: dict_anchor).sink(receiveCompletion: {completion in }, receiveValue: { val in
                    result(val)
                }).store(in: &self.cancellableCollection)
            }
            break
        case "removeNode":
            if let name = arguments!["name"] as? String {
                sceneView.scene.rootNode.childNode(withName: name, recursively: true)?.removeFromParentNode()
            }
            break
        case "transformationChanged":
            if let name = arguments!["name"] as? String, let transform = arguments!["transformation"] as? Array<NSNumber> {
                transformNode(name: name, transform: transform)
                result(nil)
            }
            break
        case "togglePlaneRenderer":
            showPlanes = false;
            for plane in trackedPlanes.values {
                plane.1.removeFromParentNode()
            }
            break
        default:
            result(FlutterMethodNotImplemented)
            break
        }
    }
    
    func onAnchorMethodCalled(_ call :FlutterMethodCall, _ result: @escaping FlutterResult) {
        let arguments = call.arguments as? Dictionary<String, Any>
        
        switch call.method {
        case "init":
            self.objectManagerChannel.invokeMethod("onError", arguments: ["ObjectTEST from iOS"])
            result(nil)
            break
        case "addAnchor":
            if let type = arguments!["type"] as? Int {
                switch type {
                case 0: //Plane Anchor
                    if let transform = arguments!["transformation"] as? Array<NSNumber>, let name = arguments!["name"] as? String {
                        addPlaneAnchor(transform: transform, name: name)
                        result(true)
                    }
                    result(false)
                    break
                default:
                    result(false)
                    
                }
            }
            result(nil)
            break
        case "removeAnchor":
            if let name = arguments!["name"] as? String {
                deleteAnchor(anchorName: name)
            }
            break
        default:
            result(FlutterMethodNotImplemented)
            break
        }
    }
    
    func initializeARView(arguments: Dictionary<String,Any>, result: FlutterResult){
        // Set plane detection configuration
        self.configuration = ARWorldTrackingConfiguration()
        self.configuration.environmentTexturing = .automatic
        if let planeDetectionConfig = arguments["planeDetectionConfig"] as? Int {
            switch planeDetectionConfig {
            case 1: 
                configuration.planeDetection = .horizontal
                
            case 2: 
                if #available(iOS 11.3, *) {
                    configuration.planeDetection = .vertical
                }
            case 3: 
                if #available(iOS 11.3, *) {
                    configuration.planeDetection = [.horizontal, .vertical]
                }
            default: 
                configuration.planeDetection = []
            }
        }
        
        // Set plane rendering options
        if let configShowPlanes = arguments["showPlanes"] as? Bool {
            showPlanes = configShowPlanes
            if (showPlanes){
                // Visualize currently tracked planes
                for plane in trackedPlanes.values {
                    plane.0.addChildNode(plane.1)
                }
            } else {
                // Remove currently visualized planes
                for plane in trackedPlanes.values {
                    plane.1.removeFromParentNode()
                }
            }
        }
        if let configCustomPlaneTexturePath = arguments["customPlaneTexturePath"] as? String {
            customPlaneTexturePath = configCustomPlaneTexturePath
        }
        
        // Set debug options
        var debugOptions = ARSCNDebugOptions().rawValue
        if let showFeaturePoints = arguments["showFeaturePoints"] as? Bool {
            if (showFeaturePoints) {
                debugOptions |= ARSCNDebugOptions.showFeaturePoints.rawValue
            }
        }
        if let showWorldOrigin = arguments["showWorldOrigin"] as? Bool {
            if (showWorldOrigin) {
                debugOptions |= ARSCNDebugOptions.showWorldOrigin.rawValue
            }
        }
        self.sceneView.debugOptions = ARSCNDebugOptions(rawValue: debugOptions)
        
        if let configHandleTaps = arguments["handleTaps"] as? Bool {
            if (configHandleTaps){
                let tapGestureRecognizer = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
                tapGestureRecognizer.delegate = self
                self.sceneView.gestureRecognizers?.append(tapGestureRecognizer)
            }
        }
        
        if let configHandlePans = arguments["handlePans"] as? Bool {
            if (configHandlePans){
                let panGestureRecognizer = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
                panGestureRecognizer.maximumNumberOfTouches = 1
                panGestureRecognizer.delegate = self
                self.sceneView.gestureRecognizers?.append(panGestureRecognizer)
            }
        }
        
        if let configHandlePinch = arguments["handlePinch"] as? Bool {
            if (configHandlePinch) {
                pinchMinScale = Float((arguments["minScale"] as? Double) ?? 0.5)
                pinchMaxScale = Float((arguments["maxScale"] as? Double) ?? 4.0)
                let pinchGestureRecognizer = UIPinchGestureRecognizer(target: self, action: #selector(handlePinch(_:)))
                pinchGestureRecognizer.delegate = self
                self.sceneView.gestureRecognizers?.append(pinchGestureRecognizer)
            }
        }
        
        if let configHandleRotation = arguments["handleRotation"] as? Bool {
            if (configHandleRotation){
                let rotationGestureRecognizer = UIRotationGestureRecognizer(target: self, action: #selector(handleRotation(_:)))
                rotationGestureRecognizer.delegate = self
                self.sceneView.gestureRecognizers?.append(rotationGestureRecognizer)
            }
        }
        
        // Add coaching view
        if let configShowAnimatedGuide = arguments["showAnimatedGuide"] as? Bool {
            if configShowAnimatedGuide {
                if self.sceneView.superview != nil && self.coachingView.superview == nil {
                    self.sceneView.addSubview(self.coachingView)
                    //            self.coachingView.translatesAutoresizingMaskIntoConstraints = false
                    self.coachingView.autoresizingMask = [
                        .flexibleWidth, .flexibleHeight
                    ]
                    self.coachingView.session = self.sceneView.session
                    self.coachingView.activatesAutomatically = true
                    if configuration.planeDetection == .horizontal {
                        self.coachingView.goal = .horizontalPlane
                    } else if configuration.planeDetection == .vertical {
                        self.coachingView.goal = .verticalPlane
                    } else {
                        self.coachingView.goal = .anyPlane
                    }
                    // TODO: look into constraints issue. This causes a crash:
                    /**
                     Terminating app due to uncaught exception 'NSGenericException', reason: 'Unable to activate constraint with anchors <NSLayoutXAxisAnchor:0x28342dec0 "ARCoachingOverlayView:0x13a470ae0.centerX"> and <NSLayoutXAxisAnchor:0x28342c680 "FlutterTouchInterceptingView:0x10bad1c90.centerX"> because they have no common ancestor.  Does the constraint or its anchors reference items in different view hierarchies?  That's illegal.'
                     */
                    //            NSLayoutConstraint.activate([
                    //                self.coachingView.centerXAnchor.constraint(equalTo: self.sceneView.superview!.centerXAnchor),
                    //                self.coachingView.centerYAnchor.constraint(equalTo: self.sceneView.superview!.centerYAnchor),
                    //                self.coachingView.widthAnchor.constraint(equalTo: self.sceneView.superview!.widthAnchor),
                    //                self.coachingView.heightAnchor.constraint(equalTo: self.sceneView.superview!.heightAnchor)
                    //                ])
                }
            }
        }
        
        // Update session configuration
        self.sceneView.session.run(configuration)
    }
    
    func renderer(_ renderer: SCNSceneRenderer, didAdd node: SCNNode, for anchor: ARAnchor) {
        
        if let planeAnchor = anchor as? ARPlaneAnchor{
            let plane = modelBuilder.makePlane(anchor: planeAnchor, flutterAssetFile: customPlaneTexturePath)
            trackedPlanes[anchor.identifier] = (node, plane)
            if (showPlanes) {
                node.addChildNode(plane)
                self.removeAnimatedGuide()
                
                DispatchQueue.main.async {
                    self.sessionManagerChannel.invokeMethod("onDetectPlane", arguments: ["find plane of x:\(node.position.x) y:\(node.position.y) z:\(node.position.z)"])
                }
            }
        }
    }
    
    func renderer(_ renderer: SCNSceneRenderer, didUpdate node: SCNNode, for anchor: ARAnchor) {
        
        if let planeAnchor = anchor as? ARPlaneAnchor, let plane = trackedPlanes[anchor.identifier] {
            modelBuilder.updatePlaneNode(planeNode: plane.1, anchor: planeAnchor)
        }
    }
    
    func renderer(_ renderer: SCNSceneRenderer, didRemove node: SCNNode, for anchor: ARAnchor) {
        trackedPlanes.removeValue(forKey: anchor.identifier)
    }
    
    func removeAnimatedGuide() {
        DispatchQueue.main.async {
            self.coachingView.removeFromSuperview()
        }
    }
    
    func addNode(dict_node: Dictionary<String, Any>, dict_anchor: Dictionary<String, Any>? = nil) -> Future<Bool, Never> {
        
        return Future {promise in
            
            switch (dict_node["type"] as! Int) {
            case 0: // GLTF2 Model from Flutter asset folder
                // Get path to given Flutter asset
                let key = FlutterDartProject.lookupKey(forAsset: dict_node["uri"] as! String)
                // Add object to scene
                if let node: SCNNode = self.modelBuilder.makeNodeFromGltf(name: dict_node["name"] as! String, modelPath: key, transformation: dict_node["transformation"] as? Array<NSNumber>) {
                    if let anchorName = dict_anchor?["name"] as? String, let anchorType = dict_anchor?["type"] as? Int {
                        switch anchorType{
                        case 0: //PlaneAnchor
                            if let anchor = self.anchorCollection[anchorName]{
                                // Attach node to the top-level node of the specified anchor
                                self.sceneView.node(for: anchor)?.addChildNode(node)
                                promise(.success(true))
                            } else {
                                promise(.success(false))
                            }
                        default:
                            promise(.success(false))
                        }
                        
                    } else {
                        // Attach to top-level node of the scene
                        self.sceneView.scene.rootNode.addChildNode(node)
                        promise(.success(true))
                    }
                    promise(.success(false))
                } else {
                    self.sessionManagerChannel.invokeMethod("onError", arguments: ["Unable to load renderable \(dict_node["uri"] as! String)"])
                    promise(.success(false))
                }
                break
            case 1: // GLB Model from the web
                // Add object to scene
                self.modelBuilder.makeNodeFromWebGlb(name: dict_node["name"] as! String, modelURL: dict_node["uri"] as! String, transformation: dict_node["transformation"] as? Array<NSNumber>)
                    .sink(receiveCompletion: {
                        completion in print("Async Model Downloading Task completed: ", completion)
                    }, receiveValue: { val in
                        if let node: SCNNode = val {
                            if let anchorName = dict_anchor?["name"] as? String, let anchorType = dict_anchor?["type"] as? Int {
                                switch anchorType{
                                case 0: //PlaneAnchor
                                    if let anchor = self.anchorCollection[anchorName]{
                                        // Attach node to the top-level node of the specified anchor
                                        self.sceneView.node(for: anchor)?.addChildNode(node)
                                        promise(.success(true))
                                    } else {
                                        promise(.success(false))
                                    }
                                default:
                                    promise(.success(false))
                                }
                                
                            } else {
                                // Attach to top-level node of the scene
                                self.sceneView.scene.rootNode.addChildNode(node)
                                promise(.success(true))
                            }
                            promise(.success(false))
                        } else {
                            self.sessionManagerChannel.invokeMethod("onError", arguments: ["Unable to load renderable \(dict_node["name"] as! String)"])
                            promise(.success(false))
                        }
                    }).store(in: &self.cancellableCollection)
                break
            case 2: // GLB Model from the app's documents folder
                // Get path to given file system asset
                let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
                let documentsDirectory = paths[0]
                let targetPath = documentsDirectory.appendingPathComponent(dict_node["uri"] as! String).path
                
                // Add object to scene
                if let node: SCNNode = self.modelBuilder.makeNodeFromFileSystemGLB(name: dict_node["name"] as! String, modelPath: targetPath, transformation: dict_node["transformation"] as? Array<NSNumber>) {
                    if let anchorName = dict_anchor?["name"] as? String, let anchorType = dict_anchor?["type"] as? Int {
                        switch anchorType{
                        case 0: //PlaneAnchor
                            if let anchor = self.anchorCollection[anchorName]{
                                // Attach node to the top-level node of the specified anchor
                                self.sceneView.node(for: anchor)?.addChildNode(node)
                                promise(.success(true))
                            } else {
                                promise(.success(false))
                            }
                        default:
                            promise(.success(false))
                        }
                        
                    } else {
                        // Attach to top-level node of the scene
                        self.sceneView.scene.rootNode.addChildNode(node)
                        promise(.success(true))
                    }
                    promise(.success(false))
                } else {
                    self.sessionManagerChannel.invokeMethod("onError", arguments: ["Unable to load renderable \(dict_node["uri"] as! String)"])
                    promise(.success(false))
                }
                break
            case 3: //fileSystemAppFolderGLTF2
                // Get path to given file system asset
                let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
                let documentsDirectory = paths[0]
                let targetPath = documentsDirectory.appendingPathComponent(dict_node["uri"] as! String).path
                
                // Add object to scene
                if let node: SCNNode = self.modelBuilder.makeNodeFromFileSystemGltf(name: dict_node["name"] as! String, modelPath: targetPath, transformation: dict_node["transformation"] as? Array<NSNumber>) {
                    if let anchorName = dict_anchor?["name"] as? String, let anchorType = dict_anchor?["type"] as? Int {
                        switch anchorType{
                        case 0: //PlaneAnchor
                            if let anchor = self.anchorCollection[anchorName]{
                                // Attach node to the top-level node of the specified anchor
                                self.sceneView.node(for: anchor)?.addChildNode(node)
                                promise(.success(true))
                            } else {
                                promise(.success(false))
                            }
                        default:
                            promise(.success(false))
                        }
                        
                    } else {
                        // Attach to top-level node of the scene
                        self.sceneView.scene.rootNode.addChildNode(node)
                        promise(.success(true))
                    }
                    promise(.success(false))
                } else {
                    self.sessionManagerChannel.invokeMethod("onError", arguments: ["Unable to load renderable \(dict_node["uri"] as! String)"])
                    promise(.success(false))
                }
                break
            case 4: // Image
                // Add object to scene
                let img = FlutterArCoreImage(map: dict_node["data"] as! [String : Any])
                if let node: SCNNode = self.modelBuilder.makeNodeFromImage(name: dict_node["name"] as! String, imageData: img.data, transformation: dict_node["transformation"] as? Array<NSNumber>) {
                    if let anchorName = dict_anchor?["name"] as? String, let anchorType = dict_anchor?["type"] as? Int {
                        switch anchorType{
                        case 0: //PlaneAnchor
                            if let anchor = self.anchorCollection[anchorName]{
                                // Attach node to the top-level node of the specified anchor
                                self.sceneView.node(for: anchor)?.addChildNode(node)
                                promise(.success(true))
                            } else {
                                promise(.success(false))
                            }
                        default:
                            promise(.success(false))
                        }
                        
                    } else {
                        // Attach to top-level node of the scene
                        self.sceneView.scene.rootNode.addChildNode(node)
                        promise(.success(true))
                    }
                    promise(.success(false))
                } else {
                    self.sessionManagerChannel.invokeMethod("onError", arguments: ["Unable to load renderable \(dict_node["uri"] as! String)"])
                    promise(.success(false))
                }
                break
            default:
                promise(.success(false))
            }
            
        }
    }
    
    func transformNode(name: String, transform: Array<NSNumber>) {
        let node = sceneView.scene.rootNode.childNode(withName: name, recursively: true)
        node?.transform = deserializeMatrix4(transform)
    }
    
    @objc func handleTap(_ recognizer: UITapGestureRecognizer) {
        guard let sceneView = recognizer.view as? ARSCNView else {
            return
        }
        let touchLocation = recognizer.location(in: sceneView)
        
        let allHitResults = sceneView.hitTest(touchLocation, options: [SCNHitTestOption.searchMode : SCNHitTestSearchMode.closest.rawValue])
        // Because 3D model loading can lead to composed nodes, we have to traverse through a node's parent until the parent node with the name assigned by the Flutter API is found
        let nodeHitResults: Array<String> = allHitResults.compactMap { nearestParentWithNameStart(node: $0.node, characters: "[#")?.name }
        if (nodeHitResults.count != 0) {
            self.objectManagerChannel.invokeMethod("onNodeTap", arguments: Array(Set(nodeHitResults))) // Chaining of Array and Set is used to remove duplicates
            return
        }
        
        let planeTypes: ARHitTestResult.ResultType
        if #available(iOS 11.3, *){
            planeTypes = ARHitTestResult.ResultType([.existingPlaneUsingGeometry, .featurePoint])
        }else {
            planeTypes = ARHitTestResult.ResultType([.existingPlaneUsingExtent, .featurePoint])
        }
        
        let planeAndPointHitResults = sceneView.hitTest(touchLocation, types: planeTypes)
        
        // store the alignment of the tapped plane anchor so we can refer to is later when transforming the node
        if planeAndPointHitResults.count > 0, let hitAnchor = planeAndPointHitResults.first?.anchor as? ARPlaneAnchor {
            self.tappedPlaneAnchorAlignment = hitAnchor.alignment
        }
        
        let serializedPlaneAndPointHitResults = planeAndPointHitResults.map{serializeHitResult($0)}
        if (serializedPlaneAndPointHitResults.count != 0) {
            self.sessionManagerChannel.invokeMethod("onPlaneOrPointTap", arguments: serializedPlaneAndPointHitResults)
        }
    }
    
    @objc func handlePan(_ recognizer: UIPanGestureRecognizer) {
        guard let sceneView = recognizer.view as? ARSCNView else {
            return
        }
        
        // State Begins
        if recognizer.state == UIGestureRecognizer.State.began
        {
            panStartLocation = recognizer.location(in: sceneView)
            if let startLocation = panStartLocation {
                let allHitResults = sceneView.hitTest(startLocation, options: [SCNHitTestOption.searchMode : SCNHitTestSearchMode.closest.rawValue])
                // Because 3D model loading can lead to composed nodes, we have to traverse through a node's parent until the parent node with the name assigned by the Flutter API is found
                let nodeHitResults: Array<String> = allHitResults.compactMap {
                    if let nearestNode = nearestParentWithNameStart(node: $0.node, characters: "[#") {
                        panningNode = nearestNode
                        return nearestNode.name
                    }else{
                        return nil
                    }
                }
                if (nodeHitResults.count != 0 && panningNode != nil) {
                    panningNodeCurrentWorldLocation = panningNode!.worldPosition
                    self.objectManagerChannel.invokeMethod("onPanStart", arguments: panningNode!.name) // Chaining of Array and Set is used to remove duplicates
                    return
                }
            }
        }
        // State Changes
        if(recognizer.state == UIGestureRecognizer.State.changed)
        {
            // the velocity of the gesture is how fast it is moving. This can be used to translate the position of the node.
            panCurrentVelocity = recognizer.velocity(in: sceneView)
            panCurrentLocation = recognizer.location(in: sceneView)
            panCurrentTranslation = recognizer.translation(in: sceneView)
            
            if let panLoc = panCurrentLocation, let panNode = panningNode {
                if let query = sceneView.raycastQuery(from: panLoc, allowing: .existingPlaneInfinite, alignment: .any) {
                    guard let result = self.sceneView.session.raycast(query).first else {
                        return
                    }
                    let posX = result.worldTransform.columns.3.x - panNode.position.x
                    let posY = result.worldTransform.columns.3.y - panNode.position.y
                    let posZ = result.worldTransform.columns.3.z - panNode.position.z
                    panNode.parent?.worldPosition = SCNVector3(posX, posY, posZ)
                }
                self.objectManagerChannel.invokeMethod("onPanChange", arguments: panNode.name)
            }
        }
        // State Ended
        if(recognizer.state == UIGestureRecognizer.State.ended)
        {
            // kill variables
            panStartLocation = nil
            panCurrentLocation = nil
            self.objectManagerChannel.invokeMethod("onPanEnd", arguments: serializeLocalTransformation(node: panningNode))
            panningNode = nil
        }
    }
    
    @objc func handlePinch(_ gesture: UIPinchGestureRecognizer) {
        guard let sceneView = gesture.view as? ARSCNView else { return }
        
        // 获取捏合手势的缩放因子
        let scale = Float(gesture.scale)
        
        if gesture.state == .began {
            // find current screen nodes
            //            let screenCenterPoint = CGPoint(x: sceneView.bounds.midX, y: sceneView.bounds.midY)
            //            let hitTestResults = sceneView.hitTest(screenCenterPoint, options: nil)
            //
            //            for result in hitTestResults {
            //                let node = result.node
            //                print("Found node: \(node.name ?? "")")
            //            }
            pinchBeginScale = scale
            let touchPoint = gesture.location(in: sceneView)
            let allHitResults = sceneView.hitTest(touchPoint, options: [SCNHitTestOption.searchMode : SCNHitTestSearchMode.closest.rawValue, SCNHitTestOption.boundingBoxOnly: true])
            let nodeHitResults: Array<String> = allHitResults.compactMap {
                if let nearestNode = nearestParentWithNameStart(node: $0.node, characters: "[#") {
                    pinchNode = nearestNode
                    return nearestNode.name
                }else{
                    return nil
                }
            }
            if (nodeHitResults.count != 0 && pinchNode != nil) {
                self.objectManagerChannel.invokeMethod("onPinchStart", arguments: pinchNode!.name) // Chaining of Array and Set is used to remove duplicates
                return
            }
        }
        
        if gesture.state == .changed {
            if pinchNode != nil {
                let nowScale = pinchNode?.parent?.scale ?? SCNVector3(0, 0, 0)
                if pinchBeginScale == nil {
                    pinchBeginScale = scale
                }
                var newScale = SCNVector3(nowScale.x + scale - pinchBeginScale! , nowScale.y - pinchBeginScale! + scale, nowScale.z - pinchBeginScale! + scale)
                pinchBeginScale = scale
                if newScale.x < pinchMinScale {
                    newScale = SCNVector3(x: pinchMinScale, y: pinchMinScale, z: pinchMinScale)
                } else if newScale.y > pinchMaxScale {
                    newScale = SCNVector3(x: pinchMaxScale, y: pinchMaxScale, z: pinchMaxScale)
                }
                pinchNode!.parent?.scale = newScale
                self.objectManagerChannel.invokeMethod("onPinchChange", arguments: pinchNode!.name)
            }
        }
        
        if gesture.state == .ended {
            pinchBeginScale = nil
            self.objectManagerChannel.invokeMethod("onPinchEnd", arguments: serializeLocalTransformation(node: pinchNode))
            pinchNode = nil
        }
    }
    
    @objc func handleRotation(_ recognizer: UIRotationGestureRecognizer) {
        guard let sceneView = recognizer.view as? ARSCNView else {
            return
        }
        
        // State Begins
        if recognizer.state == UIGestureRecognizer.State.began
        {
            rotationStartLocation = recognizer.location(in: sceneView)
            if let startLocation = rotationStartLocation {
                let allHitResults = sceneView.hitTest(startLocation, options: [SCNHitTestOption.searchMode : SCNHitTestSearchMode.closest.rawValue])
                // Because 3D model loading can lead to composed nodes, we have to traverse through a node's parent until the parent node with the name assigned by the Flutter API is found
                let nodeHitResults: Array<String> = allHitResults.compactMap {
                    if let nearestNode = nearestParentWithNameStart(node: $0.node, characters: "[#") {
                        panningNode = nearestNode
                        return nearestNode.name
                    }else{
                        return nil
                    }
                }
                if (nodeHitResults.count != 0 && panningNode != nil) {
                    self.objectManagerChannel.invokeMethod("onRotationStart", arguments: panningNode!.name) // Chaining of Array and Set is used to remove duplicates
                    return
                }
            }
        }
        // State Changes
        if(recognizer.state == UIGestureRecognizer.State.changed)
        {
            // the velocity of the gesture is how fast it is moving. This can be used to translate the position of the node.
            rotation = recognizer.rotation
            rotationVelocity = recognizer.velocity
            
            if let r = rotationVelocity, let panNode = panningNode {
                // velocity needs to be reduced substantially otherwise the rotation change seems too fast as radians; also needs inverting to match the movement of the fingers as they rotate on the screen
                let r2 = (r*0.01) * -1
                let nodeRotation = panNode.rotation
                let rotation: SCNQuaternion!
                let planeAlignment = self.tappedPlaneAnchorAlignment
                if planeAlignment == .horizontal {
                    rotation = SCNQuaternion(x: 0, y: 1, z: 0, w: nodeRotation.w+Float(r2)) // quickest way to convert screen into world positions (meters)
                }else{
                    rotation = SCNQuaternion(x: 0, y: 0, z: 1, w: nodeRotation.w+Float(r2)) // quickest way to convert screen into world positions (meters)
                }
                panNode.rotation = rotation
                self.objectManagerChannel.invokeMethod("onRotationChange", arguments: panNode.name)
            }
            
            // update position of panning node if it has been created
            // panningNode.position + the gesture delta
        }
        // State Ended
        if(recognizer.state == UIGestureRecognizer.State.ended)
        {
            // kill variables
            rotation = nil
            rotationVelocity = nil
            self.objectManagerChannel.invokeMethod("onRotationEnd", arguments: serializeLocalTransformation(node: panningNode))
            panningNode = nil
        }
        
    }
    
    // Recursive helper function to traverse a node's parents until a node with a name starting with the specified characters is found
    func nearestParentWithNameStart(node: SCNNode?, characters: String) -> SCNNode? {
        if let nodeNamePrefix = node?.name?.prefix(characters.count) {
            if (nodeNamePrefix == characters) { return node }
        }
        if let parent = node?.parent { return nearestParentWithNameStart(node: parent, characters: characters) }
        return nil
    }
    
    func addPlaneAnchor(transform: Array<NSNumber>, name: String){
        let arAnchor = ARAnchor(transform: simd_float4x4(deserializeMatrix4(transform)))
        anchorCollection[name] = arAnchor
        sceneView.session.add(anchor: arAnchor)
        // Ensure root node is added to anchor before any other function can run (if this isn't done, addNode could fail because anchor does not have a root node yet).
        // The root node is added to the anchor as soon as the async rendering loop runs once, more specifically the function "renderer(_:nodeFor:)"
        while (sceneView.node(for: arAnchor) == nil) {
            usleep(1) // wait 1 millionth of a second
        }
    }
    
    func deleteAnchor(anchorName: String) {
        if let anchor = anchorCollection[anchorName]{
            // Delete all child nodes
            if var attachedNodes = sceneView.node(for: anchor)?.childNodes {
                attachedNodes.removeAll()
            }
            // Remove anchor
            sceneView.session.remove(anchor: anchor)
            // Update bookkeeping
            anchorCollection.removeValue(forKey: anchorName)
        }
    }
}

// ---------------------- ARCoachingOverlayViewDelegate ---------------------------------------

extension IosARView: ARCoachingOverlayViewDelegate {
    
    func coachingOverlayViewWillActivate(_ coachingOverlayView: ARCoachingOverlayView){
        // use this delegate method to hide anything in the UI that could cover the coaching overlay view
    }
    
    func coachingOverlayViewDidRequestSessionReset(_ coachingOverlayView: ARCoachingOverlayView) {
        // Reset the session.
        self.sceneView.session.run(configuration, options: [.resetTracking])
    }
}
