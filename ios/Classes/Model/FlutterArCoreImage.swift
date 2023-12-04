//
//  FlutterArCoreImage.swift
//  ar_flutter_plugin
//
//  Created by 郭士君 on 2023/11/28.
//

import Foundation

class FlutterArCoreImage {
    let data: Data
    
    init(map: [String: Any]) {
        self.data = (map["bytes"] as? FlutterStandardTypedData)?.data ?? Data()
    }
}
