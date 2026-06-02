/// 平台感知的权限请求服务。
/// Web 平台：摄像头权限由浏览器在首次访问时自动请求，无需预先请求。
/// 原生平台：使用 permission_handler。
library;

export 'permission_service_stub.dart'
    if (dart.library.io) 'permission_service_native.dart';
