import { NextResponse, type NextRequest } from "next/server";
import { createServerClient } from "@supabase/ssr";

/**
 * Duas funções, nesta ordem:
 *   1. renovar a sessão a cada requisição (senão o token expira e a pessoa cai);
 *   2. barrar o que é da área logada.
 *
 * **Fecha por padrão.** A lista abaixo é a das rotas públicas; qualquer rota
 * nova nasce protegida. O inverso (listar o que proteger) esquece uma rota
 * cedo ou tarde, e o esquecimento é silencioso.
 *
 * Ainda assim, middleware não é fronteira de segurança — é conveniência de
 * navegação. Quem decide de verdade é a RLS no banco, e depois dela o
 * `sessaoAtual()` de cada página.
 */

const PUBLICAS = new Set(["/", "/entrar"]);
const PREFIXOS_PUBLICOS = ["/p/"]; // portal do paciente por link mágico (D18)

function ehPublica(caminho: string): boolean {
  return (
    PUBLICAS.has(caminho) || PREFIXOS_PUBLICOS.some((p) => caminho.startsWith(p))
  );
}

export async function middleware(req: NextRequest) {
  let resposta = NextResponse.next({ request: req });

  const url = process.env.NEXT_PUBLIC_SUPABASE_URL;
  const chave = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY;

  // Sem configuração, o middleware sai da frente em vez de derrubar o site
  // inteiro: a landing continua no ar e a área logada falha na própria página,
  // com erro legível. Deixar passar aqui não abre porta nenhuma — quem barra de
  // verdade é o `sessaoAtual()` da página e, depois dele, a RLS.
  if (!url || !chave) {
    console.error("[middleware] faltam as variáveis do Supabase no ambiente");
    return resposta;
  }

  const supabase = createServerClient(
    url,
    chave,
    {
      cookies: {
        getAll: () => req.cookies.getAll(),
        setAll: (novos) => {
          novos.forEach(({ name, value }) => req.cookies.set(name, value));
          resposta = NextResponse.next({ request: req });
          novos.forEach(({ name, value, options }) =>
            resposta.cookies.set(name, value, options),
          );
        },
      },
    },
  );

  // getUser() valida o token no servidor. Não trocar por getSession(), que só lê
  // o cookie e acredita nele.
  const {
    data: { user },
  } = await supabase.auth.getUser();

  const caminho = req.nextUrl.pathname;

  if (!user && !ehPublica(caminho)) {
    const url = req.nextUrl.clone();
    url.pathname = "/entrar";
    url.search = "";
    url.searchParams.set("proxima", caminho);
    return NextResponse.redirect(url);
  }

  if (user && caminho === "/entrar") {
    const url = req.nextUrl.clone();
    url.pathname = "/agenda";
    url.search = "";
    return NextResponse.redirect(url);
  }

  return resposta;
}

export const config = {
  matcher: [
    // Tudo, menos os estáticos do Next e arquivos com extensão.
    "/((?!_next/static|_next/image|favicon.ico|.*\\.[\\w]+$).*)",
  ],
};
