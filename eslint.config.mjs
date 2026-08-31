import { defineConfig, globalIgnores } from "eslint/config";
import nextCoreWebVitals from "eslint-config-next/core-web-vitals";
import nextTypescript from "eslint-config-next/typescript";

/**
 * Configuração flat nativa. Não usamos FlatCompat: a ponte do eslintrc quebra
 * com o eslint 9.39 + eslint-config-next 16, e o eslint-config-next já exporta
 * flat config direto.
 */
export default defineConfig([
  globalIgnores([".next/**", "node_modules/**", "next-env.d.ts"]),

  ...nextCoreWebVitals,
  ...nextTypescript,

  /**
   * A lei nº 1 da engenharia do projeto (doc 05, cicatriz nº 1 do FinanceiroX):
   * `supabase-js` não lança erro — devolve `{ data, error }`, e código que
   * ignora `error` falha em silêncio. Toda operação passa pelo helper `db()`.
   * Importar o client direto fora de lib/supabase/ reprova aqui.
   */
  {
    files: ["**/*.{ts,tsx}"],
    // Exceções: a fronteira (lib/supabase), o próprio helper, e os testes —
    // que precisam dos tipos do provedor para forjar o erro.
    ignores: ["lib/supabase/**", "lib/db.ts", "**/*.test.ts"],
    rules: {
      "no-restricted-imports": [
        "error",
        {
          paths: [
            {
              name: "@supabase/supabase-js",
              message:
                "Use supabaseServer() de lib/supabase e envolva toda operação em db() — supabase-js não lança erro sozinho.",
            },
          ],
        },
      ],
    },
  },
]);
