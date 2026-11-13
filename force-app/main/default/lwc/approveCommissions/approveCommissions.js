
import { LightningElement, api } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { CloseActionScreenEvent } from 'lightning/actions';
import { RefreshEvent } from 'lightning/refresh';

import getRegionSummary
    from '@salesforce/apex/ApproveCommissionsController.getRegionApprovalSummary';

import getPendingPropertyIds
    from '@salesforce/apex/ApproveCommissionsController.getPendingPropertyIds';

import getPropertyDetails
    from '@salesforce/apex/ApproveCommissionsController.getPendingPropertiesByIds';

import saveApprovals
    from '@salesforce/apex/ApproveCommissionsController.approveProperties';


const PAGE_SIZE = 5;
const MAX_SELECTION = 200;

const COLUMNS = [
    { label: 'Street', fieldName: 'street' },
    { label: 'Sales Office', fieldName: 'salesOfficeName' },
    {
        label: 'Office YTD Sales',
        fieldName: 'officeYearToDateSales',
        type: 'currency'
    },
    { label: 'Agent', fieldName: 'agentName' },
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
        typeAttributes: { maximumFractionDigits: 2 }
    }
];


export default class ApproveCommissions extends LightningElement {

    // Sales Region record
    _recordId;
    latestRequestId = 0;

    // Data
    columns = COLUMNS;
    regionSummary = {};
    pendingPropertyIds = [];
    currentPageProperties = [];

    // Pagination
    pageSize = PAGE_SIZE;
    currentPageNumber = 1;

    // Selected properties and commission edits
    selectedPropertyIds = [];
    commissionOverridesByPropertyId = {};
    draftValues = [];

    // UI states
    isLoading = false;
    isSubmitting = false;
    isLoaded = false;
    errorMessage = '';


    // 1. Get Sales Region ID from Quick Action
    @api
    get recordId() {
        return this._recordId;
    }

    set recordId(value) {
        if (value === this._recordId) {
            return;
        }

        this._recordId = value;
        this.latestRequestId++;

        this.resetState();

        if (value) {
            this.loadPage(true);
        }
    }

    disconnectedCallback() {
        this.latestRequestId++;
    }


    // 2. Clear previous component data
    resetState() {
        this.regionSummary = {};
        this.pendingPropertyIds = [];
        this.currentPageProperties = [];
        this.selectedPropertyIds = [];
        this.commissionOverridesByPropertyId = {};
        this.draftValues = [];
        this.currentPageNumber = 1;

        this.isLoading = false;
        this.isSubmitting = false;
        this.isLoaded = false;
        this.errorMessage = '';
    }


    // 3. UI getters
    get cardTitle() {
        return this.regionSummary.regionName
            ? `Approve Commissions - ${this.regionSummary.regionName}`
            : 'Approve Commissions';
    }

    get isBusy() {
        return this.isLoading || this.isSubmitting;
    }

    get hasPendingApprovals() {
        return this.pendingPropertyIds.length > 0;
    }

    get totalRecords() {
        return this.pendingPropertyIds.length;
    }

    get totalPages() {
        return Math.max(
            1,
            Math.ceil(this.totalRecords / PAGE_SIZE)
        );
    }

    get selectedCount() {
        return this.selectedPropertyIds.length;
    }

    get isSubmitDisabled() {
        return this.isBusy ||
            !this.isLoaded ||
            this.selectedCount === 0 ||
            Boolean(this.errorMessage);
    }


    // 4. Show the saved commission edits on the page
    get propertiesOnCurrentPage() {
        return this.currentPageProperties.map(property => ({
            ...property,
            commissionPercentage:
                this.commissionOverridesByPropertyId[property.propertyId] ??
                property.commissionPercentage
        }));
    }


    // 5. Restore selections when returning to a page
    get selectedRowsOnPage() {
        return this.currentPageProperties
            .filter(property =>
                this.selectedPropertyIds.includes(property.propertyId)
            )
            .map(property => property.propertyId);
    }


    // 6. Load summary, property IDs, and current page
    async loadPage(refreshRegionData = false) {

        if (!this.recordId) {
            return;
        }

        const requestId = ++this.latestRequestId;
        const salesRegionId = this.recordId;

        this.isLoading = true;
        this.errorMessage = '';
        this.currentPageProperties = [];
        this.draftValues = [];

        if (refreshRegionData) {
            this.isLoaded = false;
        }

        try {

            // Reload summary and IDs when requested
            if (refreshRegionData) {

                const [summary, ids] = await Promise.all([
                    getRegionSummary({ salesRegionId }),
                    getPendingPropertyIds({ salesRegionId })
                ]);

                // Ignore outdated responses
                if (requestId !== this.latestRequestId) {
                    return;
                }

                this.regionSummary = summary || {};
                this.pendingPropertyIds = ids || [];

                this.currentPageNumber = Math.min(
                    this.currentPageNumber,
                    this.totalPages
                );

                // Remove selections that are no longer pending
                const pendingIds = new Set(this.pendingPropertyIds);

                this.selectedPropertyIds =
                    this.selectedPropertyIds.filter(id =>
                        pendingIds.has(id)
                    );

                const remainingOverrides = {};

                for (const id of Object.keys(
                    this.commissionOverridesByPropertyId
                )) {
                    if (pendingIds.has(id)) {
                        remainingOverrides[id] =
                            this.commissionOverridesByPropertyId[id];
                    }
                }

                this.commissionOverridesByPropertyId =
                    remainingOverrides;
            }

            // Calculate the IDs of the current page
            const start = (this.currentPageNumber - 1) * PAGE_SIZE;

            const pageIds = this.pendingPropertyIds.slice(
                start,
                start + PAGE_SIZE
            );

            // Retrieve the 5 properties from Apex
            const properties = pageIds.length
                ? await getPropertyDetails({
                    salesRegionId,
                    propertyIds: pageIds
                })
                : [];

            if (requestId !== this.latestRequestId) {
                return;
            }

            // Check whether any property became unavailable
            if (
                properties.length !== pageIds.length ||
                properties.some(property =>
                    !pageIds.includes(property.propertyId)
                )
            ) {
                throw new Error(
                    'Some properties changed. Refresh before approving.'
                );
            }

            this.currentPageProperties = properties;
            this.isLoaded = true;

        } catch (error) {

            if (requestId === this.latestRequestId) {
                this.errorMessage =
                    error?.body?.message ||
                    error?.message ||
                    'Unable to load properties.';

                this.isLoaded = false;
            }

        } finally {

            if (requestId === this.latestRequestId) {
                this.isLoading = false;
            }
        }
    }


