"use server";

import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";
import { db } from "@/lib/db";
import { supabaseSessao } from "@/lib/supabase/server";
import { sessaoAtual } from "@/lib/conta";
import { problemaNoPost, problemaNosLinks, linksValidos } from "@/lib/blog";

/**
 * As ações do blog.
 *
 * Mesma forma das ações do painel do negócio: **nenhuma escreve numa tabela**.
 * Todas chamam funções da 0051, e a conferência de operador aparece duas vezes
 * — aqui para a tela falhar com frase em português, e lá porque é a que vale.
 *
 * O `revalidatePath` tem uma diferença que importa: além das rotas do painel,
 * ele invalida **`/` e `/blog`**. Sem isso, publicar um texto não o faria
 * aparecer na landing até o próximo deploy — e o sintoma seria "publiquei e
 * não aconteceu nada", que é indistinguível de um botão quebrado.
 */

export type Resultado = { estado: "ok" | "erro"; mensagem: string };

const OK = (m: string): Resultado => ({ estado: "ok", mensagem: m });
const ERRO = (m: string): Resultado => ({ estado: "erro", mensagem: m });

async function exigirOperador() {
  const sessao = await sessaoAtual();
  if (!sessao.operador) throw new Error("não autorizado");
}

function texto(form: FormData, campo: string): string {
  return String(form.get(campo) ?? "").trim();
}

/** As mensagens da 0051 já foram escritas para serem lidas. Mostrar a do banco. */
function comoErro(e: unknown, generico: string): Resultado {
  const m = e instanceof Error ? e.message : "";
  if (!m || /fetch|network|timeout|JWT/i.test(m)) return ERRO(generico);
  return ERRO(m);
}

/** Invalida a vitrine junto com o painel — ver o comentário do topo. */
function revalidarTudo(id?: string) {
  revalidatePath("/negocio/blog");
  if (id) revalidatePath(`/negocio/blog/${id}`);
  revalidatePath("/blog");
  revalidatePath("/");
}

/**
 * Lê a lista de links do formulário.
 *
 * O formulário manda `link_rotulo` e `link_url` repetidos, e `getAll` devolve
 * na ordem do DOM — que é a ordem que a pessoa vê. A ordem é o que a função do
 * banco grava em `ordem`, então arrastar a lista na tela um dia vai bastar.
 */
function linksDoForm(form: FormData) {
  const rotulos = form.getAll("link_rotulo").map(String);
  const urls = form.getAll("link_url").map(String);
  return rotulos.map((rotulo, i) => ({ rotulo, url: urls[i] ?? "" }));
}

export async function salvarPost(_a: Resultado, form: FormData): Promise<Resultado> {
  const id = texto(form, "id") || null;

  const campos = {
    titulo: texto(form, "titulo"),
    slug: texto(form, "slug"),
    corpo: String(form.get("corpo") ?? ""),
    resumo: texto(form, "resumo"),
    figura_url: texto(form, "figura_url"),
    figura_alt: texto(form, "figura_alt"),
  };

  // Os campos da 0054. `formato` só é enviado para rascunho: o gatilho recusa
  // trocá-lo depois da estreia, e mandar o valor atual de um texto publicado
  // seria pedir uma recusa que a pessoa não provocou.
  const formato = texto(form, "formato") || null;
  const canonica = texto(form, "canonica");
  const indexavel = String(form.get("indexavel") ?? "") === "1";
  const larg = Number(texto(form, "figura_largura"));
  const alt = Number(texto(form, "figura_altura"));

  if (canonica !== "" && !/^https:\/\//.test(canonica)) {
    return ERRO(
      "O endereço original precisa começar com https:// — canônica relativa é ambígua para o rastreador.",
    );
  }

  // As duas conferências antes de qualquer ida ao banco: a tela recusa com a
  // frase que explica, e o banco continua sendo quem decide.
  const problema = problemaNoPost(campos) ?? problemaNosLinks(linksDoForm(form));
  if (problema) return ERRO(problema);

  let novo: string | null = null;

  try {
    await exigirOperador();
    const supabase = await supabaseSessao();

    const gravado = await db<string>("blog.salvar", supabase.rpc("salvar_post", {
      p_id: id,
      p_slug: campos.slug,
      p_titulo: campos.titulo,
      p_corpo: campos.corpo,
      p_resumo: campos.resumo || null,
      p_figura_url: campos.figura_url || null,
      p_figura_alt: campos.figura_alt || null,
      p_formato: formato,
      p_canonica: canonica || null,
      p_indexavel: indexavel,
      p_figura_largura: Number.isInteger(larg) && larg > 0 ? larg : null,
      p_figura_altura: Number.isInteger(alt) && alt > 0 ? alt : null,
    }));

    await db("blog.links", supabase.rpc("definir_links_do_post", {
      p_id: gravado,
      p_links: linksValidos(linksDoForm(form)),
    }));

    if (!id) novo = gravado;
  } catch (e) {
    return comoErro(e, "Não consegui salvar agora.");
  }

  revalidarTudo(id ?? novo ?? undefined);

  // Criar leva para a tela do texto criado. Ficar no formulário vazio depois de
  // salvar faria a próxima gravação criar um segundo texto igual.
  if (novo) redirect(`/negocio/blog/${novo}`);

  return OK("Guardado.");
}

