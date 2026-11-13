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
  "lightning/platformShowToastEvent",
  () => ({
    ShowToastEvent: class extends CustomEvent {
      constructor(detail) {
        super("lightning__showtoast", { detail });
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
import { createElement } from "lwc";
import Component from "c/claimProperties";
import getSummary from "@salesforce/apex/ClaimPropertiesController.getAgentClaimSummary";
jest.mock(
  "@salesforce/apex/ClaimPropertiesController.getAgentClaimSummary",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
import getIds from "@salesforce/apex/ClaimPropertiesController.getClaimablePropertyIds";
jest.mock(
  "@salesforce/apex/ClaimPropertiesController.getClaimablePropertyIds",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
import getPage from "@salesforce/apex/ClaimPropertiesController.getClaimablePropertiesByIds";
jest.mock(
  "@salesforce/apex/ClaimPropertiesController.getClaimablePropertiesByIds",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
import save from "@salesforce/apex/ClaimPropertiesController.claimProperties";
jest.mock(
  "@salesforce/apex/ClaimPropertiesController.claimProperties",
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
const summary = {
  salesOfficeName: "Test Office",
  remainingClaimCapacity: 5,
  workingPropertyCount: 0,
  yearToDateSales: 0,
  yearToDateCommissions: 0
};
let element;
const button = (action) =>
  element.shadowRoot.querySelector(`[data-action="${action}"]`);
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
  element = createElement("c-claimProperties", { is: Component });
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
it("closes the action and explains when the agent is at claim capacity", async () => {
  await flush();
  const claimableIdCallCount = getIds.mock.calls.length;
  const propertyDetailCallCount = getPage.mock.calls.length;
  getSummary.mockResolvedValue({
    ...summary,
    workingPropertyCount: 5,
    maxWorkingProperties: 5,
    remainingClaimCapacity: 0
  });
  const closeHandler = jest.fn();
  const toastHandler = jest.fn();
  element.addEventListener("lightning__actionsclosescreen", closeHandler);
  element.addEventListener("lightning__showtoast", toastHandler);

  element.recordId = "fullCapacityOffice";
  await flush();

  expect(closeHandler).toHaveBeenCalledTimes(1);
  expect(toastHandler.mock.calls[0][0].detail).toMatchObject({
    title: "Claim limit reached",
    message: "You already have 5 Working properties.",
    variant: "info"
  });
  expect(getIds).toHaveBeenCalledTimes(claimableIdCallCount);
  expect(getPage).toHaveBeenCalledTimes(propertyDetailCallCount);
});
it("enforces capacity across page selections", async () => {
  await flush();
  select(records.slice(0, 5));
  await flush();
  button("last").click();
  await flush();
  select([records[5]]);
  await flush();
  expect(table().selectedRows).toEqual([]);
  expect(
    element.shadowRoot.querySelector('[role="alert"]').textContent
  ).toContain("up to 5");
});
it("drops a stale response after the record context changes", async () => {
  await flush();
  let resolveOldPage;
  getPage.mockImplementationOnce(
    () =>
      new Promise((resolve) => {
        resolveOldPage = resolve;
      })
  );
  button("last").click();
  await flush();
  element.recordId = "scopeB";
  await flush();
  resolveOldPage([{ propertyId: "oldRecord", street: "Stale" }]);
  await flush();
  expect(table().data.map((row) => row.propertyId)).not.toContain("oldRecord");
  expect(getSummary.mock.calls.at(-1)[0].salesOfficeId).toBe("scopeB");
});
