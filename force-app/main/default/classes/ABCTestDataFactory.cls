/**
 * Builds test data inside each test. Users and records are created inside
 * System.runAs so that user DML and record DML in the same transaction do not
 * raise MIXED_DML_OPERATION. The only org data read is a Standard profile,
 * which every org has.
 */
@isTest
public class ABCTestDataFactory {
  private static Integer sequenceNumber = 0;

  public class Dataset {
    public User manager;
    public User agentUser;
    public User otherAgentUser;
    public Sales_Region__c region;
    public Sales_Office__c office;
    public Sales_Office__c otherOffice;
    public Contact currentAgent;
    public Contact otherAgent;
  }

  public static Dataset buildDataset() {
    Dataset testData = new Dataset();
    System.runAs(new User(Id = UserInfo.getUserId())) {
      testData.manager = createUser();
      testData.agentUser = createUser();
      testData.otherAgentUser = createUser();

      assignPermission(testData.manager.Id, 'MB_RealEstateManager');
      assignPermission(testData.agentUser.Id, 'MB_RealEstateAgent');
      assignPermission(testData.otherAgentUser.Id, 'MB_RealEstateAgent');

      Account account = new Account(Name = 'ABC Real Estate ' + nextSequence());
      insert account;

      testData.region = new Sales_Region__c(
        Name = 'Test Region ' + nextSequence(),
        Regional_Manager__c = testData.manager.Id
      );
      insert testData.region;

      testData.office = newOffice(testData.region.Id);
      testData.otherOffice = newOffice(testData.region.Id);
      insert new List<Sales_Office__c>{ testData.office, testData.otherOffice };

      testData.currentAgent = newAgent(
        account.Id,
        testData.agentUser.Id,
        testData.office.Id
      );
      testData.otherAgent = newAgent(
        account.Id,
        testData.otherAgentUser.Id,
        testData.office.Id
      );
      insert new List<Contact>{ testData.currentAgent, testData.otherAgent };
    }
    return testData;
  }

  public static User createUser() {
    Integer sequenceValue = nextSequence();
    String uniqueSuffix =
      String.valueOf(sequenceValue) +
      String.valueOf(DateTime.now().getTime()) +
      String.valueOf(Crypto.getRandomInteger()).replace('-', '');
    User testUser = new User(
      Alias = 'abc' + sequenceValue,
      Email = 'abc' + uniqueSuffix + '@example.com',
      EmailEncodingKey = 'UTF-8',
      LastName = 'ABCTest' + sequenceValue,
      LanguageLocaleKey = 'en_US',
      LocaleSidKey = 'en_US',
      ProfileId = standardProfileId(),
      TimeZoneSidKey = 'America/Los_Angeles',
      UserName = 'abc' + uniqueSuffix + '@abc-test.example.com'
    );
    insert testUser;
    return testUser;
  }

  /**
   * Returns a Standard profile Id. Looks up the English name first, then
   * falls back to any Standard user type so the lookup works in orgs with
   * translated or renamed profiles.
   */
  private static Id standardProfileId() {
    List<Profile> profiles = [
      SELECT Id
      FROM Profile
      WHERE Name = 'Standard User'
      LIMIT 1
    ];
    if (profiles.isEmpty()) {
      profiles = [SELECT Id FROM Profile WHERE UserType = 'Standard' LIMIT 1];
    }
    return profiles[0].Id;
  }

  public static Sales_Office__c newOffice(Id regionId) {
    return new Sales_Office__c(
      Name = 'Office ' + nextSequence(),
      Sales_Region__c = regionId
    );
  }

  public static Contact newAgent(Id accountId, Id userId, Id officeId) {
    return new Contact(
      LastName = 'Agent ' + nextSequence(),
      AccountId = accountId,
      Agent_User__c = userId,
      Sales_Office__c = officeId,
      Default_Commission_Split__c = 40
    );
  }

  /** Unsaved property. The caller inserts it. */
  public static Property__c newProperty(
    Id officeId,
    Id agentId,
    Decimal price,
    String status,
    Date saleDate
  ) {
    Integer sequenceValue = nextSequence();
    return new Property__c(
      Name = sequenceValue + ' Test Street',
      Property_Street__c = sequenceValue + ' Test Street',
      Property_City__c = 'Atlanta',
      Listing_Price__c = price == null ? 100000 : price,
      Sales_Price__c = price,
      Sale_Date__c = saleDate,
      Status__c = status,
      Sales_Office__c = officeId,
      Agent__c = agentId,
      Agent_Commission_Percentage__c = 40
    );
  }

  public static List<Property__c> createOpenProperties(
    Id officeId,
    Integer count
  ) {
    List<Property__c> properties = new List<Property__c>();
    for (Integer i = 0; i < count; i++) {
      properties.add(
        newProperty(officeId, null, null, ABCConstants.STATUS_OPEN, null)
      );
    }
    insert properties;
    return properties;
  }

  public static Date saleDateThisYear() {
    return Date.newInstance(Date.today().year(), 3, 15);
  }

  public static Date saleDateLastYear() {
    return Date.newInstance(Date.today().year() - 1, 6, 1);
  }

  public static void assertTotals(
    Id agentId,
    Id officeId,
    Decimal expectedSales,
    Decimal expectedCommissions
  ) {
    Contact savedAgent = [
      SELECT Year_to_Date_Total_Sales__c, Year_to_Date_Total_Commissions__c
      FROM Contact
      WHERE Id = :agentId
    ];
    Sales_Office__c savedOffice = [
      SELECT Year_to_Date_Sales__c
      FROM Sales_Office__c
      WHERE Id = :officeId
    ];
    System.assertEquals(
      expectedSales,
      savedAgent.Year_to_Date_Total_Sales__c,
      'Agent YTD sales'
    );
    System.assertEquals(
      expectedCommissions,
      savedAgent.Year_to_Date_Total_Commissions__c,
      'Agent YTD commissions'
    );
    System.assertEquals(
      expectedSales,
      savedOffice.Year_to_Date_Sales__c,
      'Office YTD sales'
    );
  }

  private static Integer nextSequence() {
    sequenceNumber++;
    return sequenceNumber;
  }

  public static void assignPermission(Id userId, String permissionSetName) {
    PermissionSet permissionSet = [
      SELECT Id
      FROM PermissionSet
      WHERE Name = :permissionSetName
      LIMIT 1
    ];
    insert new PermissionSetAssignment(
      AssigneeId = userId,
      PermissionSetId = permissionSet.Id
    );
  }
  public static void claimProperties(Id agentId, Set<Id> propertyIds) {
    Contact currentAgent = [
      SELECT Agent_User__c, Sales_Office__c
      FROM Contact
      WHERE Id = :agentId
    ];
    System.runAs(new User(Id = currentAgent.Agent_User__c)) {
      PropertyClaimService.claimProperties(
        currentAgent.Sales_Office__c,
        new List<Id>(propertyIds)
      );
    }
  }
  public static void approveProperties(
    Id regionId,
    Set<Id> propertyIds,
    Map<Id, Decimal> overrides
  ) {
    List<Id> selectedPropertyIds = new List<Id>(propertyIds);
    List<Decimal> percentages = new List<Decimal>();
    for (Id propertyId : selectedPropertyIds)
      percentages.add(overrides == null ? null : overrides.get(propertyId));
    CommissionApprovalService.approveProperties(
      regionId,
      selectedPropertyIds,
      percentages
    );
  }
}
