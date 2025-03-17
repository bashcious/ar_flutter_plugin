import 'dart:math';

import 'package:ar_flutter_plugin/ar_flutter_plugin.dart';
import 'package:ar_flutter_plugin/datatypes/config_planedetection.dart';
import 'package:ar_flutter_plugin/widgets/ar_view.dart';
import 'package:flutter/material.dart';
import 'package:ar_flutter_plugin/datatypes/hittest_result_types.dart';
import 'package:ar_flutter_plugin/datatypes/node_types.dart';
import 'package:ar_flutter_plugin/managers/ar_anchor_manager.dart';
import 'package:ar_flutter_plugin/managers/ar_location_manager.dart';
import 'package:ar_flutter_plugin/managers/ar_object_manager.dart';
import 'package:ar_flutter_plugin/managers/ar_session_manager.dart';
import 'package:ar_flutter_plugin/models/ar_anchor.dart';
import 'package:ar_flutter_plugin/models/ar_hittest_result.dart';
import 'package:ar_flutter_plugin/models/ar_node.dart';
import 'package:vector_math/vector_math_64.dart' hide Colors;

class ArPage extends StatefulWidget {
  const ArPage({super.key});

  @override
  State<ArPage> createState() => _ArPageState();
}

enum ARStatus {
  checkPlane, // 检查平面tip
  clickPlane, // 点击平面tip
  tip, // 显示拖拽tip
  scale, // 显示缩放tip
  none,
}

class _ArPageState extends State<ArPage> {
  ARSessionManager? arSessionManager;
  ARObjectManager? arObjectManager;
  ARAnchorManager? arAnchorManager;

  /// AR操作中的状态
  ARStatus status = ARStatus.none;
  List<ARNode> nodes = [];
  List<ARAnchor> anchors = [];

  @override
  void initState() {
    super.initState();
  }

  void onPanStarted(String nodeName) {
    print('jingluo 开始onPanStarted');
  }

  double calculateRotationAngle(Matrix4 matrix) {
    // 提取 Matrix4 的旋转部分
    Matrix3 rotationMatrix = Matrix3.zero();
    matrix.copyRotation(rotationMatrix);

    // 计算旋转矩阵的第一列和世界坐标系 Y 轴的夹角
    Vector3 column1 = Vector3(rotationMatrix.entry(0, 0),
        rotationMatrix.entry(1, 0), rotationMatrix.entry(2, 0));
    Vector3 worldYAxis = Vector3(-1, 0, 0);
    double rotationAngle = column1.angleTo(worldYAxis);
    return rotationAngle;
  }

  void onPlaneOrPointTapped(List<ARHitTestResult> hitTestResults) async {
    ARHitTestResult? singleHitTestResult;
    for (var hitTestResult in hitTestResults) {
      if (hitTestResult.type == ARHitTestResultType.plane) {
        singleHitTestResult = hitTestResult;
        break;
      }
    }
    if (singleHitTestResult == null) return;
    double rotationAngle =
        calculateRotationAngle(singleHitTestResult.worldTransform);
    singleHitTestResult.worldTransform.rotateX(rotationAngle);
    var newAnchor =
        ARPlaneAnchor(transformation: singleHitTestResult.worldTransform);
    bool? didAddAnchor = await arAnchorManager!.addAnchor(newAnchor);
    if (didAddAnchor == true) {
      anchors.add(newAnchor);
      String fileName = 'assets/obj/Chicken_01/Chicken_01.gltf';
      double nodeScale = 0.2;

      var newNode = ARNode(
        type: NodeType.localGLTF2,
        uri: fileName,
        parentName: "test",
        position: Vector3(0, 0, 0),
        // rotation: Vector4(1.0, 0, 0, 0),
        scale: Vector3(nodeScale, nodeScale, nodeScale),
      );
      var rotation = Matrix3.rotationY(50);
      Matrix3 rotationZ = Matrix3.rotationZ(pi);
      rotation *= rotationZ;
      newNode.rotation = rotation;
      bool? didAddNodeToAnchor =
          await arObjectManager!.addNode(newNode, planeAnchor: newAnchor);
      if (didAddNodeToAnchor!) {
        arObjectManager?.togglePlaneRenderer();
        nodes.add(newNode);
      } else {
        arSessionManager!.onError("Adding Node to Anchor failed");
      }
    } else {
      arSessionManager!.onError("Adding Anchor failed");
    }
  }

  void onARViewCreated(
      ARSessionManager arSessionManager,
      ARObjectManager arObjectManager,
      ARAnchorManager arAnchorManager,
      ARLocationManager arLocationManager) {
    this.arSessionManager = arSessionManager;
    this.arObjectManager = arObjectManager;
    this.arAnchorManager = arAnchorManager;

    this.arSessionManager!.onInitialize(
          showAnimatedGuide: true,
          showPlanes: true,
          showWorldOrigin: false,
          handlePans: true,
          handleRotation: false,
          handlePinch: true,
        );
    this.arObjectManager!.onInitialize();

    this.arSessionManager!.onPlaneOrPointTap = onPlaneOrPointTapped;
    this.arSessionManager!.onDetectPlane = () {
      if (status.index < ARStatus.clickPlane.index) {
        status = ARStatus.clickPlane;
        setState(() {});
      }
    };
    this.arObjectManager!.onPanStart = onPanStarted;
    this.arObjectManager!.onPinchStart = (_) {
      if (status.index <= ARStatus.scale.index) {
        status = ARStatus.none;
        setState(() {});
      }
    };
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
        appBar: AppBar(
          backgroundColor: Theme.of(context).colorScheme.inversePrimary,
          title: const Text("ar Page"),
        ),
        body: SizedBox(
          width: double.infinity,
          height: double.infinity,
          // Center is a layout widget. It takes a single child and positions it
          // in the middle of the parent.
          child: ARView(
            onARViewCreated: onARViewCreated,
            planeDetectionConfig: PlaneDetectionConfig.horizontalAndVertical,
          ),
        ));
  }
}
