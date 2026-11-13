public with sharing class AgentSelector {
  // 1. Find the agent linked to the logged-in user
  public static List<Contact> selectByUserId(Id userId) {
    if (userId == null) {
      return new List<Contact>();
    }

    return [
      SELECT
        Id,
        Agent_User__c,
        Sales_Office__c,
        Year_to_Date_Total_Sales__c,
        Year_to_Date_Total_Commissions__c
      FROM Contact
      WHERE Agent_User__c = :userId
      WITH USER_MODE
      LIMIT 2
    ];
  }

  // 2. Lock agent during property claiming
  public static Contact lockById(Id agentId) {
    if (agentId == null) {
      throw new ABCException('Agent ID is required.');
    }

    List<Contact> agents = [
      SELECT
        Id,
        Agent_User__c,
        Sales_Office__c,
        Year_to_Date_Total_Sales__c, // <-- Added this field
        Year_to_Date_Total_Commissions__c // <-- Added this field
      FROM Contact
      WHERE Id = :agentId
      WITH USER_MODE
      FOR UPDATE
    ];

    if (agents.isEmpty()) {
      throw new ABCException('Your agent record is unavailable.');
    }

    return agents[0];
  }
}
