import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:qr_steam/qr_steam.dart';

void main() {
  group('RaptorQPacket', () {
    test('round-trips through toBytes / fromBytes', () {
      final data = Uint8List.fromList(List.generate(300, (i) => i & 0xFF));
      final pkt = RaptorQPacket(
        totalLength: 1234,
        numChunks: 5,
        chunkSize: 300,
        seqNo: 42,
        isRepair: true,
        degree: 3,
        data: data,
      );
      final restored = RaptorQPacket.fromBytes(pkt.toBytes());
      expect(restored.totalLength, equals(pkt.totalLength));
      expect(restored.numChunks, equals(pkt.numChunks));
      expect(restored.seqNo, equals(pkt.seqNo));
      expect(restored.isRepair, equals(pkt.isRepair));
      expect(restored.degree, equals(pkt.degree));
      expect(restored.data, equals(pkt.data));
    });

    test('round-trips through base64url', () {
      final data = Uint8List(100);
      final pkt = RaptorQPacket(
        totalLength: 100,
        numChunks: 1,
        chunkSize: 100,
        seqNo: 0,
        isRepair: false,
        degree: 1,
        data: data,
      );
      final restored = RaptorQPacket.fromBase64Url(pkt.toBase64Url());
      expect(restored.seqNo, equals(0));
      expect(restored.isRepair, isFalse);
    });
  });

  group('RaptorQEncoder + RaptorQDecoder', () {
    Uint8List _makeData(int size) =>
        Uint8List.fromList(List.generate(size, (i) => (i * 37 + 13) & 0xFF));

    void _roundTrip(int dataSize, int chunkSize) {
      final original = _makeData(dataSize);
      final encoder = RaptorQEncoder(original, chunkSize: chunkSize);
      final decoder = RaptorQDecoder();

      // 最多发送 k * 2 个包（理论上 k + ε 足够）
      final maxPkts = encoder.numChunks * 2 + 20;
      for (int i = 0; i < maxPkts; i++) {
        final pkt = encoder.nextPacket();
        if (decoder.addPacket(pkt)) break;
      }

      expect(decoder.isComplete, isTrue,
          reason: 'dataSize=$dataSize chunkSize=$chunkSize');
      expect(decoder.decodedData, equals(original));
    }

    test('tiny data (< 1 chunk)', () => _roundTrip(50, 300));
    test('data exactly one chunk', () => _roundTrip(300, 300));
    test('small data (5 chunks)', () => _roundTrip(1500, 300));
    test('medium data (20 chunks)', () => _roundTrip(6000, 300));
    test('system symbols (first k pkts) should be enough if no loss', () {
      final original = _makeData(600);
      final encoder = RaptorQEncoder(original, chunkSize: 300);
      final decoder = RaptorQDecoder();
      // Only send system symbols (first numChunks packets)
      for (int i = 0; i < encoder.numChunks; i++) {
        decoder.addPacket(encoder.nextPacket());
      }
      expect(decoder.isComplete, isTrue);
      expect(decoder.decodedData, equals(original));
    });

    test('decoder reset allows reuse', () {
      final data = _makeData(600);
      final encoder = RaptorQEncoder(data, chunkSize: 300);
      final decoder = RaptorQDecoder();
      for (int i = 0; i < encoder.numChunks + 5; i++) {
        if (decoder.addPacket(encoder.nextPacket())) break;
      }
      expect(decoder.isComplete, isTrue);
      decoder.reset();
      expect(decoder.isComplete, isFalse);
      expect(decoder.decodedData, isNull);
    });
  });
}
