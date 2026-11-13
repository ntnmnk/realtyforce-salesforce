public class RegionApprovalSummary {
  @AuraEnabled
  public String regionName { get; set; }
  @AuraEnabled
  public Decimal regionYearToDateSales { get; set; }
}
