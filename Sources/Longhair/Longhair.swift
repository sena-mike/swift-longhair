private import CLonghair
import Foundation

public enum Cauchy256 {

  /// This closure will run exactly once, the first time _initializer is touched.
  private static let _initializer: Void = {
    precondition(_cauchy_256_init(CAUCHY_256_VERSION) == 0)
    precondition(gf256_init_(GF256_VERSION) == 0)
  }()

  /// Encodes the given data blocks into recovery blocks using the Cauchy 256 algorithm.
  ///
  /// - Parameters:
  ///   - dataBlocks: An array of `Data` objects representing the original data blocks to be encoded.
  ///   - recoveryBlockCount: The number of recovery blocks to generate.
  /// - Returns: An array of `Block` representing the recovery blocks. The value of `block.row` will starts at `dataBlock.count`.
  public static func encode(
    dataBlocks: [Data],
    recoveryBlockCount: Int
  ) -> [Block] {
    // “touch” the initializer; safe to do from any thread/Task
    _ = _initializer

    precondition(!dataBlocks.isEmpty)

    let bytesPerBlock = dataBlocks[0].count
    precondition(bytesPerBlock % 8 == 0)
    precondition(dataBlocks.allSatisfy({ $0.count == bytesPerBlock }))

    // Allocate recovery blocks
    var recoveryBuffer = Data(count: recoveryBlockCount * bytesPerBlock)

    precondition(dataBlocks.count + recoveryBlockCount <= 256)

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

    precondition(result == 0)

    return (0..<recoveryBlockCount).map { blockIndex in
      let data = recoveryBuffer.subdata(
        in: blockIndex * bytesPerBlock ..< (blockIndex + 1) * bytesPerBlock
      )
      return .init(data: data, row: UInt8(dataBlocks.count) + UInt8(blockIndex))
    }
  }

  public struct Block {
    public var data: Data?
    public var row: UInt8

    public init(data: Data? = nil, row: UInt8) {
      self.data = data
      self.row = row
    }
  }

  /// Decodes the original data blocks from a mix of data and recovery blocks using the Cauchy 256 algorithm.
  ///
  /// - Parameters:
  ///   - blocks: An array of `Block` containing `k` original data blocks (some may have `.data == nil`)
  ///     and `m` recovery blocks. Each block’s `row` must be set to the block index (0..<k for original,
  ///     k..<k+m for recovery).
  ///   - recoveryBlockCount: The number of recovery blocks in `blocks`.
  /// - Throws: `DecodeError.missingData` if no block contains data;
  ///           `DecodeError.decodeFailed(code:)` if the C API decode fails.
  /// - Returns: A `Data` object containing the reconstructed original data concatenated in row order (0..<k).
  public enum DecodeError: Error {
    case missingData
    case decodeFailed(code: Int32)
  }

  public static func decode(blocks: [Block], recoveryBlockCount: Int32) throws -> Data {
    _ = _initializer

    let m = recoveryBlockCount
    let total = blocks.count
    let k = Int32(total) - m
    precondition(k > 0, "must pass at least one block")
    precondition(m >= 0, "recoveryBlockCount must be non-negative")
    precondition(total == Int(k) + Int(m), "blocks.count must equal k + m")
    precondition(k + m <= 256, "k + m must be ≤ 256")

    guard let firstData = blocks.first(where: { $0.data != nil })?.data else {
      throw DecodeError.missingData
    }
    let bytesPerBlock = firstData.count
    precondition(bytesPerBlock % 8 == 0, "bytesPerBlock must be a multiple of 8")
    precondition(
      blocks.allSatisfy({ $0.data?.count == bytesPerBlock || $0.data == nil }),
      "all non-nil blocks must have the same size"
    )

    let blockCount = Int(k)
    var cBlocks = [CLonghair.Block](repeating: .init(data: nil, row: 0), count: blockCount)
    var originalCount = 0
    var recoveryCount = 0
    var blockData = Data(count: blockCount * bytesPerBlock)

    let resultCode: Int32 = blockData.withUnsafeMutableBytes { rawBuffer in
      let basePtr = rawBuffer.baseAddress!.assumingMemoryBound(to: UInt8.self)

      for block in blocks {
        if let data = block.data, block.row < UInt8(k) {
          let dest = basePtr.advanced(by: originalCount * bytesPerBlock)
          data.copyBytes(to: dest, count: bytesPerBlock)
          cBlocks[originalCount] = CLonghair.Block(data: dest, row: block.row)
          originalCount += 1
        } else if let data = block.data, block.row >= UInt8(k), recoveryCount < Int(m) {
          recoveryCount += 1
          let dest = basePtr.advanced(by: (blockCount - recoveryCount) * bytesPerBlock)
          data.copyBytes(to: dest, count: bytesPerBlock)
          cBlocks[blockCount - recoveryCount] = CLonghair.Block(data: dest, row: block.row)
        }
      }

      return cBlocks.withUnsafeMutableBufferPointer { ptr in
        cauchy_256_decode(
          k,
          m,
          ptr.baseAddress!,
          Int32(bytesPerBlock)
        )
      }
    }
    if resultCode != 0 {
      throw DecodeError.decodeFailed(code: resultCode)
    }

    var output = Data()
    output.reserveCapacity(Int(k) * bytesPerBlock)
    for originalRow in 0..<Int(k) {
      let idx = cBlocks.firstIndex(where: { $0.row == UInt8(originalRow) })!
      let start = idx * bytesPerBlock
      output.append(blockData.subdata(in: start ..< start + bytesPerBlock))
    }
    return output
  }

}
