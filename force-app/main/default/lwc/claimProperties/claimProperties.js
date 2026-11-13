import { LightningElement, api } from "lwc";
import { ShowToastEvent } from "lightning/platformShowToastEvent";
import { CloseActionScreenEvent } from "lightning/actions";
import { RefreshEvent } from "lightning/refresh";
import getAgentSummary from "@salesforce/apex/ClaimPropertiesController.getAgentClaimSummary";
import getClaimablePropertyIds from "@salesforce/apex/ClaimPropertiesController.getClaimablePropertyIds";
import getPropertyDetails from "@salesforce/apex/ClaimPropertiesController.getClaimablePropertiesByIds";
import claimProperties from "@salesforce/apex/ClaimPropertiesController.claimProperties";

const PAGE_SIZE = 5;

const COLUMNS = [
  { label: "Street", fieldName: "street", wrapText: true },
  { label: "City", fieldName: "city" },
  { label: "Listing Price", fieldName: "listingPrice", type: "currency" },
  { label: "Status", fieldName: "status" },
  { label: "Date Added", fieldName: "createdDate", type: "date" }
];

export default class ClaimProperties extends LightningElement {
  _recordId;

  // Ignore responses from earlier loads after the office or page changes.
  latestRequestId = 0;

  columns = COLUMNS;
  officeSummary = {};
  claimablePropertyIds = [];
  propertiesOnCurrentPage = [];
  selectedPropertyIds = [];
  currentPageNumber = 1;
  isLoading = false;
  isSubmitting = false;
  isLoaded = false;
  isAtCapacity = false;
  errorMessage = "";

  // A record-action component may receive recordId after it connects.
  @api
  get recordId() {
    return this._recordId;
  }

  set recordId(value) {
    if (value === this._recordId) return;

    this._recordId = value;
    this.latestRequestId++;
    this.resetForOfficeChange();
    if (value) this.refreshData();
  }

  resetForOfficeChange() {
    this.officeSummary = {};
    this.claimablePropertyIds = [];
    this.propertiesOnCurrentPage = [];
    this.selectedPropertyIds = [];
    this.currentPageNumber = 1;
    this.isLoading = false;
    this.isLoaded = false;
    this.isAtCapacity = false;
    this.errorMessage = "";
  }

  disconnectedCallback() {
    this.latestRequestId++;
  }

  get cardTitle() {
    const officeName = this.officeSummary.salesOfficeName;
    return officeName ? `Claim Properties - ${officeName}` : "Claim Properties";
  }

  get isBusy() {
    return this.isLoading || this.isSubmitting;
  }

  get hasProperties() {
    return this.claimablePropertyIds.length > 0;
  }

  get totalPages() {
    return Math.max(1, Math.ceil(this.claimablePropertyIds.length / PAGE_SIZE));
  }

  get selectedCount() {
    return this.selectedPropertyIds.length;
  }

  get remainingClaimCapacity() {
    return Math.max(0, this.officeSummary.remainingClaimCapacity ?? 0);
  }

  get selectedRowsOnPage() {
    return this.propertiesOnCurrentPage
      .filter((property) =>
        this.selectedPropertyIds.includes(property.propertyId)
      )
      .map((property) => property.propertyId);
  }

  get isPreviousDisabled() {
    return this.isBusy || !this.isLoaded || this.currentPageNumber === 1;
  }

  get isNextDisabled() {
    return (
      this.isBusy || !this.isLoaded || this.currentPageNumber >= this.totalPages
    );
  }

  get isSubmitDisabled() {
    return (
      this.isBusy ||
      !this.isLoaded ||
      this.selectedCount === 0 ||
      this.selectedCount > this.remainingClaimCapacity
    );
  }

  refreshData() {
    return this.loadCurrentPage(true);
  }

