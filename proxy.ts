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
 * Ainda assim, isto não é fronteira de segurança — é conveniência de navegação.
 * Quem decide de verdade é a RLS no banco, e depois dela o `sessaoAtual()` de
 * cada página.
 *
 * O arquivo se chama `proxy.ts` porque o Next 16 aposentou a convenção
 * `middleware.ts`. Mesmo papel, nome novo.
 */

const PUBLICAS = new Set([
  "/",
  "/entrar",
  "/panorama",

  // **Os três documentos, e eles estavam atrás do login.**
  //
  // Achado escrevendo a B40, e é o terceiro defeito desta mesma família — o
  // 307 mudo das rotas de máquina e o das URLs limpas do Panorama foram os
  // dois primeiros. `/termos`, `/privacidade` e `/seguranca` não têm extensão,
  // então acordam o proxy; o proxy fecha por padrão; e ninguém os tinha posto
  // nesta lista. Toda visitante sem sessão era mandada para `/entrar`.
  //
  // O custo é grande e específico. O rodapé de todas as páginas do site aponta
  // para os três, e a **própria tela de criar conta** aponta — no parágrafo que
  // existe porque o Manual do CFP de nov/2025 manda a psicóloga conferir as
  // cláusulas de eliminação do software **antes** de confiar prontuário a ele.
  // Ou seja: o único momento em que alguém decide confiar, e o link a joga numa
  // tela de login.
  "/termos",
  "/privacidade",
  "/seguranca",

  // A página do incidente (B40). É o que ela mostra ao CRP e à ANPD, e é o que
  // ela abre no dia em que o site dela precisa dizer alguma coisa.
  "/incidente",

  // O blog. A 0051 o chamou de "a primeira coisa escrita para estranhos", e
  // estranho nenhum conseguia abri-lo — nem o rastreador do buscador, que não
  // tem cookie. O `sitemap.xml` da 0054 anunciava endereços que redirecionavam
  // para `/entrar`, e `/entrar` está no `Disallow` do `robots.txt`: a build
  // inteira de SEO apontando para uma porta fechada.
  "/blog",

  // A tela de sem conexão (B47). Ela é pré-carregada no cache do aparelho pelo
  // `sw.js` e servida quando a navegação falha — e a navegação falha, por
  // definição, **sem rede**: se ela estivesse atrás do login, o proxy nem seria
  // consultado no momento em que ela é servida, mas o pré-carregamento (que
  // acontece com rede, e às vezes sem sessão ainda) receberia um 307 para
  // `/entrar` e guardaria a tela de login no lugar dela. É o mesmo 307 mudo de
  // sempre, e desta vez ele só apareceria no dia sem sinal.
  "/offline",
]);

const PREFIXOS_PUBLICOS = [
  // As páginas por link mágico. Eram duas (contrato e remarcação, B19/B21) e
  // desde o P7 são três — `/p/agora/[token]` e o documento dentro dela. O
  // prefixo cobre as três e cobre as próximas, que é o certo: a lista escrita à
  // mão é o que já deixou os três documentos legais e o blog inteiro atrás do
  // login por três dias, com um 307 que não parece erro para ninguém.
  //
  // (O nome antigo disto era "portal do paciente", o D18. Ele morreu no doc 30
  // — "vira produto paralelo" — e o que existe é a página transacional.)
  "/p/",

  // Cada texto publicado. `/blog` sozinho abre a vitrine e não os posts.
  "/blog/",

  // **A pesquisa Panorama.** Páginas estáticas em `public/panorama/`, com URL
  // limpa por rewrite no `next.config.ts`. Quem chega aqui é uma psicóloga que
  // veio de um post ou de um ofício do CRP e não tem — nem vai criar — conta
  // no produto.
  //
  // O arquivo com extensão (`/panorama/pesquisa.html`) já escapa pelo matcher.
  // A URL limpa (`/panorama/pesquisa`) não escapa, e sem esta linha ela vira
  // um 307 para `/entrar`: a pesquisa inteira divulgada, e todo mundo caindo
  // numa tela de login. É o mesmo defeito que as rotas de máquina tiveram, e
  // ele continua sendo silencioso — um 307 não parece erro para ninguém.
  //
  // Abrir aqui não expõe nada: em `public/` não há dado, e as tabelas da
  // pesquisa são insert-only pela RLS.
  "/panorama/",

  // **Rotas de máquina.** Quem bate nelas é o cron da Vercel e o provedor de
  // WhatsApp — nunca alguém com cookie de sessão. Sem esta linha, o proxy
  // mandava os dois para /entrar com um 307, e as rotas nunca respondiam:
  // o cron acusaria sucesso (307 não é erro), a fila não andaria, as mensagens
  // não sairiam, e a agenda pararia de se estender. Tudo em silêncio.
  //
  // Elas não ficam desprotegidas por isso: cada uma exige o próprio segredo e
  // devolve 404 sem ele. A tranca é delas, e é mais forte do que a daqui.
  "/api/",

  // O outro lado do link de confirmação de e-mail. Quem chega aqui **ainda não
  // tem sessão** — é justamente esta rota que cria a sessão. Barrá-la é impedir
  // a confirmação de funcionar, para sempre.
  "/auth/",
];

/**
 * Exportada para ser testável. É a regra que decide quem entra sem sessão, e
 * uma regra dessas não pode ser conferida só por leitura.
 */
export function ehPublica(caminho: string): boolean {
  return (
    PUBLICAS.has(caminho) || PREFIXOS_PUBLICOS.some((p) => caminho.startsWith(p))
  );
}

export default async function proxy(req: NextRequest) {
  let resposta = NextResponse.next({ request: req });

  const url = process.env.NEXT_PUBLIC_SUPABASE_URL;
  const chave = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY;

  // Sem configuração, o proxy sai da frente em vez de derrubar o site
  // inteiro: a landing continua no ar e a área logada falha na própria página,
  // com erro legível. Deixar passar aqui não abre porta nenhuma — quem barra de
  // verdade é o `sessaoAtual()` da página e, depois dele, a RLS.
  if (!url || !chave) {
    console.error("[proxy] faltam as variáveis do Supabase no ambiente");
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
