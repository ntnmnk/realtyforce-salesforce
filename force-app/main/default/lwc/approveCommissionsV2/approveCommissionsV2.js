
import { LightningElement, api, wire } from 'lwc';
import { refreshApex } from '@salesforce/apex';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { CloseActionScreenEvent } from 'lightning/actions';
import { RefreshEvent } from 'lightning/refresh';

import getRegionSummary
    from '@salesforce/apex/ApproveCommissionsController.getRegionApprovalSummary';

import getPendingPropertyIds
    from '@salesforce/apex/ApproveCommissionsController.getPendingPropertyIds';

import getPropertyDetails
    from '@salesforce/apex/ApproveCommissionsController.getPendingPropertiesByIds';

import approveProperties
    from '@salesforce/apex/ApproveCommissionsController.approveProperties';


const PAGE_SIZE = 5;
const MAX_SELECTION = 200;

const COLUMNS = [
    {
        label: 'Street',
        fieldName: 'street',
        wrapText: true
    },
    {
        label: 'Sales Office',
        fieldName: 'salesOfficeName'
    },
    {
        label: 'Office YTD Sales',
        fieldName: 'officeYearToDateSales',
        type: 'currency'
    },
    {
        label: 'Agent',
        fieldName: 'agentName'
    },
    {
        label: 'Listing Price',
        fieldName: 'listingPrice',
        type: 'currency'
    },
    {
        label: 'Sales Price',
        fieldName: 'salesPrice',
        type: 'currency'
    },
    {
        label: 'Commission %',
        fieldName: 'commissionPercentage',
        type: 'number',
        editable: true,
        typeAttributes: {
            maximumFractionDigits: 2
        }
    }
];


function getErrorMessage(error) {
    return error?.body?.message ||
        error?.message ||
        'Something went wrong.';
}


export default class ApproveCommissionsV2 extends LightningElement {

    // 1. Sales Region ID from Quick Action
    salesRegionId;

    @api
    get recordId() {
        return this.salesRegionId;
    }

    set recordId(value) {
        if (value === this.salesRegionId) {
            return;
        }

        this.salesRegionId = value;
        this.currentPageNumber = 1;
        this.pendingPropertyIds = [];
        this.pagePropertyIds = undefined;
        this.selectedPropertyIds = [];
        this.commissionOverrides = {};
        this.draftValues = [];
        this.actionError = '';
    }


    // 2. Component state
    columns = COLUMNS;
    pageSize = PAGE_SIZE;

    currentPageNumber = 1;
    pendingPropertyIds = [];
    pagePropertyIds;

    selectedPropertyIds = [];
    commissionOverrides = {};
    draftValues = [];

    actionError = '';

    isRefreshing = false;
    isSubmitting = false;


    // 3. Wire regional summary
    @wire(getRegionSummary, {
        salesRegionId: '$salesRegionId'
    })
    regionWire;


    // 4. Wire pending property IDs
    idsWire;

    @wire(getPendingPropertyIds, {
        salesRegionId: '$salesRegionId'
    })
    wiredPendingIds(result) {

        // Store the complete wire result for refreshApex
        this.idsWire = result;

        if (result.data !== undefined) {

            this.pendingPropertyIds = [...result.data];

            // Remove selections that are no longer pending
            this.removeUnavailableSelections();

            // Keep current page within available pages
            this.currentPageNumber = Math.min(
                this.currentPageNumber,
                this.totalPages
            );

            // Update the IDs needed by the third wire
            this.updatePagePropertyIds();

        } else if (result.error) {

            this.pendingPropertyIds = [];
            this.pagePropertyIds = undefined;
        }
    }


    // 5. Wire current-page details
    @wire(getPropertyDetails, {
        salesRegionId: '$salesRegionId',
        propertyIds: '$pagePropertyIds'
    })
    pageWire;


    // 6. Regional summary
    get regionSummary() {
        return this.regionWire?.data || {};
    }

    get cardTitle() {
        return this.regionSummary.regionName
            ? `Approve Commissions - ${this.regionSummary.regionName}`
            : 'Approve Commissions V2';
    }


    // 7. Pagination getters
    get totalRecords() {
        return this.pendingPropertyIds.length;
    }

    get totalPages() {
        return Math.max(
            1,
            Math.ceil(this.totalRecords / PAGE_SIZE)
        );
    }

    get hasPendingApprovals() {
        return this.totalRecords > 0;
    }


