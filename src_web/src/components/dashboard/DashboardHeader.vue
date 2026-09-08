<script setup lang="ts">
import { Plus, RefreshCw } from "lucide-vue-next";

defineEmits<{
  refresh: [];
}>();
</script>

<template>
  <section class="page-header">
    <div>
      <p class="eyebrow">NATIVE SDK + VUE</p>
      <h1>Good afternoon.</h1>
      <p class="page-description">
        Monitor your local application, tasks and system activity from one place.
      </p>
    </div>

    <div class="header-actions">
      <button class="secondary-button" type="button" @click="$emit('refresh')">
        <RefreshCw :size="13" />
        Refresh
      </button>
      <button class="primary-button" type="button">
        <Plus :size="14" />
        New Task
      </button>
    </div>
  </section>
</template>
