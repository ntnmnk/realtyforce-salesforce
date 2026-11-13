public class CommissionApprovalRow {
  @AuraEnabled
  public Id propertyId { get; set; }
  @AuraEnabled
  public String street { get; set; }
  @AuraEnabled
  public String salesOfficeName { get; set; }
  @AuraEnabled
  public String agentName { get; set; }
  @AuraEnabled
  public Decimal listingPrice { get; set; }
  @AuraEnabled
  public Decimal salesPrice { get; set; }
  @AuraEnabled
  public Decimal commissionPercentage { get; set; }
  @AuraEnabled
  public Decimal officeYearToDateSales { get; set; }
}
