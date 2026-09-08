<script setup lang="ts">
import type { DashboardStat } from "../../features/dashboard/types";

defineProps<{
  stats: DashboardStat[];
}>();
</script>

<template>
  <section class="stats-grid">
    <article v-for="stat in stats" :key="stat.label" class="stat-card">
      <div class="stat-header">
        <span>{{ stat.label }}</span>
        <div class="stat-icon">
          <component :is="stat.icon" :size="13" />
        </div>
      </div>
      <div class="stat-value">{{ stat.value }}</div>
      <div class="stat-footer">
        <span class="trend">{{ stat.change }}</span>
        <span>vs. last period</span>
      </div>
    </article>
  </section>
</template>
