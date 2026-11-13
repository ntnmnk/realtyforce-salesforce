
import { LightningElement, api } from 'lwc';

export default class RecordPagination extends LightningElement {

    // Values received from the parent LWC
    @api pageNumber = 1;
    @api pageSize = 5;
    @api totalRecords = 0;
    @api disabled = false;

    // Total number of pages
    get totalPages() {
        return Math.max(
            1,
            Math.ceil(this.totalRecords / this.pageSize)
        );
    }

    get pageText() {
        return `Page ${this.pageNumber} of ${this.totalPages}`;
    }

    get isPreviousDisabled() {
        return this.disabled || this.pageNumber <= 1;
    }

    get isNextDisabled() {
        return this.disabled || this.pageNumber >= this.totalPages;
    }

    // Notify parent when the page changes
    changePage(pageNumber) {
        if (
            this.disabled ||
            pageNumber < 1 ||
            pageNumber > this.totalPages ||
            pageNumber === this.pageNumber
        ) {
            return;
        }

        this.dispatchEvent(
            new CustomEvent('pagechange', {
                detail: { pageNumber }
            })
        );
    }

    handleFirst() {
        this.changePage(1);
    }

    handlePrevious() {
        this.changePage(this.pageNumber - 1);
    }

    handleNext() {
        this.changePage(this.pageNumber + 1);
    }

    handleLast() {
        this.changePage(this.totalPages);
    }
}
