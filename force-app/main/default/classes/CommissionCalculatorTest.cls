@isTest
private class CommissionCalculatorTest {
  @isTest
  static void calculatesSpecExample() {
    // 100,000 x 3% x 40% = 1,200
    System.assertEquals(
      1200.00,
      CommissionCalculator.agentCommission(100000, 40)
    );
  }

  @isTest
  static void nullInputsYieldZero() {
    System.assertEquals(0, CommissionCalculator.agentCommission(null, 40));
  }

  @isTest
  static void validatesSplitRange() {
    System.assert(CommissionCalculator.isValidSplit(0));
    System.assert(CommissionCalculator.isValidSplit(100));
    System.assert(!CommissionCalculator.isValidSplit(-1));
    System.assert(!CommissionCalculator.isValidSplit(101));
    System.assert(!CommissionCalculator.isValidSplit(null));
  }
}
