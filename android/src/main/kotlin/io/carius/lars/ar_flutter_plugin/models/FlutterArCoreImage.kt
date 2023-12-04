package io.carius.lars.ar_flutter_plugin.models

class FlutterArCoreImage(map: HashMap<String, *>) {
    val bytes: ByteArray = map["bytes"] as ByteArray
}