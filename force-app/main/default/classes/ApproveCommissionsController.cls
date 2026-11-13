public with sharing class ApproveCommissionsController {
  @AuraEnabled(cacheable=true)
  public static RegionApprovalSummary getRegionApprovalSummary(
    Id salesRegionId
  ) {
    try {
      return CommissionApprovalService.getRegionApprovalSummary(salesRegionId);
    } catch (Exception ex) {
      throw ABCErrors.toAuraException(ex);
    }
  }
  @AuraEnabled(cacheable=true)
  public static List<Id> getPendingPropertyIds(Id salesRegionId) {
    try {
      return CommissionApprovalService.getPendingPropertyIds(salesRegionId);
    } catch (Exception ex) {
      throw ABCErrors.toAuraException(ex);
    }
  }
  @AuraEnabled(cacheable=true)
  public static List<CommissionApprovalRow> getPendingPropertiesByIds(
    Id salesRegionId,
    List<Id> propertyIds
  ) {
    try {
      return CommissionApprovalService.getPendingPropertiesByIds(
        salesRegionId,
        propertyIds
      );
    } catch (Exception ex) {
      throw ABCErrors.toAuraException(ex);
    }
  }
  @AuraEnabled
  public static RegionApprovalSummary approveProperties(
    Id salesRegionId,
    List<Id> propertyIds,
    List<Decimal> commissionPercentages
  ) {
    try {
      return CommissionApprovalService.approveProperties(
        salesRegionId,
        propertyIds,
        commissionPercentages
      );
    } catch (Exception ex) {
      throw ABCErrors.toAuraException(ex);
    }
  }
}
