import { defineConfig } from "vitest/config";
import path from "node:path";

export default defineConfig({
  test: {
    environment: "node",
    include: ["**/*.test.ts"],
    exclude: ["node_modules/**", ".next/**"],
  },
  resolve: {
    alias: {
      "@": path.resolve(import.meta.dirname, "."),
      // `server-only` só existe dentro do build do Next (ver testes/server-only.ts).
      "server-only": path.resolve(import.meta.dirname, "testes/server-only.ts"),
    },
  },
});
