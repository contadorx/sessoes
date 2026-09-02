import "server-only";
import { db } from "@/lib/db";
import { supabaseServer, supabaseSessao } from "@/lib/supabase/server";
import type { Post, PostLink, PostNoPainel } from "@/lib/blog";

/**
 * As leituras do blog, e elas vêm em dois sabores por um motivo de segurança.
 *
 * **A vitrine usa `supabaseServer()`** — o cliente sem sessão, que roda como
 * `anon`. Não é economia: é o que garante que a página pública mostre
 * exatamente o que a política `posts: o que esta no ar` deixa passar. Se a
 * listagem pública usasse o cliente com cookie, ela mostraria **rascunhos para
 * mim** e nada para os outros, e eu passaria meses achando que publiquei um
 * texto que ninguém vê. O bug seria invisível justamente para quem poderia
 * notá-lo.
 *
 * **O painel usa `supabaseSessao()`** e chama funções `security definer` com
 * `e_operador()` dentro — a mesma forma da 0045 e da 0050.
 */

// ============================================ a vitrine (anônima)

export type PostNaVitrine = Pick<
  Post,
  "slug" | "titulo" | "resumo" | "figura_url" | "figura_alt" | "publicado_em"
>;

/**
 * O cliente anônimo, ou `null` quando não há ambiente configurado.
 *
 * **Isto existe por causa de um defeito que só a validação em diretório limpo
 * encontrou.** A landing passou a ler `posts`, e `supabaseServer()` *lança* se
 * faltarem as variáveis. Como a página é estática, essa leitura acontece no
 * **build** — e um `npm run build` sem `.env.local` parava de compilar com
 * "faltam NEXT_PUBLIC_SUPABASE_URL e NEXT_PUBLIC_SUPABASE_ANON_KEY".
 *
 * A regra já estava escrita no `lib/supabase/server.ts`, no comentário do
 * `supabaseSessao`: *"nenhuma página autenticada pode depender de configuração
 * para compilar"*. Eu a violei do lado público, que é pior — a landing é a
 * única página que precisa subir mesmo quando tudo o mais está fora do ar.
 *
 * O sintoma seria um deploy que falha inteiro por causa de uma variável de
 * ambiente errada num ambiente novo, e a página que vende o produto é a
 * primeira a cair.
 *
 * **Regra que ficou:** leitura de banco em página estática degrada, nunca
 * estoura. Sem ambiente, o blog não existe; a landing existe.
 */
function clientePublico() {
  try {
    return supabaseServer();
  } catch (e) {
    console.error("[blog] sem ambiente do Supabase — a vitrine fica vazia", {
      motivo: e instanceof Error ? e.message : String(e),
    });
    return null;
  }
}

export async function lerVitrine(limite = 12): Promise<PostNaVitrine[]> {
  const supabase = clientePublico();
  if (!supabase) return [];

  const { data, error } = await supabase
    .from("posts")
    .select("slug, titulo, resumo, figura_url, figura_alt, publicado_em")
    .order("publicado_em", { ascending: false })
    .limit(limite);

  // A vitrine é enfeite de uma página que tem de subir de qualquer jeito. Se o
  // banco não responder, a landing aparece **sem a seção**, e não com um erro:
  // um blog fora do ar não pode derrubar a página que vende o produto.
  if (error) {
    console.error("[blog] vitrine indisponível", { motivo: error.message });
    return [];
  }
  return data ?? [];
}

export async function lerPost(
  slug: string,
): Promise<{ post: Post; links: PostLink[] } | null> {
  const supabase = clientePublico();
  if (!supabase) return null;

  const { data, error } = await supabase
    .from("posts")
    .select("id, slug, titulo, resumo, corpo, figura_url, figura_alt, publicado_em, visivel")
    .eq("slug", slug)
    .maybeSingle();

  if (error || !data) return null;

  const { data: links } = await supabase
    .from("post_links")
    .select("rotulo, url")
    .eq("post_id", data.id)
    .order("ordem");

  return { post: data as Post, links: (links ?? []) as PostLink[] };
}

/** Os endereços que existem, para o `generateStaticParams` e para o sitemap. */
export async function lerEnderecos(): Promise<string[]> {
  const supabase = clientePublico();
  if (!supabase) return [];
  const { data } = await supabase.from("posts").select("slug");
  return (data ?? []).map((p: { slug: string }) => p.slug);
}

// ============================================ o painel (operador)

export async function lerPostsDoPainel(): Promise<PostNoPainel[]> {
  const supabase = await supabaseSessao();
  return (
    (await db<PostNoPainel[]>("blog.painel", supabase.rpc("posts_do_painel"))) ?? []
  );
}

export async function lerPostDoPainel(
  id: string,
): Promise<{ post: Post; links: PostLink[] } | null> {
  const supabase = await supabaseSessao();
  const v = await db<{ post: Post; links: PostLink[] }>(
    "blog.post",
    supabase.rpc("post_do_painel", { p_id: id }),
  );
  return v ?? null;
}
