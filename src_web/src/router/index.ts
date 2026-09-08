import { createRouter, createWebHashHistory } from "vue-router";
import appManifest from "../../../app.json";

const router = createRouter({
  // Hash history 同时适用于 Vite HTTP 地址和 Native SDK 的离线 zero:// 来源。
  history: createWebHashHistory(),
  routes: [
    {
      path: "/",
      name: "dashboard",
      component: () => import("../views/DashboardView.vue"),
      meta: { title: appManifest.display_name },
    },
    { path: "/:pathMatch(.*)*", redirect: "/" },
  ],
});

router.afterEach((route) => {
  document.title = String(route.meta.title ?? appManifest.display_name);
});

export default router;
