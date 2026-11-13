# Validation and remaining sandbox checks

## Local checks

- 12 LWC Jest tests across both screens: pass (mocked Apex).
- Apex/trigger syntax parsing using prettier-plugin-apex: pass. This is NOT Salesforce compilation or type checking.
- LWC template compilation/transformation during Jest: pass.
- XML well-formedness, class metadata companions, custom-field references and LWC-to-Apex method references: pass.
- JavaScript ESLint and final formatting check: see accompanying validation results.
- ZIP integrity is checked before delivery.

No authenticated Salesforce org was available. Apex tests, deployment validation, actual CRUD/FLS behavior,
code coverage, real concurrent transactions, and interactions with your org's existing automations were NOT executed.
Passing local tests cannot establish that Salesforce deployment will pass.

## Apex suites included (execution pending)

- ClaimPropertiesControllerTest: responses, claim, invalid IDs/selections, wrong office, unmapped user, >2,000 IDs.
- PropertyServiceTest: claim default split/capacity/stale selection, manager authorization and approval totals.
- ApproveCommissionsControllerTest: selected approvals and unauthorized agents.
- CommissionApprovalServiceTest: summary/page ordering, stale batch rollback, reduced and duplicate approvals.
- PropertyRulesTest: direct bulk capacity/default split, undelete capacity, close defaults, partial DML, direct agent approval guard.
- PropertyTriggerTest: current/prior-year totals, delete/undelete, 200-record bulk approval, invalid commission.
- PropertyReversalTest: reversal, capacity boundary, cross-office claims, invalid batch override.
- CommissionCalculatorTest: arithmetic and bounds.

## Manual sandbox checklist

1. Validate deployment with RunLocalTests; verify required coverage and inspect every failure.
2. Agent sees only eligible properties for their office, five per page; first/last and selections work.
3. Claim exactly five; reject a sixth, including through Data Loader and undelete.
4. Two browser sessions claim the same property; one succeeds and the other fails without overwriting the agent.
5. Two sessions for the same agent claim different properties concurrently; Working total never exceeds five.
6. Simultaneous closes for different agents in one office leave correct office totals. Retry lock conflicts.
7. Manager increases commission on selected rows across pages; unselected edits do not persist.
8. Agent direct approval is blocked with the agent permission set; wrong regional manager is blocked by the screen service.
9. Closing/approval, reversal, delete/undelete, reassignment, date changes across year boundaries and bulk operations preserve totals.
10. Save-and-continue refreshes; Cancel never saves; retry after a read failure works.
11. Test restricted object/field permissions and existing validation rules/flows/workflows with representative users.
12. Inspect object/schema configuration and layout action placement in the target org.

The 20,000-ID screen bound and 200-approval transaction bound are intentional, visible limits; read README before larger-volume use.
