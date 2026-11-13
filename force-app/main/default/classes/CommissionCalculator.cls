/**
 * Pure commission calculations with no SOQL or DML.
 */
public class CommissionCalculator {
  /**
   * Agent commission = sales price x agency rate x agent split.
   * Example: 100,000 x 3% x 40% = 1,200.00
   */
  public static Decimal agentCommission(
    Decimal salesPrice,
    Decimal commissionPercentage
  ) {
    if (salesPrice == null || commissionPercentage == null) {
      return 0;
    }

    return (salesPrice *
      ABCConstants.AGENCY_COMMISSION_RATE *
      (commissionPercentage / 100))
      .setScale(2);
  }

  public static Boolean isValidSplit(Decimal commissionPercentage) {
    return commissionPercentage != null &&
      commissionPercentage >= 0 &&
      commissionPercentage <= 100;
  }

  public static Decimal zeroIfNull(Decimal value) {
    return value == null ? 0 : value;
  }
}
