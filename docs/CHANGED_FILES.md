# File changes

Generated against the uploaded MBHoldings.7z source (excluding dependencies/authentication/cache folders).

## Added

- `.github/workflows/validate.yml`
- `docs/ARCHITECTURE.md`
- `docs/VALIDATION.md`
- `force-app/main/default/classes/AgentClaimSummary.cls`
- `force-app/main/default/classes/AgentClaimSummary.cls-meta.xml`
- `force-app/main/default/classes/AgentSelector.cls`
- `force-app/main/default/classes/AgentSelector.cls-meta.xml`
- `force-app/main/default/classes/AvailableProperty.cls`
- `force-app/main/default/classes/AvailableProperty.cls-meta.xml`
- `force-app/main/default/classes/CommissionApprovalRow.cls`
- `force-app/main/default/classes/CommissionApprovalRow.cls-meta.xml`
- `force-app/main/default/classes/CommissionApprovalService.cls`
- `force-app/main/default/classes/CommissionApprovalService.cls-meta.xml`
- `force-app/main/default/classes/CommissionApprovalServiceTest.cls`
- `force-app/main/default/classes/CommissionApprovalServiceTest.cls-meta.xml`
- `force-app/main/default/classes/PropertyClaimService.cls`
- `force-app/main/default/classes/PropertyClaimService.cls-meta.xml`
- `force-app/main/default/classes/PropertyRules.cls`
- `force-app/main/default/classes/PropertyRules.cls-meta.xml`
- `force-app/main/default/classes/PropertyRulesTest.cls`
- `force-app/main/default/classes/PropertyRulesTest.cls-meta.xml`
- `force-app/main/default/classes/PropertySelector.cls`
- `force-app/main/default/classes/PropertySelector.cls-meta.xml`
- `force-app/main/default/classes/RegionApprovalSummary.cls`
- `force-app/main/default/classes/RegionApprovalSummary.cls-meta.xml`
- `force-app/main/default/classes/SalesOfficeSelector.cls`
- `force-app/main/default/classes/SalesOfficeSelector.cls-meta.xml`
- `force-app/main/default/classes/SalesRegionSelector.cls`
- `force-app/main/default/classes/SalesRegionSelector.cls-meta.xml`
- `force-app/main/default/customPermissions/MB_RealEstateAgent.customPermission-meta.xml`
- `force-app/main/default/lwc/approveCommissions/__tests__/approveCommissions.test.js`
- `force-app/main/default/lwc/claimProperties/__tests__/claimProperties.test.js`
- `force-app/main/default/objects/Property__c/validationRules/Agent_Cannot_Approve.validationRule-meta.xml`
- `force-app/main/default/permissionsets/MB_RealEstateAgent.permissionset-meta.xml`
- `force-app/main/default/permissionsets/MB_RealEstateManager.permissionset-meta.xml`
- `force-app/main/default/quickActions/Sales_Office__c.Claim_Properties.quickAction-meta.xml`
- `force-app/main/default/quickActions/Sales_Region__c.Approve_Commissions.quickAction-meta.xml`
- `manifest/deploy.xml`
- `scripts/validate_structure.py`

## Removed from source

- `force-app/main/default/classes/PropertyService.cls`
- `force-app/main/default/classes/PropertyService.cls-meta.xml`
- `force-app/main/default/lwc/claimPropertie/__tests__/claimPropertie.test.js`
- `force-app/main/default/lwc/claimPropertie/claimPropertie.html`
- `force-app/main/default/lwc/claimPropertie/claimPropertie.js`
- `force-app/main/default/lwc/claimPropertie/claimPropertie.js-meta.xml`

## Updated

- `.gitignore`
- `README.md`
- `force-app/main/default/classes/ABCConstants.cls`
- `force-app/main/default/classes/ABCConstants.cls-meta.xml`
- `force-app/main/default/classes/ABCErrors.cls`
- `force-app/main/default/classes/ABCErrors.cls-meta.xml`
- `force-app/main/default/classes/ABCException.cls`
- `force-app/main/default/classes/ABCException.cls-meta.xml`
- `force-app/main/default/classes/ABCTestDataFactory.cls`
- `force-app/main/default/classes/ABCTestDataFactory.cls-meta.xml`
- `force-app/main/default/classes/ApproveCommissionsController.cls`
- `force-app/main/default/classes/ApproveCommissionsController.cls-meta.xml`
- `force-app/main/default/classes/ApproveCommissionsControllerTest.cls`
- `force-app/main/default/classes/ApproveCommissionsControllerTest.cls-meta.xml`
- `force-app/main/default/classes/ClaimPropertiesController.cls`
- `force-app/main/default/classes/ClaimPropertiesController.cls-meta.xml`
- `force-app/main/default/classes/ClaimPropertiesControllerTest.cls`
- `force-app/main/default/classes/ClaimPropertiesControllerTest.cls-meta.xml`
- `force-app/main/default/classes/CommissionCalculator.cls`
- `force-app/main/default/classes/CommissionCalculator.cls-meta.xml`
- `force-app/main/default/classes/CommissionCalculatorTest.cls`
- `force-app/main/default/classes/CommissionCalculatorTest.cls-meta.xml`
- `force-app/main/default/classes/PropertyReversalTest.cls`
- `force-app/main/default/classes/PropertyReversalTest.cls-meta.xml`
- `force-app/main/default/classes/PropertyServiceTest.cls`
- `force-app/main/default/classes/PropertyServiceTest.cls-meta.xml`
- `force-app/main/default/classes/PropertyTriggerHandler.cls`
- `force-app/main/default/classes/PropertyTriggerHandler.cls-meta.xml`
- `force-app/main/default/classes/PropertyTriggerTest.cls`
- `force-app/main/default/classes/PropertyTriggerTest.cls-meta.xml`
- `force-app/main/default/classes/YearToDateService.cls`
- `force-app/main/default/classes/YearToDateService.cls-meta.xml`
- `force-app/main/default/lwc/approveCommissions/approveCommissions.html`
- `force-app/main/default/lwc/approveCommissions/approveCommissions.js`
- `force-app/main/default/lwc/approveCommissions/approveCommissions.js-meta.xml`
- `force-app/main/default/lwc/claimProperties/claimProperties.html`
- `force-app/main/default/lwc/claimProperties/claimProperties.js`
- `force-app/main/default/lwc/claimProperties/claimProperties.js-meta.xml`
- `force-app/main/default/triggers/PropertyTrigger.trigger`
- `force-app/main/default/triggers/PropertyTrigger.trigger-meta.xml`
- `manifest/package.xml`
- `sfdx-project.json`
