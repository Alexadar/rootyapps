import Foundation

/// Minimal ZIP container writer: STORED entries only (no compression), fixed DOS timestamp
/// (1980-01-01 00:00) so identical input yields identical bytes. Pure, stateless.
/// Oracle = PKWARE APPNOTE.TXT (ZIP file format specification), sections 4.3.7–4.3.16.
enum Zip {

    struct Entry {
        let name: String   // forward-slash path, ASCII/UTF-8
        let data: Data
    }

    static func archive(_ entries: [Entry]) -> Data {
        var out = Data()
        var central = Data()
        var count: UInt16 = 0
        let dosDate: UInt16 = 0x0021  // 1980-01-01
        let dosTime: UInt16 = 0

        for entry in entries {
            let name = Data(entry.name.utf8)
            let crc = crc32(entry.data)
            let size = UInt32(entry.data.count)
            let offset = UInt32(out.count)

            // Local file header (4.3.7)
            out.appendLE(UInt32(0x0403_4b50))
            out.appendLE(UInt16(20))          // version needed
            out.appendLE(UInt16(0))           // flags
            out.appendLE(UInt16(0))           // method: stored
            out.appendLE(dosTime)
            out.appendLE(dosDate)
            out.appendLE(crc)
            out.appendLE(size)                // compressed
            out.appendLE(size)                // uncompressed
            out.appendLE(UInt16(name.count))
            out.appendLE(UInt16(0))           // extra len
            out.append(name)
            out.append(entry.data)

            // Central directory record (4.3.12)
            central.appendLE(UInt32(0x0201_4b50))
            central.appendLE(UInt16(20))      // version made by
            central.appendLE(UInt16(20))      // version needed
            central.appendLE(UInt16(0))       // flags
            central.appendLE(UInt16(0))       // method
            central.appendLE(dosTime)
            central.appendLE(dosDate)
            central.appendLE(crc)
            central.appendLE(size)
            central.appendLE(size)
            central.appendLE(UInt16(name.count))
            central.appendLE(UInt16(0))       // extra
            central.appendLE(UInt16(0))       // comment
            central.appendLE(UInt16(0))       // disk start
            central.appendLE(UInt16(0))       // internal attrs
            central.appendLE(UInt32(0))       // external attrs
            central.appendLE(offset)
            central.append(name)
            count += 1
        }

        let cdOffset = UInt32(out.count)
        out.append(central)

        // End of central directory (4.3.16)
        out.appendLE(UInt32(0x0605_4b50))
        out.appendLE(UInt16(0))               // this disk
        out.appendLE(UInt16(0))               // cd disk
        out.appendLE(count)
        out.appendLE(count)
        out.appendLE(UInt32(central.count))
        out.appendLE(cdOffset)
        out.appendLE(UInt16(0))               // comment len
        return out
    }

    /// CRC-32, IEEE 802.3 polynomial (reflected 0xEDB88320) — the ZIP standard CRC.
    /// Standard check value: crc32("123456789") == 0xCBF43926.
    static func crc32(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFF_FFFF
        for byte in data {
            crc ^= UInt32(byte)
            for _ in 0..<8 {
                crc = (crc & 1) != 0 ? (crc >> 1) ^ 0xEDB8_8320 : crc >> 1
            }
        }
        return ~crc
    }
}

extension Data {
    mutating func appendLE(_ v: UInt16) {
        append(UInt8(v & 0xFF)); append(UInt8(v >> 8))
    }
    mutating func appendLE(_ v: UInt32) {
        append(UInt8(v & 0xFF)); append(UInt8((v >> 8) & 0xFF))
        append(UInt8((v >> 16) & 0xFF)); append(UInt8(v >> 24))
    }
}
