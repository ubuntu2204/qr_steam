# qr_steam

一个通过**动态 QR 码**传输任意二进制数据的 Flutter 插件，支持 **顺序分片** 与 **LT 喷泉码** 两种模式。灵感来源于 [txqr/QRStream](https://github.com/divan/txqr)。

## 工作原理

```
发送端（Windows）                          接收端（Android）
─────────────────                         ─────────────────
截取屏幕 (PNG)                             摄像头预览
      │                                         │
      ▼                                         ▼
AVIF / HEIC 压缩                        QrStreamReceiver 组件
      │                  QR 码流                │
      ▼         ───────────────────────►        ▼
SequentialEncoder /                     SequentialDecoder /
FountainEncoder                         FountainDecoder
      │                                         │
      ▼                                         ▼
QrStreamSender 组件                     AVIF/HEIC 字节
（动态 QR 显示）                         Image.memory(bytes)
```

### 两种模式的区别

`QrTransferMode.sequential`：按块顺序循环发送，逻辑简单，适合调试或稳定场景。

`QrTransferMode.fountain`：随机发送冗余包，接收方不需要按顺序看到所有帧，更适合真实摄像头扫描环境。

理论上，喷泉码在接收约 **1.05k** 帧（k = 源数据块总数）后即可成功解码，冗余率仅约 5%。

## 特性

- 🔢 **双传输模式** — `QrTransferMode` 支持顺序分片和 LT 喷泉码
- 📸 **Windows 发送端** — 截屏 → AVIF/HEIC 压缩 → 动态 QR 码
- 📷 **Android 接收端** — 摄像头扫描 → 顺序分片/喷泉码解码 → 显示图片
- 🧩 **模块化 API** — `SequentialEncoder` / `SequentialDecoder` 与 `FountainEncoder` / `FountainDecoder` 都可独立于 QR 使用
- 🖼️ **AVIF 全平台支持** — 通过 `flutter_avif` 在 Windows/Android/iOS 上均可编解码
- 🔄 **HEIC/AVIF 可切换** — 发送端设置面板中一键切换压缩格式

## 安装

在 `pubspec.yaml` 中添加：

```yaml
dependencies:
  qr_steam:
    git:
      url: https://github.com/example/qr_steam
```

## 使用方法

### 发送端（Windows）

```dart
import 'package:qr_steam/qr_steam.dart';

// 将压缩后的数据（如 AVIF 截图）传入组件显示：
QrStreamSender(
  data: avifCompressedBytes,   // Uint8List
  fps: 8,                      // QR 码刷新帧率
  size: 350,                   // 组件尺寸（逻辑像素）
  chunkSize: 280,              // 每个喷泉码源块的字节数
  mode: QrTransferMode.fountain,
)
```

### 接收端（Android）

```dart
QrStreamReceiver(
  onDecoded: (Uint8List bytes) {
    // bytes 即为原始数据（AVIF/HEIC 图片）
    setState(() => _imageBytes = bytes);
  },
  onProgress: (double progress, int packetsReceived) {
    print('${(progress * 100).toInt()}% — 已接收 $packetsReceived 帧');
  },
  mode: QrTransferMode.fountain,
)
```

### 单独使用顺序分片编解码器

```dart
final encoder = SequentialEncoder(data, chunkSize: 300);
final packet = encoder.nextPacket();
final qrString = packet.toBase64Url();

final decoder = SequentialDecoder();
final isComplete = decoder.addPacket(
  SequentialPacket.fromBase64Url(scannedString),
);
if (isComplete) {
  final original = decoder.decodedData!;
}
```

### 单独使用喷泉码编解码器

```dart
// 编码
final encoder = FountainEncoder(data, chunkSize: 300);
final packet = encoder.nextPacket();          // 获取一个 FountainPacket
final qrString = packet.toBase64Url();        // 写入 QR 码

// 解码
final decoder = FountainDecoder();
final isComplete = decoder.addPacket(
  FountainPacket.fromBase64Url(scannedString),
);
if (isComplete) {
  final original = decoder.decodedData!;
}
```

## Example 示例应用

`example/` 目录包含一个完整的 Flutter 示例应用：

| 平台      | 行为                                          |
|---------|---------------------------------------------|
| Windows | 截屏 → AVIF/HEIC 压缩 → 顺序分片或喷泉码动态 QR |
| Android | 摄像头扫描 QR 帧 → 顺序分片或喷泉码解码 → 显示图片 |
| 其他     | 首页，可导航到发送端或接收端演示                  |

### 运行示例

```bash
# Windows 发送端
cd example
flutter run -d windows

# Android 接收端
flutter run -d <android-device-id>
```

### Android 要求

- `minSdkVersion 29`（`flutter_image_compress` HEIC 支持要求）
- 运行时授予摄像头权限

### Windows 要求

- `screen_capturer` 在 Windows 10/11 上无需额外配置
- Windows 10 1903+ 首次截屏时系统可能弹出屏幕录制授权提示

## 数据包格式

每个喷泉码数据包的二进制线路格式（大端序，固定 19 字节头部 + 载荷）：

```
偏移   大小   字段
────   ────   ───────────────────────────────────────────
0      4      魔数：0x51535452（ASCII: 'QSTR'）
4      1      版本号：0x01
5      4      总数据长度 uint32（原始字节数）
9      2      源块总数 k uint16
11     2      块大小 uint16（每块字节数）
13     4      序列号 / PRNG 种子 uint32
17     2      度数 uint16（异或了几个源块）
19     N      XOR 载荷（N = 块大小字节数）
```

整个数据包经 base64url 编码后作为 QR 码的文本内容。

## LT 码算法原理

1. **分割**：将原始数据分成 *k* 个等长源块。
2. **编码**：对序列号为 *seq* 的每个输出数据包：
   - 用 `Random(seq)` 从鲁棒孤子分布中采样度数 *d*。
   - 用 `Random(seq ^ 0xDEADBEEF)` 采样 *d* 个唯一源块下标。
   - 将 *d* 个源块按位 XOR → 载荷。
3. **解码**（置信传播 / 剥离算法）：
   - 找到度数为 1 的数据包 → 直接恢复对应源块。
   - 将已恢复的源块 XOR 进所有引用它的数据包（度数减 1）。
   - 重复直到所有 *k* 个源块恢复完毕。

在鲁棒孤子分布下，接收约 *1.05k* 个数据包后解码成功概率极高。

## 项目结构

```
lib/
  qr_steam.dart                  # 库入口，统一导出
  src/
    fountain/
      fountain_encoder.dart      # LT 喷泉码编码器
      fountain_decoder.dart      # LT 喷泉码解码器（置信传播）
      fountain_packet.dart       # 数据包序列化 / 反序列化
      soliton.dart               # 鲁棒孤子分布实现
    widgets/
      qr_stream_sender.dart      # 发送端 Flutter 组件
      qr_stream_receiver.dart    # 接收端 Flutter 组件

example/
  lib/
    main.dart                    # 应用入口，平台路由
    pages/
      home_page.dart             # 首页（非 Windows/Android 平台）
      sender_page.dart           # 发送端页面（Windows）
      receiver_page.dart         # 接收端页面（Android）
    services/
      image_service.dart         # 截图 + AVIF/HEIC 压缩服务
```

## 许可证

BSD 3-Clause，详见仓库根目录下的 LICENSE。
