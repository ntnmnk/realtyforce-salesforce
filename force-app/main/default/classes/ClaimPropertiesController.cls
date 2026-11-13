public with sharing class ClaimPropertiesController {
  // 1. Get agent summary for a Sales Office
  @AuraEnabled(cacheable=true)
  public static AgentClaimSummary getAgentClaimSummary(Id salesOfficeId) {
    try {
      return PropertyClaimService.getAgentClaimSummary(salesOfficeId);
    } catch (Exception ex) {
      throw ABCErrors.toAuraException(ex);
    }
  }

  // 2. Get IDs of available properties
  @AuraEnabled(cacheable=true)
  public static List<Id> getClaimablePropertyIds(Id salesOfficeId) {
    try {
      return PropertyClaimService.getClaimablePropertyIds(salesOfficeId);
    } catch (Exception ex) {
      throw ABCErrors.toAuraException(ex);
    }
  }

  // 3. Get property details for the current page
  @AuraEnabled(cacheable=true)
  public static List<AvailableProperty> getClaimablePropertiesByIds(
    Id salesOfficeId,
    List<Id> propertyIds
  ) {
    try {
      return PropertyClaimService.getClaimablePropertiesByIds(
        salesOfficeId,
        propertyIds
      );
    } catch (Exception ex) {
      throw ABCErrors.toAuraException(ex);
    }
  }

  // 4. Claim selected properties
  @AuraEnabled
  public static AgentClaimSummary claimProperties(
    Id salesOfficeId,
    List<Id> propertyIds
  ) {
    try {
      return PropertyClaimService.claimProperties(salesOfficeId, propertyIds);
    } catch (Exception ex) {
      throw ABCErrors.toAuraException(ex);
    }
  }
}
