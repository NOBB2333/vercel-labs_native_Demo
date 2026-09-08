<script setup lang="ts">
import {
  BarChart3,
  CircleHelp,
  Ellipsis,
  FolderKanban,
  House,
  ListTodo,
  Settings,
} from "lucide-vue-next";

const activeItem = defineModel<string>("activeItem", { required: true });

const navItems = [
  { label: "Overview", icon: House },
  { label: "Tasks", icon: ListTodo },
  { label: "Projects", icon: FolderKanban },
  { label: "Analytics", icon: BarChart3 },
];

const systemItems = [
  { label: "Settings", icon: Settings },
  { label: "Help Center", icon: CircleHelp },
];
</script>

<template>
  <aside class="sidebar">
    <div class="brand">
      <div class="brand-mark" aria-hidden="true">
        <span></span>
        <span></span>
        <span></span>
      </div>

      <div>
        <strong>Native</strong>
        <span>Desktop Console</span>
      </div>
    </div>

    <div class="workspace">
      <div class="workspace-avatar">N</div>
      <div class="workspace-info">
        <strong>My Workspace</strong>
        <span>Personal</span>
      </div>
      <button
        class="workspace-menu"
        type="button"
        aria-label="Workspace menu"
        title="Workspace menu"
      >
        <Ellipsis :size="15" />
      </button>
    </div>

    <nav class="navigation" aria-label="Primary navigation">
      <div class="nav-section-title">Workspace</div>
      <button
        v-for="item in navItems"
        :key="item.label"
        class="nav-item"
        :class="{ active: activeItem === item.label }"
        type="button"
        @click="activeItem = item.label"
      >
        <component :is="item.icon" class="nav-icon" :size="14" />
        <span>{{ item.label }}</span>
      </button>

      <div class="nav-section-title secondary">System</div>
      <button
        v-for="item in systemItems"
        :key="item.label"
        class="nav-item"
        :class="{ active: activeItem === item.label }"
        type="button"
        @click="activeItem = item.label"
      >
        <component :is="item.icon" class="nav-icon" :size="14" />
        <span>{{ item.label }}</span>
      </button>
    </nav>

    <div class="sidebar-footer">
      <div class="user-avatar">W</div>
      <div class="user-info">
        <strong>Workspace User</strong>
        <span>Local account</span>
      </div>
      <button class="more-button" type="button" aria-label="User menu" title="User menu">
        <Ellipsis :size="15" />
      </button>
    </div>
  </aside>
</template>
