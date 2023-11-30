//
//  FlutterArCoreImage.swift
//  ar_flutter_plugin
//
//  Created by 郭士君 on 2023/11/28.
//

import Foundation

class FlutterArCoreImage {
    let width: Double
    let height: Double
    let data: Data
    
    init(map: [String: Any]) {
        self.width = Double(truncating: map["width"] as? NSNumber ?? 0.0)
        self.height = Double(truncating: map["height"] as? NSNumber ?? 0.0)
        self.data = (map["bytes"] as? FlutterStandardTypedData)?.data ?? Data()
    }
}
