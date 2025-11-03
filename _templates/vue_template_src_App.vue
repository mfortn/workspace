<script setup>
const api = import.meta.env.VITE_API_URL || 'http://localhost:8081'
</script>

<template>
  <main style="padding:2rem; font-family: system-ui;">
    <h1>Vue + Vite</h1>
    <p>API base: {{ api }}</p>
  </main>
</template>

<style>
h1 { margin-bottom: .5rem; }
</style>
