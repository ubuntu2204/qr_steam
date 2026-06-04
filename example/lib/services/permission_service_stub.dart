import 'dart:js_interop';
import 'package:web/web.dart' as web;

/// Web 平台权限服务：通过浏览器 Permissions API 和 getUserMedia 检测摄像头权限。
///
/// 注意：getUserMedia 始终在主线程（UI 线程）调用，WASM 工作线程
/// 不会直接访问 MediaDevices，避免跨线程权限隔离问题。
class CameraPermissionService {
  /// 请求摄像头权限，返回是否授权。
  ///
  /// 流程：
  /// 1. 先查询 Permissions API（navigator.permissions）获取当前状态
  /// 2. 如状态不明确，尝试调用 getUserMedia 触发浏览器权限弹窗
  /// 3. 捕获所有异常并打印详细日志
  static Future<bool> requestCameraPermission() async {
    try {
      // Step 1: 查询 Permissions API
      final status = await _queryPermissionState();
      if (status != null) {
        _log('[权限查询] Permissions API 返回状态: $status');
        if (status == 'granted') return true;
        if (status == 'denied') {
          _logErr('权限已被用户明确拒绝。请在浏览器地址栏左侧点击锁图标 → 站点设置 → 允许摄像头。');
          return false;
        }
        // status == 'prompt'：继续尝试 getUserMedia 触发弹窗
      }

      // Step 2: 通过 getUserMedia 实际请求权限
      _log('[权限请求] 调用 getUserMedia 请求摄像头权限...');
      final stream = await _getUserMedia();
      if (stream != null) {
        // 立即停止轨道，仅用于权限检测
        _stopStream(stream);
        _log('[权限请求] 摄像头权限已授予 ✓');

        // Step 3: 验证 enumerateDevices 能否列出设备
        await _enumerateDevices();
        return true;
      }
      return false;
    } catch (e, stack) {
      _logErr('摄像头权限请求失败: $e');
      _logErr('错误堆栈: $stack');
      _diagnoseError(e);
      return false;
    }
  }

  /// Web 平台无应用设置页，无操作。
  static Future<void> openSettings() async {}

  // ---------------------------------------------------------------------------
  // 内部辅助方法
  // ---------------------------------------------------------------------------

  /// 通过 Permissions API 查询摄像头权限状态。
  /// 返回 'granted' | 'denied' | 'prompt' | null(不支持时)。
  static Future<String?> _queryPermissionState() async {
    try {
      final permissions = web.window.navigator.permissions;
      final descriptor = {'name': 'camera'}.jsify()! as JSObject;
      final queryResult = await permissions.query(descriptor).toDart;
      return queryResult.state;
    } catch (e) {
      _log('[权限查询] Permissions API 不可用或查询失败: $e');
      return null; // 部分浏览器不支持 Permissions API 的 camera 查询
    }
  }

  /// 调用 getUserMedia 获取摄像头流。
  static Future<web.MediaStream?> _getUserMedia() async {
    try {
      final mediaDevices = web.window.navigator.mediaDevices;
      final constraints = web.MediaStreamConstraints(
        video: {'facingMode': 'environment'}.jsify()!,
        audio: false.toJS,
      );
      final stream = await mediaDevices.getUserMedia(constraints).toDart;
      return stream;
    } on web.DOMException catch (e) {
      _logErr('getUserMedia DOMException:');
      _logErr('  name: ${e.name}');
      _logErr('  message: ${e.message}');
      _logErr('  code: ${e.code}');
      return null;
    } catch (e) {
      _logErr('getUserMedia 未知异常: $e');
      return null;
    }
  }

  /// 停止 MediaStream 的所有轨道。
  static void _stopStream(web.MediaStream stream) {
    final tracks = stream.getTracks().toDart;
    for (final track in tracks) {
      track.stop();
    }
  }

  /// 枚举媒体设备并打印日志。
  static Future<void> _enumerateDevices() async {
    try {
      final devices =
          await web.window.navigator.mediaDevices.enumerateDevices().toDart;
      final deviceList = devices.toDart;
      _log('[设备枚举] 共发现 ${deviceList.length} 个媒体设备:');
      for (final d in deviceList) {
        _log('  [${d.kind}] ${d.label.isNotEmpty ? d.label : "(未授权标签)"} '
            '(deviceId: ${d.deviceId})');
      }
    } catch (e) {
      _log('[设备枚举] enumerateDevices 失败: $e');
    }
  }

  /// 根据错误类型输出诊断建议。
  static void _diagnoseError(Object e) {
    final msg = e.toString().toLowerCase();
    if (msg.contains('notallowederror') || msg.contains('permission')) {
      _logErr('[诊断] 用户拒绝了摄像头权限或浏览器策略阻止了访问。');
      _logErr('[诊断] 请确认: 1) HTTPS 环境  2) 浏览器地址栏未屏蔽摄像头  '
          '3) Permissions-Policy 头正确配置');
    } else if (msg.contains('notfounderror') || msg.contains('notreadable')) {
      _logErr('[诊断] 未检测到摄像头设备，或摄像头被其他应用占用。');
    } else if (msg.contains('notsecureerror') || msg.contains('insecure')) {
      _logErr('[诊断] 当前页面非 HTTPS，浏览器禁止访问摄像头。'
          '请使用 HTTPS 部署。');
    } else if (msg.contains('overconstrainederror')) {
      _logErr('[诊断] 摄像头约束条件无法满足（如不支持指定的分辨率）。');
    } else {
      _logErr('[诊断] 未知错误，请检查浏览器控制台获取更多信息。');
    }
  }

  static void _log(String msg) => print('[CameraPermission] $msg');
  static void _logErr(String msg) => print('[CameraPermission][ERROR] $msg');
}
