@isTest
private class PropertyTriggerTest {
  @isTest
  static void approvedInsertRollsUpAgentAndOfficeTotals() {
    ABCTestDataFactory.Dataset testData = ABCTestDataFactory.buildDataset();
    Property__c propertyRecord = ABCTestDataFactory.newProperty(
      testData.office.Id,
      testData.currentAgent.Id,
      100000,
      ABCConstants.STATUS_CLOSED_APPROVED,
      ABCTestDataFactory.saleDateThisYear()
    );

    Test.startTest();
    insert propertyRecord;
    Test.stopTest();

    // 100,000 x 3% x 40% = 1,200 commission
    ABCTestDataFactory.assertTotals(
      testData.currentAgent.Id,
      testData.office.Id,
      100000.00,
      1200.00
    );
  }

  @isTest
  static void pendingSalesCountTowardSalesButNotCommissions() {
    ABCTestDataFactory.Dataset testData = ABCTestDataFactory.buildDataset();
    insert ABCTestDataFactory.newProperty(
      testData.office.Id,
      testData.currentAgent.Id,
      100000,
      ABCConstants.STATUS_CLOSED_PENDING,
      ABCTestDataFactory.saleDateThisYear()
    );

    ABCTestDataFactory.assertTotals(
      testData.currentAgent.Id,
      testData.office.Id,
      100000.00,
      0.00
    );
  }

  @isTest
  static void priorYearSalesAreExcluded() {
    ABCTestDataFactory.Dataset testData = ABCTestDataFactory.buildDataset();
    insert ABCTestDataFactory.newProperty(
      testData.office.Id,
      testData.currentAgent.Id,
      100000,
      ABCConstants.STATUS_CLOSED_APPROVED,
      ABCTestDataFactory.saleDateLastYear()
    );

    ABCTestDataFactory.assertTotals(
      testData.currentAgent.Id,
      testData.office.Id,
      0.00,
      0.00
    );
  }

  @isTest
  static void deleteAndUndeleteKeepTotalsConsistent() {
    ABCTestDataFactory.Dataset testData = ABCTestDataFactory.buildDataset();
    Property__c propertyRecord = ABCTestDataFactory.newProperty(
      testData.office.Id,
      testData.currentAgent.Id,
      100000,
      ABCConstants.STATUS_CLOSED_APPROVED,
      ABCTestDataFactory.saleDateThisYear()
    );
    insert propertyRecord;

    delete propertyRecord;
    ABCTestDataFactory.assertTotals(
      testData.currentAgent.Id,
      testData.office.Id,
      0.00,
      0.00
    );

    List<Property__c> deleted = [
      SELECT Id
      FROM Property__c
      WHERE Id = :propertyRecord.Id
      ALL ROWS
    ];
    undelete deleted;
    ABCTestDataFactory.assertTotals(
      testData.currentAgent.Id,
      testData.office.Id,
      100000.00,
      1200.00
    );
  }

  @isTest
  static void bulkApprovalRollsUpCorrectly() {
    ABCTestDataFactory.Dataset testData = ABCTestDataFactory.buildDataset();
    List<Property__c> properties = new List<Property__c>();
    for (Integer i = 0; i < 200; i++) {
      properties.add(
        ABCTestDataFactory.newProperty(
          testData.office.Id,
          testData.currentAgent.Id,
          10000,
          ABCConstants.STATUS_CLOSED_APPROVED,
          ABCTestDataFactory.saleDateThisYear()
        )
      );
    }

    Test.startTest();
    insert properties;
    Test.stopTest();

    // 200 x 10,000 = 2,000,000 sales; 200 x 120 = 24,000 commission
    ABCTestDataFactory.assertTotals(
      testData.currentAgent.Id,
      testData.office.Id,
      2000000.00,
      24000.00
    );
  }

  @isTest
  static void invalidSplitOnApprovalIsRejected() {
    ABCTestDataFactory.Dataset testData = ABCTestDataFactory.buildDataset();
    Property__c propertyRecord = ABCTestDataFactory.newProperty(
      testData.office.Id,
      testData.currentAgent.Id,
      100000,
      ABCConstants.STATUS_CLOSED_APPROVED,
      ABCTestDataFactory.saleDateThisYear()
    );
    propertyRecord.Agent_Commission_Percentage__c = 150;

    try {
      insert propertyRecord;
      System.assert(false, 'Split above 100% must be rejected');
    } catch (DmlException ex) {
      System.assert(
        ex.getMessage().contains('between 0 and 100'),
        ex.getMessage()
      );
    }
  }
}
