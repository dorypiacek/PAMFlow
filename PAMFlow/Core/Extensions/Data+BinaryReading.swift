//
//  Data+BinaryReading.swift
//  PAMFlow
//
//  Created by Dory on 12/08/2026.
//

import Foundation

extension Data {
    nonisolated func readInt32(at offset: Int) -> Int32? {
        guard offset >= 0, offset + 4 <= count else { return nil }
        let value = (UInt32(self[offset]) << 24)
            | (UInt32(self[offset + 1]) << 16)
            | (UInt32(self[offset + 2]) << 8)
            | UInt32(self[offset + 3])
        return Int32(bitPattern: value)
    }

    nonisolated func readInt64(at offset: Int) -> Int64? {
        guard offset >= 0, offset + 8 <= count else { return nil }
        var value: UInt64 = 0
        for byteOffset in 0..<8 {
            value = (value << 8) | UInt64(self[offset + byteOffset])
        }
        return Int64(bitPattern: value)
    }
}

extension Data.SubSequence {
    nonisolated func readInt32(atRelativeOffset relativeOffset: Int) -> Int32? {
        let offset = startIndex + relativeOffset
        guard relativeOffset >= 0, offset + 4 <= endIndex else { return nil }
        let value = (UInt32(self[offset]) << 24)
            | (UInt32(self[offset + 1]) << 16)
            | (UInt32(self[offset + 2]) << 8)
            | UInt32(self[offset + 3])
        return Int32(bitPattern: value)
    }

    nonisolated func readInt64(atRelativeOffset relativeOffset: Int) -> Int64? {
        let offset = startIndex + relativeOffset
        guard relativeOffset >= 0, offset + 8 <= endIndex else { return nil }
        var value: UInt64 = 0
        for byteOffset in 0..<8 {
            value = (value << 8) | UInt64(self[offset + byteOffset])
        }
        return Int64(bitPattern: value)
    }

    nonisolated func readInt32(offset: inout Int) -> Int32? {
        guard offset + 4 <= endIndex else { return nil }
        let value = (UInt32(self[offset]) << 24)
            | (UInt32(self[offset + 1]) << 16)
            | (UInt32(self[offset + 2]) << 8)
            | UInt32(self[offset + 3])
        offset += 4
        return Int32(bitPattern: value)
    }

    nonisolated func readInt64(offset: inout Int) -> Int64? {
        guard offset + 8 <= endIndex else { return nil }
        var value: UInt64 = 0
        for byteOffset in 0..<8 {
            value = (value << 8) | UInt64(self[offset + byteOffset])
        }
        offset += 8
        return Int64(bitPattern: value)
    }

    nonisolated func readJavaUTF(offset: inout Int) -> String? {
        guard let length = readUInt16(offset: &offset),
              offset + Int(length) <= endIndex else {
            return nil
        }
        let end = offset + Int(length)
        let value = String(data: Data(self[offset..<end]), encoding: .utf8)
        offset = end
        return value
    }

    nonisolated var hexString: String {
        map { String(format: "%02x", $0) }.joined()
    }

    nonisolated private func readUInt16(offset: inout Int) -> UInt16? {
        guard offset + 2 <= endIndex else { return nil }
        let value = (UInt16(self[offset]) << 8) | UInt16(self[offset + 1])
        offset += 2
        return value
    }
}
