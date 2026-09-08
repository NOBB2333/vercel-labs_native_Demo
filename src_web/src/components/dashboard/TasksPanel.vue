<script setup lang="ts">
import { Ellipsis, Search } from "lucide-vue-next";
import { computed } from "vue";
import type { DashboardTask, TaskStatus } from "../../features/dashboard/types";

const props = defineProps<{
  tasks: DashboardTask[];
}>();
const search = defineModel<string>("search", { required: true });

const filteredTasks = computed(() => {
  const keyword = search.value.trim().toLowerCase();
  if (!keyword) return props.tasks;

  return props.tasks.filter((task) => {
    return (
      task.name.toLowerCase().includes(keyword) ||
      task.description.toLowerCase().includes(keyword) ||
      task.status.toLowerCase().includes(keyword)
    );
  });
});

const runningTasks = computed(() => props.tasks.filter((task) => task.status === "Running").length);
const getStatusClass = (status: TaskStatus) => status.toLowerCase();
</script>

<template>
  <article class="panel tasks-panel">
    <div class="panel-header">
      <div>
        <h2>Recent tasks</h2>
        <p>{{ runningTasks }} tasks currently running</p>
      </div>

      <div class="panel-actions">
        <label class="search-box">
          <Search :size="12" />
          <input
            v-model="search"
            type="search"
            placeholder="Search tasks..."
            aria-label="Search tasks"
          />
        </label>
        <button class="small-button" type="button">View all</button>
      </div>
    </div>

    <div class="task-list">
      <div v-for="task in filteredTasks" :key="task.id" class="task-row">
        <div class="task-main">
          <div class="task-status" :class="getStatusClass(task.status)"><span></span></div>
          <div class="task-info">
            <strong>{{ task.name }}</strong>
            <span>{{ task.description }}</span>
          </div>
        </div>

        <div class="task-progress">
          <div class="progress-track">
            <div class="progress-value" :style="{ width: `${task.progress}%` }"></div>
          </div>
          <span>{{ task.progress }}%</span>
        </div>

        <div class="task-meta">
          <span class="status-label" :class="getStatusClass(task.status)">{{ task.status }}</span>
          <small>{{ task.updatedAt }}</small>
        </div>

        <button class="row-menu" type="button" :aria-label="`${task.name} menu`" title="Task menu">
          <Ellipsis :size="14" />
        </button>
      </div>
      <p v-if="filteredTasks.length === 0" class="task-empty">No matching tasks.</p>
    </div>
  </article>
</template>
