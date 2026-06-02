import 'package:permission_handler/permission_handler.dart' as ph;

/// 原生平台（Android / iOS）的权限请求服务。
class CameraPermissionService {
  static Future<bool> requestCameraPermission() async {
    final status = await ph.Permission.camera.request();
    return status.isGranted;
  }

  static Future<void> openSettings() async {
    await ph.openAppSettings();
  }
}
