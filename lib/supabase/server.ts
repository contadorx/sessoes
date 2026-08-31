import "server-only";
import { createClient } from "@supabase/supabase-js";
import { createServerClient } from "@supabase/ssr";
import { cookies } from "next/headers";

/**
 * Dois clientes, dois papéis. A segurança vem da RLS nos dois casos — a chave
 * publicável é pública por natureza.
 */

function ambiente() {
  const url = process.env.NEXT_PUBLIC_SUPABASE_URL;
  const chave = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY;

  if (!url || !chave) {
    throw new Error(
      "Faltam NEXT_PUBLIC_SUPABASE_URL e NEXT_PUBLIC_SUPABASE_ANON_KEY no ambiente.",
    );
  }
  return { url, chave };
}

/**
 * Sem sessão — para o que é público de propósito (a lista de espera da landing).
 * Roda como `anon`, e a única coisa que `anon` pode fazer é o que a RLS permite.
 */
export function supabaseServer() {
  const { url, chave } = ambiente();
  return createClient(url, chave, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
}

/**
 * Com a sessão da pessoa logada, lida dos cookies. É por aqui que a RLS sabe
 * quem está perguntando — `conta_atual()` depende do `auth.uid()` deste cliente.
 */
export async function supabaseSessao() {
  const { url, chave } = ambiente();
  const jar = await cookies();

  return createServerClient(url, chave, {
    cookies: {
      getAll: () => jar.getAll(),
      setAll: (novos) => {
        try {
          novos.forEach(({ name, value, options }) => jar.set(name, value, options));
        } catch {
          // Server Component não pode escrever cookie. O middleware já renovou
          // a sessão nesta requisição, então ignorar aqui é seguro.
        }
      },
    },
  });
}
