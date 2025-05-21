# Plan for implementing `decode(blocks:recoveryBlockCount:)` in Longhair.swift

This document outlines a step-by-step approach to flesh out the `decode(blocks:recoveryBlockCount:)` stub in `Sources/Longhair/Longhair.swift`. Each step references existing code or tests to ensure consistency with the `encode(_:)` implementation and the underlying C API.

## 1. Touch the C initializer

Just like in `encode(_:)`, reference `_initializer` at the start of `decode(_:)` to ensure the C library is set up:
```swift
public static func decode(blocks: [Block], recoveryBlockCount: Int32) throws -> Data {
    _ = _initializer
    // … implementation goes here
}
```

## 2. Compute k and m and sanity-check parameters

Calculate `k` (number of original data blocks) and `m` (number of recovery blocks), then validate:
```swift
let m = recoveryBlockCount
let total = blocks.count
let k = Int32(total) - m
precondition(k > 0, "must pass at least one block")
precondition(m >= 0, "recoveryBlockCount must be non-negative")
precondition(total == Int(k) + Int(m), "blocks.count must equal k + m")
precondition(k + m <= 256, "k + m must be ≤ 256")
```

## 3. Determine and validate `bytesPerBlock`

All non-nil blocks must have the same size (and be a multiple of 8 bytes). For example:
```swift
// Find bytesPerBlock from the first non-nil block
guard let firstData = blocks.first(where: { $0.data != nil })?.data else {
    throw DecodeError.missingData
}
let bytesPerBlock = firstData.count
precondition(bytesPerBlock % 8 == 0, "bytesPerBlock must be a multiple of 8")
// Ensure every non-nil block matches this length
precondition(
    blocks.allSatisfy({ $0.data?.count == bytesPerBlock || $0.data == nil }),
    "all non-nil blocks must have the same size"
)
```

## 4. Allocate buffers for missing (nil) blocks

For each block whose `.data` is `nil`, allocate a zeroed `Data` buffer so the C decoder can recover into it:
```swift
for i in 0..<blocks.count {
    if blocks[i].data == nil {
        blocks[i].data = Data(count: bytesPerBlock)
    }
}
```

## 5. Build a C-struct array of `Block`

Convert Swift `Block` values into a contiguous C array (`CLonghair.Block`) with pinned pointers into each `Data`:
```swift
var cBlocks = blocks.map { swiftBlock in
    CBlock(data: nil, row: swiftBlock.row)
}
cBlocks.withUnsafeMutableBufferPointer { ptr in
    for i in ptr.indices {
        ptr[i].data = blocks[i].data!.withUnsafeMutableBytes { $0.baseAddress!.assumingMemoryBound(to: UInt8.self) }
    }
    // call into the C API here
}
```

## 6. Call `cauchy_256_decode` inside pinned pointers

Within the `withUnsafeMutableBufferPointer` (and nested `withUnsafeBytes` / `withUnsafeMutableBytes` on each `Data`), invoke:
```swift
let resultCode = cBlocks.withUnsafeMutableBufferPointer { ptr in
    cauchy_256_decode(
        k,
        m,
        ptr.baseAddress!,
        Int32(bytesPerBlock)
    )
}
```

## 7. Check the return code and throw on failure

The C function returns 0 on success; non-zero indicates failure. Throw a Swift error accordingly:
```swift
if resultCode != 0 {
    throw DecodeError.decodeFailed(code: resultCode)
}
```

## 8. Reassemble the original data in row order

After decoding, concatenate the `k` original rows (in ascending `row` order) from the recovered buffers into the final `Data`:
```swift
var output = Data()
output.reserveCapacity(Int(k) * bytesPerBlock)
for originalRow in 0..<Int(k) {
    let idx = cBlocks.firstIndex(where: { $0.row == UInt8(originalRow) })!
    output.append(blocks[idx].data!)
}
return output
```

## 9. Write and verify unit tests for missing-data recovery

- Add a new test in `Tests/LonghairTests/InterfaceTests.swift` that simulates one or more missing data blocks (setting `.data = nil`) and asserts that `decode(blocks:recoveryBlockCount:)` successfully reconstructs the original data.
- Ensure the existing encode/decode test for the no-loss scenario still passes.

## 10. Update documentation

Enhance the doc comment above `decode(blocks:recoveryBlockCount:)` to explain:
- The expected contents of `blocks` (original + recovery, with proper `row` values)
- The meaning of `recoveryBlockCount`
- Possible thrown errors
- The format of the returned `Data`

---

### Key references

- Swift stub: `Sources/Longhair/Longhair.swift`
- C API signature: `Sources/CLonghair/cauchy_256.h`
- C API example: `Sources/CLonghair/README.md`
- Swift test: `Tests/LonghairTests/InterfaceTests.swift`
- `encode(_:)` pattern: `Sources/Longhair/Longhair.swift`