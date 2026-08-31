"use client";

import { createBrowserClient } from "@supabase/ssr";

/** Cliente do navegador — só para o fluxo de auth (entrar, sair, cadastrar). */
export function supabaseNavegador() {
  const url = process.env.NEXT_PUBLIC_SUPABASE_URL;
  const chave = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY;

  if (!url || !chave) {
    throw new Error("Faltam as variáveis do Supabase no ambiente do navegador.");
  }

  return createBrowserClient(url, chave);
}
