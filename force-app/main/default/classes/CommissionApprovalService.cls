public with sharing class CommissionApprovalService {
  private static final Integer MAX_APPROVALS = 200;

  // 1. Get regional summary
  public static RegionApprovalSummary getRegionApprovalSummary(
    Id salesRegionId
  ) {
    Sales_Region__c region = validateRegionManager(salesRegionId);

    return getRegionSummary(region);
  }

  // 2. Get IDs of pending properties
  public static List<Id> getPendingPropertyIds(Id salesRegionId) {
    validateRegionManager(salesRegionId);

    return PropertySelector.getPendingPropertyIds(salesRegionId);
  }

  // 3. Get details for the selected page
  public static List<CommissionApprovalRow> getPendingPropertiesByIds(
    Id salesRegionId,
    List<Id> propertyIds
  ) {
    validateRegionManager(salesRegionId);

    return PropertySelector.getPendingPropertiesByIds(
      salesRegionId,
      propertyIds
    );
  }

  // 4. Approve selected properties
  public static RegionApprovalSummary approveProperties(
    Id salesRegionId,
    List<Id> propertyIds,
    List<Decimal> commissionPercentages
  ) {
    // Step 1: Check region manager permission.
    validateRegionManager(salesRegionId);

    // Step 2: Validate IDs and commission percentages.
    Map<Id, Decimal> requestedPercentages = validateApprovalRequest(
      propertyIds,
      commissionPercentages
    );

    // Step 3: Lock region and recheck manager.
    SalesRegionSelector.lockById(salesRegionId);

    Sales_Region__c region = validateRegionManager(salesRegionId);

    // Step 4: Lock selected properties.
    List<Property__c> properties = PropertySelector.lockAndRead(
      requestedPercentages.keySet()
    );

    if (properties.size() != requestedPercentages.size()) {
      throw new ABCException(
        'Some properties are unavailable. Refresh and try again.'
      );
    }

    List<Property__c> propertiesToUpdate = new List<Property__c>();

    // Step 5: Validate and prepare approvals.
    for (Property__c prop : properties) {
      // Property must belong to this region.
      if (
        prop.Sales_Office__r == null ||
        prop.Sales_Office__r.Sales_Region__c != salesRegionId
      ) {
        throw new ABCException('Property does not belong to this region.');
      }

      // Property must still be awaiting approval.
      if (prop.Status__c != ABCConstants.STATUS_CLOSED_PENDING) {
        throw new ABCException('Property is no longer pending approval.');
      }

      // Use override, otherwise keep existing split.
      Decimal newPercentage = requestedPercentages.get(prop.Id);

      if (newPercentage == null) {
        newPercentage = prop.Agent_Commission_Percentage__c;
      }

      // Validate final percentage.
      if (!CommissionCalculator.isValidSplit(newPercentage)) {
        throw new ABCException(
          'Commission percentage must be between 0 and 100.'
        );
      }

      // Manager cannot decrease existing split.
      if (
        prop.Agent_Commission_Percentage__c != null &&
        newPercentage < prop.Agent_Commission_Percentage__c
      ) {
        throw new ABCException('Commission percentage cannot be decreased.');
      }

      propertiesToUpdate.add(
        new Property__c(
          Id = prop.Id,
          Status__c = ABCConstants.STATUS_CLOSED_APPROVED,
          Agent_Commission_Percentage__c = newPercentage
        )
      );
    }

    // Step 6: Save all approvals.
    // The trigger calculates commission amounts.
    update as user propertiesToUpdate;

    // Step 7: Return updated regional summary.
    return getRegionSummary(region);
  }

  // 5. Validate selected IDs and percentages
  private static Map<Id, Decimal> validateApprovalRequest(
    List<Id> propertyIds,
    List<Decimal> percentages
  ) {
    if (propertyIds == null || propertyIds.isEmpty()) {
      throw new ABCException('Select at least one property.');
    }

    if (percentages == null || percentages.size() != propertyIds.size()) {
      throw new ABCException('Approval details are incomplete.');
    }

    if (propertyIds.size() > MAX_APPROVALS) {
      throw new ABCException('Approve at most 200 properties.');
    }

    Map<Id, Decimal> requested = new Map<Id, Decimal>();

    for (Integer i = 0; i < propertyIds.size(); i++) {
      Id propertyId = propertyIds[i];
      Decimal percentage = percentages[i];

      if (
        propertyId == null ||
        propertyId.getSObjectType() != Property__c.SObjectType
      ) {
        throw new ABCException('Invalid property ID.');
      }

      if (requested.containsKey(propertyId)) {
        throw new ABCException('Duplicate property selected.');
      }

      if (
        percentage != null && !CommissionCalculator.isValidSplit(percentage)
      ) {
        throw new ABCException(
          'Commission percentage must be between 0 and 100.'
        );
      }

      // Null means use the property's existing split.
      requested.put(propertyId, percentage);
    }

    return requested;
  }

  // 6. Verify regional manager
  private static Sales_Region__c validateRegionManager(Id salesRegionId) {
    if (
      salesRegionId == null ||
      salesRegionId.getSObjectType() != Sales_Region__c.SObjectType
    ) {
      throw new ABCException('Open this action from a Sales Region.');
    }

    List<Sales_Region__c> regions = SalesRegionSelector.selectById(
      salesRegionId
    );

    if (regions.isEmpty()) {
      throw new ABCException('Sales Region not found.');
    }

    Sales_Region__c region = regions[0];

    if (region.Regional_Manager__c != UserInfo.getUserId()) {
      throw new ABCException('Only the assigned regional manager can approve.');
    }

    return region;
  }

  // 7. Build regional summary
  private static RegionApprovalSummary getRegionSummary(
    Sales_Region__c region
  ) {
    RegionApprovalSummary summary = new RegionApprovalSummary();

    summary.regionName = region.Name;

    summary.regionYearToDateSales = SalesOfficeSelector.selectRegionYearToDateSales(
      region.Id
    );

    return summary;
  }
}
