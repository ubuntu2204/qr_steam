# qr_steam

A Flutter plugin for streaming arbitrary binary data via **animated QR codes** using either **sequential chunks** or **LT fountain codes**. Inspired by [txqr/QRStream](https://github.com/divan/txqr).

## How it works

```
Sender (Windows)                       Receiver (Android)
─────────────────                      ─────────────────
Screenshot (PNG)                       Camera preview
      │                                      │
      ▼                                      ▼
AVIF / WebP compress                 QrStreamReceiver widget
      │                  QR codes           │
      ▼          ──────────────────►        ▼
SequentialEncoder /                  SequentialDecoder /
FountainEncoder                      FountainDecoder
      │                                      │
      ▼                                      ▼
QrStreamSender widget               AVIF/WebP bytes
(animated QR display)               Image.memory(bytes)
```

`QrTransferMode.sequential` sends chunks in order and is easy to reason about.

`QrTransferMode.fountain` emits random redundant packets, so the receiver can reconstruct the original data from any sufficient subset of frames. This is a better fit for noisy/lossy camera scanning.

## Features

- 🔢 **Dual transfer modes** — sequential chunks or LT fountain packets via `QrTransferMode`
- 📸 **Windows sender** — full-screen capture → AVIF/WebP compression → animated QR
- 📷 **Android receiver** — camera scan → sequential/fountain decode → display image
- 🧩 **Modular API** — use `SequentialEncoder` / `SequentialDecoder` or `FountainEncoder` / `FountainDecoder` independently of QR

## Getting started

```yaml
dependencies:
  qr_steam:
    git:
      url: https://github.com/example/qr_steam
```

## Usage

### Sender (Windows)

```dart
import 'package:qr_steam/qr_steam.dart';

// Compress your data (e.g. AVIF screenshot) then display:
QrStreamSender(
  data: avifCompressedBytes,   // Uint8List
  fps: 8,                      // QR update rate
  size: 350,                   // widget size in logical pixels
  chunkSize: 280,              // bytes per fountain block
  mode: QrTransferMode.fountain,
)
```

### Receiver (Android)

```dart
QrStreamReceiver(
  onDecoded: (Uint8List bytes) {
    // `bytes` is the original data (AVIF/WebP image)
    setState(() => _imageBytes = bytes);
  },
  onProgress: (double progress, int packetsReceived) {
    print('${(progress * 100).toInt()}% — $packetsReceived packets');
  },
  mode: QrTransferMode.fountain,
)
```

### Sequential codec (standalone)

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

### Fountain codec (standalone)

```dart
// Encode
final encoder = FountainEncoder(data, chunkSize: 300);
final packet = encoder.nextPacket();          // FountainPacket
final qrString = packet.toBase64Url();        // put in QR code

// Decode
final decoder = FountainDecoder();
final isComplete = decoder.addPacket(
  FountainPacket.fromBase64Url(scannedString),
);
if (isComplete) {
  final original = decoder.decodedData!;
}
```

## Example app

The `example/` directory contains a full Flutter app:

| Platform | Behaviour |
|----------|-----------|
| Windows  | Capture screen → AVIF/WebP compress → sequential or fountain QR stream |
| Android  | Camera → scan QR frames → sequential or fountain decode → display image |
| Others   | Home page with navigation to both demos |

### Running

```bash
# Windows sender
cd example
flutter run -d windows

# Android receiver
flutter run -d <android-device>
```

### Android requirements

- `minSdkVersion 29` (required by `flutter_image_compress` AVIF support)
- Camera permission granted at runtime

### Windows requirements

- `screen_capturer` requires no special setup on Windows 10/11.
- On Windows 10 1903+ the OS may prompt for screen recording consent.

## Packet wire format

```
Offset  Size  Field
──────  ────  ─────────────────────────────────────────
0       4     Magic: 0x51535452 ('QSTR')
4       1     Version: 0x01
5       4     Total data length (uint32 big-endian)
9       2     Number of source chunks k (uint16)
11      2     Chunk size in bytes (uint16)
13      4     Sequence / PRNG seed (uint32)
17      2     Degree – how many source blocks XOR-ed (uint16)
19      N     XOR-ed payload (N = chunk size)
```

The packet is base64url-encoded and stored as the QR code's text payload.

## LT codes algorithm

1. **Split** data into *k* source blocks of equal size.
2. **Encode**: for each output packet with sequence *seq*:
   - Sample degree *d* from the Robust Soliton Distribution using `Random(seq)`.
   - Sample *d* unique source block indices using `Random(seq ^ 0xDEADBEEF)`.
   - XOR the *d* blocks together → payload.
3. **Decode** (belief propagation / peeling):
   - Find degree-1 packets → recover source block.
   - XOR recovered block into all other packets that reference it (reducing their degree).
   - Repeat until all *k* blocks are recovered.

With the Robust Soliton Distribution, decoding succeeds with high probability after receiving ≈ *1.05 k* packets.

## License

MIT
