import 'dart:convert';
import 'dart:typed_data';

/// 一个 RaptorQ-inspired 编码数据包，可嵌入 QR 码。
///
/// 二进制线路格式（大端序，固定 20 字节头部 + 载荷）：
/// ```
/// [0..3]   magic     : 0x51535251  (ASCII: 'QSRQ')
/// [4]      version   : 0x01
/// [5..8]   totalLen  : uint32  – 原始数据总字节数
/// [9..10]  numChunks : uint16  – k（源块总数）
/// [11..12] chunkSize : uint16  – 单块字节数
/// [13..16] seqNo     : uint32  – 序列号
/// [17]     flags     : uint8   – 位0: isRepair (1=修复包, 0=系统包)
/// [18..19] degree    : uint16  – XOR 了几个源块（仅修复包有效）
/// [20..N]  data      : chunkSize 字节 – 载荷
/// ```
class RaptorQPacket {
  static const int _magic = 0x51535251; // 'QSRQ'
  static const int _version = 1;
  static const int headerSize = 20;

  final int totalLength;
  final int numChunks;
  final int chunkSize;
  final int seqNo;
  final bool isRepair; // true=修复符号, false=系统符号（原始数据块）
  final int degree;
  final Uint8List data;

  const RaptorQPacket({
    required this.totalLength,
    required this.numChunks,
    required this.chunkSize,
    required this.seqNo,
    required this.isRepair,
    required this.degree,
    required this.data,
  });

  Uint8List toBytes() {
    final buf = Uint8List(headerSize + data.length);
    final bd = ByteData.view(buf.buffer);
    bd.setUint32(0, _magic);
    bd.setUint8(4, _version);
    bd.setUint32(5, totalLength);
    bd.setUint16(9, numChunks);
    bd.setUint16(11, chunkSize);
    bd.setUint32(13, seqNo);
    bd.setUint8(17, isRepair ? 1 : 0);
    bd.setUint16(18, degree);
    buf.setRange(headerSize, buf.length, data);
    return buf;
  }

  String toBase64Url() => base64Url.encode(toBytes());

  factory RaptorQPacket.fromBytes(Uint8List bytes) {
    if (bytes.length < headerSize) throw const FormatException('Too short');
    final bd = ByteData.view(bytes.buffer, bytes.offsetInBytes);
    if (bd.getUint32(0) != _magic) throw const FormatException('Bad magic');
    if (bd.getUint8(4) != _version) throw const FormatException('Bad version');
    final totalLength = bd.getUint32(5);
    final numChunks = bd.getUint16(9);
    final chunkSize = bd.getUint16(11);
    final seqNo = bd.getUint32(13);
    final isRepair = bd.getUint8(17) == 1;
    final degree = bd.getUint16(18);
    final data = bytes.sublist(headerSize);
    return RaptorQPacket(
      totalLength: totalLength,
      numChunks: numChunks,
      chunkSize: chunkSize,
      seqNo: seqNo,
      isRepair: isRepair,
      degree: degree,
      data: data,
    );
  }

  factory RaptorQPacket.fromBase64Url(String s) =>
      RaptorQPacket.fromBytes(base64Url.decode(s));
}