  // A refresh gets the summary and ID list; page changes only fetch five records.
  async loadCurrentPage(refreshOfficeData = false) {
    if (!this.recordId) return;

    const requestId = ++this.latestRequestId;
    const salesOfficeId = this.recordId;
    this.isLoading = true;
    this.errorMessage = "";
    if (refreshOfficeData) this.isLoaded = false;

    try {
      if (refreshOfficeData) {
        const summary = await getAgentSummary({ salesOfficeId });
        if (requestId !== this.latestRequestId) return;

        this.officeSummary = summary || {};
        if (this.remainingClaimCapacity === 0) {
          this.showCapacityReachedMessage();
          return;
        }

        const propertyIds = await getClaimablePropertyIds({ salesOfficeId });
        if (requestId !== this.latestRequestId) return;

        this.claimablePropertyIds = propertyIds || [];

        const availableIds = new Set(this.claimablePropertyIds);
        this.selectedPropertyIds = this.selectedPropertyIds.filter((id) =>
          availableIds.has(id)
        );
        this.currentPageNumber = Math.min(
          this.currentPageNumber,
          this.totalPages
        );
      }

      const startIndex = (this.currentPageNumber - 1) * PAGE_SIZE;
      const propertyIdsForPage = this.claimablePropertyIds.slice(
        startIndex,
        startIndex + PAGE_SIZE
      );
      const result = propertyIdsForPage.length
        ? await getPropertyDetails({
            salesOfficeId,
            propertyIds: propertyIdsForPage
          })
        : [];
      if (requestId !== this.latestRequestId) return;

      const properties = result || [];
      const returnedIds = new Set(
        properties.map((property) => property.propertyId)
      );
      const missingIds = new Set(
        propertyIdsForPage.filter((id) => !returnedIds.has(id))
      );
      this.selectedPropertyIds = this.selectedPropertyIds.filter(
        (id) => !missingIds.has(id)
      );

      if (missingIds.size) {
        this.errorMessage =
          "Some properties are no longer available. Refresh the list before continuing.";
      }

      this.propertiesOnCurrentPage = properties;
      this.isLoaded = true;
    } catch (error) {
      if (requestId === this.latestRequestId) {
        this.errorMessage = this.getUserFacingErrorMessage(error);
        this.propertiesOnCurrentPage = [];
        this.isLoaded = false;
      }
    } finally {
      if (requestId === this.latestRequestId) this.isLoading = false;
    }
  }

  showCapacityReachedMessage() {
    this.isAtCapacity = true;
    this.dispatchEvent(
      new ShowToastEvent({
        title: "Claim limit reached",
        message: `You already have ${this.officeSummary.maxWorkingProperties} Working properties.`,
        variant: "info"
      })
    );
    this.dispatchEvent(new CloseActionScreenEvent());
  }

  navigateToPage(pageNumber) {
    if (this.isBusy || !this.isLoaded) return;

    const page = Math.max(1, Math.min(pageNumber, this.totalPages));
    if (page === this.currentPageNumber) return;

    this.currentPageNumber = page;
    this.loadCurrentPage();
  }

  handleFirst() {
    this.navigateToPage(1);
  }

  handlePrevious() {
    this.navigateToPage(this.currentPageNumber - 1);
  }

  handleNext() {
    this.navigateToPage(this.currentPageNumber + 1);
  }

  handleLast() {
    this.navigateToPage(this.totalPages);
  }

  handleRefresh() {
    if (!this.isBusy) this.refreshData();
  }

  handleRowSelection(event) {
    if (this.isBusy) return;

    const currentPageIds = new Set(
      this.propertiesOnCurrentPage.map((property) => property.propertyId)
    );
    const selectedOnOtherPages = this.selectedPropertyIds.filter(
      (id) => !currentPageIds.has(id)
    );
    const selectedOnThisPage = event.detail.selectedRows.map(
      (property) => property.propertyId
    );
    const selectedIds = [
      ...new Set([...selectedOnOtherPages, ...selectedOnThisPage])
    ];

    this.selectedPropertyIds = selectedIds.slice(
      0,
      this.remainingClaimCapacity
    );
    this.errorMessage =
      selectedIds.length > this.remainingClaimCapacity
        ? `You can select up to ${this.remainingClaimCapacity} properties.`
        : "";
  }

  handleSubmit() {
    this.claimSelectedProperties(false);
  }

  handleSubmitAndContinue() {
    this.claimSelectedProperties(true);
  }

  async claimSelectedProperties(stayOpenAfterClaim) {
    if (this.isSubmitDisabled) return;

    this.isSubmitting = true;
    this.errorMessage = "";
    const propertyIds = [...this.selectedPropertyIds];
    const salesOfficeId = this.recordId;
    const requestId = this.latestRequestId;

    try {
      const updatedSummary = await claimProperties({
        salesOfficeId,
        propertyIds
      });
      if (requestId !== this.latestRequestId) return;

      this.officeSummary = updatedSummary || {};
      this.selectedPropertyIds = [];
      this.currentPageNumber = 1;

      this.dispatchEvent(
        new ShowToastEvent({
          title: "Success",
          message: `${propertyIds.length} properties claimed.`,
          variant: "success"
        })
      );
      this.dispatchEvent(new RefreshEvent());

      if (stayOpenAfterClaim) {
        await this.refreshData();
        if (!this.isLoaded && !this.isAtCapacity) {
          this.errorMessage =
            "Claim succeeded, but refresh failed. Refresh the list; do not submit again.";
        }
      } else {
        this.dispatchEvent(new CloseActionScreenEvent());
      }
    } catch (error) {
      if (requestId === this.latestRequestId) {
        this.errorMessage = this.getUserFacingErrorMessage(error);
      }
    } finally {
      this.isSubmitting = false;
    }
  }

  handleCancel() {
    if (!this.isBusy) {
      this.dispatchEvent(new CloseActionScreenEvent());
    }
  }

  getUserFacingErrorMessage(error) {
    return (
      error?.body?.message ||
      error?.message ||
      "Unable to complete the request."
    );
  }
}
