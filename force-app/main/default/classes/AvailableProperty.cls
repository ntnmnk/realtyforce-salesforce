public class AvailableProperty {
  @AuraEnabled
  public Id propertyId { get; set; }
  @AuraEnabled
  public String propertyName { get; set; }
  @AuraEnabled
  public String street { get; set; }
  @AuraEnabled
  public String city { get; set; }
  @AuraEnabled
  public Decimal listingPrice { get; set; }
  @AuraEnabled
  public String status { get; set; }
  @AuraEnabled
  public Datetime createdDate { get; set; }
}
