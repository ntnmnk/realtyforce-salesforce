public with sharing class SalesRegionSelector {
  // 1. Get Sales Region details
  public static List<Sales_Region__c> selectById(Id salesRegionId) {
    if (salesRegionId == null) {
      throw new ABCException('Sales Region ID is required.');
    }

    return [
      SELECT Id, Name, Regional_Manager__c
      FROM Sales_Region__c
      WHERE Id = :salesRegionId
      WITH USER_MODE
      LIMIT 1
    ];
  }

  // 2. Lock Sales Region during approval
  public static void lockById(Id salesRegionId) {
    if (salesRegionId == null) {
      throw new ABCException('Sales Region ID is required.');
    }

    List<Sales_Region__c> regions = [
      SELECT Id
      FROM Sales_Region__c
      WHERE Id = :salesRegionId
      WITH USER_MODE
      FOR UPDATE
    ];

    if (regions.isEmpty()) {
      throw new ABCException('Sales Region is unavailable.');
    }
  }
}
