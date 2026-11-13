@IsTest
private class ApproveCommissionsControllerTest {
  @IsTest
  static void testManagerApprovesSelectedProperties() {
    ABCTestDataFactory.Dataset testData = ABCTestDataFactory.buildDataset();

    List<Property__c> pendingProperties = new List<Property__c>();

    for (Integer i = 0; i < 6; i++) {
      pendingProperties.add(
        ABCTestDataFactory.newProperty(
          testData.office.Id,
          testData.currentAgent.Id,
          10000,
          ABCConstants.STATUS_CLOSED_PENDING,
          ABCTestDataFactory.saleDateThisYear()
        )
      );
    }

    insert pendingProperties;

    List<Id> pendingPropertyIds;

    System.runAs(testData.manager) {
      pendingPropertyIds = ApproveCommissionsController.getPendingPropertyIds(
        testData.region.Id
      );

      System.assertEquals(
        6,
        pendingPropertyIds.size(),
        'Six properties should be pending approval.'
      );

      // Approve two properties
      List<Id> selectedPropertyIds = new List<Id>{
        pendingPropertyIds[0],
        pendingPropertyIds[1]
      };

      // First: override to 50%
      // Second: keep existing 40%
      List<Decimal> commissionPercents = new List<Decimal>{ 50, null };

      Test.startTest();

      ApproveCommissionsController.approveProperties(
        testData.region.Id,
        selectedPropertyIds,
        commissionPercents
      );

      Test.stopTest();
    }

    // Verify approved properties
    Map<Id, Property__c> approvedProperties = new Map<Id, Property__c>(
      [
        SELECT
          Id,
          Status__c,
          Agent_Commission_Percentage__c,
          Agent_Commission_Amount__c
        FROM Property__c
        WHERE Id IN :pendingPropertyIds
      ]
    );

    Property__c firstProperty = approvedProperties.get(pendingPropertyIds[0]);

    System.assertEquals(
      ABCConstants.STATUS_CLOSED_APPROVED,
      firstProperty.Status__c
    );

    System.assertEquals(50, firstProperty.Agent_Commission_Percentage__c);

    System.assertEquals(150, firstProperty.Agent_Commission_Amount__c);

    Property__c secondProperty = approvedProperties.get(pendingPropertyIds[1]);

    System.assertEquals(
      ABCConstants.STATUS_CLOSED_APPROVED,
      secondProperty.Status__c
    );

    System.assertEquals(40, secondProperty.Agent_Commission_Percentage__c);

    System.assertEquals(120, secondProperty.Agent_Commission_Amount__c);

    // Remaining four properties must stay pending
    for (Integer i = 2; i < pendingPropertyIds.size(); i++) {
      System.assertEquals(
        ABCConstants.STATUS_CLOSED_PENDING,
        approvedProperties.get(pendingPropertyIds[i]).Status__c
      );
    }

    // Verify YTD totals
    ABCTestDataFactory.assertTotals(
      testData.currentAgent.Id,
      testData.office.Id,
      60000,
      270
    );
  }

  @IsTest
  static void testAgentCannotApproveCommissions() {
    ABCTestDataFactory.Dataset testData = ABCTestDataFactory.buildDataset();

    Boolean accessDenied = false;

    System.runAs(testData.agentUser) {
      Test.startTest();

      try {
        ApproveCommissionsController.getRegionApprovalSummary(
          testData.region.Id
        );
      } catch (AuraHandledException ex) {
        accessDenied = true;
      }

      Test.stopTest();
    }

    System.assertEquals(
      true,
      accessDenied,
      'Only the assigned regional manager should access approvals.'
    );
  }
}
