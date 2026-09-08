import { beforeEach, describe, expect, it, vi } from "vitest";
import { getBackendHealth, hasNativeBridge } from "./native";

describe("native bridge adapter", () => {
  beforeEach(() => {
    Reflect.deleteProperty(window, "zero");
  });

  it("detects browser preview mode", () => {
    expect(hasNativeBridge()).toBe(false);
  });

  it("invokes the typed health command", async () => {
    const health = {
      status: "ok" as const,
      app: "Native Demo",
      version: "0.1.0",
      requestCount: 1,
    };
    const invoke = vi.fn().mockResolvedValue(health);
    window.zero = { invoke };

    await expect(getBackendHealth()).resolves.toEqual(health);
    expect(invoke).toHaveBeenCalledWith("app.health");
  });

  it("rejects calls when the page is outside the desktop shell", async () => {
    await expect(getBackendHealth()).rejects.toThrow("Native bridge is not available");
  });
});