    // 7. Handle pagination event from child LWC
    handlePageChange(event) {

        if (this.isBusy || !this.isLoaded) {
            return;
        }

        const pageNumber = event.detail.pageNumber;

        if (
            pageNumber < 1 ||
            pageNumber > this.totalPages ||
            pageNumber === this.currentPageNumber
        ) {
            return;
        }

        this.currentPageNumber = pageNumber;

        this.loadPage();
    }


    // 8. Refresh current data
    handleRefresh() {
        if (!this.isBusy) {
            this.loadPage(true);
        }
    }


    // 9. Handle row selection across pages
    handleRowSelection(event) {

        if (this.isBusy || !this.isLoaded) {
            return;
        }

        // IDs displayed on the current page
        const pageIds = new Set(
            this.currentPageProperties.map(
                property => property.propertyId
            )
        );

        // Keep selections from other pages
        const otherPages = this.selectedPropertyIds.filter(
            id => !pageIds.has(id)
        );

        // Get selected rows on this page
        const thisPage = event.detail.selectedRows.map(
            property => property.propertyId
        );

        const selectedIds = [...otherPages, ...thisPage];

        // Enforce maximum 200 selections
        this.selectedPropertyIds =
            selectedIds.slice(0, MAX_SELECTION);

        this.errorMessage =
            selectedIds.length > MAX_SELECTION
                ? `Select no more than ${MAX_SELECTION} properties.`
                : '';
    }


    // 10. Save commission edits across pages
    handleCellChange(event) {

        if (this.isBusy || !this.isLoaded) {
            return;
        }

        const overrides = {
            ...this.commissionOverridesByPropertyId
        };

        for (const draft of event.detail.draftValues) {

            const original = this.currentPageProperties.find(
                property =>
                    property.propertyId === draft.propertyId
            );

            if (!original) {
                continue;
            }

            const entered = draft.commissionPercentage;
            const percentage = Number(entered);

            const minimum = Number(
                original.commissionPercentage ?? 0
            );

            // Cannot decrease the original percentage
            if (
                String(entered ?? '').trim() === '' ||
                !Number.isFinite(percentage) ||
                percentage < minimum ||
                percentage > 100
            ) {
                this.errorMessage =
                    'Commission must be between the existing percentage and 100.';

                this.draftValues = [];
                return;
            }

            // Save the edit using Property ID as key
            overrides[draft.propertyId] = percentage;
        }

        this.commissionOverridesByPropertyId = overrides;

        this.draftValues = event.detail.draftValues.map(
            draft => ({ ...draft })
        );

        this.errorMessage = '';
    }


    // 11. Approve and close Quick Action
    handleSubmit() {
        this.submitApprovals(false);
    }


    // 12. Approve and keep Quick Action open
    handleSubmitAndContinue() {
        this.submitApprovals(true);
    }


    // 13. Save selected approvals using Apex
    async submitApprovals(keepOpen) {

        if (this.isSubmitDisabled || !this.recordId) {
            return;
        }

        this.isSubmitting = true;
        this.errorMessage = '';

        const salesRegionId = this.recordId;
        const requestId = this.latestRequestId;

        const propertyIds = [...this.selectedPropertyIds];

        // Keep percentage values aligned with Property IDs
        const commissionPercentages = propertyIds.map(
            id => this.commissionOverridesByPropertyId[id] ?? null
        );

        try {

            await saveApprovals({
                salesRegionId,
                propertyIds,
                commissionPercentages
            });

            if (requestId !== this.latestRequestId) {
                return;
            }

            // Clear selections after successful approval
            this.selectedPropertyIds = [];
            this.commissionOverridesByPropertyId = {};
            this.draftValues = [];
            this.currentPageNumber = 1;

            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Success',
                    message: `${propertyIds.length} properties approved.`,
                    variant: 'success'
                })
            );

            // Notify the Lightning record page
            this.dispatchEvent(new RefreshEvent());

            if (keepOpen) {

                // Reload pending approvals and regional summary
                await this.loadPage(true);

                if (!this.isLoaded) {
                    this.errorMessage =
                        'Approval succeeded, but refresh failed. Refresh; do not submit again.';
                }

            } else {

                // Close the Quick Action modal
                this.dispatchEvent(
                    new CloseActionScreenEvent()
                );
            }

        } catch (error) {

            if (requestId === this.latestRequestId) {
                this.errorMessage =
                    error?.body?.message ||
                    error?.message ||
                    'Unable to approve properties.';
            }

        } finally {
            this.isSubmitting = false;
        }
    }


    // 14. Cancel the Quick Action
    handleCancel() {
        if (!this.isBusy) {
            this.dispatchEvent(
                new CloseActionScreenEvent()
            );
        }
    }
}
