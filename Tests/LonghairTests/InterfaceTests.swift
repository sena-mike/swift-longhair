import CLonghair
import Testing

@Test func verifyAPICompat() async throws {
  print(CAUCHY_256_VERSION)
  if _cauchy_256_init(CAUCHY_256_VERSION) != 0 {
    Issue.record("Cauchy 256 init failed")
   } 
}
