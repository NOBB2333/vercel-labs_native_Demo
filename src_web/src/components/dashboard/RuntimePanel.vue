<script setup lang="ts">
import { Cable } from "lucide-vue-next";

const props = defineProps<{
  status: string;
  error: string;
  version: string;
}>();

const message = () => {
  if (props.status === "Available") return "JavaScript bridge is connected.";
  return props.error || "Open the page in the desktop shell to connect.";
};
</script>

<template>
  <article class="panel bridge-panel">
    <div class="panel-header compact">
      <div>
        <h2>Native bridge</h2>
        <p>Runtime environment</p>
      </div>
      <span class="bridge-indicator" :class="{ connected: status === 'Available' }"></span>
    </div>

    <div class="bridge-status">
      <div class="bridge-icon"><Cable :size="16" /></div>
      <div>
        <strong>{{ status }}</strong>
        <p>{{ message() }}</p>
      </div>
    </div>

    <div class="runtime-grid">
      <div><span>Runtime</span><strong>Native SDK</strong></div>
      <div><span>Frontend</span><strong>Vue 3</strong></div>
      <div><span>Renderer</span><strong>WebView</strong></div>
      <div>
        <span>Version</span><strong>{{ version }}</strong>
      </div>
    </div>
  </article>
</template>
