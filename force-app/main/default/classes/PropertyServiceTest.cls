@isTest
private class PropertyServiceTest {
  @isTest
  static void claimAssignsAgentAndDefaultSplit() {
    ABCTestDataFactory.Dataset testData = ABCTestDataFactory.buildDataset();
    Property__c propertyRecord = ABCTestDataFactory.createOpenProperties(
      testData.office.Id,
      1
    )[0];

    Test.startTest();
    ABCTestDataFactory.claimProperties(
      testData.currentAgent.Id,
      new Set<Id>{ propertyRecord.Id }
    );
    Test.stopTest();

    Property__c saved = [
      SELECT Status__c, Agent__c, Agent_Commission_Percentage__c
      FROM Property__c
      WHERE Id = :propertyRecord.Id
    ];
    System.assertEquals(ABCConstants.STATUS_WORKING, saved.Status__c);
    System.assertEquals(testData.currentAgent.Id, saved.Agent__c);
    System.assertEquals(40.00, saved.Agent_Commission_Percentage__c);
  }

  @isTest
  static void claimRejectsMoreThanTheWorkingCap() {
    ABCTestDataFactory.Dataset testData = ABCTestDataFactory.buildDataset();
    List<Property__c> properties = ABCTestDataFactory.createOpenProperties(
      testData.office.Id,
      ABCConstants.MAX_WORKING_PER_AGENT + 1
    );
    Set<Id> ids = new Map<Id, Property__c>(properties).keySet();

    Boolean threw = false;
    try {
      ABCTestDataFactory.claimProperties(testData.currentAgent.Id, ids);
    } catch (ABCException ex) {
      threw = true;
    }
    System.assert(threw, 'Expected ABCException for the working-property cap');

    System.assertEquals(
      0,
      [
        SELECT COUNT()
        FROM Property__c
        WHERE Agent__c = :testData.currentAgent.Id
      ],
      'No property should be assigned after a rejected claim'
    );
  }

  @isTest
  static void claimFailsAtomicallyWhenAnyPropertyAlreadyClaimed() {
    ABCTestDataFactory.Dataset testData = ABCTestDataFactory.buildDataset();
    List<Property__c> properties = ABCTestDataFactory.createOpenProperties(
      testData.office.Id,
      2
    );

    // Another agent claims the second property after our list loaded.
    ABCTestDataFactory.claimProperties(
      testData.otherAgent.Id,
      new Set<Id>{ properties[1].Id }
    );

    Boolean threw = false;
    try {
      ABCTestDataFactory.claimProperties(
        testData.currentAgent.Id,
        new Set<Id>{ properties[0].Id, properties[1].Id }
      );
    } catch (ABCException ex) {
      threw = true;
    }
    System.assert(threw, 'Expected ABCException for a stale claim');

    // All-or-nothing: the first property must remain unclaimed.
    Property__c first = [
      SELECT Status__c, Agent__c
      FROM Property__c
      WHERE Id = :properties[0].Id
    ];
    System.assertEquals(ABCConstants.STATUS_OPEN, first.Status__c);
    System.assertEquals(null, first.Agent__c);
  }

  @isTest
  static void approvalRequiresRegionalManager() {
    ABCTestDataFactory.Dataset testData = ABCTestDataFactory.buildDataset();
    Property__c propertyRecord = ABCTestDataFactory.newProperty(
      testData.office.Id,
      testData.currentAgent.Id,
      100000,
      ABCConstants.STATUS_CLOSED_PENDING,
      ABCTestDataFactory.saleDateThisYear()
    );
    insert propertyRecord;

    Boolean threw = false;
    System.runAs(testData.agentUser) {
      try {
        ABCTestDataFactory.approveProperties(
          testData.region.Id,
          new Set<Id>{ propertyRecord.Id },
          null
        );
      } catch (ABCException ex) {
        threw = true;
      }
    }
    System.assert(threw, 'Agents must not approve commissions');

    System.assertEquals(
      ABCConstants.STATUS_CLOSED_PENDING,
      [SELECT Status__c FROM Property__c WHERE Id = :propertyRecord.Id]
      .Status__c
    );
  }

  @isTest
  static void approvalComputesCommissionAndRollsUpTotals() {
    ABCTestDataFactory.Dataset testData = ABCTestDataFactory.buildDataset();
    Property__c propertyRecord = ABCTestDataFactory.newProperty(
      testData.office.Id,
      testData.currentAgent.Id,
      100000,
      ABCConstants.STATUS_CLOSED_PENDING,
      ABCTestDataFactory.saleDateThisYear()
    );
    insert propertyRecord;

    System.runAs(testData.manager) {
      // Manager overrides the 40% default to 50%.
      ABCTestDataFactory.approveProperties(
        testData.region.Id,
        new Set<Id>{ propertyRecord.Id },
        new Map<Id, Decimal>{ propertyRecord.Id => 50.0 }
      );
    }

    Property__c saved = [
      SELECT
        Status__c,
        Agent_Commission_Amount__c,
        Agent_Commission_Percentage__c
      FROM Property__c
      WHERE Id = :propertyRecord.Id
    ];
    System.assertEquals(ABCConstants.STATUS_CLOSED_APPROVED, saved.Status__c);
    System.assertEquals(50.00, saved.Agent_Commission_Percentage__c);
    System.assertEquals(1500.00, saved.Agent_Commission_Amount__c); // 100,000 x 3% x 50%
    ABCTestDataFactory.assertTotals(
      testData.currentAgent.Id,
      testData.office.Id,
      100000.00,
      1500.00
    );
  }

  @isTest
  static void approvalRejectsPropertiesNotPendingApproval() {
    ABCTestDataFactory.Dataset testData = ABCTestDataFactory.buildDataset();
    Property__c propertyRecord = ABCTestDataFactory.createOpenProperties(
      testData.office.Id,
      1
    )[0];

    Boolean threw = false;
    System.runAs(testData.manager) {
      try {
        ABCTestDataFactory.approveProperties(
          testData.region.Id,
          new Set<Id>{ propertyRecord.Id },
          null
        );
      } catch (ABCException ex) {
        threw = true;
      }
    }
    System.assert(threw, 'Open properties must not be approvable');

    System.assertEquals(
      ABCConstants.STATUS_OPEN,
      [SELECT Status__c FROM Property__c WHERE Id = :propertyRecord.Id]
      .Status__c
    );
  }
}
