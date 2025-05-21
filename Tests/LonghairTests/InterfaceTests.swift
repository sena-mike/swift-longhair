import CLonghair
import Longhair
import Foundation
import Testing

@Test func verifyAPICompat() throws {
  print(CAUCHY_256_VERSION)
  if _cauchy_256_init(CAUCHY_256_VERSION) != 0 {
    Issue.record("Cauchy 256 init failed")
  }
}


@Test func verifyEncode() throws {
  let source = Data(repeating: 0xFF, count: 1024)
  var dataBlocks = [Data]()
  // Break source into 8 equal sized blocks of 128 bytes
  for i in stride(from: 0, to: source.count, by: 128) {
    let start = source.index(source.startIndex, offsetBy: i)
    let end = source.index(source.startIndex, offsetBy: i + 128)
    let block = source[start..<end]
    dataBlocks.append(block)
  }

  let recoveryBlocks = Cauchy256.encode(dataBlocks: dataBlocks, recoveryBlockCount: 2)

  for block in recoveryBlocks {
    print(block.data?.hexEncodedString())
  }

  let blocks = dataBlocks.enumerated().map { Cauchy256.Block(data: $0.element, row: UInt8($0.offset))}
  let recoveryBlocks2 = recoveryBlocks.enumerated().map { Cauchy256.Block(data: $0.element.data, row: UInt8($0.offset + dataBlocks.count))}
  let result = try Cauchy256.decode(blocks: blocks + recoveryBlocks2, recoveryBlockCount: Int32(recoveryBlocks.count))

  #expect(source == result)
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
}
