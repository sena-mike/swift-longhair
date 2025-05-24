private import CLonghair
import Foundation

public enum LonghairError: Error {
  case encodingFailed
  case decodingFailed

  // The `dataBlocks` array is empty for encoding.
  case noBlocksProvided
  case noBlocksContainData
  case notEnoughtBlocksToDecode

  // Invalid parameters for encoding
  case invalidBlockSize
  case inconsistentBlockSizes
  case tooManyBlocks

  // Invalid parameters for decoding
  case invalidBlockCount
}

public enum Cauchy256 {

  /// Represents a block of data used in the Cauchy 256 encoding/decoding process.
  ///
  /// A `Block` can either be an original data block or a recovery block. Each block
  /// is identified by its `row` value, which indicates its position in the encoding
  /// process.
  ///
  /// - Properties:
  ///   - data: The data contained in the block. This can be `nil` if the block is missing or unused.
  ///   - row: The row index of the block. For original data blocks, this is their position in the input array.
  ///          For recovery blocks, this starts at the index immediately following the last data block.
  public struct Block {
      public var data: Data?
      public var row: UInt8

      /// Initializes a new `Block` instance.
      ///
      /// - Parameters:
      ///   - data: The data for the block. Defaults to `nil` if the block is empty or missing.
      ///   - row: The row index of the block.
      public init(data: Data? = nil, row: UInt8) {
          self.data = data
          self.row = row
      }
  }

  /// This closure will run exactly once, the first time _initializer is touched.
  private static let _initializer: Void = {
    precondition(_cauchy_256_init(CAUCHY_256_VERSION) == 0)
    precondition(gf256_init_(GF256_VERSION) == 0)
  }()

  /// Encodes the given data blocks and generates recovery blocks using the Cauchy 256 algorithm.
  ///
  /// - Parameters:
  ///   - dataBlocks: An array of `Data` objects representing the original data blocks to be encoded.
  ///   - recoveryBlockCount: The number of recovery blocks to generate.
  /// - Returns: An array of `Block` representing the original data blocks followed by the recovery blocks.
  ///            Recovery blocks start at row index equal to `dataBlocks.count`.
  /// - Throws: `LonghairError.noBlocksProvided` if `dataBlocks` is empty.
  ///           `LonghairError.invalidBlockSize` if block size is not a multiple of 8.
  ///           `LonghairError.inconsistentBlockSizes` if input blocks are not the same size.
  ///           `LonghairError.tooManyBlocks` if `dataBlocks.count + recoveryBlockCount` exceeds 256.
  ///           `LonghairError.encodingFailed` if the C API encoding fails.
  public static func encode(
    dataBlocks: [Data],
    recoveryBlockCount: Int
  ) throws -> [Block] {

    // “touch” the initializer
    _ = _initializer

    guard !dataBlocks.isEmpty else { throw LonghairError.noBlocksProvided }

    let bytesPerBlock = dataBlocks[0].count
    guard bytesPerBlock % 8 == 0 else { throw LonghairError.invalidBlockSize }
    guard dataBlocks.allSatisfy({ $0.count == bytesPerBlock }) else { throw LonghairError.inconsistentBlockSizes }

    // Allocate recovery blocks
    var recoveryBuffer = Data(count: recoveryBlockCount * bytesPerBlock)

    guard dataBlocks.count + recoveryBlockCount <= 256 else { throw LonghairError.tooManyBlocks }

    var dataBlockPointers: [UnsafePointer<UInt8>?] = dataBlocks.map {
      $0.withUnsafeBytes { $0.bindMemory(to: UInt8.self).baseAddress }
    }

    let result = dataBlockPointers.withUnsafeMutableBufferPointer { pointerArray in
      recoveryBuffer.withUnsafeMutableBytes { recoveryRawBuffer in
        return cauchy_256_encode(
          Int32(dataBlocks.count),
          Int32(recoveryBlockCount),
          pointerArray.baseAddress!,
          recoveryRawBuffer.baseAddress!,
          Int32(bytesPerBlock)
        )
      }
    }
    guard result == 0 else {
      throw LonghairError.encodingFailed
    }

    // Combine original data blocks and recovery blocks
    let originalBlocks = dataBlocks.enumerated().map { index, data in
      Block(data: data, row: UInt8(index))
    }

    let recoveryBlocks = (0..<recoveryBlockCount).map { blockIndex in
      let data = recoveryBuffer.subdata(
        in: blockIndex * bytesPerBlock ..< (blockIndex + 1) * bytesPerBlock
      )
      return Block(data: data, row: UInt8(dataBlocks.count) + UInt8(blockIndex))
    }

    return originalBlocks + recoveryBlocks
  }

