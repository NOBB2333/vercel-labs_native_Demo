import { flushPromises, mount } from "@vue/test-utils";
import { beforeEach, describe, expect, it, vi } from "vitest";
import DashboardView from "./DashboardView.vue";

const bridge = vi.hoisted(() => ({
  getBackendHealth: vi.fn(),
  hasNativeBridge: vi.fn(),
}));

vi.mock("../services/native", () => bridge);

describe("DashboardView", () => {
  beforeEach(() => {
    bridge.getBackendHealth.mockReset();
    bridge.hasNativeBridge.mockReset();
    bridge.hasNativeBridge.mockReturnValue(false);
  });

  it("renders the full dashboard in browser preview mode", async () => {
    const wrapper = mount(DashboardView);
    await flushPromises();

    expect(wrapper.text()).toContain("Good afternoon.");
    expect(wrapper.text()).toContain("Production Build");
    expect(wrapper.text()).toContain("Browser preview");
  });

  it("filters recent tasks", async () => {
    const wrapper = mount(DashboardView);
    await wrapper.get('input[aria-label="Search tasks"]').setValue("database");

    expect(wrapper.text()).toContain("Database Migration");
    expect(wrapper.text()).not.toContain("Production Build");
  });

  it("refreshes task timestamps and bridge health", async () => {
    bridge.hasNativeBridge.mockReturnValue(true);
    bridge.getBackendHealth.mockResolvedValue({
      status: "ok",
      app: "Native Demo",
      version: "0.1.0",
      requestCount: 1,
    });
    const wrapper = mount(DashboardView);
    await flushPromises();

    await wrapper.get("button.secondary-button").trigger("click");
    await flushPromises();

    expect(wrapper.text()).toContain("just now");
    expect(wrapper.text()).toContain("Available");
    expect(bridge.getBackendHealth).toHaveBeenCalledTimes(2);
  });
});
