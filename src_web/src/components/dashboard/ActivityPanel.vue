<script setup lang="ts">
import { Ellipsis } from "lucide-vue-next";
import type { DashboardActivity } from "../../features/dashboard/types";

defineProps<{
  activities: DashboardActivity[];
}>();
</script>

<template>
  <article class="panel activity-panel">
    <div class="panel-header compact">
      <div>
        <h2>Activity</h2>
        <p>Latest system events</p>
      </div>
      <button class="small-button" type="button" aria-label="Activity menu" title="Activity menu">
        <Ellipsis :size="14" />
      </button>
    </div>

    <div class="activity-list">
      <div v-for="activity in activities" :key="activity.title" class="activity-item">
        <div class="activity-marker" :class="activity.type"></div>
        <div class="activity-content">
          <strong>{{ activity.title }}</strong>
          <span>{{ activity.description }}</span>
          <small>{{ activity.time }}</small>
        </div>
      </div>
    </div>
  </article>
</template>
