/**
 * @description Selector class responsible for querying Property__c records.
 *              Enforces user-mode security (FLS/CRUD/Sharing) and provides
 *              concurrency locking and pagination support.
 */
public with sharing class PropertySelector {
  // Status and pagination constants from central configuration
  private static final String OPEN = ABCConstants.STATUS_OPEN;
  private static final String PENDING = ABCConstants.STATUS_CLOSED_PENDING;
  private static final Integer PAGE_SIZE = ABCConstants.PAGE_SIZE;
  private static final Integer MAX_RECORDS = 20000;
  private static final Integer QUERY_LIMIT = MAX_RECORDS + 1;

  // Centralized error messages for maintainability
  private static final String ERR_OFFICE_REQUIRED = 'Sales Office is required.';
  private static final String ERR_REGION_REQUIRED = 'Sales Region is required.';
  private static final String ERR_TOO_MANY_AVAILABLE = 'Too many available properties.';
  private static final String ERR_TOO_MANY_PENDING = 'Too many properties pending approval.';
  private static final String ERR_PAGE_LIMIT_EXCEEDED = 'Too many properties requested.';

  // Null-Object Prototypes
  private static final Id UNASSIGNED_ID;
  private static final Contact EMPTY_AGENT = new Contact();
  private static final Sales_Office__c EMPTY_OFFICE = new Sales_Office__c();

  /**
   * @description Locks and retrieves Property__c records before a Claim or Approval action.
   *              Note: FOR UPDATE automatically orders by Id in Salesforce.
   * @param propertyIds Set of Property__c IDs to lock and read.
   * @return List of locked Property__c records.
   */
  public static List<Property__c> lockAndRead(Set<Id> propertyIds) {
    if (propertyIds == null || propertyIds.isEmpty()) {
      return new List<Property__c>();
    }

    return [
      SELECT
        Id,
        Agent__c,
        Status__c,
        Sales_Office__c,
        Sales_Office__r.Sales_Region__c,
        Property_Street__c,
        Agent_Commission_Percentage__c
      FROM Property__c
      WHERE Id IN :propertyIds
      WITH USER_MODE
      FOR UPDATE
    ];
  }

  /**
   * @description Retrieves all claimable (Open & Unassigned) Property IDs for a Sales Office.
   *              Enforces a maximum record ceiling of 20,000 records.
   * @param salesOfficeId The ID of the Sales_Office__c to filter by.
   * @return Ordered List of claimable Property__c IDs.
   */
  public static List<Id> getClaimablePropertyIds(Id salesOfficeId) {
    requireId(salesOfficeId, ERR_OFFICE_REQUIRED);

    Map<Id, Property__c> propertyMap = new Map<Id, Property__c>(
      [
        SELECT Id
        FROM Property__c
        WHERE
          Sales_Office__c = :salesOfficeId
          AND Status__c = :OPEN
          AND Agent__c = :UNASSIGNED_ID
        WITH USER_MODE
        ORDER BY Property_Street__c, Id
        LIMIT :QUERY_LIMIT
      ]
    );

    if (propertyMap.size() > MAX_RECORDS) {
      throw new ABCException(ERR_TOO_MANY_AVAILABLE);
    }

    return new List<Id>(propertyMap.keySet());
  }

  /**
   * @description Retrieves detailed wrapper rows for a specific page of claimable properties.
   * @param salesOfficeId The ID of the Sales_Office__c.
   * @param propertyIds The current page's subset of Property__c IDs.
   * @return List of AvailableProperty DTOs for UI rendering.
   */
  public static List<AvailableProperty> getClaimablePropertiesByIds(
    Id salesOfficeId,
    List<Id> propertyIds
  ) {
    requireId(salesOfficeId, ERR_OFFICE_REQUIRED);

    List<AvailableProperty> results = new List<AvailableProperty>();
    if (propertyIds == null || propertyIds.isEmpty()) {
      return results;
    }

    validatePageSize(propertyIds);

    for (Property__c prop : [
      SELECT
        Id,
        Name,
        Property_Street__c,
        Property_City__c,
        Listing_Price__c,
        Status__c,
        CreatedDate
      FROM Property__c
      WHERE
        Id IN :propertyIds
        AND Sales_Office__c = :salesOfficeId
        AND Status__c = :OPEN
        AND Agent__c = :UNASSIGNED_ID
      WITH USER_MODE
      ORDER BY Property_Street__c, Id
    ]) {
      results.add(mapToAvailableProperty(prop));
    }

    return results;
  }

  /**
   * @description Retrieves all Pending Approval Property IDs for a given Sales Region.
   *              Enforces a maximum record ceiling of 20,000 records.
   * @param salesRegionId The ID of the Sales_Region__c to filter by.
   * @return Ordered List of pending Property__c IDs.
   */
  public static List<Id> getPendingPropertyIds(Id salesRegionId) {
    requireId(salesRegionId, ERR_REGION_REQUIRED);

    Map<Id, Property__c> propertyMap = new Map<Id, Property__c>(
      [
        SELECT Id
        FROM Property__c
        WHERE
          Sales_Office__r.Sales_Region__c = :salesRegionId
          AND Status__c = :PENDING
        WITH USER_MODE
        ORDER BY Property_Street__c, Id
        LIMIT :QUERY_LIMIT
      ]
    );

    if (propertyMap.size() > MAX_RECORDS) {
      throw new ABCException(ERR_TOO_MANY_PENDING);
    }

    return new List<Id>(propertyMap.keySet());
  }

  /**
   * @description Retrieves detailed wrapper rows for a specific page of pending properties.
   * @param salesRegionId The ID of the Sales_Region__c.
   * @param propertyIds The current page's subset of Property__c IDs.
   * @return List of CommissionApprovalRow DTOs for UI rendering.
   */
  public static List<CommissionApprovalRow> getPendingPropertiesByIds(
    Id salesRegionId,
    List<Id> propertyIds
  ) {
    requireId(salesRegionId, ERR_REGION_REQUIRED);

    List<CommissionApprovalRow> results = new List<CommissionApprovalRow>();
    if (propertyIds == null || propertyIds.isEmpty()) {
      return results;
    }

    validatePageSize(propertyIds);

    for (Property__c prop : [
      SELECT
        Id,
        Property_Street__c,
        Sales_Office__c,
        Sales_Office__r.Name,
        Sales_Office__r.Year_to_Date_Sales__c,
        Agent__c,
        Agent__r.Name,
        Listing_Price__c,
        Sales_Price__c,
        Agent_Commission_Percentage__c
      FROM Property__c
      WHERE
        Id IN :propertyIds
        AND Sales_Office__r.Sales_Region__c = :salesRegionId
        AND Status__c = :PENDING
      WITH USER_MODE
      ORDER BY Property_Street__c, Id
    ]) {
      results.add(mapToCommissionApprovalRow(prop));
    }

    return results;
  }

  // =========================================================================
  // Private Validation & Mapping Helpers
  // =========================================================================

  private static void requireId(Id recordId, String errorMessage) {
    if (String.isBlank(recordId)) {
      throw new ABCException(errorMessage);
    }
  }

  private static void validatePageSize(List<Id> propertyIds) {
    if (propertyIds.size() > PAGE_SIZE) {
      throw new ABCException(ERR_PAGE_LIMIT_EXCEEDED);
    }
  }

  private static AvailableProperty mapToAvailableProperty(Property__c prop) {
    AvailableProperty row = new AvailableProperty();
    row.propertyId = prop.Id;
    row.propertyName = prop.Name;
    row.street = prop.Property_Street__c;
    row.city = prop.Property_City__c;
    row.listingPrice = prop.Listing_Price__c;
    row.status = prop.Status__c;
    row.createdDate = prop.CreatedDate;
    return row;
  }

  private static CommissionApprovalRow mapToCommissionApprovalRow(
    Property__c prop
  ) {
    Sales_Office__c office = getSalesOffice(prop);
    Contact agent = getAgent(prop);

    CommissionApprovalRow row = new CommissionApprovalRow();
    row.propertyId = prop.Id;
    row.street = prop.Property_Street__c;
    row.salesOfficeName = office.Name;
    row.officeYearToDateSales = office.Year_to_Date_Sales__c;
    row.agentName = agent.Name;
    row.listingPrice = prop.Listing_Price__c;
    row.salesPrice = prop.Sales_Price__c;
    row.commissionPercentage = prop.Agent_Commission_Percentage__c;
    return row;
  }

  private static Sales_Office__c getSalesOffice(Property__c prop) {
    if (String.isNotBlank(prop.Sales_Office__c)) {
      return prop.Sales_Office__r;
    }
    return EMPTY_OFFICE;
  }

  private static Contact getAgent(Property__c prop) {
    if (String.isNotBlank(prop.Agent__c)) {
      return prop.Agent__r;
    }
    return EMPTY_AGENT;
  }
}
