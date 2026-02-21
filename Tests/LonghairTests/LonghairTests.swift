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

@Test func verifyLosslessTransferDoesDecodeToOriginal() throws {
  let sources = [Data(repeating: 0xFF, count: 1024), Data.random(size: 1024)]
  for source in sources {

    // Slice up the source into equal sized blocks
    let dataBlocks = generateDataBlocks(from: source, blockSize: 128)
    // Compute the original and recovery blocks with Cauchy256
    let encodedBlocks = try Cauchy256.encode(dataBlocks: dataBlocks, recoveryBlockCount: 2)

    // Verify we get the original data back even with lossless transmission
    let result = try Cauchy256.decode(
      blocks: encodedBlocks,
      recoveryBlockCount: 2
    )

    #expect(source == result)
  }
}

@Test func verifyDecodeRecoversSingleMissingBlock() throws {
  let sources = [Data(repeating: 0xFF, count: 1024), Data.random(size: 1024)]
  for source in sources {

    // Slice up the source into equal sized blocks
    let dataBlocks = generateDataBlocks(from: source, blockSize: 128)

    var blocks = try Cauchy256.encode(dataBlocks: dataBlocks, recoveryBlockCount: 2)
    blocks[3].data = nil
    #expect(blocks[3].data == nil)
    let result = try Cauchy256.decode(
      blocks: blocks,
      recoveryBlockCount: 2
    )
    #expect(source == result)
  }
}

@Test func verifyDecodeRecoversTwoMissingBlocks() throws {
  let source = Data(repeating: 0xFF, count: 1024)
  let dataBlocks = generateDataBlocks(from: source, blockSize: 128)

  var blocks = try Cauchy256.encode(dataBlocks: dataBlocks, recoveryBlockCount: 2)
  let missingIndices: Set<Int> = [1, 4]
  for idx in missingIndices { blocks[idx].data = nil }
  let result = try Cauchy256.decode(
    blocks: blocks,
    recoveryBlockCount: 2
  )
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

  let encodedBlocks = try Cauchy256.encode(dataBlocks: dataBlocks, recoveryBlockCount: recoveryCount)
  for missingIndex in 0..<blockCount {
    var blocks = encodedBlocks
    blocks[missingIndex].data = nil
    let result1 = try Cauchy256.decode(blocks: blocks, recoveryBlockCount: Int32(recoveryCount))
    #expect(source == result1)
  }
  for i in 0..<(blockCount - 1) {
    for j in (i + 1)..<blockCount {
      var blocks = encodedBlocks
      blocks[i].data = nil
      blocks[j].data = nil
      let result2 = try Cauchy256.decode(blocks: blocks, recoveryBlockCount: Int32(recoveryCount))
      #expect(source == result2)
    }
  }
}

@Test func verifyDecodeWithPermutedBlockOrder() throws {
  let source = Data(repeating: 0xFF, count: 1024)
  let dataBlocks = generateDataBlocks(from: source, blockSize: 128)

  var blocks = try Cauchy256.encode(dataBlocks: dataBlocks, recoveryBlockCount: 2)
  let missingIndex = 5
  blocks[missingIndex].data = nil

  let permutedOrder = Array(blocks.reversed())
  let result = try Cauchy256.decode(blocks: permutedOrder, recoveryBlockCount: 2)
  #expect(source == result)
}

@Test func stressDecodeRepeatedMemoryLeakTest() throws {
  for _ in 0..<1_000 {
#if canImport(Darwin)
    try autoreleasepool {
      try runStressDecodeIteration()
    }
#else
    try runStressDecodeIteration()
#endif
  }
}

private func runStressDecodeIteration() throws {
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

  var blocks = try Cauchy256.encode(dataBlocks: dataBlocks, recoveryBlockCount: recoveryCount)
  let missingIndex = Int.random(in: 0..<blockCount)
  blocks[missingIndex].data = nil
  let result = try Cauchy256.decode(blocks: blocks, recoveryBlockCount: Int32(recoveryCount))
  #expect(source == result)
}


#if os(Linux)
@Test func stressDecodeMemoryGrowthRemainsBoundedOnLinux() throws {
  for _ in 0..<200 {
    try runStressDecodeIteration()
  }

  let startRSS = try currentResidentMemoryBytesLinux()

  for _ in 0..<4_000 {
    try runStressDecodeIteration()
  }

  let endRSS = try currentResidentMemoryBytesLinux()
  let growth = endRSS - startRSS
  let maxAllowedGrowth = 64 * 1024 * 1024
  #expect(growth < maxAllowedGrowth)
}

