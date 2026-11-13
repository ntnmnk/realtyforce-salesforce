# Find the right file

All Apex classes and their `.cls-meta.xml` companions live in `force-app/main/default/classes`.
Use VS Code Ctrl+P and a class name or suffix (`Controller`, `Selector`, `Test`).
Apex folders do not create Java-style packages.

| Area | Files | Responsibility |
| --- | --- | --- |
| Claim endpoint | ClaimPropertiesController | LWC methods and safe error conversion |
| Claim use case | PropertyClaimService | Agent mapping, selection validation, locks, atomic claim and summary |
| Approval endpoint | ApproveCommissionsController | LWC methods and safe error conversion |
| Approval use case | CommissionApprovalService | Regional authorization, edits, atomic approval and summary |
| Queries | AgentSelector, PropertySelector, SalesOfficeSelector, SalesRegionSelector | User-mode reads and explicit record locks |
| Responses | AgentClaimSummary, AvailableProperty, RegionApprovalSummary, CommissionApprovalRow | Standalone LWC serialization contracts |
| Property events | ../triggers/PropertyTrigger.trigger, PropertyTriggerHandler | Event routing and record defaults/calculation |
| Integrity | PropertyRules | System-wide Working counts, parent locks and capacity rejection |
| Rollups | YearToDateService | Locked recalculation of affected old/new agents and offices |
| Pure arithmetic | CommissionCalculator | Percentage validation and commission amount |
| Shared configuration/errors | ABCConstants, ABCException, ABCErrors | Constants and controlled error messages |
| Fixtures | ABCTestDataFactory | Isolated test records, users and permission assignments |
| Tests | *Test.cls | Apex business tests; must execute in Salesforce |

The only `without sharing` production classes are PropertyRules, PropertyTriggerHandler and YearToDateService.
They enforce integrity across records independent of UI sharing. They are not Aura endpoints.
Services authorize the caller before requesting protected data. Selectors do not replace business authorization.

The rule lifecycle:

1. LWC calls controller; controller delegates to the use-case service.
2. Service authorizes and validates, locks records, then performs sparse user-mode DML.
3. Trigger locks affected agents, applies defaults and commission calculation.
4. After DML, the trigger rejects over-capacity assignments and recalculates affected totals.
5. Service returns fresh summary values; LWC refreshes or closes the quick action.

Data Loader enters at step 3 and therefore receives the same integrity rules.
There are no blanket static recursion flags: relevant changes drive idempotent recalculation.

## Frontend

- `lwc/claimProperties`: claim screen and tests.
- `lwc/approveCommissions`: approval screen and tests.
- All property rows use `propertyId` as the datatable key.
- Selection IDs persist independently of the current page.
- Commission edits remain in memory until approval; paging and cancel do not save them.
- Request version numbers reject stale async responses when context changes.
- Refresh is imperative: summary values are fetched from Apex, not a cached wire result.

## Metadata

- `permissionsets`: agent/manager read and write access, plus controller access.
- `customPermissions`: agent role marker for the direct-approval validation rule.
- `quickActions`: screen-action definitions; place them on existing layouts manually.
- `objects`: unchanged schema plus agent approval validation rule.
- `manifest/deploy.xml`: scoped application deployment.
- `.github/workflows/validate.yml`: local CI checks; no authenticated org deployment.

## Renamed public contracts

| Old | New |
| --- | --- |
| ClaimPropertiesController.getContext | getAgentClaimSummary |
| ClaimPropertiesController.getClaimableIds | getClaimablePropertyIds |
| ClaimPropertiesController.getPropertiesByIds | getClaimablePropertiesByIds |
| ApproveCommissionsController.getContext | getRegionApprovalSummary |
| ApproveCommissionsController.getPendingIds | getPendingPropertyIds |
| ApproveCommissionsController.getPropertiesByIds | getPendingPropertiesByIds |
| approval splitPercents parameter | commissionPercentages |
| workingCount / remainingCapacity | workingPropertyCount / remainingClaimCapacity |
| ytdSales / ytdCommissions | yearToDateSales / yearToDateCommissions |
| row id / name | propertyId / propertyName |
| splitPercent | commissionPercentage |

Both included LWCs and Apex tests use the new contracts.