    // 8. Current page data returned by @wire
    get currentPageProperties() {

        if (!this.pagePropertyIds?.length) {
            return [];
        }

        const rows = this.pageWire?.data;

        if (
            !rows ||
            rows.length !== this.pagePropertyIds.length
        ) {
            return [];
        }

        // Avoid displaying a previous page's wired results
        const expectedIds = new Set(this.pagePropertyIds);

        return rows.every(row =>
            expectedIds.has(row.propertyId)
        )
            ? rows
            : [];
    }


    // 9. Loading state
    get isLoaded() {

        const regionLoaded =
            this.regionWire?.data !== undefined;

        const idsLoaded =
            this.idsWire?.data !== undefined;

        const pageLoaded =
            !this.pagePropertyIds?.length ||
            this.currentPageProperties.length ===
                this.pagePropertyIds.length;

        return Boolean(
            this.salesRegionId &&
            regionLoaded &&
            idsLoaded &&
            pageLoaded
        );
    }

    get isBusy() {
        return this.isRefreshing ||
            this.isSubmitting ||
            Boolean(
                this.salesRegionId &&
                !this.isLoaded &&
                !this.errorMessage
            );
    }

    get errorMessage() {
        return this.actionError ||
            (
                this.regionWire?.error &&
                getErrorMessage(this.regionWire.error)
            ) ||
            (
                this.idsWire?.error &&
                getErrorMessage(this.idsWire.error)
            ) ||
            (
                this.pagePropertyIds?.length &&
                this.pageWire?.error &&
                getErrorMessage(this.pageWire.error)
            ) ||
            '';
    }


    // 10. Selection getters
    get selectedCount() {
        return this.selectedPropertyIds.length;
    }

    get isSubmitDisabled() {
        return this.isBusy ||
            !this.isLoaded ||
            this.selectedCount === 0 ||
            Boolean(this.errorMessage);
    }


    // 11. Apply commission edits to displayed records
    get propertiesOnCurrentPage() {

        return this.currentPageProperties.map(row => ({
            ...row,

            commissionPercentage:
                this.commissionOverrides[row.propertyId] ??
                row.commissionPercentage
        }));
    }


    // 12. Restore selected rows on the current page
    get selectedRowsOnPage() {

        const selectedIds =
            new Set(this.selectedPropertyIds);

        return this.currentPageProperties
            .filter(row => selectedIds.has(row.propertyId))
            .map(row => row.propertyId);
    }


    // 13. Get current page IDs
    updatePagePropertyIds() {

        const start =
            (this.currentPageNumber - 1) * PAGE_SIZE;

        const nextIds = this.pendingPropertyIds.slice(
            start,
            start + PAGE_SIZE
        );

        const oldIds = this.pagePropertyIds || [];

        // No need to change reactive parameter
        // if the same page IDs are already loaded
        if (
            nextIds.length === oldIds.length &&
            nextIds.every(
                (id, index) => id === oldIds[index]
            )
        ) {
            return;
        }

        // This triggers the third @wire
        this.pagePropertyIds =
            nextIds.length ? nextIds : undefined;

        this.draftValues = [];
    }


    // 14. Handle the child pagination event
    handlePageChange(event) {

        if (this.isBusy || !this.isLoaded) {
            return;
        }

        const newPage = event.detail.pageNumber;

        if (
            newPage < 1 ||
            newPage > this.totalPages
        ) {
            return;
        }

        this.currentPageNumber = newPage;
        this.actionError = '';

        this.updatePagePropertyIds();
    }


    // 15. Remove properties no longer pending approval
    removeUnavailableSelections() {

        const pendingIds =
            new Set(this.pendingPropertyIds);

        this.selectedPropertyIds =
            this.selectedPropertyIds.filter(
                id => pendingIds.has(id)
            );

        const retainedOverrides = {};

        for (const id of Object.keys(
            this.commissionOverrides
        )) {

            if (pendingIds.has(id)) {
                retainedOverrides[id] =
                    this.commissionOverrides[id];
            }
        }

        this.commissionOverrides = retainedOverrides;
    }


