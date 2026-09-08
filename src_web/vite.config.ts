import tailwindcss from "@tailwindcss/vite";
import vue from "@vitejs/plugin-vue";
import { defineConfig } from "vitest/config";
import nativeConfig from "../config/native.json" with { type: "json" };

export default defineConfig({
  base: "./",
  publicDir: false,
  plugins: [vue(), tailwindcss()],
  server: {
    host: nativeConfig.devServer.host === "[::1]" ? "::1" : nativeConfig.devServer.host,
    port: nativeConfig.devServer.port,
    strictPort: nativeConfig.devServer.strictPort,
  },
  test: {
    environment: "jsdom",
    restoreMocks: true,
    setupFiles: ["./src/test/setup.ts"],
  },
});
