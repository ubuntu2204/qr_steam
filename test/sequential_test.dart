import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:qr_steam/qr_steam.dart';

void main() {
  Uint8List makeData(int size) =>
      Uint8List.fromList(List.generate(size, (i) => (i * 19 + 11) % 256));

  group('SequentialPacket', () {
    test('round-trips through bytes and base64url', () {
      final packet = SequentialPacket(
        totalLength: 1024,
        numChunks: 4,
        chunkSize: 300,
        chunkIndex: 2,
        data: Uint8List.fromList(List.generate(124, (i) => i)),
      );

      final restored = SequentialPacket.fromBytes(packet.toBytes());
      expect(restored.totalLength, packet.totalLength);
      expect(restored.numChunks, packet.numChunks);
      expect(restored.chunkSize, packet.chunkSize);
      expect(restored.chunkIndex, packet.chunkIndex);
      expect(restored.data, packet.data);

      final fromBase64 = SequentialPacket.fromBase64Url(packet.toBase64Url());
      expect(fromBase64.chunkIndex, packet.chunkIndex);
      expect(fromBase64.data, packet.data);
    });
  });

  group('SequentialEncoder + SequentialDecoder', () {
    test('round-trips after receiving one full cycle', () {
      final original = makeData(1337);
      final encoder = SequentialEncoder(original, chunkSize: 200);
      final decoder = SequentialDecoder();

      bool done = false;
      for (int i = 0; i < encoder.numChunks; i++) {
        done = decoder.addPacket(encoder.nextPacket());
      }

      expect(done, isTrue);
      expect(decoder.decodedData, equals(original));
    });

    test('decoder ignores duplicate packets after a chunk is known', () {
      final original = makeData(900);
      final encoder = SequentialEncoder(original, chunkSize: 150);
      final decoder = SequentialDecoder();

      final first = encoder.nextPacket();
      decoder.addPacket(first);
      decoder.addPacket(first);
      expect(decoder.receivedCount, 1);

      bool done = false;
      for (int i = 1; i < encoder.numChunks && !done; i++) {
        done = decoder.addPacket(encoder.nextPacket());
      }

      expect(done, isTrue);
      expect(decoder.decodedData, equals(original));
    });

    test('reset clears progress for reuse', () {
      final original = makeData(512);
      final encoder = SequentialEncoder(original, chunkSize: 128);
      final decoder = SequentialDecoder();

      decoder.addPacket(encoder.nextPacket());
      expect(decoder.progress, greaterThan(0));

      decoder.reset();
      expect(decoder.progress, 0.0);
      expect(decoder.isComplete, isFalse);
      expect(decoder.decodedData, isNull);
    });
  });
}
