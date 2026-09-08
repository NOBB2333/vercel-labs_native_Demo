<script setup lang="ts">
import { ArrowRight, ListChecks, Play, Target, TrendingUp } from "lucide-vue-next";
import { onMounted, onUnmounted, ref } from "vue";
import appManifest from "../../../app.json";
import ActivityPanel from "../components/dashboard/ActivityPanel.vue";
import DashboardHeader from "../components/dashboard/DashboardHeader.vue";
import RuntimePanel from "../components/dashboard/RuntimePanel.vue";
import StatsGrid from "../components/dashboard/StatsGrid.vue";
import TasksPanel from "../components/dashboard/TasksPanel.vue";
import AppSidebar from "../components/layout/AppSidebar.vue";
import AppTopbar from "../components/layout/AppTopbar.vue";
import type { DashboardActivity, DashboardStat, DashboardTask } from "../features/dashboard/types";
import { getBackendHealth, hasNativeBridge, type BackendHealth } from "../services/native";

const bridge = ref("checking...");
const bridgeHealth = ref<BackendHealth | null>(null);
const bridgeError = ref("");
const activeNav = ref("Overview");
const search = ref("");
const currentTime = ref("");
let clockTimer: number | undefined;

const stats: DashboardStat[] = [
  {
    label: "Total Tasks",
    value: "1,289",
    change: "+12.5%",
    icon: ListChecks,
  },
  {
    label: "Running",
    value: "24",
    change: "+4",
    icon: Play,
  },
  {
    label: "Completed",
    value: "1,198",
    change: "+18.2%",
    icon: TrendingUp,
  },
  {
    label: "Success Rate",
    value: "96.8%",
    change: "+2.4%",
    icon: Target,
  },
];

const tasks = ref<DashboardTask[]>([
  {
    id: 1,
    name: "Production Build",
    description: "Building application bundles for production",
    status: "Running",
    progress: 78,
    updatedAt: "2 min ago",
  },
  {
    id: 2,
    name: "Database Migration",
    description: "Updating production database schema",
    status: "Completed",
    progress: 100,
    updatedAt: "18 min ago",
  },
  {
    id: 3,
    name: "Dependency Update",
    description: "Checking outdated packages and vulnerabilities",
    status: "Pending",
    progress: 0,
    updatedAt: "32 min ago",
  },
  {
    id: 4,
    name: "System Diagnostics",
    description: "Running local environment diagnostics",
    status: "Failed",
    progress: 46,
    updatedAt: "1 hour ago",
  },
]);

const activities: DashboardActivity[] = [
  {
    title: "Build completed",
    description: "Production build finished successfully",
    time: "2 minutes ago",
    type: "success",
  },
  {
    title: "Configuration updated",
    description: "Application settings were changed",
    time: "15 minutes ago",
    type: "info",
  },
  {
    title: "High memory usage",
    description: "Memory usage exceeded 80%",
    time: "28 minutes ago",
    type: "warning",
  },
  {
    title: "Database connected",
    description: "PostgreSQL connection established",
    time: "42 minutes ago",
    type: "success",
  },
];

const updateTime = () => {
  currentTime.value = new Intl.DateTimeFormat("en-US", {
    hour: "2-digit",
    minute: "2-digit",
    second: "2-digit",
  }).format(new Date());
};

async function checkBridge() {
  bridgeError.value = "";

  if (!hasNativeBridge()) {
    bridge.value = "Browser preview";
    bridgeHealth.value = null;
    return;
  }

  bridge.value = "Checking...";
  try {
    bridgeHealth.value = await getBackendHealth();
    bridge.value = "Available";
  } catch (error) {
    bridge.value = "Unavailable";
    bridgeError.value = error instanceof Error ? error.message : "Unknown bridge error";
  }
}

onMounted(() => {
  void checkBridge();
  updateTime();
  clockTimer = window.setInterval(updateTime, 1000);
});