export async function publicarPost(_a: Resultado, form: FormData): Promise<Resultado> {
  try {
    await exigirOperador();
    const supabase = await supabaseSessao();
    await db("blog.publicar", supabase.rpc("publicar_post", { p_id: texto(form, "id") }));
    revalidarTudo(texto(form, "id"));
    return OK("No ar. O endereço está valendo, e por isso ele não muda mais.");
  } catch (e) {
    return comoErro(e, "Não consegui publicar agora.");
  }
}

export async function despublicarPost(_a: Resultado, form: FormData): Promise<Resultado> {
  try {
    await exigirOperador();
    const supabase = await supabaseSessao();
    await db("blog.despublicar", supabase.rpc("despublicar_post", { p_id: texto(form, "id") }));
    revalidarTudo(texto(form, "id"));
    return OK("Fora da vitrine. O texto continua guardado, com a data em que estreou.");
  } catch (e) {
    return comoErro(e, "Não consegui tirar do ar agora.");
  }
}

export async function apagarPost(_a: Resultado, form: FormData): Promise<Resultado> {
  try {
    await exigirOperador();
    const supabase = await supabaseSessao();
    await db("blog.apagar", supabase.rpc("apagar_post", { p_id: texto(form, "id") }));
  } catch (e) {
    return comoErro(e, "Não consegui apagar agora.");
  }

  revalidarTudo();
  redirect("/negocio/blog");
}


// ============================================================ as figuras (0054)

export type ResultadoFigura =
  | { estado: "ok"; id: string }
  | { estado: "erro"; mensagem: string };

/**
 * Registra a figura que o navegador acabou de subir.
 *
 * Recebe objeto e não `FormData` de propósito: quem chama não é um `<form>`, é
 * o widget de upload depois de o arquivo já ter chegado ao balde. Um
 * `useActionState` aqui obrigaria a inventar um formulário para uma ação que
 * não tem nenhum.
 *
 * O arquivo **não passa por aqui**. Ele foi do navegador direto para o storage,
 * com a sessão de quem está logado e as políticas da 0054 no caminho. Passar
 * megabytes por um server action seria trafegar tudo duas vezes e esbarrar no
 * limite de corpo justamente na figura grande.
 */
export async function registrarFigura(f: {
  caminho: string;
  url: string;
  alt: string;
  largura: number;
  altura: number;
  bytes: number;
  tipo: string;
}): Promise<ResultadoFigura> {
  try {
    await exigirOperador();
    const supabase = await supabaseSessao();

    const id = await db<string>("blog.figura.registrar", supabase.rpc("registrar_figura", {
      p_caminho: f.caminho,
      p_url: f.url,
      p_alt: f.alt,
      p_largura: f.largura,
      p_altura: f.altura,
      p_bytes: f.bytes,
      p_tipo: f.tipo,
    }));

    revalidatePath("/negocio/blog/figuras");
    return { estado: "ok", id };
  } catch (e) {
    const r = comoErro(e, "Não consegui registrar a figura.");
    return { estado: "erro", mensagem: r.mensagem };
  }
}

/**
 * Tira a figura da biblioteca, e depois o arquivo do balde.
 *
 * **Nesta ordem, e ela é a decisão.** A função do banco recusa se a figura
 * estiver em texto que já estreou (invariante 3) e devolve o caminho; só então
 * o arquivo sai. Apagar o arquivo primeiro deixaria, no caso da recusa, uma
 * linha apontando para um arquivo que não existe mais — e a figura quebrada
 * apareceria num texto sem ninguém ter mexido nele.
 *
 * Se o arquivo não sair, a linha já saiu e sobra um órfão no balde. É o lado
 * barato de errar, e ele fica no log em vez de virar erro na tela: para quem
 * está usando, a figura saiu da biblioteca, que é o que ela pediu.
 */
export async function apagarFigura(id: string): Promise<Resultado> {
  try {
    await exigirOperador();
    const supabase = await supabaseSessao();

    const caminho = await db<string>(
      "blog.figura.apagar",
      supabase.rpc("apagar_figura", { p_id: id }),
    );

    if (caminho) {
      const { error } = await supabase.storage.from("blog").remove([caminho]);
      if (error) {
        console.error("[blog] a linha saiu e o arquivo ficou no balde", {
          caminho,
          motivo: error.message,
        });
      }
    }

    revalidatePath("/negocio/blog/figuras");
    return OK("Tirada.");
  } catch (e) {
    return comoErro(e, "Não consegui tirar a figura.");
  }
}
