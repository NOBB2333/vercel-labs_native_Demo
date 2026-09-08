<script setup lang="ts">
import { Bell } from "lucide-vue-next";

defineProps<{
  activeItem: string;
  currentTime: string;
}>();
</script>

<template>
  <header class="topbar">
    <div class="breadcrumb">
      <span>Workspace</span>
      <span class="separator">/</span>
      <strong>{{ activeItem }}</strong>
    </div>

    <div class="topbar-actions">
      <div class="clock">
        <span class="status-dot"></span>
        {{ currentTime }}
      </div>
      <button class="icon-button" type="button" aria-label="Notifications" title="Notifications">
        <Bell :size="15" />
        <span class="notification-dot"></span>
      </button>
      <button class="avatar-button" type="button" aria-label="User profile" title="User profile">
        W
      </button>
    </div>
  </header>
</template>
