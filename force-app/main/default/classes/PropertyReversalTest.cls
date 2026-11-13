/**
 * Edge-case tests: approval reversal, the exact claim-cap boundary,
 * cross-office claims, and out-of-range split overrides.
 */
@isTest
private class PropertyReversalTest {
  @isTest
  static void revertingApprovalRemovesCommissionButKeepsSale() {
    ABCTestDataFactory.Dataset testData = ABCTestDataFactory.buildDataset();
    Property__c propertyRecord = ABCTestDataFactory.newProperty(
      testData.office.Id,
      testData.currentAgent.Id,
      100000,
      ABCConstants.STATUS_CLOSED_APPROVED,
      ABCTestDataFactory.saleDateThisYear()
    );
    insert propertyRecord;
    ABCTestDataFactory.assertTotals(
      testData.currentAgent.Id,
      testData.office.Id,
      100000.00,
      1200.00
    );

    propertyRecord.Status__c = ABCConstants.STATUS_CLOSED_PENDING;
    update propertyRecord;

    // Still counts as a sale, but no commission is owed.
    ABCTestDataFactory.assertTotals(
      testData.currentAgent.Id,
      testData.office.Id,
      100000.00,
      0.00
    );
    Property__c saved = [
      SELECT Agent_Commission_Amount__c
      FROM Property__c
      WHERE Id = :propertyRecord.Id
    ];
    System.assertEquals(null, saved.Agent_Commission_Amount__c);
  }

  @isTest
  static void claimCapAllowsExactlyFiveAndRejectsTheSixth() {
    ABCTestDataFactory.Dataset testData = ABCTestDataFactory.buildDataset();
    List<Property__c> properties = ABCTestDataFactory.createOpenProperties(
      testData.office.Id,
      5
    );
    Set<Id> firstFive = new Set<Id>();
    for (Property__c propertyRecord : properties) {
      firstFive.add(propertyRecord.Id);
    }

    ABCTestDataFactory.claimProperties(testData.currentAgent.Id, firstFive);

    String workingStatus = ABCConstants.STATUS_WORKING;
    System.assertEquals(
      5,
      [
        SELECT COUNT()
        FROM Property__c
        WHERE
          Agent__c = :testData.currentAgent.Id
          AND Status__c = :workingStatus
      ]
    );

    Property__c sixth = ABCTestDataFactory.createOpenProperties(
      testData.office.Id,
      1
    )[0];
    try {
      ABCTestDataFactory.claimProperties(
        testData.currentAgent.Id,
        new Set<Id>{ sixth.Id }
      );
      System.assert(false, 'The sixth working property must be rejected');
    } catch (ABCException ex) {
      System.assert(ex.getMessage().contains('at most 5'), ex.getMessage());
    }
    System.assertEquals(
      ABCConstants.STATUS_OPEN,
      [SELECT Status__c FROM Property__c WHERE Id = :sixth.Id].Status__c
    );
  }

  @isTest
  static void agentCannotClaimPropertyInAnotherOffice() {
    ABCTestDataFactory.Dataset testData = ABCTestDataFactory.buildDataset();
    Property__c propertyRecord = ABCTestDataFactory.createOpenProperties(
      testData.otherOffice.Id,
      1
    )[0];

    try {
      ABCTestDataFactory.claimProperties(
        testData.currentAgent.Id,
        new Set<Id>{ propertyRecord.Id }
      );
      System.assert(false, 'Agents must not claim outside their own office');
    } catch (ABCException ex) {
      System.assert(
        ex.getMessage().contains('no longer available'),
        ex.getMessage()
      );
    }
    System.assertEquals(
      ABCConstants.STATUS_OPEN,
      [SELECT Status__c FROM Property__c WHERE Id = :propertyRecord.Id]
      .Status__c
    );
  }

  @isTest
  static void outOfRangeOverrideRejectsWholeApprovalBatch() {
    ABCTestDataFactory.Dataset testData = ABCTestDataFactory.buildDataset();
    List<Property__c> properties = new List<Property__c>{
      ABCTestDataFactory.newProperty(
        testData.office.Id,
        testData.currentAgent.Id,
        100000,
        ABCConstants.STATUS_CLOSED_PENDING,
        ABCTestDataFactory.saleDateThisYear()
      ),
      ABCTestDataFactory.newProperty(
        testData.office.Id,
        testData.currentAgent.Id,
        100000,
        ABCConstants.STATUS_CLOSED_PENDING,
        ABCTestDataFactory.saleDateThisYear()
      )
    };
    insert properties;

    System.runAs(testData.manager) {
      try {
        ABCTestDataFactory.approveProperties(
          testData.region.Id,
          new Set<Id>{ properties[0].Id, properties[1].Id },
          new Map<Id, Decimal>{ properties[0].Id => 150 }
        );
        System.assert(false, 'A split above 100 must be rejected');
      } catch (ABCException ex) {
        System.assert(
          ex.getMessage().contains('between 0 and 100'),
          ex.getMessage()
        );
      }
    }

    // All-or-nothing: both properties must stay pending.
    String pendingStatus = ABCConstants.STATUS_CLOSED_PENDING;
    System.assertEquals(
      2,
      [
        SELECT COUNT()
        FROM Property__c
        WHERE
          Agent__c = :testData.currentAgent.Id
          AND Status__c = :pendingStatus
      ]
    );
  }
}
