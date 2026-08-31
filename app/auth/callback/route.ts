import { NextResponse, type NextRequest } from "next/server";
import { supabaseSessao } from "@/lib/supabase/server";

/**
 * O outro lado do link de confirmação.
 *
 * Quem clica em "confirme seu e-mail" volta para cá com um `code`. Sem esta
 * rota, esse clique dava 404 — a primeira coisa que uma pessoa via depois de
 * decidir criar a conta. Era o buraco mais barato e mais caro que o projeto
 * tinha.
 *
 * Duas decisões:
 *
 * **O destino é validado.** O `next` vem da URL, ou seja, de fora. Aceitar
 * qualquer valor transformaria esta rota num redirecionador aberto: um link que
 * começa em sessoes.com.br e termina em outro lugar é exatamente o formato de um
 * golpe de phishing convincente. Só caminho interno passa.
 *
 * **Erro não é tela em branco.** Link expirado ou já usado acontece o tempo
 * todo — a pessoa clica no e-mail de ontem. Volta para /entrar com um recado
 * legível, não para uma página de erro do framework.
 */

export const dynamic = "force-dynamic";

/** Só caminho relativo do próprio app. Nada de "//outro.site" nem de esquema. */
function destinoSeguro(bruto: string | null): string {
  if (!bruto) return "/agenda";
  if (!bruto.startsWith("/")) return "/agenda";
  if (bruto.startsWith("//")) return "/agenda";
  return bruto;
}

export async function GET(req: NextRequest) {
  const url = new URL(req.url);
  const code = url.searchParams.get("code");
  const proxima = destinoSeguro(url.searchParams.get("next"));

  if (!code) {
    return NextResponse.redirect(new URL("/entrar?erro=sem_codigo", url.origin));
  }

  const supabase = await supabaseSessao();
  const { error } = await supabase.auth.exchangeCodeForSession(code);

  if (error) {
    console.error("[auth/callback] troca de código falhou", { motivo: error.message });
    return NextResponse.redirect(new URL("/entrar?erro=link_expirado", url.origin));
  }

  return NextResponse.redirect(new URL(proxima, url.origin));
}
