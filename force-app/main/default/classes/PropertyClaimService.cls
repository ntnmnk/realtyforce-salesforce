public with sharing class PropertyClaimService {
  private static final Integer MAX_WORKING_PROPERTIES = ABCConstants.MAX_WORKING_PER_AGENT;
  private static final String STATUS_OPEN = ABCConstants.STATUS_OPEN;
  private static final String STATUS_WORKING = ABCConstants.STATUS_WORKING;

  public static AgentClaimSummary getAgentClaimSummary(Id salesOfficeId) {
    Contact currentAgent = getCurrentAgentForOffice(salesOfficeId, false);
    Integer workingCount = PropertyRules.countWorkingProperties(
      currentAgent.Id
    );
    return buildClaimSummary(currentAgent, salesOfficeId, workingCount);
  }

  public static List<Id> getClaimablePropertyIds(Id salesOfficeId) {
    getCurrentAgentForOffice(salesOfficeId, false);
    return PropertySelector.getClaimablePropertyIds(salesOfficeId);
  }

  public static List<AvailableProperty> getClaimablePropertiesByIds(
    Id salesOfficeId,
    List<Id> propertyIds
  ) {
    getCurrentAgentForOffice(salesOfficeId, false);
    return PropertySelector.getClaimablePropertiesByIds(
      salesOfficeId,
      propertyIds
    );
  }

  /**
   * Claims the selected properties for the running user's Agent Contact.
   * Enforces concurrency locks on both the Agent Contact and Property__c records.
   */
  public static AgentClaimSummary claimProperties(
    Id salesOfficeId,
    List<Id> propertyIds
  ) {
    validateSalesOfficeId(salesOfficeId);
    Set<Id> selectedPropertyIds = validateSelectedPropertyIds(propertyIds);

    Savepoint claimSavepoint = Database.setSavepoint();
    try {
      // 1. Fetch and lock the Agent record in a single query to prevent race conditions
      Contact lockedAgent = getCurrentAgentForOffice(salesOfficeId, true);

      // 2. Verify capacity against the locked agent
      Integer currentWorkingCount = PropertyRules.countWorkingProperties(
        lockedAgent.Id
      );
      Integer projectedWorkingCount =
        currentWorkingCount + selectedPropertyIds.size();

      if (projectedWorkingCount > MAX_WORKING_PROPERTIES) {
        throw new ABCException(
          'You can have at most ' +
            MAX_WORKING_PROPERTIES +
            ' Working properties.'
        );
      }

      // 3. Lock and validate the target properties in deterministic ID order
      List<Property__c> propertiesToClaim = getAvailablePropertiesForClaim(
        salesOfficeId,
        selectedPropertyIds
      );

      // 4. Prepare and execute DML update
      List<Property__c> propertyUpdates = new List<Property__c>();
      for (Property__c propertyRecord : propertiesToClaim) {
        propertyUpdates.add(
          new Property__c(
            Id = propertyRecord.Id,
            Agent__c = lockedAgent.Id,
            Status__c = STATUS_WORKING
          )
        );
      }

      update as user propertyUpdates;

      // 5. Build summary using the known post-update count (saves 2 SOQL queries)
      return buildClaimSummary(
        lockedAgent,
        salesOfficeId,
        projectedWorkingCount
      );
    } catch (Exception ex) {
      Database.rollback(claimSavepoint);
      throw ex;
    }
  }

  // --- PRIVATE HELPER METHODS ---

  private static void validateSalesOfficeId(Id salesOfficeId) {
    if (
      salesOfficeId == null ||
      salesOfficeId.getSObjectType() != Sales_Office__c.SObjectType
    ) {
      throw new ABCException('Invalid Sales Office.');
    }
  }

  private static Set<Id> validateSelectedPropertyIds(List<Id> propertyIds) {
    if (propertyIds == null || propertyIds.isEmpty()) {
      throw new ABCException('Select at least one property.');
    }

    Set<Id> selectedPropertyIds = new Set<Id>();
    for (Id propertyId : propertyIds) {
      if (
        propertyId == null ||
        propertyId.getSObjectType() != Property__c.SObjectType
      ) {
        throw new ABCException(
          'The selection contains an invalid property ID.'
        );
      }
      if (!selectedPropertyIds.add(propertyId)) {
        throw new ABCException('Invalid or duplicate properties selected.');
      }
    }

    if (selectedPropertyIds.size() > MAX_WORKING_PROPERTIES) {
      throw new ABCException(
        'You can claim at most ' +
          MAX_WORKING_PROPERTIES +
          ' properties at a time.'
      );
    }
    return selectedPropertyIds;
  }

  private static List<Property__c> getAvailablePropertiesForClaim(
    Id salesOfficeId,
    Set<Id> selectedPropertyIds
  ) {
    // Sort IDs before locking to prevent deadlocks when two agents select overlapping properties
    List<Id> sortedIds = new List<Id>(selectedPropertyIds);
    sortedIds.sort();

    List<Property__c> properties = PropertySelector.lockAndRead(
      new Set<Id>(sortedIds)
    );

    if (properties.size() != selectedPropertyIds.size()) {
      throw new ABCException(
        'Some selected properties are no longer available.'
      );
    }

    for (Property__c propertyRecord : properties) {
      if (
        propertyRecord.Sales_Office__c != salesOfficeId ||
        propertyRecord.Status__c != STATUS_OPEN ||
        propertyRecord.Agent__c != null
      ) {
        throw new ABCException(
          'One or more selected properties are no longer available to claim.'
        );
      }
    }
    return properties;
  }

  private static Contact getCurrentAgentForOffice(
    Id salesOfficeId,
    Boolean shouldLock
  ) {
    validateSalesOfficeId(salesOfficeId);
    List<Contact> agents = AgentSelector.selectByUserId(UserInfo.getUserId());

    if (agents.isEmpty()) {
      throw new ABCException('Your user is not linked to an agent Contact.');
    }
    if (agents.size() > 1) {
      throw new ABCException('Multiple agent Contacts linked to your user.');
    }

    Contact currentAgent = shouldLock
      ? AgentSelector.lockById(agents[0].Id)
      : agents[0];

    if (
      currentAgent == null ||
      currentAgent.Agent_User__c != UserInfo.getUserId() ||
      currentAgent.Sales_Office__c != salesOfficeId
    ) {
      throw new ABCException(
        'Assigned Sales Office mismatch or agent assignment changed.'
      );
    }

    return currentAgent;
  }

  private static AgentClaimSummary buildClaimSummary(
    Contact currentAgent,
    Id salesOfficeId,
    Integer workingPropertyCount
  ) {
    Sales_Office__c salesOffice = SalesOfficeSelector.selectById(salesOfficeId);
    if (salesOffice == null) {
      throw new ABCException('Sales Office not found or inaccessible.');
    }

    AgentClaimSummary summary = new AgentClaimSummary();
    summary.salesOfficeName = salesOffice.Name;
    summary.workingPropertyCount = workingPropertyCount;
    summary.maxWorkingProperties = MAX_WORKING_PROPERTIES;
    summary.remainingClaimCapacity = Math.max(
      0,
      MAX_WORKING_PROPERTIES - workingPropertyCount
    );
    summary.yearToDateSales = currentAgent.Year_to_Date_Total_Sales__c ?? 0;
    summary.yearToDateCommissions = currentAgent.Year_to_Date_Total_Commissions__c ??
      0;

    return summary;
  }
}