  /// Decodes the given blocks and reconstructs the original data using the Cauchy 256 algorithm.
  ///
  /// - Parameters:
  ///   - blocks: An array of `Block` objects containing original and/or recovery data blocks.
  ///   - recoveryBlockCount: The number of recovery blocks provided.
  /// - Returns: A `Data` object containing the reconstructed original data.
  /// - Throws: `LonghairError.invalidBlockCount` if `blocks.count` or `recoveryBlockCount` parameters are invalid.
  ///           `LonghairError.noBlocksContainData` if none of the blocks contain data.
  ///           `LonghairError.notEnoughtBlocksToDecode` if there are not enough blocks with data to decode.
  ///           `LonghairError.invalidBlockSize` if block sizes are not multiples of 8.
  ///           `LonghairError.inconsistentBlockSizes` if non-nil blocks have mismatched sizes.
  ///           `LonghairError.decodingFailed` if the C API decoding fails.
  public static func decode(blocks: [Block], recoveryBlockCount: Int32) throws -> Data {
    _ = _initializer

    let total = blocks.count
    let originalBlockCount = Int32(total) - recoveryBlockCount
    guard originalBlockCount > 0 else { throw LonghairError.invalidBlockCount }
    guard recoveryBlockCount >= 0 else { throw LonghairError.invalidBlockCount }
    guard total == Int(originalBlockCount) + Int(recoveryBlockCount) else { throw LonghairError.invalidBlockCount }
    guard originalBlockCount + recoveryBlockCount <= 256 else { throw LonghairError.invalidBlockCount }

    guard let firstData = blocks.first(where: { $0.data != nil })?.data else {
      throw LonghairError.noBlocksContainData
    }
    guard blocks.count(where: { $0.data != nil }) >= Int(originalBlockCount) else {
      throw LonghairError.notEnoughtBlocksToDecode
    }
    let bytesPerBlock = firstData.count
    guard bytesPerBlock % 8 == 0 else { throw LonghairError.invalidBlockSize }
    guard blocks.allSatisfy({ $0.data?.count == bytesPerBlock || $0.data == nil }) else {
      throw LonghairError.inconsistentBlockSizes
    }

    let blockCount = Int(originalBlockCount)
    var cBlocks = [CLonghair.Block](repeating: .init(data: nil, row: 0), count: blockCount)
    var originalCount = 0
    var recoveryCount = 0
    var blockData = Data(count: blockCount * bytesPerBlock)

    let result: Int32 = blockData.withUnsafeMutableBytes { rawBuffer in
      let basePtr = rawBuffer.baseAddress!.assumingMemoryBound(to: UInt8.self)

      for block in blocks {
        if let data = block.data, block.row < UInt8(originalBlockCount) {
          let dest = basePtr.advanced(by: originalCount * bytesPerBlock)
          data.copyBytes(to: dest, count: bytesPerBlock)
          cBlocks[originalCount] = CLonghair.Block(data: dest, row: block.row)
          originalCount += 1
        } else if let data = block.data, block.row >= UInt8(originalBlockCount), recoveryCount < Int(recoveryBlockCount) {
          recoveryCount += 1
          let dest = basePtr.advanced(by: (blockCount - recoveryCount) * bytesPerBlock)
          data.copyBytes(to: dest, count: bytesPerBlock)
          cBlocks[blockCount - recoveryCount] = CLonghair.Block(data: dest, row: block.row)
        }
      }

      return cBlocks.withUnsafeMutableBufferPointer { ptr in
        cauchy_256_decode(
          originalBlockCount,
          recoveryBlockCount,
          ptr.baseAddress!,
          Int32(bytesPerBlock)
        )
      }
    }
    guard result == 0 else {
      throw LonghairError.decodingFailed
    }

    var output = Data()
    output.reserveCapacity(Int(originalBlockCount) * bytesPerBlock)
    for originalRow in 0..<Int(originalBlockCount) {
      let idx = cBlocks.firstIndex(where: { $0.row == UInt8(originalRow) })!
      let start = idx * bytesPerBlock
      output.append(blockData.subdata(in: start ..< start + bytesPerBlock))
    }
    return output
  }

}