    // 16. Handle selection across multiple pages
    handleRowSelection(event) {

        if (this.isBusy) {
            return;
        }

        const pageIds = new Set(
            this.currentPageProperties.map(
                row => row.propertyId
            )
        );

        // Keep selections on other pages
        const otherPages = this.selectedPropertyIds.filter(
            id => !pageIds.has(id)
        );

        // Current page's selected rows
        const thisPage = event.detail.selectedRows.map(
            row => row.propertyId
        );

        const combined = [...otherPages, ...thisPage];

        this.selectedPropertyIds =
            combined.slice(0, MAX_SELECTION);

        this.actionError =
            combined.length > MAX_SELECTION
                ? `Choose at most ${MAX_SELECTION} properties.`
                : '';
    }


    // 17. Handle commission percentage edits
    handleCellChange(event) {

        if (this.isBusy) {
            return;
        }

        const nextOverrides = {
            ...this.commissionOverrides
        };

        for (const draft of event.detail.draftValues) {

            const original =
                this.currentPageProperties.find(
                    row =>
                        row.propertyId === draft.propertyId
                );

            if (
                !original ||
                draft.commissionPercentage === undefined
            ) {
                continue;
            }

            const raw = draft.commissionPercentage;
            const percentage = Number(raw);

            const originalPercentage = Number(
                original.commissionPercentage ?? 0
            );

            if (
                String(raw ?? '').trim() === '' ||
                !Number.isFinite(percentage) ||
                percentage < originalPercentage ||
                percentage > 100
            ) {
                this.actionError =
                    'Commission % must not decrease ' +
                    'and must be at most 100.';

                this.draftValues = [];
                return;
            }

            // Preserve changes across pages
            nextOverrides[draft.propertyId] = percentage;
        }

        this.commissionOverrides = nextOverrides;
        this.draftValues = [];
        this.actionError = '';
    }


    // 18. Refresh Apex wire results
    async refreshData() {

        this.isRefreshing = true;
        this.actionError = '';

        try {

            const previousPageKey =
                (this.pagePropertyIds || []).join(',');

            // Refresh region summary and pending IDs
            const requests = [
                this.regionWire,
                this.idsWire
            ]
                .filter(Boolean)
                .map(wireResult =>
                    refreshApex(wireResult)
                );

            await Promise.all(requests);

            const newPageKey =
                (this.pagePropertyIds || []).join(',');

            // Refresh details if page IDs did not change
            if (
                newPageKey &&
                previousPageKey === newPageKey &&
                this.pageWire
            ) {
                await refreshApex(this.pageWire);
            }

        } catch (error) {

            this.actionError = getErrorMessage(error);
            throw error;

        } finally {

            this.isRefreshing = false;
        }
    }


    // 19. Refresh button
    async handleRefresh() {

        if (this.isBusy) {
            return;
        }

        try {
            await this.refreshData();
        } catch {
            // Error already displayed by refreshData.
        }
    }


    // 20. Approve button
    handleSubmit() {
        this.submitApprovals(false);
    }


    // 21. Approve and Continue button
    handleSubmitAndContinue() {
        this.submitApprovals(true);
    }


    // 22. Save approvals using imperative Apex
    async submitApprovals(keepOpen) {

        if (this.isSubmitDisabled) {
            return;
        }

        this.isSubmitting = true;
        this.actionError = '';

        const propertyIds = [
            ...this.selectedPropertyIds
        ];

        // Indexes must match the property IDs
        const commissionPercentages = propertyIds.map(
            id => this.commissionOverrides[id] ?? null
        );

        try {

            await approveProperties({
                salesRegionId: this.salesRegionId,
                propertyIds,
                commissionPercentages
            });

            // Clear selection and edits after success
            this.selectedPropertyIds = [];
            this.commissionOverrides = {};
            this.draftValues = [];
            this.currentPageNumber = 1;

            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Success',
                    message:
                        `${propertyIds.length} properties approved.`,
                    variant: 'success'
                })
            );

            // Notify the Lightning record page
            this.dispatchEvent(new RefreshEvent());

            if (keepOpen) {

                try {
                    await this.refreshData();
                } catch {

                    this.actionError =
                        'Approval succeeded, but refreshing failed. ' +
                        'Click Refresh.';
                }

            } else {

                this.dispatchEvent(
                    new CloseActionScreenEvent()
                );
            }

        } catch (error) {

            this.actionError =
                getErrorMessage(error);

        } finally {

            this.isSubmitting = false;
        }
    }


    // 23. Cancel button
    handleCancel() {

        if (!this.isBusy) {
            this.dispatchEvent(
                new CloseActionScreenEvent()
            );
        }
    }
}
