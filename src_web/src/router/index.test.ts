import { describe, expect, it } from "vitest";
import router from "./index";
import appManifest from "../../../app.json";

describe("router", () => {
  it("uses the dashboard as the root route", () => {
    const root = router.getRoutes().find((route) => route.path === "/");

    expect(root?.name).toBe("dashboard");
    expect(root?.meta.title).toBe(appManifest.display_name);
  });

  it("declares a fallback route", () => {
    expect(router.getRoutes().some((route) => route.path.includes("pathMatch"))).toBe(true);
  });
});
