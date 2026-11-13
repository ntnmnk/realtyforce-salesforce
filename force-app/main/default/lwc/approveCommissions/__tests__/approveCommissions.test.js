import { createElement } from "lwc";
import Component from "c/approveCommissions";
import getSummary from "@salesforce/apex/ApproveCommissionsController.getRegionApprovalSummary";
import getIds from "@salesforce/apex/ApproveCommissionsController.getPendingPropertyIds";
import getPage from "@salesforce/apex/ApproveCommissionsController.getPendingPropertiesByIds";
import save from "@salesforce/apex/ApproveCommissionsController.approveProperties";

jest.mock(
  "lightning/actions",
  () => ({
    CloseActionScreenEvent: class extends CustomEvent {
      constructor() {
        super("lightning__actionsclosescreen");
      }
    }
  }),
  { virtual: true }
);
jest.mock(
  "lightning/refresh",
  () => ({
    RefreshEvent: class extends CustomEvent {
      constructor() {
        super("refresh");
      }
    }
  }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/ApproveCommissionsController.getRegionApprovalSummary",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/ApproveCommissionsController.getPendingPropertyIds",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/ApproveCommissionsController.getPendingPropertiesByIds",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/ApproveCommissionsController.approveProperties",
  () => ({ default: jest.fn() }),
  { virtual: true }
);

const flush = () =>
  Array.from({ length: 12 }).reduce(
    (pending) => pending.then(() => Promise.resolve()),
    Promise.resolve()
  );
const records = Array.from({ length: 6 }, (_, index) => ({
  propertyId: `property${index}`,
  street: `${index} Test Street`,
  commissionPercentage: 40,
  listingPrice: 100000,
  status: "Open"
}));
const summary = { regionName: "Test Region", regionYearToDateSales: 100000 };
let element;
const buttonLabels = {
  first: "First",
  previous: "Previous",
  next: "Next",
  last: "Last",
  refresh: "Refresh",
  cancel: "Cancel",
  continue: "Approve and Continue",
  submit: "Approve"
};
const button = (action) =>
  Array.from(element.shadowRoot.querySelectorAll("lightning-button")).find(
    (lightningButton) => lightningButton.label === buttonLabels[action]
  );
const table = () => element.shadowRoot.querySelector("lightning-datatable");
const select = (rows) =>
  table().dispatchEvent(
    new CustomEvent("rowselection", { detail: { selectedRows: rows } })
  );
beforeEach(() => {
  getSummary.mockResolvedValue(summary);
  getIds.mockResolvedValue(records.map((row) => row.propertyId));
  getPage.mockImplementation(({ propertyIds }) =>
    Promise.resolve(
      records.filter((row) => propertyIds.includes(row.propertyId))
    )
  );
  save.mockResolvedValue(summary);
  element = createElement("c-approveCommissions", { is: Component });
  document.body.appendChild(element);
  element.recordId = "scopeA";
});
afterEach(() => {
  while (document.body.firstChild)
    document.body.removeChild(document.body.firstChild);
  jest.resetAllMocks();
});
it("loads five details and preserves selections across pages", async () => {
  await flush();
  expect(getPage.mock.calls[0][0].propertyIds).toHaveLength(5);
  select([records[0]]);
  await flush();
  button("next").click();
  await flush();
  expect(table().data).toHaveLength(1);
  select([records[5]]);
  await flush();
  button("first").click();
  await flush();
  expect(table().selectedRows).toEqual(["property0"]);
  button("submit").click();
  await flush();
  expect(save.mock.calls[0][0].propertyIds).toEqual(["property0", "property5"]);
});
it("does not close or discard selections on a failed save", async () => {
  await flush();
  select([records[0]]);
  await flush();
  save.mockRejectedValue({
    body: { message: "Record was claimed by another user." }
  });
  const closeHandler = jest.fn();
  element.addEventListener("lightning__actionsclosescreen", closeHandler);
  button("submit").click();
  await flush();
  expect(
    element.shadowRoot.querySelector('[role="alert"]').textContent
  ).toContain("Record was claimed");
  expect(table().selectedRows).toEqual(["property0"]);
  expect(closeHandler).not.toHaveBeenCalled();
});
it("refreshes and clears selections after save and continue", async () => {
  await flush();
  select([records[0]]);
  await flush();
  getIds.mockResolvedValue(records.slice(1).map((row) => row.propertyId));
  button("continue").click();
  await flush();
  expect(save).toHaveBeenCalledTimes(1);
  expect(getIds).toHaveBeenCalledTimes(2);
  expect(table().selectedRows).toEqual([]);
  expect(button("submit").disabled).toBe(true);
});
it("shows a load failure and permits retry without mutation", async () => {
  await flush();
  getPage.mockRejectedValueOnce({ body: { message: "Read failed" } });
  button("last").click();
  await flush();
  expect(button("submit").disabled).toBe(true);
  expect(
    element.shadowRoot.querySelector('[role="alert"]').textContent
  ).toContain("Read failed");
  button("refresh").click();
  await flush();
  expect(table()).not.toBeNull();
  expect(save).not.toHaveBeenCalled();
});
it("shows a clear message when the region has no pending approvals", async () => {
  await flush();
  getIds.mockResolvedValue([]);
  button("refresh").click();
  await flush();

  expect(table()).toBeNull();
  expect(
    element.shadowRoot.querySelector('[role="status"]').textContent
  ).toContain("There are no properties pending approval in this region.");
});
it("preserves commission edits across pages and submits only selected records", async () => {
  await flush();
  table().dispatchEvent(
    new CustomEvent("cellchange", {
      detail: {
        draftValues: [{ propertyId: "property0", commissionPercentage: "55" }]
      }
    })
  );
  select([records[0]]);
  await flush();
  expect(table().draftValues).toEqual([
    { propertyId: "property0", commissionPercentage: "55" }
  ]);
  expect(table().data[0].commissionPercentage).toBe(55);
  button("last").click();
  await flush();
  button("first").click();
  await flush();
  expect(table().data[0].commissionPercentage).toBe(55);
  button("submit").click();
  await flush();
  expect(save.mock.calls[0][0].commissionPercentages).toEqual([55]);
  expect(save.mock.calls[0][0].propertyIds).toEqual(["property0"]);
});
it("rejects reducing the existing commission percentage", async () => {
  await flush();
  table().dispatchEvent(
    new CustomEvent("cellchange", {
      detail: {
        draftValues: [{ propertyId: "property0", commissionPercentage: 20 }]
      }
    })
  );
  await flush();
  expect(table().data[0].commissionPercentage).toBe(40);
  expect(
    element.shadowRoot.querySelector('[role="alert"]').textContent
  ).toContain("existing percentage");
});