onUnmounted(() => {
  if (clockTimer !== undefined) window.clearInterval(clockTimer);
});

const refreshTasks = () => {
  tasks.value = tasks.value.map((task) => ({
    ...task,
    updatedAt: "just now",
  }));
  void checkBridge();
};
</script>

<template>
  <div class="app-shell">
    <AppSidebar v-model:active-item="activeNav" />

    <main class="main-content">
      <AppTopbar :active-item="activeNav" :current-time="currentTime" />

      <div class="content">
        <DashboardHeader @refresh="refreshTasks" />
        <StatsGrid :stats="stats" />

        <section class="dashboard-grid">
          <TasksPanel v-model:search="search" :tasks="tasks" />

          <div class="right-column">
            <RuntimePanel
              :status="bridge"
              :error="bridgeError"
              :version="bridgeHealth?.version ?? appManifest.version"
            />
            <ActivityPanel :activities="activities" />
          </div>
        </section>

        <!-- Bottom -->
        <section class="bottom-grid">
          <article class="panel system-panel">
            <div class="panel-header compact">
              <div>
                <h2>System health</h2>
                <p>Local machine status</p>
              </div>

              <span class="healthy-label">
                <span></span>
                All systems operational
              </span>
            </div>

            <div class="health-bars">
              <div class="health-item">
                <div>
                  <span>CPU</span>
                  <strong>32%</strong>
                </div>

                <div class="health-track">
                  <div style="width: 32%"></div>
                </div>
              </div>

              <div class="health-item">
                <div>
                  <span>Memory</span>
                  <strong>64%</strong>
                </div>

                <div class="health-track">
                  <div style="width: 64%"></div>
                </div>
              </div>

              <div class="health-item">
                <div>
                  <span>Storage</span>
                  <strong>48%</strong>
                </div>

                <div class="health-track">
                  <div style="width: 48%"></div>
                </div>
              </div>
            </div>
          </article>

          <article class="panel quick-panel">
            <div>
              <span class="quick-eyebrow">QUICK ACTION</span>

              <h2>Ready to build?</h2>

              <p>Create a new task and start working with your native runtime.</p>
            </div>

            <button class="primary-button" type="button">
              Create task
              <ArrowRight :size="13" />
            </button>
          </article>
        </section>
      </div>
    </main>
  </div>
</template>

<style>
* {
  box-sizing: border-box;
}

body {
  margin: 0;
  min-width: 320px;
  min-height: 100vh;
  background: #f5f6f8;
  color: #181a1f;
  font-family:
    Inter,
    -apple-system,
    BlinkMacSystemFont,
    "SF Pro Display",
    "SF Pro Text",
    "Segoe UI",
    sans-serif;
}

button,
input {
  font: inherit;
}

button {
  border: 0;
}

.app-shell {
  display: flex;
  min-height: 100vh;
  background: #f5f6f8;
}

/* Sidebar */

.sidebar {
  position: fixed;
  inset: 0 auto 0 0;
  display: flex;
  flex-direction: column;
  width: 248px;
  padding: 22px 14px 14px;
  border-right: 1px solid #e2e4e8;
  background: #fbfbfc;
}

.brand {
  display: flex;
  align-items: center;
  gap: 11px;
  padding: 0 9px 22px;
}

.brand-mark {
  display: grid;
  grid-template-columns: repeat(3, 5px);
  align-items: end;
  gap: 3px;
  width: 30px;
  height: 30px;
  padding: 7px;
  border: 1px solid #dfe2e7;
  border-radius: 8px;
  background: #fff;
}

.brand-mark span {
  display: block;
  height: 8px;
  border-radius: 2px;
  background: #17191d;
}

.brand-mark span:nth-child(2) {
  height: 12px;
}

.brand-mark span:nth-child(3) {
  height: 15px;
}

.brand strong {
  display: block;
  font-size: 14px;
  letter-spacing: -0.2px;
}

.brand span {
  display: block;
  margin-top: 2px;
  color: #8a8f98;
  font-size: 10px;
}

