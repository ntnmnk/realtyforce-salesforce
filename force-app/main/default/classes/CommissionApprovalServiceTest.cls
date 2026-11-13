@IsTest
private class CommissionApprovalServiceTest {
  @IsTest
  static void readsRegionSummaryAndOrderedPage() {
    ABCTestDataFactory.Dataset testData = ABCTestDataFactory.buildDataset();
    List<Property__c> properties = new List<Property__c>();
    for (Integer index = 0; index < 2; index++)
      properties.add(
        ABCTestDataFactory.newProperty(
          testData.office.Id,
          testData.currentAgent.Id,
          100000,
          ABCConstants.STATUS_CLOSED_PENDING,
          Date.today()
        )
      );
    insert properties;
    System.runAs(testData.manager) {
      RegionApprovalSummary summary = ApproveCommissionsController.getRegionApprovalSummary(
        testData.region.Id
      );
      Assert.areEqual(200000, summary.regionYearToDateSales);
      List<Id> requestedIds = new List<Id>{
        properties[1].Id,
        properties[0].Id
      };
      List<CommissionApprovalRow> rows = ApproveCommissionsController.getPendingPropertiesByIds(
        testData.region.Id,
        requestedIds
      );
      Assert.areEqual(2, rows.size());
      Assert.areEqual(properties[1].Id, rows[0].propertyId);
      Assert.areEqual(200000, rows[0].officeYearToDateSales);
    }
  }
  @IsTest
  static void staleApprovalRollsBackWholeSelection() {
    ABCTestDataFactory.Dataset testData = ABCTestDataFactory.buildDataset();
    List<Property__c> properties = new List<Property__c>();
    for (Integer index = 0; index < 2; index++)
      properties.add(
        ABCTestDataFactory.newProperty(
          testData.office.Id,
          testData.currentAgent.Id,
          100000,
          ABCConstants.STATUS_CLOSED_PENDING,
          Date.today()
        )
      );
    insert properties;
    properties[1].Status__c = ABCConstants.STATUS_CLOSED_APPROVED;
    update properties[1];
    System.runAs(testData.manager) {
      try {
        CommissionApprovalService.approveProperties(
          testData.region.Id,
          new List<Id>{ properties[0].Id, properties[1].Id },
          new List<Decimal>{ 50, 50 }
        );
        Assert.fail('Stale approval must fail.');
      } catch (ABCException ex) {
        Assert.isTrue(ex.getMessage().contains('pending approval'));
      }
    }
    Assert.areEqual(
      ABCConstants.STATUS_CLOSED_PENDING,
      [SELECT Status__c FROM Property__c WHERE Id = :properties[0].Id].Status__c
    );
    ABCTestDataFactory.assertTotals(
      testData.currentAgent.Id,
      testData.office.Id,
      200000,
      1200
    );
  }
  @IsTest
  static void rejectsReducedAndDuplicateApprovals() {
    ABCTestDataFactory.Dataset testData = ABCTestDataFactory.buildDataset();
    Property__c propertyRecord = ABCTestDataFactory.newProperty(
      testData.office.Id,
      testData.currentAgent.Id,
      100000,
      ABCConstants.STATUS_CLOSED_PENDING,
      Date.today()
    );
    insert propertyRecord;
    System.runAs(testData.manager) {
      try {
        CommissionApprovalService.approveProperties(
          testData.region.Id,
          new List<Id>{ propertyRecord.Id },
          new List<Decimal>{ 30 }
        );
        Assert.fail('Reduced commission must fail.');
      } catch (ABCException ex) {
        Assert.isTrue(ex.getMessage().contains('decreased'));
      }
      try {
        CommissionApprovalService.approveProperties(
          testData.region.Id,
          new List<Id>{ propertyRecord.Id, propertyRecord.Id },
          new List<Decimal>{ 50, 50 }
        );
        Assert.fail('Duplicates must fail.');
      } catch (ABCException ex) {
        Assert.isTrue(ex.getMessage().contains('more than once'));
      }
    }
  }
}
