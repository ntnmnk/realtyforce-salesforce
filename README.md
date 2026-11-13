# MBHoldings — ABC Real Estate

Refactored Salesforce DX project for claiming properties and approving commissions.
Start with `docs/ARCHITECTURE.md` to find a class and `docs/VALIDATION.md` for verification status.

## What is included

- Thin LWC controllers; claim and approval services; selectors; standalone response DTOs.
- Two screen quick actions with five-row server detail requests, first/previous/next/last navigation,
  cross-page selections, and cross-page commission edits (approval only).
- Bulk trigger rules for default commission percentages, five Working properties per agent,
  close defaults, approved commission calculations, and YTD totals including delete/undelete.
- Permission sets, agent approval guard, tests, and a scoped deployment manifest.
- Existing object metadata and unrelated exported metadata are preserved in source.

## Open and test locally

1. Extract the ZIP into a new folder. Open the enclosed `MBHoldings` folder in VS Code.
2. Install Node.js 22 LTS, Salesforce CLI, and Salesforce extensions for VS Code.
3. Run:

```sh
npm ci --ignore-scripts
npm run lint
npm run test:unit -- -- --runInBand
python scripts/validate_structure.py
```

Python is optional and used only for the offline structural check. Windows installations can use `py` instead of `python`.
The Jest tests mock Apex: they do not prove Apex compilation or Salesforce transaction behavior.

## Validate in a sandbox before using the app

```sh
sf org login web --instance-url https://test.salesforce.com --alias mb-sandbox
sf project deploy start --manifest manifest/deploy.xml --target-org mb-sandbox --dry-run --test-level RunLocalTests --wait 60
```

Resolve any org-specific metadata conflicts, validation-rule conflicts, failing tests, or coverage failures before deploying.
The supplied archive has no authenticated org connection, so no org deployment or Apex test run has been performed here.
Do not upload org authentication folders or tokens when reporting errors.

After successful validation, deploy to that sandbox:

```sh
sf project deploy start --manifest manifest/deploy.xml --target-org mb-sandbox --test-level RunLocalTests --wait 60
```

Use `manifest/deploy.xml`, not the broad retrieval manifest `manifest/package.xml`, to avoid deploying unrelated
exported Account and Contact customizations. Salesforce object/field API names and relationships are retained.

## Configure the two screens

1. Assign `MB_RealEstateAgent` to agent users and `MB_RealEstateManager` to regional managers.
   These permission sets grant application access but do not revoke broader permissions in existing profiles.
2. Ensure exactly one Contact maps to each agent's User through `Agent_User__c`, with its office and default split populated.
3. Populate `Sales_Region__c.Regional_Manager__c` with the regional manager User.
4. On the Sales Office layout, add **Claim Properties** from Salesforce Mobile and Lightning Experience Actions.
5. On the Sales Region layout, add **Approve Commissions** similarly. For Dynamic Actions, add them in Lightning App Builder.
6. Test as the actual agent and manager users, not just as an administrator.

Quick actions are included; existing layouts are not overwritten. The agent permission set includes a custom permission
used by `Agent_Cannot_Approve` to block direct approval by agents unless they manage that property's region.
The approval service independently checks the regional manager on every call. Administrators can still perform bulk corrections.
If your org has an existing equivalent approval rule, review both rules for compatibility.

## Important behavior and limits

- All records selected in one save succeed together or roll back. Errors from triggers/validation are displayed in the screen.
- Working-property capacity is checked in the trigger with system-wide visibility. Parent locks coordinate capacity and totals.
  Contention can still cause lock exceptions or deadlocks: these fail/roll back rather than silently bypassing the rule.
- Property reads and UI updates enforce user-mode permissions. Trigger integrity/rollup helpers deliberately run without sharing.
- IDs are loaded as a snapshot (maximum 20,000 eligible records per screen). Details are fetched five at a time.
  More than 20,000 produces an explicit error, not a truncated list. Larger deployments need cursor-based pagination.
- A maximum of five claims or 200 approvals can be submitted at once. Approval count limits are also enforced in the server.
- Stale pages can temporarily contain fewer than five rows. Refresh rebuilds the ID snapshot; save always revalidates eligibility.
- Close defaults are implemented as null-only assignments in the trigger because the archive did not include the assignment's
  workflow metadata. They coexist with equivalent null-only workflows; review any other automation in your org.
- Historical approved commission amounts remain stable on unrelated edits. Correcting sales price or commission percentage
  recalculates the amount using the configured agency rate; reverting approval clears the commission amount.
- APIs are consistently pinned to 66.0 for predictable system-mode legacy test setup/trigger operations. User-facing operations
  explicitly use USER_MODE. Review all database access modes before upgrading to API 67+.

## Replacing an existing project

Use this ZIP as a clean project folder rather than copying it over an old folder: ordinary copying does not remove obsolete files.
`PropertyService.cls` and the empty misspelled `claimPropertie` bundle were removed from source.
The original `PropertyServiceTest` metadata name is retained with updated calls so existing-org deployments replace that test.
Old unused components already deployed in an org are not automatically deleted. After checking for external references,
remove the obsolete `PropertyService` and `claimPropertie` components separately. No destructive deployment is bundled.
No other project outside this ZIP was examined for callers of renamed controller methods.
