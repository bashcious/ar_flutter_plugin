import Flutter
import UIKit
import ARKit

public class SwiftArFlutterPlugin: NSObject, FlutterPlugin {
    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(name: "ar_flutter_plugin", binaryMessenger: registrar.messenger())
        let instance = SwiftArFlutterPlugin()
        registrar.addMethodCallDelegate(instance, channel: channel)
        
        let factory = IosARViewFactory(messenger: registrar.messenger())
        registrar.register(factory, withId: "ar_flutter_plugin")
    }
    
    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        if (call.method == "getPlatformVersion") {
            result("iOS " + UIDevice.current.systemVersion)
        } else if (call.method == "isSupport") {
            var res = ARConfiguration.isSupported
            result(res)
        }
    }
    
}
