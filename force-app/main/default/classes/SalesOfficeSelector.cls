public with sharing class SalesOfficeSelector {
  // 1. Get Sales Office details
  public static Sales_Office__c selectById(Id salesOfficeId) {
    if (salesOfficeId == null) {
      throw new ABCException('Sales Office ID is required.');
    }

    List<Sales_Office__c> offices = [
      SELECT Id, Name
      FROM Sales_Office__c
      WHERE Id = :salesOfficeId
      WITH USER_MODE
      LIMIT 1
    ];

    if (offices.isEmpty()) {
      throw new ABCException('Sales Office is unavailable.');
    }

    return offices[0];
  }

  // 2. Calculate total YTD sales for a region
  public static Decimal selectRegionYearToDateSales(Id salesRegionId) {
    if (salesRegionId == null) {
      throw new ABCException('Sales Region ID is required.');
    }

    AggregateResult result = [
      SELECT SUM(Year_to_Date_Sales__c) totalSales
      FROM Sales_Office__c
      WHERE Sales_Region__c = :salesRegionId
      WITH USER_MODE
    ];

    return CommissionCalculator.zeroIfNull((Decimal) result.get('totalSales'));
  }
}
