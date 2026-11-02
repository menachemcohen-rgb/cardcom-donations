@IsTest
private class ChargeRunLockTest {
  @IsTest
  static void acquireAndRelease() {
    ChargeRunLock.release(); // no record yet: no-op
    Assert.isFalse(ChargeRunLock.isChainActive());
    ChargeRunLock.acquire();
    Assert.isTrue(ChargeRunLock.isChainActive());
    ChargeRunLock.release();
    Assert.isFalse(ChargeRunLock.isChainActive());
  }
}
