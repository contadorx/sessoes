import "server-only";
import { createClient } from "@supabase/supabase-js";

/**
 * O cliente do worker. Roda com `service_role`, que **ignora a RLS**.
 *
 * Três regras, e nenhuma é sugestão:
 *
 *  1. A chave nunca leva o prefixo `NEXT_PUBLIC_`. Se levasse, o Next a embutiria
 *     no bundle do navegador e ela viraria pública — e uma chave que ignora RLS
 *     no navegador é o fim do isolamento entre contas.
 *  2. Este arquivo é `server-only`. Importá-lo de um componente de cliente
 *     quebra a compilação, que é exatamente o que se quer.
 *  3. Só o outbox usa. Tela nenhuma. Toda página autenticada continua passando
 *     pela RLS via `supabaseSessao()` — a RLS é a fronteira, e uma exceção
 *     conveniente é como uma fronteira deixa de existir.
 */
export function supabaseServico() {
  const url = process.env.NEXT_PUBLIC_SUPABASE_URL;
  const chave = process.env.SUPABASE_SERVICE_ROLE_KEY;

  if (!url || !chave) {
    throw new Error(
      "Faltam NEXT_PUBLIC_SUPABASE_URL e SUPABASE_SERVICE_ROLE_KEY no ambiente do servidor.",
    );
  }

  return createClient(url, chave, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
}