private func currentResidentMemoryBytesLinux() throws -> Int {
  let status = try String(contentsOfFile: "/proc/self/status", encoding: .utf8)
  guard let vmRSSLine = status.split(separator: "\n").first(where: { $0.hasPrefix("VmRSS:") }) else {
    throw LonghairError.invalidBlockCount
  }

  let fields = vmRSSLine.split(whereSeparator: { $0 == " " || $0 == "\t" })
  guard fields.count >= 2, let rssInKB = Int(fields[1]) else {
    throw LonghairError.invalidBlockCount
  }

  return rssInKB * 1024
}
#endif

@Test func testDecodingFailed() throws {
  let source = Data.random(size: 1024)
  let dataBlocks = generateDataBlocks(from: source, blockSize: 128)

  var blocks = try Cauchy256.encode(dataBlocks: dataBlocks, recoveryBlockCount: 2)
  for idx in 0..<dataBlocks.count { blocks[idx].data = nil }
  #expect(throws: LonghairError.notEnoughtBlocksToDecode) {
    try Cauchy256.decode(
      blocks: blocks,
      recoveryBlockCount: 2
    )
  }
}

@Test func testEncodeNoBlocksProvided() throws {
  #expect(throws: LonghairError.noBlocksProvided) {
    try Cauchy256.encode(dataBlocks: [], recoveryBlockCount: 1)
  }
}

@Test func testEncodeBlockSizeNotMultipleOf8() throws {
  let data = Data(repeating: 0, count: 7)
  #expect(throws: LonghairError.invalidBlockSize) {
    try Cauchy256.encode(dataBlocks: [data], recoveryBlockCount: 1)
  }
}

@Test func testEncodeInconsistentBlockSizes() throws {
  let data1 = Data(repeating: 0, count: 8)
  let data2 = Data(repeating: 0, count: 16)
  #expect(throws: LonghairError.inconsistentBlockSizes) {
    try Cauchy256.encode(dataBlocks: [data1, data2], recoveryBlockCount: 0)
  }
}

@Test func testEncodeTooManyBlocks() throws {
  let block = Data(repeating: 0, count: 8)
  let dataBlocks = Array(repeating: block, count: 256)
  #expect(throws: LonghairError.tooManyBlocks) {
    try Cauchy256.encode(dataBlocks: dataBlocks, recoveryBlockCount: 1)
  }
}

@Test func testDecodeNoBlocks() throws {
  #expect(throws: LonghairError.invalidBlockCount) {
    try Cauchy256.decode(blocks: [], recoveryBlockCount: 0)
  }
}

@Test func testDecodeNegativeRecoveryCount() throws {
  let data = Data(repeating: 0, count: 8)
  let block = Cauchy256.Block(data: data, row: 0)
  #expect(throws: LonghairError.invalidBlockCount) {
    try Cauchy256.decode(blocks: [block], recoveryBlockCount: -1)
  }
}

@Test func testDecodeBlockCountMismatch() throws {
  let data = Data(repeating: 0, count: 8)
  let block = Cauchy256.Block(data: data, row: 0)
  #expect(throws: LonghairError.invalidBlockCount) {
    try Cauchy256.decode(blocks: [block], recoveryBlockCount: 2)
  }
}

@Test func testDecodeInvalidBlockSize() throws {
  let data1 = Data(repeating: 0, count: 8)
  let data2 = Data(repeating: 0, count: 16)
  let blocks = [Cauchy256.Block(data: data1, row: 0), Cauchy256.Block(data: data2, row: 1)]

  #expect(throws: LonghairError.inconsistentBlockSizes) {
    try Cauchy256.decode(blocks: blocks, recoveryBlockCount: 0)
  }
}

@Test func testDecodeBlockSizeNotMultipleOf8() throws {
  let data = Data(repeating: 0, count: 7)
  let block = Cauchy256.Block(data: data, row: 0)
  #expect(throws: LonghairError.invalidBlockSize) {
    try Cauchy256.decode(blocks: [block], recoveryBlockCount: 0)
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
