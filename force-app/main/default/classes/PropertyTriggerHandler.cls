
/**
 * ABC Real Estate Property Trigger Handler
 *
 * BEFORE SAVE:
 *   1. Detect new Working assignments.
 *   2. Calculate approved commissions.
 *   3. Lock affected agents.
 *   4. Copy default commission split on first claim.
 *   5. Count existing and proposed Working properties.
 *   6. Prevent exceeding five Working properties.
 *
 * AFTER CHANGE:
 *   1. Validate restored Working properties.
 *   2. Find affected agents and sales offices.
 *   3. Recalculate agent YTD sales and commissions.
 *   4. Recalculate sales office YTD sales.
 *
 * Only TWO handler methods.
 * All SOQL queries and DML are bulkified.
 */
public without sharing class PropertyTriggerHandler {

    // Business constants from the project
    private static final String WORKING = 'Working';
    private static final String PENDING = 'Closed Pending Approval';
    private static final String APPROVED = 'Closed Approved';

    private static final Integer MAX_WORKING = 5;
    private static final Decimal AGENCY_RATE = 0.03;

    private static final Set<String> CLOSED_STATUSES =
        new Set<String>{PENDING, APPROVED};


    // ====================================================
    // METHOD 1: BEFORE INSERT AND BEFORE UPDATE
    // ====================================================

    public static void beforeSave(
        List<Property__c> properties,
        Map<Id, Property__c> oldMap
    ) {

        // Stores properties taking a new Working slot
        List<Property__c> newClaims = new List<Property__c>();

        // Stores affected agent IDs
        Set<Id> agentIds = new Set<Id>();

        // Stores updated property IDs, so we can exclude
        // them from the database count and count them once
        Set<Id> changedPropertyIds = new Set<Id>();


        // STEP 1: Find new claims and calculate commissions

        for (Property__c property : properties) {

            // Previous version of the property
            // Null when inserting a new property
            Property__c oldProperty = oldMap.get(property.Id);

            if (property.Id != null) {
                changedPropertyIds.add(property.Id);
            }

            // RULE 1: A Working property needs an agent
            if (property.Status__c == WORKING) {

                if (property.Agent__c == null) {
                    property.addError(
                        'A Working property must have an agent.'
                    );
                }
                else if (
                    oldProperty == null ||
                    oldProperty.Status__c != WORKING ||
                    oldProperty.Agent__c != property.Agent__c
                ) {

                    // This property is taking a Working slot
                    newClaims.add(property);
                    agentIds.add(property.Agent__c);

                    // Include the previous agent on reassignment
                    if (
                        oldProperty != null &&
                        oldProperty.Status__c == WORKING &&
                        oldProperty.Agent__c != null
                    ) {
                        agentIds.add(oldProperty.Agent__c);
                    }
                }
            }


            // RULE 2: Calculate commission when approved
            if (property.Status__c == APPROVED) {

                // Recalculate only when a relevant field changed.
                // This preserves historical amounts when the
                // agency commission rate changes in the future.
                Boolean recalculate =
                    oldProperty == null ||
                    oldProperty.Status__c != APPROVED ||
                    property.Sales_Price__c !=
                        oldProperty.Sales_Price__c ||
                    property.Agent_Commission_Percentage__c !=
                        oldProperty.Agent_Commission_Percentage__c ||
                    property.Agent_Commission_Amount__c !=
                        oldProperty.Agent_Commission_Amount__c;

                if (recalculate) {

                    // The PDF says an existing workflow fills
                    // Sales Price from Listing Price if blank.
                    Decimal price = property.Sales_Price__c;

                    if (price == null) {
                        price = property.Listing_Price__c;
                    }

                    if (
                        property.Agent__c == null ||
                        property.Agent_Commission_Percentage__c == null ||
                        price == null
                    ) {
                        property.addError(
                            'Approved property requires an agent, price and commission split.'
                        );
                    }
                    else {

                        // Example:
                        // 100000 * 0.03 * 40 / 100 = 1200
                        property.Agent_Commission_Amount__c = (
                            price *
                            AGENCY_RATE *
                            property.Agent_Commission_Percentage__c / 100
                        ).setScale(2);
                    }
                }
            }
            else if (
                oldProperty != null &&
                oldProperty.Status__c == APPROVED
            ) {
                // No longer approved
                property.Agent_Commission_Amount__c = null;
            }
        }


        // No new claims: no capacity query is required
        if (newClaims.isEmpty()) {
            return;
        }


        // STEP 2: Lock affected agents
        //
        // FOR UPDATE prevents two transactions from
        // simultaneously taking the same available capacity.

        Map<Id, Contact> agents;

        try {
            agents = new Map<Id, Contact>([
                SELECT Id, Default_Commission_Split__c
                FROM Contact
                WHERE Id IN :agentIds
                FOR UPDATE
            ]);
        }
        catch (QueryException error) {

            for (Property__c property : newClaims) {
                property.addError(
                    'Agent is busy. Please try again.'
                );
            }

            return;
        }


        // STEP 3: Set default commission on first claim

        for (Property__c property : newClaims) {

            // Skip invalid properties
            if (property.hasErrors()) {
                continue;
            }

            Contact agent = agents.get(property.Agent__c);

            if (agent == null) {
                property.addError(
                    'Assigned agent was not found.'
                );
                continue;
            }

            Property__c oldProperty = oldMap.get(property.Id);

            Boolean enteringWorking =
                oldProperty == null ||
                oldProperty.Status__c != WORKING;

            if (enteringWorking) {

                if (agent.Default_Commission_Split__c == null) {
                    property.addError(
                        'Agent needs a default commission split.'
                    );
                    continue;
                }

                property.Agent_Commission_Percentage__c =
                    agent.Default_Commission_Split__c;
            }
        }


        // STEP 4: Count existing Working properties
        //
        // Exclude properties currently being updated.
        // Their final status is handled in the next steps.

        Map<Id, Integer> workingCounts =
            new Map<Id, Integer>();

        // Start each agent at zero
        for (Id agentId : agentIds) {
            workingCounts.put(agentId, 0);
        }

        // One query for all affected agents
        for (AggregateResult result : [
            SELECT Agent__c agentId,
                   COUNT(Id) propertyCount
            FROM Property__c
            WHERE Agent__c IN :agentIds
            AND Status__c = :WORKING
            AND Id NOT IN :changedPropertyIds
            GROUP BY Agent__c
        ]) {

            workingCounts.put(
                (Id) result.get('agentId'),
                (Integer) result.get('propertyCount')
            );
        }


        // STEP 5: Add Working assignments that remain occupied
        //
        // Example: a property was already Working and is still
        // Working with the same agent after this update.
        //
        // If a property has an error, its old assignment cannot
        // safely be counted as a freed slot.

        for (Property__c property : properties) {

            Property__c oldProperty = oldMap.get(property.Id);

            if (
                oldProperty == null ||
                oldProperty.Status__c != WORKING ||
                oldProperty.Agent__c == null ||
                !workingCounts.containsKey(oldProperty.Agent__c)
            ) {
                continue;
            }

            Boolean keepsOldSlot =
                property.hasErrors() ||
                (
                    property.Status__c == WORKING &&
                    property.Agent__c == oldProperty.Agent__c
                );

            if (keepsOldSlot) {

                Id oldAgentId = oldProperty.Agent__c;

                workingCounts.put(
                    oldAgentId,
                    workingCounts.get(oldAgentId) + 1
                );
            }
        }


        // STEP 6: Check the proposed Working-property counts

        Boolean overLimit = false;

        for (Property__c property : newClaims) {

            if (property.hasErrors()) {
                continue;
            }

            Id agentId = property.Agent__c;

            Integer count = workingCounts.get(agentId);

            count++;

            workingCounts.put(agentId, count);

            if (count > MAX_WORKING) {
                overLimit = true;
            }
        }

        // Reject the full batch if it would exceed capacity.
        // This keeps same-batch reassignments consistent.
        if (overLimit) {

            for (Property__c property : properties) {
                property.addError(
                    'Claim not saved. An agent cannot have more than 5 Working properties.'
                );
            }
        }
    }


    // ====================================================
    // METHOD 2: AFTER INSERT, UPDATE, DELETE AND UNDELETE
    // ====================================================

    public static void afterChange(
        List<Property__c> properties,
        Map<Id, Property__c> oldMap
    ) {

        try {

            // STEP 1: Check restored Working properties
            //
            // An undeleted Working property also counts
            // toward the maximum of five.

            if (Trigger.isUndelete) {

                Set<Id> restoredAgentIds = new Set<Id>();
                Boolean missingAgent = false;

                for (Property__c property : properties) {

                    if (property.Status__c == WORKING) {

                        if (property.Agent__c == null) {
                            missingAgent = true;
                        }
                        else {
                            restoredAgentIds.add(property.Agent__c);
                        }
                    }
                }

                if (missingAgent) {

                    for (Property__c property : properties) {
                        property.addError(
                            'Cannot restore. A Working property needs an agent.'
                        );
                    }

                    return;
                }

                if (!restoredAgentIds.isEmpty()) {

                    // Lock the affected agents first
                    List<Contact> lockedAgents = [
                        SELECT Id
                        FROM Contact
                        WHERE Id IN :restoredAgentIds
                        FOR UPDATE
                    ];

                    Boolean overLimit = false;

                    // Restored properties are already in database counts
                    for (AggregateResult result : [
                        SELECT Agent__c agentId,
                               COUNT(Id) propertyCount
                        FROM Property__c
                        WHERE Agent__c IN :restoredAgentIds
                        AND Status__c = :WORKING
                        GROUP BY Agent__c
                    ]) {

                        Integer count =
                            (Integer) result.get('propertyCount');

                        if (count > MAX_WORKING) {
                            overLimit = true;
                        }
                    }

                    if (overLimit) {

                        for (Property__c property : properties) {
                            property.addError(
                                'Cannot restore. Agent would exceed 5 Working properties.'
                            );
                        }

                        return;
                    }
                }
            }


            // STEP 2: Find affected agents and offices

            Set<Id> agentIds = new Set<Id>();
            Set<Id> officeIds = new Set<Id>();

            for (Property__c property : properties) {

                // On delete, old version is Trigger.old
                Property__c oldProperty = Trigger.isDelete
                    ? property
                    : oldMap.get(property.Id);

                Property__c newProperty = Trigger.isDelete
                    ? null
                    : property;

                Boolean wasClosed =
                    oldProperty != null &&
                    CLOSED_STATUSES.contains(oldProperty.Status__c);

                Boolean isClosed =
                    newProperty != null &&
                    CLOSED_STATUSES.contains(newProperty.Status__c);

                // Open / Working / Withdrawn do not
                // contribute to closed-sales totals.
                if (!wasClosed && !isClosed) {
                    continue;
                }

                // Skip changes unrelated to totals
                if (
                    Trigger.isUpdate &&
                    oldProperty.Status__c == newProperty.Status__c &&
                    oldProperty.Agent__c == newProperty.Agent__c &&
                    oldProperty.Sales_Office__c ==
                        newProperty.Sales_Office__c &&
                    oldProperty.Sale_Date__c == newProperty.Sale_Date__c &&
                    oldProperty.Sales_Price__c == newProperty.Sales_Price__c &&
                    oldProperty.Agent_Commission_Amount__c ==
                        newProperty.Agent_Commission_Amount__c
                ) {
                    continue;
                }

                // Include the old agent and office
                if (wasClosed) {

                    if (oldProperty.Agent__c != null) {
                        agentIds.add(oldProperty.Agent__c);
                    }

                    if (oldProperty.Sales_Office__c != null) {
                        officeIds.add(oldProperty.Sales_Office__c);
                    }
                }

                // Include the new agent and office
                if (isClosed) {

                    if (newProperty.Agent__c != null) {
                        agentIds.add(newProperty.Agent__c);
                    }

                    if (newProperty.Sales_Office__c != null) {
                        officeIds.add(newProperty.Sales_Office__c);
                    }
                }
            }


            // STEP 3: Recalculate Agent YTD Sales and Commissions

            if (!agentIds.isEmpty()) {

                Map<Id, Contact> agents =
                    new Map<Id, Contact>([
                        SELECT Id,
                               Year_To_Date_Total_Sales__c,
                               Year_To_Date_Total_Commissions__c
                        FROM Contact
                        WHERE Id IN :agentIds
                        FOR UPDATE
                    ]);

                // Reset the totals before recalculation
                for (Contact agent : agents.values()) {
                    agent.Year_To_Date_Total_Sales__c = 0;
                    agent.Year_To_Date_Total_Commissions__c = 0;
                }

                // Aggregate all closed properties for the current year
                for (AggregateResult result : [
                    SELECT Agent__c agentId,
                           Status__c propertyStatus,
                           SUM(Sales_Price__c) totalSales,
                           SUM(Agent_Commission_Amount__c) totalCommission
                    FROM Property__c
                    WHERE Agent__c IN :agentIds
                    AND Status__c IN :CLOSED_STATUSES
                    AND Sale_Date__c = THIS_YEAR
                    GROUP BY Agent__c, Status__c
                ]) {

                    Id agentId = (Id) result.get('agentId');

                    Contact agent = agents.get(agentId);

                    if (agent == null) {
                        continue;
                    }

                    Decimal sales =
                        (Decimal) result.get('totalSales');

                    Decimal commission =
                        (Decimal) result.get('totalCommission');

                    String status =
                        (String) result.get('propertyStatus');

                    // Pending and Approved both count as sales
                    if (sales != null) {
                        agent.Year_To_Date_Total_Sales__c += sales;
                    }

                    // Only Approved counts as earned commission
                    if (status == APPROVED && commission != null) {
                        agent.Year_To_Date_Total_Commissions__c +=
                            commission;
                    }
                }

                // Update all agents in one DML statement
                if (!agents.isEmpty()) {
                    update agents.values();
                }
            }


            // STEP 4: Recalculate Sales Office YTD Sales

            if (!officeIds.isEmpty()) {

                Map<Id, Sales_Office__c> offices =
                    new Map<Id, Sales_Office__c>([
                        SELECT Id, Year_To_Date_Sales__c
                        FROM Sales_Office__c
                        WHERE Id IN :officeIds
                        FOR UPDATE
                    ]);

                // Start at zero
                for (Sales_Office__c office : offices.values()) {
                    office.Year_To_Date_Sales__c = 0;
                }

                // Count all current-year closed sales
                for (AggregateResult result : [
                    SELECT Sales_Office__c officeId,
                           SUM(Sales_Price__c) totalSales
                    FROM Property__c
                    WHERE Sales_Office__c IN :officeIds
                    AND Status__c IN :CLOSED_STATUSES
                    AND Sale_Date__c = THIS_YEAR
                    GROUP BY Sales_Office__c
                ]) {

                    Id officeId = (Id) result.get('officeId');

                    Sales_Office__c office = offices.get(officeId);

                    if (
                        office != null &&
                        result.get('totalSales') != null
                    ) {
                        office.Year_To_Date_Sales__c =
                            (Decimal) result.get('totalSales');
                    }
                }

                // Update all offices in one DML statement
                if (!offices.isEmpty()) {
                    update offices.values();
                }
            }

        } catch (Exception error) {

            // Do not leave a saved property with incorrect totals
            System.debug(
                LoggingLevel.ERROR,
                'Property trigger failed: ' + error.getMessage()
            );

            for (Property__c property : properties) {
                property.addError(
                    'Property change was not saved because totals could not be updated.'
                );
            }
        }
    }
}
