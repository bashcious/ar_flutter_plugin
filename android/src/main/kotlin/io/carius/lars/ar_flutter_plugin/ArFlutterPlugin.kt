package io.carius.lars.ar_flutter_plugin

import android.content.Context
import android.util.Log
import androidx.annotation.NonNull
import com.google.ar.core.ArCoreApk
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result

/** ArFlutterPlugin */
class ArFlutterPlugin : FlutterPlugin, MethodCallHandler, ActivityAware {
  /// The MethodChannel that will the communication between Flutter and native Android
  ///
  /// This local reference serves to register the plugin with the Flutter Engine and unregister it
  /// when the Flutter Engine is detached from the Activity
  private lateinit var channel: MethodChannel
  private lateinit var flutterPluginBinding: FlutterPlugin.FlutterPluginBinding
  private lateinit var context: Context

  override fun onAttachedToEngine(
      @NonNull flutterPluginBinding: FlutterPlugin.FlutterPluginBinding
  ) {
    channel = MethodChannel(flutterPluginBinding.binaryMessenger, "ar_flutter_plugin")
    channel.setMethodCallHandler(this)

    this.flutterPluginBinding = flutterPluginBinding
    context = this.flutterPluginBinding.applicationContext
  }

  override fun onMethodCall(@NonNull call: MethodCall, @NonNull result: Result) {
    if (call.method == "getPlatformVersion") {
      result.success("Android ${android.os.Build.VERSION.RELEASE}")
    } else if (call.method == "isSupport") {
      val value = when (ArCoreApk.getInstance().checkAvailability(context)) {
        ArCoreApk.Availability.SUPPORTED_INSTALLED -> true // 设备支持且已安装 ARCore
        ArCoreApk.Availability.SUPPORTED_APK_TOO_OLD,
        ArCoreApk.Availability.SUPPORTED_NOT_INSTALLED -> {
          // 设备支持但未安装 ARCore，或 ARCore 版本过旧
          // 可以提示用户安装或更新 ARCore
          false
        }
        else -> false // 设备不支持 ARCore
      }
      result.success(value)
    }
    else {
      result.notImplemented()
    }
  }

  override fun onDetachedFromEngine(@NonNull binding: FlutterPlugin.FlutterPluginBinding) {
    channel.setMethodCallHandler(null)
  }

  override fun onDetachedFromActivity() {
    channel.setMethodCallHandler(null)
  }

  override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
    onAttachedToActivity(binding)
  }

  override fun onAttachedToActivity(binding: ActivityPluginBinding) {
    this.flutterPluginBinding.platformViewRegistry.registerViewFactory(
        "ar_flutter_plugin", AndroidARViewFactory(binding.activity, flutterPluginBinding.binaryMessenger))
  }

  override fun onDetachedFromActivityForConfigChanges() {
    onDetachedFromActivity()
  }
}
