public without sharing class YearToDateService {
  private static final Set<String> CLOSED_STATUSES = new Set<String>{
    ABCConstants.STATUS_CLOSED_PENDING,
    ABCConstants.STATUS_CLOSED_APPROVED
  };

  // 1. Called from the Property trigger
  public static void handle(
    List<Property__c> newRecords,
    Map<Id, Property__c> oldMap
  ) {
    if (newRecords == null && oldMap == null) {
      return;
    }

    Set<Id> agentIds = new Set<Id>();
    Set<Id> officeIds = new Set<Id>();

    List<Property__c> properties = newRecords != null
      ? newRecords
      : oldMap.values();

    for (Property__c property : properties) {
      agentIds.add(property.Agent__c);
      officeIds.add(property.Sales_Office__c);

      // Also recalculate previous agent and office
      if (oldMap != null && oldMap.containsKey(property.Id)) {
        Property__c oldProperty = oldMap.get(property.Id);

        agentIds.add(oldProperty.Agent__c);
        officeIds.add(oldProperty.Sales_Office__c);
      }
    }

    recalculate(agentIds, officeIds);
  }

  // 2. Recalculate affected agents and offices
  public static void recalculate(Set<Id> agentIds, Set<Id> officeIds) {
    if (agentIds != null) {
      agentIds.remove(null);

      if (!agentIds.isEmpty()) {
        recalculateAgents(agentIds);
      }
    }

    if (officeIds != null) {
      officeIds.remove(null);

      if (!officeIds.isEmpty()) {
        recalculateOffices(officeIds);
      }
    }
  }

  // 3. Calculate agent YTD totals
  private static void recalculateAgents(Set<Id> agentIds) {
    List<Contact> agents = [
      SELECT Id, Year_to_Date_Total_Sales__c, Year_to_Date_Total_Commissions__c
      FROM Contact
      WHERE Id IN :agentIds
      FOR UPDATE
    ];

    Map<Id, Decimal> salesByAgent = new Map<Id, Decimal>();
    Map<Id, Decimal> commissionsByAgent = new Map<Id, Decimal>();

    for (Id agentId : agentIds) {
      salesByAgent.put(agentId, 0);
      commissionsByAgent.put(agentId, 0);
    }

    for (AggregateResult result : [
      SELECT
        Agent__c agentId,
        Status__c status,
        SUM(Sales_Price__c) totalSales,
        SUM(Agent_Commission_Amount__c) totalCommissions
      FROM Property__c
      WHERE
        Agent__c IN :agentIds
        AND Status__c IN :CLOSED_STATUSES
        AND Sale_Date__c = THIS_YEAR
      GROUP BY Agent__c, Status__c
    ]) {
      Id agentId = (Id) result.get('agentId');

      Decimal sales = (Decimal) result.get('totalSales');
      Decimal commissions = (Decimal) result.get('totalCommissions');

      salesByAgent.put(
        agentId,
        salesByAgent.get(agentId) + (sales == null ? 0 : sales)
      );

      if (
        (String) result.get('status') == ABCConstants.STATUS_CLOSED_APPROVED
      ) {
        commissionsByAgent.put(
          agentId,
          commissionsByAgent.get(agentId) +
          (commissions == null ? 0 : commissions)
        );
      }
    }

    List<Contact> agentsToUpdate = new List<Contact>();

    for (Contact agent : agents) {
      Decimal sales = salesByAgent.get(agent.Id);
      Decimal commissions = commissionsByAgent.get(agent.Id);

      if (
        agent.Year_to_Date_Total_Sales__c != sales ||
        agent.Year_to_Date_Total_Commissions__c != commissions
      ) {
        agent.Year_to_Date_Total_Sales__c = sales;
        agent.Year_to_Date_Total_Commissions__c = commissions;

        agentsToUpdate.add(agent);
      }
    }

    if (!agentsToUpdate.isEmpty()) {
      update agentsToUpdate;
    }
  }

  // 4. Calculate sales office YTD totals
  private static void recalculateOffices(Set<Id> officeIds) {
    List<Sales_Office__c> offices = [
      SELECT Id, Year_to_Date_Sales__c
      FROM Sales_Office__c
      WHERE Id IN :officeIds
      FOR UPDATE
    ];

    Map<Id, Decimal> salesByOffice = new Map<Id, Decimal>();

    for (Id officeId : officeIds) {
      salesByOffice.put(officeId, 0);
    }

    for (AggregateResult result : [
      SELECT Sales_Office__c officeId, SUM(Sales_Price__c) totalSales
      FROM Property__c
      WHERE
        Sales_Office__c IN :officeIds
        AND Status__c IN :CLOSED_STATUSES
        AND Sale_Date__c = THIS_YEAR
      GROUP BY Sales_Office__c
    ]) {
      Id officeId = (Id) result.get('officeId');
      Decimal sales = (Decimal) result.get('totalSales');

      salesByOffice.put(officeId, sales == null ? 0 : sales);
    }

    List<Sales_Office__c> officesToUpdate = new List<Sales_Office__c>();

    for (Sales_Office__c office : offices) {
      Decimal sales = salesByOffice.get(office.Id);

      if (office.Year_to_Date_Sales__c != sales) {
        office.Year_to_Date_Sales__c = sales;
        officesToUpdate.add(office);
      }
    }

    if (!officesToUpdate.isEmpty()) {
      update officesToUpdate;
    }
  }
}
