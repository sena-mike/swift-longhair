import CLonghair
import Longhair
import Foundation
import Testing

@Test func verifyAPICompat() throws {
  print("CAUCHY_256_VERSION: \(CAUCHY_256_VERSION)")
  if _cauchy_256_init(CAUCHY_256_VERSION) != 0 {
    Issue.record("Cauchy 256 init failed")
  }
}

@Test func verifyEncode() throws {
  let source = Data(repeating: 0xFF, count: 1024)
  let dataBlocks = generateDataBlocks(from: source, blockSize: 128)

  let recoveryBlocks = Cauchy256.encode(dataBlocks: dataBlocks, recoveryBlockCount: 2)

  let blocks = dataBlocks.enumerated().map { Cauchy256.Block(data: $0.element, row: UInt8($0.offset))}
  let recoveryBlocks2 = recoveryBlocks.enumerated().map { Cauchy256.Block(data: $0.element.data, row: UInt8($0.offset + dataBlocks.count))}
  let result = try Cauchy256.decode(blocks: blocks + recoveryBlocks2, recoveryBlockCount: Int32(recoveryBlocks.count))

  #expect(source == result)
}

@Test func verifyDecodeRecoversSingleMissingBlock() throws {
  let sources = [Data(repeating: 0xFF, count: 1024), Data.random(size: 1024)]
  for source in sources {
    let dataBlocks = generateDataBlocks(from: source, blockSize: 128)

    let recoveryBlocks = Cauchy256.encode(dataBlocks: dataBlocks, recoveryBlockCount: 2)
    let missingIndex = 3
    let blocks = dataBlocks.enumerated().map { idx, blockData in
      Cauchy256.Block(data: idx == missingIndex ? nil : blockData, row: UInt8(idx))
    }
    #expect(blocks[3].data == nil)
    let result = try Cauchy256.decode(blocks: blocks + recoveryBlocks, recoveryBlockCount: Int32(recoveryBlocks.count))

    #expect(source == result)
  }
}

@Test func verifyDecodeRecoversTwoMissingBlocks() throws {
  let source = Data(repeating: 0xFF, count: 1024)
  let dataBlocks = generateDataBlocks(from: source, blockSize: 128)

  let recoveryBlocks = Cauchy256.encode(dataBlocks: dataBlocks, recoveryBlockCount: 2)
  let missingIndices: Set<Int> = [1, 4]
  let enumeratedBlocks = dataBlocks.enumerated().map { idx, blockData in
    Cauchy256.Block(data: missingIndices.contains(idx) ? nil : blockData, row: UInt8(idx))
  }
  let result = try Cauchy256.decode(blocks: enumeratedBlocks + recoveryBlocks, recoveryBlockCount: Int32(recoveryBlocks.count))

  #expect(source == result)
}

@Test func stressDecodeAllMissingCombinations() throws {
  let blockCount = 8
  let recoveryCount = 2
  let bytesPerBlock = 128
  let totalBytes = blockCount * bytesPerBlock
  let source = Data((0..<totalBytes).map { UInt8($0 & 0xFF) })
  var dataBlocks = [Data]()
  for i in stride(from: 0, to: source.count, by: bytesPerBlock) {
    let start = source.index(source.startIndex, offsetBy: i)
    let end = source.index(source.startIndex, offsetBy: i + bytesPerBlock)
    dataBlocks.append(source[start..<end])
  }

  let recoveryBlocks = Cauchy256.encode(dataBlocks: dataBlocks, recoveryBlockCount: recoveryCount)
  for missingIndex in 0..<blockCount {
    let blocks = (0..<blockCount).map { idx in
      Cauchy256.Block(data: idx == missingIndex ? nil : dataBlocks[idx], row: UInt8(idx))
    }
    let result1 = try Cauchy256.decode(blocks: blocks + recoveryBlocks, recoveryBlockCount: Int32(recoveryCount))
    #expect(source == result1)
  }
  for i in 0..<(blockCount - 1) {
    for j in (i + 1)..<blockCount {
      let missing = Set([i, j])
      let blocks = (0..<blockCount).map { idx in
        Cauchy256.Block(data: missing.contains(idx) ? nil : dataBlocks[idx], row: UInt8(idx))
      }
      let result2 = try Cauchy256.decode(blocks: blocks + recoveryBlocks, recoveryBlockCount: Int32(recoveryCount))
      #expect(source == result2)
    }
  }
}

@Test func verifyDecodeWithPermutedBlockOrder() throws {
  let source = Data(repeating: 0xFF, count: 1024)
  let dataBlocks = generateDataBlocks(from: source, blockSize: 128)

  let recoveryBlocks = Cauchy256.encode(dataBlocks: dataBlocks, recoveryBlockCount: 2)
  let missingIndex = 5
  let convertedBlocks = dataBlocks.enumerated().map { idx, blockData in
    Cauchy256.Block(data: idx == missingIndex ? nil : blockData, row: UInt8(idx))
  }

  let permutedOrder = Array(convertedBlocks.reversed()) + recoveryBlocks.reversed()
  let result = try Cauchy256.decode(blocks: permutedOrder, recoveryBlockCount: Int32(recoveryBlocks.count))
  #expect(source == result)
}

@Test func stressDecodeRepeatedMemoryLeakTest() throws {
  for _ in 0..<1_000 {
    autoreleasepool {
      let blockCount = 8
      let recoveryCount = 2
      let bytesPerBlock = 128
      let totalBytes = blockCount * bytesPerBlock
      let source = Data((0..<totalBytes).map { UInt8($0 & 0xFF) })
      var dataBlocks = [Data]()
      for i in stride(from: 0, to: source.count, by: bytesPerBlock) {
        let start = source.index(source.startIndex, offsetBy: i)
        let end = source.index(source.startIndex, offsetBy: i + bytesPerBlock)
        dataBlocks.append(source[start..<end])
      }

      let recoveryBlocks = Cauchy256.encode(dataBlocks: dataBlocks, recoveryBlockCount: recoveryCount)
      let missingIndex = Int.random(in: 0..<blockCount)
      let blocks = (0..<blockCount).map { idx in
        Cauchy256.Block(data: idx == missingIndex ? nil : dataBlocks[idx], row: UInt8(idx))
      }
      let result = try! Cauchy256.decode(blocks: blocks + recoveryBlocks, recoveryBlockCount: Int32(recoveryCount))
      #expect(source == result)
    }
  }
}

extension Data {
  struct HexEncodingOptions: OptionSet {
    let rawValue: Int
    static let upperCase = HexEncodingOptions(rawValue: 1 << 0)
  }

  func hexEncodedString(options: HexEncodingOptions = []) -> String {
    let format = options.contains(.upperCase) ? "%02hhX" : "%02hhx"
    return self.map { String(format: format, $0) }.joined()
  }

  static func random(size: Int) -> Data {
    return Data((0..<size).map { _ in UInt8.random(in: 0...255) })
  }
}

func generateDataBlocks(from source: Data, blockSize: Int) -> [Data] {
  var dataBlocks = [Data]()
  for i in stride(from: 0, to: source.count, by: blockSize) {
    let start = source.index(source.startIndex, offsetBy: i)
    let end = source.index(source.startIndex, offsetBy: i + blockSize)
    dataBlocks.append(source[start..<end])
  }
  return dataBlocks
}
