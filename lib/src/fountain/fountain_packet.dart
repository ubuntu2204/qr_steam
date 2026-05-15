import 'dart:convert';
import 'dart:typed_data';

/// 一个喷泉码编码数据包，可嵌入 QR 码。
///
/// 二进制线路格式（大端序，固定 19 字节头部 + 载荷）：
/// ```
/// [0..3]   magic     : 0x51535452  (ASCII: 'QSTR')
/// [4]      version   : 0x01
/// [5..8]   totalLen  : uint32  – 原始数据总字节数
/// [9..10]  numChunks : uint16  – k（源块总数）
/// [11..12] chunkSize : uint16  – 单块字节数
/// [13..16] seqNo     : uint32  – 序列号 / PRNG 种子
/// [17..18] degree    : uint16  – XOR 了几个源块
/// [19..N]  data      : chunkSize 字节 – XOR 结果
/// ```
class FountainPacket {
  /// 数据包魔数，ASCII 为 'QSTR'，用于判断是否为有效的 QrStream 包
  static const int _magic = 0x51535452;

  /// 数据包版本号
  static const int _version = 1;

  /// 头部固定字节数
  static const int headerSize = 19;

  /// 原始数据的总字节数
  final int totalLength;

  /// 源块总数 k
  final int numChunks;

  /// 单块字节数
  final int chunkSize;

  /// 包序列号（同时作为 PRNG 种子由解码器复现下标）
  final int seqNo;

  /// 度数：该包 XOR 了多少个源块
  final int degree;

  /// XOR 载荷（长度 = chunkSize）
  final Uint8List data;

  const FountainPacket({
    required this.totalLength,
    required this.numChunks,
    required this.chunkSize,
    required this.seqNo,
    required this.degree,
    required this.data,
  });

  // ---------------------------------------------------------------------------
  // 序列化 / 反序列化
  // ---------------------------------------------------------------------------

  /// 序列化为原始字节，用于嵌入 QR 码。
  Uint8List toBytes() {
    final buf = Uint8List(headerSize + data.length);
    final view = ByteData.sublistView(buf);

    view.setUint32(0, _magic); // 魔数 'QSTR'
    view.setUint8(4, _version); // 版本号
    view.setUint32(5, totalLength); // 总数据长度
    view.setUint16(9, numChunks); // 源块数
    view.setUint16(11, chunkSize); // 块大小
    view.setUint32(13, seqNo); // 序列号
    view.setUint16(17, degree); // 度数
    buf.setRange(headerSize, buf.length, data); // 载荷

    return buf;
  }

  /// 从原始字节反序列化。
  ///
  /// 数据无效或不支持时抛出 [FormatException]。
  factory FountainPacket.fromBytes(Uint8List bytes) {
    if (bytes.length < headerSize) {
      throw const FormatException('FountainPacket: too short');
    }

    final view = ByteData.sublistView(bytes, 0, headerSize);

    // 校验魔数
    if (view.getUint32(0) != _magic) {
      throw const FormatException('FountainPacket: bad magic');
    }
    // 校验版本号
    if (view.getUint8(4) != _version) {
      throw const FormatException('FountainPacket: unsupported version');
    }

    final totalLength = view.getUint32(5);
    final numChunks = view.getUint16(9);
    final chunkSize = view.getUint16(11);
    final seqNo = view.getUint32(13);
    final degree = view.getUint16(17);
    final data = bytes.sublist(headerSize);

    // 校验载荷长度是否匹配头部中声明的 chunkSize
    if (data.length != chunkSize) {
      throw FormatException(
        'FountainPacket: expected $chunkSize data bytes, got ${data.length}',
      );
    }

    return FountainPacket(
      totalLength: totalLength,
      numChunks: numChunks,
      chunkSize: chunkSize,
      seqNo: seqNo,
      degree: degree,
      data: data,
    );
  }

  // ---------------------------------------------------------------------------
  // Base64url 辅助方法（用于 QR 码内嵌入）
  // ---------------------------------------------------------------------------

  /// 编码为 URL-safe base64 字符串，适合嵌入 QR 码。
  String toBase64Url() => base64Url.encode(toBytes());

  /// 从 QR 码扫描到的 URL-safe base64 字符串反序列化。
  factory FountainPacket.fromBase64Url(String encoded) =>
      FountainPacket.fromBytes(base64Url.decode(encoded));

  @override
  String toString() =>
      'FountainPacket(seq=$seqNo, deg=$degree, chunks=$numChunks, '
      'chunkSize=$chunkSize, totalLen=$totalLength)';
}
