@IsTest
private class ClaimPropertiesControllerTest {
  @IsTest
  static void claimsSelectedRecordsAndReturnsFreshSummary() {
    ABCTestDataFactory.Dataset testData = ABCTestDataFactory.buildDataset();
    List<Property__c> properties = ABCTestDataFactory.createOpenProperties(
      testData.office.Id,
      6
    );
    System.runAs(testData.agentUser) {
      Test.startTest();
      List<Id> availableIds = ClaimPropertiesController.getClaimablePropertyIds(
        testData.office.Id
      );
      Assert.areEqual(6, availableIds.size());
      List<AvailableProperty> page = ClaimPropertiesController.getClaimablePropertiesByIds(
        testData.office.Id,
        new List<Id>{ availableIds[0], availableIds[1] }
      );
      Assert.areEqual(2, page.size());
      AgentClaimSummary summary = ClaimPropertiesController.claimProperties(
        testData.office.Id,
        new List<Id>{ availableIds[0], availableIds[1] }
      );
      Assert.areEqual(2, summary.workingPropertyCount);
      Assert.areEqual(3, summary.remainingClaimCapacity);
      Assert.areEqual(0, summary.yearToDateSales);
      Assert.areEqual(
        4,
        ClaimPropertiesController.getClaimablePropertyIds(testData.office.Id)
          .size()
      );
      Test.stopTest();
    }
    Property__c saved = [
      SELECT Agent_Commission_Percentage__c
      FROM Property__c
      WHERE Agent__c = :testData.currentAgent.Id
      LIMIT 1
    ];
    Assert.areEqual(40, saved.Agent_Commission_Percentage__c);
  }
  @IsTest
  static void invalidSelectionsDoNotMutateData() {
    ABCTestDataFactory.Dataset testData = ABCTestDataFactory.buildDataset();
    Property__c propertyRecord = ABCTestDataFactory.createOpenProperties(
      testData.office.Id,
      1
    )[0];
    List<List<Id>> invalidSelections = new List<List<Id>>{
      null,
      new List<Id>(),
      new List<Id>{ null },
      new List<Id>{ testData.office.Id },
      new List<Id>{ propertyRecord.Id, propertyRecord.Id }
    };
    System.runAs(testData.agentUser) {
      for (List<Id> selection : invalidSelections) {
        try {
          ClaimPropertiesController.claimProperties(
            testData.office.Id,
            selection
          );
          Assert.fail('Invalid selection must fail.');
        } catch (AuraHandledException ex) {
          Assert.isNotNull(ex.getMessage());
        }
      }
    }
    Assert.areEqual(
      'Open',
      [SELECT Status__c FROM Property__c WHERE Id = :propertyRecord.Id]
      .Status__c
    );
  }
  @IsTest
  static void rejectsWrongOfficeAndUnmappedUser() {
    ABCTestDataFactory.Dataset testData = ABCTestDataFactory.buildDataset();
    System.runAs(testData.agentUser) {
      try {
        ClaimPropertiesController.getAgentClaimSummary(testData.otherOffice.Id);
        Assert.fail('Wrong office must fail.');
      } catch (AuraHandledException ex) {
        Assert.isTrue(ex.getMessage().contains('Office'));
      }
    }
    System.runAs(testData.manager) {
      try {
        ClaimPropertiesController.getAgentClaimSummary(testData.office.Id);
        Assert.fail('Unmapped user must fail.');
      } catch (AuraHandledException ex) {
        Assert.isTrue(ex.getMessage().contains('agent Contact'));
      }
    }
  }
  @IsTest
  static void listsBeyondTheOldTwoThousandLimit() {
    ABCTestDataFactory.Dataset testData = ABCTestDataFactory.buildDataset();
    ABCTestDataFactory.createOpenProperties(testData.office.Id, 2001);
    System.runAs(testData.agentUser) {
      Test.startTest();
      Assert.areEqual(
        2001,
        ClaimPropertiesController.getClaimablePropertyIds(testData.office.Id)
          .size()
      );
      Test.stopTest();
    }
  }
}