.workspace {
  display: flex;
  align-items: center;
  gap: 9px;
  margin: 0 2px 20px;
  padding: 10px;
  border: 1px solid #e5e7eb;
  border-radius: 9px;
  background: #fff;
}

.workspace-avatar,
.user-avatar {
  display: grid;
  flex: 0 0 auto;
  place-items: center;
  width: 30px;
  height: 30px;
  border-radius: 7px;
  background: #181a1f;
  color: white;
  font-size: 11px;
  font-weight: 700;
}

.workspace-info,
.user-info {
  min-width: 0;
  flex: 1;
}

.workspace-info strong,
.user-info strong {
  display: block;
  overflow: hidden;
  font-size: 12px;
  font-weight: 600;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.workspace-info span,
.user-info span {
  display: block;
  margin-top: 3px;
  color: #92969e;
  font-size: 10px;
}

.workspace-menu,
.more-button {
  padding: 3px;
  color: #92969e;
  background: transparent;
  cursor: pointer;
}

.navigation {
  flex: 1;
}

.nav-section-title {
  padding: 0 11px 7px;
  color: #a0a4ab;
  font-size: 10px;
  font-weight: 600;
  letter-spacing: 0.08em;
  text-transform: uppercase;
}

.nav-section-title.secondary {
  margin-top: 24px;
}

.nav-item {
  display: flex;
  align-items: center;
  width: 100%;
  height: 36px;
  margin: 2px 0;
  padding: 0 11px;
  border-radius: 7px;
  color: #686d76;
  background: transparent;
  font-size: 12px;
  text-align: left;
  cursor: pointer;
  transition: 0.15s ease;
}

.nav-item:hover {
  background: #f0f1f3;
  color: #22252a;
}

.nav-item.active {
  background: #e9eaed;
  color: #16181c;
  font-weight: 600;
}

.nav-icon {
  width: 24px;
  color: #7d828a;
  font-size: 14px;
}

.nav-item.active .nav-icon {
  color: #181a1f;
}

.sidebar-footer {
  display: flex;
  align-items: center;
  gap: 9px;
  padding: 12px 8px 2px;
  border-top: 1px solid #e6e7ea;
}

/* Main */

.main-content {
  width: calc(100% - 248px);
  margin-left: 248px;
}

.topbar {
  display: flex;
  align-items: center;
  justify-content: space-between;
  height: 58px;
  padding: 0 32px;
  border-bottom: 1px solid #e3e5e8;
  background: rgba(255, 255, 255, 0.8);
}

.breadcrumb {
  display: flex;
  align-items: center;
  gap: 9px;
  color: #969aa2;
  font-size: 11px;
}

.breadcrumb strong {
  color: #35383e;
  font-weight: 600;
}

.separator {
  color: #c3c6ca;
}

.topbar-actions {
  display: flex;
  align-items: center;
  gap: 14px;
}

.clock {
  display: flex;
  align-items: center;
  gap: 7px;
  color: #8c9098;
  font-size: 10px;
  font-variant-numeric: tabular-nums;
}

.status-dot,
.bridge-indicator {
  width: 6px;
  height: 6px;
  border-radius: 50%;
  background: #a3a7ae;
}

.status-dot {
  background: #31a46c;
}

.icon-button {
  position: relative;
  display: grid;
  place-items: center;
  width: 30px;
  height: 30px;
  color: #666b73;
  background: transparent;
  cursor: pointer;
}

.notification-dot {
  position: absolute;
  top: 6px;
  right: 6px;
  width: 5px;
  height: 5px;
  border: 1px solid white;
  border-radius: 50%;
  background: #d85050;
}

.avatar-button {
  display: grid;
  place-items: center;
  width: 29px;
  height: 29px;
  border-radius: 50%;
  background: #e8e9eb;
  color: #555a62;
  font-size: 10px;
  font-weight: 700;
}

/* Content */

.content {
  max-width: 1500px;
  margin: 0 auto;
  padding: 34px 38px 50px;
}

.page-header {
  display: flex;
  align-items: flex-end;
  justify-content: space-between;
  margin-bottom: 28px;
}

.eyebrow,
.quick-eyebrow {
  margin: 0 0 9px;
  color: #8e939c;
  font-size: 9px;
  font-weight: 700;
  letter-spacing: 0.13em;
}

.page-header h1 {
  margin: 0;
  color: #181a1f;
  font-size: 30px;
  font-weight: 650;
  letter-spacing: -0.04em;
}

.page-description {
  max-width: 600px;
  margin: 8px 0 0;
  color: #81868f;
  font-size: 12px;
  line-height: 1.6;
}

.header-actions,
.panel-actions {
  display: flex;
  align-items: center;
  gap: 8px;
}

.primary-button,
.secondary-button,
.small-button {
  display: inline-flex;
  align-items: center;
  justify-content: center;
  gap: 7px;
  height: 32px;
  padding: 0 12px;
  border-radius: 6px;
  font-size: 11px;
  font-weight: 600;
  cursor: pointer;
}

.primary-button {
  background: #181a1f;
  color: white;
}

.primary-button:hover {
  background: #303238;
}

.secondary-button,
.small-button {
  border: 1px solid #dfe1e5;
  background: white;
  color: #5e636b;
}

.secondary-button:hover,
.small-button:hover {
  background: #f7f7f8;
}

/* Stats */

.stats-grid {
  display: grid;
  grid-template-columns: repeat(4, 1fr);
  gap: 12px;
  margin-bottom: 14px;
}

.stat-card {
  padding: 17px 18px 15px;
  border: 1px solid #e1e3e7;
  border-radius: 9px;
  background: white;
}

.stat-header {
  display: flex;
  align-items: center;
  justify-content: space-between;
  color: #858a93;
  font-size: 10px;
}

.stat-icon {
  display: grid;
  place-items: center;
  width: 25px;
  height: 25px;
  border: 1px solid #e4e5e8;
  border-radius: 6px;
  color: #6d727a;
  font-size: 12px;
}

.stat-value {
  margin-top: 14px;
  font-size: 25px;
  font-weight: 650;
  letter-spacing: -0.04em;
}

.stat-footer {
  display: flex;
  align-items: center;
  gap: 7px;
  margin-top: 7px;
  color: #9a9ea5;
  font-size: 9px;
}

.trend {
  color: #3c9b6c;
  font-weight: 600;
}

/* Panels */

.dashboard-grid {
  display: grid;
  grid-template-columns: minmax(0, 1.65fr) minmax(320px, 0.85fr);
  gap: 14px;
}

.panel {
  border: 1px solid #e1e3e7;
  border-radius: 9px;
  background: white;
}

.panel-header {
  display: flex;
  align-items: center;
  justify-content: space-between;
  padding: 18px 19px;
  border-bottom: 1px solid #eceef0;
}

.panel-header.compact {
  padding: 16px 17px;
}

.panel-header h2 {
  margin: 0;
  color: #25282d;
  font-size: 12px;
  font-weight: 650;
}

.panel-header p {
  margin: 4px 0 0;
  color: #989ca4;
  font-size: 9px;
}

.search-box {
  display: flex;
  align-items: center;
  width: 150px;
  height: 28px;
  gap: 6px;
  padding: 0 8px;
  border: 1px solid #e3e5e8;
  border-radius: 5px;
  background: #fafafa;
}

.search-box span {
  color: #9da1a8;
}

.search-box input {
  width: 100%;
  border: 0;
  outline: 0;
  background: transparent;
  color: #33363b;
  font-size: 9px;
}

.task-list {
  padding: 0 18px;
}

.task-empty {
  margin: 0;
  padding: 24px 0;
  color: #92969e;
  font-size: 10px;
  text-align: center;
}

.task-row {
  display: grid;
  grid-template-columns: minmax(200px, 1.5fr) minmax(110px, 0.8fr) 90px 20px;
  align-items: center;
  gap: 15px;
  min-height: 68px;
  border-bottom: 1px solid #f0f1f3;
}

.task-row:last-child {
  border-bottom: 0;
}

.task-main {
  display: flex;
  align-items: center;
  gap: 10px;
  min-width: 0;
}

.task-status {
  display: grid;
  flex: 0 0 auto;
  place-items: center;
  width: 22px;
  height: 22px;
  border: 1px solid #e1e3e6;
  border-radius: 6px;
}

.task-status span {
  width: 6px;
  height: 6px;
  border-radius: 50%;
  background: #a6aab0;
}

.task-status.running span {
  background: #4e88d7;
}

.task-status.completed span {
  background: #43a26f;
}

.task-status.failed span {
  background: #d85d5d;
}

.task-info {
  min-width: 0;
}

.task-info strong {
  display: block;
  overflow: hidden;
  color: #35383d;
  font-size: 10px;
  font-weight: 600;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.task-info span {
  display: block;
  overflow: hidden;
  margin-top: 4px;
  color: #9a9ea6;
  font-size: 8px;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.task-progress {
  display: flex;
  align-items: center;
  gap: 7px;
}

.task-progress > span {
  width: 28px;
  color: #7f848c;
  font-size: 8px;
  text-align: right;
}

.progress-track {
  flex: 1;
  height: 4px;
  overflow: hidden;
  border-radius: 10px;
  background: #eceef0;
}

.progress-value {
  height: 100%;
  border-radius: inherit;
  background: #565b64;
}

.task-meta {
  text-align: right;
}

.status-label {
  font-size: 8px;
  font-weight: 600;
}

.status-label.running {
  color: #4e88d7;
}

.status-label.completed {
  color: #3d9868;
}

.status-label.pending {
  color: #999da4;
}

.status-label.failed {
  color: #d85d5d;
}

.task-meta small {
  display: block;
  margin-top: 5px;
  color: #a6a9af;
  font-size: 7px;
}

.row-menu {
  color: #aaaeb4;
  background: transparent;
  cursor: pointer;
}

/* Right */

.right-column {
  display: flex;
  flex-direction: column;
  gap: 14px;
}

.bridge-status {
  display: flex;
  align-items: center;
  gap: 11px;
  padding: 16px 17px;
}

.bridge-icon {
  display: grid;
  place-items: center;
  width: 35px;
  height: 35px;
  border-radius: 8px;
  background: #f0f1f3;
  color: #555a62;
}

.bridge-status strong {
  display: block;
  color: #303339;
  font-size: 11px;
}

.bridge-status p {
  margin: 4px 0 0;
  color: #9499a1;
  font-size: 8px;
}

.bridge-indicator {
  background: #b4b7bd;
}

.bridge-indicator.connected {
  background: #3ea16d;
}

.runtime-grid {
  display: grid;
  grid-template-columns: 1fr 1fr;
  border-top: 1px solid #eceef0;
}

.runtime-grid div {
  padding: 11px 16px;
  border-right: 1px solid #eceef0;
  border-bottom: 1px solid #eceef0;
}

.runtime-grid div:nth-child(even) {
  border-right: 0;
}

.runtime-grid div:nth-last-child(-n + 2) {
  border-bottom: 0;
}

.runtime-grid span {
  display: block;
  color: #a0a4ab;
  font-size: 8px;
}

.runtime-grid strong {
  display: block;
  margin-top: 4px;
  color: #555960;
  font-size: 9px;
  font-weight: 600;
}

.activity-list {
  padding: 4px 17px 12px;
}

.activity-item {
  display: flex;
  gap: 10px;
  padding: 10px 0;
  border-bottom: 1px solid #f0f1f3;
}

.activity-item:last-child {
  border-bottom: 0;
}

.activity-marker {
  flex: 0 0 auto;
  width: 5px;
  height: 5px;
  margin-top: 4px;
  border-radius: 50%;
  background: #a3a7ad;
}

.activity-marker.success {
  background: #46a473;
}

.activity-marker.info {
  background: #588bd0;
}

.activity-marker.warning {
  background: #d2a148;
}

.activity-content strong {
  display: block;
  color: #4a4e54;
  font-size: 9px;
  font-weight: 600;
}

.activity-content span {
  display: block;
  margin-top: 3px;
  color: #969aa2;
  font-size: 8px;
}

.activity-content small {
  display: block;
  margin-top: 4px;
  color: #b0b3b9;
  font-size: 7px;
}

/* Bottom */

.bottom-grid {
  display: grid;
  grid-template-columns: 1.4fr 1fr;
  gap: 14px;
  margin-top: 14px;
}

.health-bars {
  display: grid;
  grid-template-columns: repeat(3, 1fr);
  gap: 20px;
  padding: 16px 18px 19px;
}

.health-item > div:first-child {
  display: flex;
  justify-content: space-between;
  color: #858a92;
  font-size: 8px;
}

.health-item strong {
  color: #45494f;
  font-weight: 600;
}

.health-track {
  height: 4px;
  margin-top: 9px;
  overflow: hidden;
  border-radius: 10px;
  background: #eceef0;
}

.health-track div {
  height: 100%;
  border-radius: inherit;
  background: #636870;
}

.healthy-label {
  display: flex;
  align-items: center;
  gap: 6px;
  color: #4b9b70;
  font-size: 8px;
}

.healthy-label span {
  width: 5px;
  height: 5px;
  border-radius: 50%;
  background: #4b9b70;
}

.quick-panel {
  display: flex;
  align-items: center;
  justify-content: space-between;
  min-height: 102px;
  padding: 18px;
  background: #1b1d21;
  color: white;
}

.quick-panel .quick-eyebrow {
  margin-bottom: 5px;
  color: #8d929b;
}

.quick-panel h2 {
  margin: 0;
  font-size: 14px;
  letter-spacing: -0.02em;
}

.quick-panel p {
  max-width: 250px;
  margin: 5px 0 0;
  color: #989ca4;
  font-size: 8px;
  line-height: 1.5;
}

.quick-panel .primary-button {
  flex: 0 0 auto;
  background: white;
  color: #1b1d21;
}

@media (max-width: 1200px) {
  .content {
    padding: 28px 25px 40px;
  }

  .dashboard-grid {
    grid-template-columns: 1fr;
  }

  .right-column {
    display: grid;
    grid-template-columns: 1fr 1fr;
  }
}

@media (max-width: 1000px) {
  .stats-grid {
    grid-template-columns: repeat(2, 1fr);
  }

  .bottom-grid {
    grid-template-columns: 1fr;
  }

  .right-column {
    grid-template-columns: 1fr;
  }
}

@media (max-width: 760px) {
  .sidebar {
    position: static;
    width: 100%;
    min-height: auto;
  }

  .navigation,
  .sidebar-footer {
    display: none;
  }

  .workspace {
    margin-bottom: 0;
  }

  .app-shell {
    display: block;
  }

  .main-content {
    width: 100%;
    margin-left: 0;
  }

  .topbar,
  .page-header,
  .panel-header,
  .quick-panel {
    align-items: flex-start;
    flex-direction: column;
    height: auto;
    gap: 12px;
  }

  .topbar,
  .content {
    padding: 18px;
  }

  .stats-grid,
  .health-bars {
    grid-template-columns: 1fr;
  }

  .task-row {
    grid-template-columns: minmax(0, 1fr) auto;
    gap: 10px;
    padding: 12px 0;
  }

  .task-progress {
    grid-column: 1 / -1;
    grid-row: 2;
  }

  .task-meta {
    grid-column: 2;
    grid-row: 1;
  }

  .row-menu {
    display: none;
  }

  .header-actions,
  .panel-actions,
  .search-box {
    width: 100%;
  }
}
</style>
