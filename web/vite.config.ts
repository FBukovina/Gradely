import { defineConfig } from "vite";
import react from "@vitejs/plugin-react";

const apiPort = process.env.GRADEY_WEB_API_PORT ?? "8787";

export default defineConfig({
  plugins: [react()],
  publicDir: "public",
  build: {
    outDir: "dist/client",
    emptyOutDir: true,
    sourcemap: false,
  },
  server: {
    port: 5173,
    strictPort: true,
    proxy: {
      "/api": {
        target: `http://127.0.0.1:${apiPort}`,
        changeOrigin: false,
      },
    },
  },
  test: {
    environment: "node",
    include: ["tests/**/*.test.ts"],
  },
});
