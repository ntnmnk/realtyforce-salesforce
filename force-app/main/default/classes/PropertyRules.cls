/**
 * Business rules for Property__c, shared by PropertyTriggerHandler and
 * PropertyClaimService:
 *   - before-save rules (defaults, validation, commission calculation)
 *   - agent locking
 *   - the maximum-Working-properties limit
 *
 * Runs WITHOUT sharing on purpose: the capacity check must count ALL of an
 * agent's Working properties, not only the ones the running user can see.
 */
public without sharing class PropertyRules {
  private static final Integer MAX_WORKING = ABCConstants.MAX_WORKING_PER_AGENT;
  private static final String WORKING = ABCConstants.STATUS_WORKING;
  private static final String CLOSED_APPROVED = ABCConstants.STATUS_CLOSED_APPROVED;

  public static final Set<String> CLOSED_STATUSES = new Set<String>{
    ABCConstants.STATUS_CLOSED_PENDING,
    ABCConstants.STATUS_CLOSED_APPROVED
  };

  public static final String ERR_NO_AGENT = 'A Working property must have an agent.';
  public static final String ERR_LIMIT_EXCEEDED =
    'An agent can have at most ' +
    MAX_WORKING +
    ' Working properties.';
  public static final String ERR_DEFAULT_SPLIT = 'Agent default commission percentage must be between 0 and 100.';
  public static final String ERR_COMMISSION_PERCENT = 'Commission percentage must be between 0 and 100.';
  public static final String ERR_SALES_PRICE = 'A nonnegative sales price is required.';

  // =====================================================
  // 1. BEFORE INSERT / BEFORE UPDATE
  // =====================================================

  public static void applyBeforeSave(
    List<Property__c> properties,
    Map<Id, Property__c> oldMap
  ) {
    if (properties == null || properties.isEmpty()) {
      return;
    }

    // Lock agents first so the capacity check and the later YTD rollups
    // see a stable view.
    Map<Id, Contact> agents = lockAgents(properties, oldMap);

    List<Property__c> validProperties = new List<Property__c>();

    for (Property__c prop : properties) {
      if (applyRules(prop, getOldProp(prop, oldMap), agents)) {
        validProperties.add(prop);
      }
    }

    // Rule 5: enforce the maximum number of Working properties.
    validateWorkingCapacity(validProperties, oldMap);
  }

  /** Applies rules 1-4. Returns true if the record passed and needs the capacity check. */
  private static Boolean applyRules(
    Property__c prop,
    Property__c oldProp,
    Map<Id, Contact> agents
  ) {
    if (prop.hasErrors()) {
      return false;
    }

    // Rule 1: Working requires an agent.
    if (isWorkingWithoutAgent(prop)) {
      prop.addError(ERR_NO_AGENT);
      return false;
    }

    // Rule 2: copy the agent's default commission when first claimed or reassigned.
    if (isNewWorkingAssignment(prop, oldProp)) {
      Contact agent = agents.get(prop.Agent__c);
      Decimal defaultSplit = agent == null
        ? null
        : agent.Default_Commission_Split__c;

      if (!isValidPercentage(defaultSplit)) {
        prop.addError(ERR_DEFAULT_SPLIT);
        return false;
      }

      prop.Agent_Commission_Percentage__c = defaultSplit;
    }

    // Rule 3: defaults for closed properties.
    if (CLOSED_STATUSES.contains(prop.Status__c)) {
      if (prop.Sale_Date__c == null) {
        prop.Sale_Date__c = Date.today();
      }

      if (prop.Sales_Price__c == null) {
        prop.Sales_Price__c = prop.Listing_Price__c;
      }
    }

    // Rule 4: commission is calculated, and payable, only after approval.
    if (prop.Status__c == CLOSED_APPROVED) {
      if (!isValidPercentage(prop.Agent_Commission_Percentage__c)) {
        prop.addError(ERR_COMMISSION_PERCENT);
        return false;
      }

      if (prop.Sales_Price__c == null || prop.Sales_Price__c < 0) {
        prop.addError(ERR_SALES_PRICE);
        return false;
      }

      prop.Agent_Commission_Amount__c =
        (prop.Sales_Price__c * prop.Agent_Commission_Percentage__c) / 100;
    } else {
      prop.Agent_Commission_Amount__c = null;
    }

    return true;
  }

  // =====================================================
  // 2. LOCK AGENT RECORDS
  // =====================================================

  /** For before delete, after undelete and inserts: there are no previous values. */
  public static Map<Id, Contact> lockAgents(List<Property__c> properties) {
    return lockAgents(properties, null);
  }

  /**
   * Locks every agent referenced by the records (current and previous agent).
   * No explicit ORDER BY: FOR UPDATE does not combine with it.
   * The YTD fields are selected so callers can read them from the returned
   * Contacts without an SObjectException.
   */
  public static Map<Id, Contact> lockAgents(
    List<Property__c> properties,
    Map<Id, Property__c> oldMap
  ) {
    Set<Id> agentIds = new Set<Id>();

    if (properties != null) {
      for (Property__c prop : properties) {
        agentIds.add(prop.Agent__c);

        Property__c oldProp = getOldProp(prop, oldMap);
        if (oldProp != null) {
          agentIds.add(oldProp.Agent__c);
        }
      }
    }
    agentIds.remove(null);

    if (agentIds.isEmpty()) {
      return new Map<Id, Contact>();
    }

    return new Map<Id, Contact>(
      [
        SELECT
          Id,
          Default_Commission_Split__c,
          Year_to_Date_Total_Sales__c,
          Year_to_Date_Total_Commissions__c
        FROM Contact
        WHERE Id IN :agentIds
        WITH SYSTEM_MODE
        FOR UPDATE
      ]
    );
  }

  // =====================================================
  // 3. COUNT WORKING PROPERTIES
  // =====================================================

  /** Single-ID method used by PropertyClaimService. */
  public static Integer countWorkingProperties(Id agentId) {
    if (agentId == null) {
      return 0;
    }
    return getWorkingPropertyCounts(new Set<Id>{ agentId }).get(agentId);
  }

  /** Working-property counts per agent, as currently stored in the database. */
  public static Map<Id, Integer> getWorkingPropertyCounts(Set<Id> agentIds) {
    Map<Id, Integer> counts = new Map<Id, Integer>();

    if (agentIds == null) {
      return counts;
    }

    for (Id agentId : agentIds) {
      if (agentId != null) {
        counts.put(agentId, 0);
      }
    }

    if (counts.isEmpty()) {
      return counts;
    }

    for (AggregateResult result : [
      SELECT Agent__c agentId, COUNT(Id) total
      FROM Property__c
      WHERE Agent__c IN :counts.keySet() AND Status__c = :WORKING
      WITH SYSTEM_MODE
      GROUP BY Agent__c
    ]) {
      counts.put((Id) result.get('agentId'), (Integer) result.get('total'));
    }

    return counts;
  }

  // =====================================================
  // 4. VALIDATE CAPACITY: BEFORE INSERT / BEFORE UPDATE
  // =====================================================

  public static void validateWorkingCapacity(List<Property__c> properties) {
    validateWorkingCapacity(properties, null);
  }

  public static void validateWorkingCapacity(
    List<Property__c> properties,
    Map<Id, Property__c> oldMap
  ) {
    if (properties == null || properties.isEmpty()) {
      return;
    }

    Set<Id> agentIds = new Set<Id>();
    List<Property__c> claims = new List<Property__c>();
    List<Id> releasedAgentIds = new List<Id>();

    // Step 1: classify each record as a new claim and/or a released slot.
    for (Property__c prop : properties) {
      // Records that already failed will not be saved, so they neither claim
      // nor release a slot.
      if (prop.hasErrors()) {
        continue;
      }

      if (isWorkingWithoutAgent(prop)) {
        prop.addError(ERR_NO_AGENT);
        continue;
      }

      Property__c oldProp = getOldProp(prop, oldMap);

      if (isNewWorkingAssignment(prop, oldProp)) {
        claims.add(prop);
        agentIds.add(prop.Agent__c);
      }

      // Leaving Working, or moving to another agent, frees a slot for the old agent.
      if (
        isWorkingWithAgent(oldProp) &&
        (!isWorkingWithAgent(prop) || oldProp.Agent__c != prop.Agent__c)
      ) {
        releasedAgentIds.add(oldProp.Agent__c);
        agentIds.add(oldProp.Agent__c);
      }
    }

    if (claims.isEmpty()) {
      return;
    }

    // Step 2: current counts from the database (one query for all agents).
    Map<Id, Integer> counts = getWorkingPropertyCounts(agentIds);

    // Step 3: give back the slots being released.
    for (Id agentId : releasedAgentIds) {
      counts.put(agentId, counts.get(agentId) - 1);
    }

    // Step 4: reserve a slot for each claim, or reject it when the agent is full.
    for (Property__c prop : claims) {
      Integer currentCount = counts.get(prop.Agent__c);

      if (currentCount >= MAX_WORKING) {
        prop.addError(ERR_LIMIT_EXCEEDED);
      } else {
        counts.put(prop.Agent__c, currentCount + 1);
      }
    }
  }

  // =====================================================
  // 5. VALIDATE CAPACITY: AFTER UNDELETE
  // =====================================================

  public static void validateRestoredWorkingCapacity(
    List<Property__c> properties
  ) {
    if (properties == null || properties.isEmpty()) {
      return;
    }

    List<Property__c> restoredWorking = new List<Property__c>();
    Map<Id, Integer> restoredPerAgent = new Map<Id, Integer>();

    for (Property__c prop : properties) {
      if (prop.Status__c != WORKING) {
        continue;
      }

      if (prop.Agent__c == null) {
        prop.addError(ERR_NO_AGENT);
        continue;
      }

      restoredWorking.add(prop);

      Integer existing = restoredPerAgent.get(prop.Agent__c);
      restoredPerAgent.put(prop.Agent__c, existing == null ? 1 : existing + 1);
    }

    if (restoredWorking.isEmpty()) {
      return;
    }

    // The restored rows are already in the database count, so back them out
    // first, then admit them one by one: only the overflow is rejected.
    Map<Id, Integer> counts = getWorkingPropertyCounts(
      restoredPerAgent.keySet()
    );
    for (Id agentId : restoredPerAgent.keySet()) {
      counts.put(agentId, counts.get(agentId) - restoredPerAgent.get(agentId));
    }

    for (Property__c prop : restoredWorking) {
      Integer currentCount = counts.get(prop.Agent__c);

      if (currentCount >= MAX_WORKING) {
        prop.addError(ERR_LIMIT_EXCEEDED);
      } else {
        counts.put(prop.Agent__c, currentCount + 1);
      }
    }
  }

  // =====================================================
  // 6. SHARED CHECKS
  // =====================================================

  /** True when the record is being claimed now: newly Working, or Working under a different agent. */
  public static Boolean isNewWorkingAssignment(
    Property__c prop,
    Property__c oldProp
  ) {
    return isWorkingWithAgent(prop) &&
      (!isWorkingWithAgent(oldProp) || oldProp.Agent__c != prop.Agent__c);
  }

  public static Boolean isWorkingWithAgent(Property__c prop) {
    return prop != null && prop.Status__c == WORKING && prop.Agent__c != null;
  }

  public static Boolean isWorkingWithoutAgent(Property__c prop) {
    return prop != null && prop.Status__c == WORKING && prop.Agent__c == null;
  }

  // =====================================================
  // 7. PRIVATE HELPERS
  // =====================================================

  /** Previous version of the record, or null on insert / when no old map is supplied. */
  private static Property__c getOldProp(
    Property__c prop,
    Map<Id, Property__c> oldMap
  ) {
    return (oldMap == null || prop.Id == null) ? null : oldMap.get(prop.Id);
  }

  private static Boolean isValidPercentage(Decimal percentage) {
    return percentage != null && percentage >= 0 && percentage <= 100;
  }
}
