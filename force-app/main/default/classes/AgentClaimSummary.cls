public class AgentClaimSummary {
  @AuraEnabled
  public String salesOfficeName { get; set; }
  @AuraEnabled
  public Integer workingPropertyCount { get; set; }
  @AuraEnabled
  public Integer maxWorkingProperties { get; set; }
  @AuraEnabled
  public Integer remainingClaimCapacity { get; set; }
  @AuraEnabled
  public Decimal yearToDateSales { get; set; }
  @AuraEnabled
  public Decimal yearToDateCommissions { get; set; }
}
