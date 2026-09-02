import { NextResponse, type NextRequest } from "next/server";
import { supabaseSessao } from "@/lib/supabase/server";

/**
 * O outro lado do link de confirmação — a metade que o servidor alcança.
 *
 * TRÊS FORMATOS CHEGAM AQUI, E ANTES SÓ UM ERA TRATADO
 *
 * O Supabase manda a pessoa de volta de três jeitos diferentes, dependendo de
 * como o link foi montado:
 *
 *   1. `?code=…`        — fluxo PKCE. É o único que esta rota tratava.
 *   2. `?token_hash=…&type=signup` — quando o modelo de e-mail usa
 *      `{{ .TokenHash }}` e aponta direto para cá. É o formato **recomendado**
 *      para servidor, porque a confirmação acontece do lado de cá e a sessão
 *      já sai nos cookies.
 *   3. `#access_token=…` — o padrão de fábrica, que passa pelo `/auth/v1/verify`
 *      do Supabase e devolve os tokens **no fragmento**. Fragmento não chega ao
 *      servidor: quem trata esse caso é o `<Confirmar />`, no navegador.
 *
 * O Leandro clicou e não entrou em lugar nenhum, e o motivo é que o link dele
 * era do terceiro tipo. Esta rota passou a tratar o segundo, o `<Confirmar />`
 * trata o terceiro, e o primeiro continua como estava — os três caminhos levam
 * ao mesmo lugar, e nenhum deles depende de eu ter configurado o modelo de
 * e-mail de um jeito específico.
 *
 * AS DUAS DECISÕES ANTIGAS, QUE FICAM
 *
 * **O destino é validado.** O `next` vem de fora. Aceitar qualquer valor faria
 * desta rota um redirecionador aberto — um link que começa em sessoes.com.br e
 * termina em outro lugar é o formato de um golpe de phishing convincente.
 *
 * **Erro não é tela em branco.** Link expirado ou já usado acontece o tempo
 * todo: a pessoa clica no e-mail de ontem. Volta para `/entrar` com um recado
 * legível.
 */

export const dynamic = "force-dynamic";

/** Só caminho relativo do próprio app. Nada de "//outro.site" nem de esquema. */
function destinoSeguro(bruto: string | null): string {
  if (!bruto) return "/agenda";
  if (!bruto.startsWith("/")) return "/agenda";
  if (bruto.startsWith("//")) return "/agenda";
  return bruto;
}

/**
 * Os tipos de link que o Supabase manda por e-mail.
 *
 * A lista é escrita à mão em vez de importada do `@supabase/supabase-js`: o
 * ESLint deste projeto proíbe importar dele fora de `lib/supabase`, e a regra
 * está certa mesmo para um `import type` — a exceção "só o tipo" é como a
 * proibição vira hábito de contornar. Cinco strings custam menos que uma
 * exceção.
 */
type TipoDeLink = "signup" | "invite" | "magiclink" | "recovery" | "email_change" | "email";

const TIPOS: TipoDeLink[] = ["signup", "invite", "magiclink", "recovery", "email_change", "email"];

function tipoValido(bruto: string | null): TipoDeLink {
  return TIPOS.includes(bruto as TipoDeLink) ? (bruto as TipoDeLink) : "email";
}

export async function GET(req: NextRequest) {
  const url = new URL(req.url);
  const code = url.searchParams.get("code");
  const tokenHash = url.searchParams.get("token_hash");
  const proxima = destinoSeguro(url.searchParams.get("next"));

  // O erro pode vir na própria URL, quando o Supabase recusa antes de redirigir.
  const erroDoProvedor = url.searchParams.get("error_description") ?? url.searchParams.get("error");
  if (erroDoProvedor && !code && !tokenHash) {
    console.error("[auth/callback] o provedor recusou", { motivo: erroDoProvedor });
    return NextResponse.redirect(new URL("/entrar?erro=link_expirado", url.origin));
  }

  if (!code && !tokenHash) {
    return NextResponse.redirect(new URL("/entrar?erro=sem_codigo", url.origin));
  }

  const supabase = await supabaseSessao();

  const { error } = tokenHash
    ? await supabase.auth.verifyOtp({
        type: tipoValido(url.searchParams.get("type")),
        token_hash: tokenHash,
      })
    : await supabase.auth.exchangeCodeForSession(code!);

  if (error) {
    console.error("[auth/callback] a troca falhou", {
      formato: tokenHash ? "token_hash" : "code",
      motivo: error.message,
    });
    return NextResponse.redirect(new URL("/entrar?erro=link_expirado", url.origin));
  }

  return NextResponse.redirect(new URL(proxima, url.origin));
}
