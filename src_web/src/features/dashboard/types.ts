import type { Component } from "vue";

export type TaskStatus = "Running" | "Completed" | "Pending" | "Failed";

export interface DashboardTask {
  id: number;
  name: string;
  description: string;
  status: TaskStatus;
  progress: number;
  updatedAt: string;
}

export interface DashboardActivity {
  title: string;
  description: string;
  time: string;
  type: "success" | "info" | "warning";
}

export interface DashboardStat {
  label: string;
  value: string;
  change: string;
  icon: Component;
}
