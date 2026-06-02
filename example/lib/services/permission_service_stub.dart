/// Web 平台存根：摄像头权限由浏览器自动处理。
class CameraPermissionService {
  /// Web 平台始终返回已授权（权限在摄像头访问时由浏览器处理）。
  static Future<bool> requestCameraPermission() async => true;

  /// Web 平台无应用设置页，无操作。
  static Future<void> openSettings() async {}
}
