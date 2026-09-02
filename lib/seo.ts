import { blocos, textoPuro, palavras, figurasDoCorpo, subtitulos, links, lerCorpo, primeiroParagrafo } from "@/lib/marcacao";
import { slugValido } from "@/lib/blog";

/**
 * A conferência de SEO — e o que ela recusa fazer.
 *
 * Este arquivo foi escrito lendo a documentação do Google, não os artigos que
 * falam sobre ela. A diferença apareceu em quatro pontos, e nos quatro o que
 * "todo mundo sabe" está errado:
 *
 *   1. **Não existe limite de caracteres para a descrição.** A documentação diz,
 *      com essas palavras, que não há limite e que o trecho é cortado "conforme
 *      necessário, tipicamente para caber na largura do aparelho". Os 155
 *      caracteres são folclore. O que este arquivo faz é dizer **onde costuma
 *      cortar num celular** — que é informação — em vez de reprovar em 156.
 *
 *   2. **Não existe número mínimo de palavras.** A documentação diz que não há
 *      contagem mágica. Um editor que exige 300 palavras ensina a encher
 *      linguiça, e texto com enchimento é pior para as duas pontas.
 *
 *   3. **A ordem dos títulos não afeta posição.** Pular do `##` para o `####`
 *      é problema de leitor de tela — que é motivo suficiente e é o motivo que
 *      a frase dá. Não é penalidade de busca, e dizer que é seria mentir.
 *
 *   4. **A meta keywords não é usada pela Busca.** Por isso não há campo de
 *      palavra-chave neste produto, e a 0054 tem uma verificação que reprova o
 *      dia em que alguém acrescentar um.
 *
 * E o que ele recusa: **nota**. Não há pontuação de 0 a 100, nem semáforo com
 * cor calculada a partir de peso inventado. Cada item é um fato verificável com
 * a consequência escrita ao lado, e a pessoa decide. É a mesma regra do
 * `piso_multa` da B24: o produto conta, e não adjetiva.
 */

// ================================================== o que costuma caber na tela

/**
 * Onde o Google costuma cortar num celular. **Não é limite** — é observação.
 *
 * A tela usa este número para dizer "daqui para a frente costuma sumir num
 * celular", e nunca para reprovar. Um texto com resumo de 300 caracteres não
 * está errado; ele só tem 140 caracteres que a maioria não vai ler no resultado
 * da busca.
 */
export const CORTE_TITULO = 60;
export const CORTE_DESCRICAO = 160;

export function ondeCorta(s: string, corte: number): { cabe: string; sobra: string } {
  const t = s.trim();
  if (t.length <= corte) return { cabe: t, sobra: "" };
  return { cabe: t.slice(0, corte), sobra: t.slice(corte) };
}

// ============================================================ a conferência

export type Estado = "ok" | "atencao" | "falta";

export type Item = {
  id: string;
  titulo: string;
  estado: Estado;
  frase: string;
};

export type PostParaConferir = {
  titulo: string;
  slug: string;
  resumo: string;
  corpo: string;
  formato: string;
  figura_url: string;
  figura_alt: string;
  figura_largura: number | null;
  figura_altura: number | null;
  canonica: string;
  indexavel: boolean;
};

/** Rótulos que não descrevem para onde o link vai. */
const ROTULOS_VAZIOS = [
  "clique aqui", "clique", "aqui", "saiba mais", "leia mais", "veja",
  "link", "este link", "neste link", "acesse", "mais",
];

/**
 * A lista de fatos, na ordem em que resolvê-los faz diferença.
 *
 * A ordem é a lição da 0037b outra vez: quem ainda não tem título não precisa
 * ouvir sobre alternativa de figura.
 */
export function conferencia(p: PostParaConferir): Item[] {
  const itens: Item[] = [];
  const arvore = lerCorpo(p.corpo, p.formato);
  const titulo = p.titulo.trim();
  const resumo = p.resumo.trim();

  // ---------------------------------------------------------------- o título
  if (titulo === "") {
    itens.push({
      id: "titulo",
      titulo: "O título",
      estado: "falta",
      frase: "Sem título não há o que mostrar no resultado da busca nem na aba do navegador.",
    });
  } else {
    const { sobra } = ondeCorta(titulo, CORTE_TITULO);
    itens.push({
      id: "titulo",
      titulo: "O título",
      estado: sobra === "" ? "ok" : "atencao",
      frase:
        sobra === ""
          ? `${titulo.length} caracteres. Cabe inteiro no resultado da busca.`
          : `${titulo.length} caracteres. O Google não tem limite — ele corta pela largura da tela, e num celular costuma sumir a partir de “${sobra.trim().slice(0, 24)}…”. Ponha o que importa no começo.`,
    });
  }

  // --------------------------------------------------------------- o endereço
  const slug = p.slug.trim();
  if (!slugValido(slug)) {
    itens.push({
      id: "endereco",
      titulo: "O endereço",
      estado: "falta",
      frase: "Só letras minúsculas, números e hífen — é o que vai depois de /blog/.",
    });
  } else {
    const soNumeros = /^[\d-]+$/.test(slug);
    const comPalavras = slug.split("-").filter((w) => w.length >= 3).length >= 2;
    itens.push({
      id: "endereco",
      titulo: "O endereço",
      estado: soNumeros ? "atencao" : comPalavras ? "ok" : "atencao",
      frase: soNumeros
        ? "O endereço é só número. A documentação do Google pede caminhos com palavras que digam do que a página trata."
        : comPalavras
          ? `/blog/${slug} — palavras, e não identificador.`
          : "O endereço está curto para dizer do que o texto trata. Vale enquanto é rascunho: depois de publicar ele congela.",
    });
  }

  // ---------------------------------------------------------------- o resumo
  if (resumo === "") {
    itens.push({
      id: "resumo",
      titulo: "O resumo",
      estado: "falta",
      frase:
        "Sem resumo, o Google monta o trecho com um pedaço qualquer do texto — e a vitrine do blog fica sem a frase que convida a abrir.",
    });
  } else {
    const { sobra } = ondeCorta(resumo, CORTE_DESCRICAO);
    itens.push({
      id: "resumo",
      titulo: "O resumo",
      estado: "ok",
      frase:
        sobra === ""
          ? `${resumo.length} caracteres, e a frase inteira aparece.`
          : `${resumo.length} caracteres. Não há limite, mas num celular costuma caber até uns ${CORTE_DESCRICAO} — escreva a coisa toda antes disso e o resto vira complemento.`,
    });
  }

  // ------------------------------------------------------------------ o texto
  const n = palavras(p.corpo);
  itens.push({
    id: "tamanho",
    titulo: "O tamanho",
    estado: n === 0 ? "falta" : "ok",
    frase:
      n === 0
        ? "Ainda não há texto."
        : `${n} palavras, uns ${Math.max(1, Math.round(n / 200))} min de leitura. Não existe número mínimo — a documentação do Google diz que não há contagem mágica de palavras.`,
  });

  // -------------------------------------------------------------- subtítulos
  const subs = subtitulos(arvore);
  if (n > 400 && subs.length === 0) {
    itens.push({
      id: "subtitulos",
      titulo: "Os subtítulos",
      estado: "atencao",
      frase:
        "Texto longo sem nenhum subtítulo. Não é penalidade de busca — a ordem dos títulos não muda posição —, é que quem lê no celular precisa de onde parar.",
    });
  } else {
    itens.push({
      id: "subtitulos",
      titulo: "Os subtítulos",
      estado: "ok",
      frase:
        subs.length === 0
          ? "Nenhum, e o texto é curto o bastante para dispensar."
          : `${subs.length} subtítulo${subs.length > 1 ? "s" : ""}, cada um com endereço próprio para citar direto.`,
    });
  }

  // ----------------------------------------------------------------- a capa
  const fig = p.figura_url.trim();
  if (fig === "") {
    itens.push({
      id: "capa",
      titulo: "A figura de capa",
      estado: "atencao",
      frase:
        "Sem capa, o texto compartilhado no WhatsApp e nas redes aparece só como uma linha de link.",
    });
  } else if (p.figura_alt.trim().length < 3) {
    itens.push({
      id: "capa",
      titulo: "A figura de capa",
      estado: "falta",
      frase: "A capa está sem alternativa. Quem usa leitor de tela recebe silêncio no lugar dela.",
    });
  } else if (p.figura_largura === null || p.figura_altura === null) {
    itens.push({
      id: "capa",
      titulo: "A figura de capa",
      estado: "atencao",
      frase:
        "A capa está sem largura e altura. Sem elas o navegador não reserva o espaço, e o texto pula quando a imagem carrega.",
    });
  } else {
    itens.push({
      id: "capa",
      titulo: "A figura de capa",
      estado: "ok",
      frase: `${p.figura_largura}×${p.figura_altura}, com alternativa. O espaço fica reservado antes de a imagem chegar.`,
    });
  }

  // ------------------------------------------------------- figuras do corpo
  const doCorpo = figurasDoCorpo(arvore);
  const semAlt = doCorpo.filter((f) => f.alt.trim().length < 3).length;
  if (doCorpo.length > 0) {
    itens.push({
      id: "figuras",
      titulo: "As figuras do texto",
      estado: semAlt > 0 ? "falta" : "ok",
      frase:
        semAlt > 0
          ? `${semAlt} de ${doCorpo.length} está sem alternativa. É o que o leitor de tela lê no lugar da imagem — e é o que o Google usa para saber do que ela trata.`
          : `${doCorpo.length} figura${doCorpo.length > 1 ? "s" : ""}, todas com alternativa.`,
    });
  }

  // ------------------------------------------------------------- os links
  const ls = links(arvore);
  const vagos = ls.filter((l) => ROTULOS_VAZIOS.includes(l.rotulo.trim().toLowerCase()));
  if (ls.length === 0) {
    itens.push({
      id: "links",
      titulo: "Os links",
      estado: "atencao",
      frase:
        "Nenhum link no texto. Um para outra página do site ajuda quem lê a seguir o assunto — e é assim que o rastreador acha o resto.",
    });
  } else {
    itens.push({
      id: "links",
      titulo: "Os links",
      estado: vagos.length > 0 ? "atencao" : "ok",
      frase:
        vagos.length > 0
          ? `${vagos.length} link com rótulo que não diz para onde vai (“${vagos[0].rotulo}”). Quem navega por leitor de tela ouve a lista de links fora do texto.`
          : `${ls.length} link${ls.length > 1 ? "s" : ""}, todos com rótulo que descreve o destino.`,
    });
  }

  // ------------------------------------------------------------- a canônica
  if (p.canonica.trim() !== "") {
    itens.push({
      id: "canonica",
      titulo: "O original",
      estado: "ok",
      frase:
        "Este texto declara que o original está em outro endereço. Ele não entra no sitemap, e é isso mesmo — o sitemap indica originais.",
    });
  }

  // ------------------------------------------------------------- indexação
  if (!p.indexavel) {
    itens.push({
      id: "indexavel",
      titulo: "A indexação",
      estado: "atencao",
      frase:
        "Este texto pede aos buscadores para não indexá-lo. Ele continua público para quem tem o link — não indexar não é esconder.",
    });
  }

  return itens;
}

export function quantosFaltam(itens: Item[]): number {
  return itens.filter((i) => i.estado === "falta").length;
}

// ================================================== o que vai para a página

export type MetaDoPost = {
  titulo: string;
  descricao: string;
  canonica: string;
  indexavel: boolean;
  figura: string | null;
  figuraAlt: string | null;
};

/**
 * O que a `generateMetadata` precisa saber.
 *
 * Quando não há resumo, a descrição vem do primeiro pedaço do texto **sem
 * marcação** — nunca do corpo cru, senão os asteriscos vão para o resultado da
 * busca. E nunca é o título repetido: descrição igual ao título não acrescenta
 * nada a quem lê o resultado.
 */
export function metaDoPost(
  p: {
    titulo: string;
    slug: string;
    resumo: string | null;
    corpo: string;
    formato: string;
    figura_url: string | null;
    figura_alt: string | null;
    canonica: string | null;
    indexavel: boolean;
  },
  base: string,
): MetaDoPost {
  const limpo = textoPuro(lerCorpo(p.corpo, p.formato)).replace(/\s+/g, " ").trim();
  const doTexto = limpo.length > 300 ? `${limpo.slice(0, 297).trimEnd()}…` : limpo;

  return {
    titulo: p.titulo.trim(),
    descricao: (p.resumo ?? "").trim() || doTexto,
    canonica: (p.canonica ?? "").trim() || `${base}/blog/${p.slug}`,
    indexavel: p.indexavel,
    figura: (p.figura_url ?? "").trim() || null,
    figuraAlt: (p.figura_alt ?? "").trim() || null,
  };
}

// ================================================== os dados estruturados

/**
 * O JSON-LD do texto.
 *
 * A documentação do Google diz que **nenhuma propriedade de Article é
 * obrigatória** — a orientação é declarar o que de fato se aplica. Então aqui
 * não há campo preenchido com placeholder para "completar o schema": o que não
 * existe fica de fora, e uma propriedade inventada seria pior que a ausência
 * dela, porque dados estruturados que não batem com a página são violação
 * declarada de política.
 */
export function jsonLdDoPost(p: {
  titulo: string;
  slug: string;
  descricao: string;
  publicado_em: string | null;
  atualizado_em: string | null;
  figura: string | null;
  autor: string;
  site: string;
  base: string;
}): Record<string, unknown> {
  const o: Record<string, unknown> = {
    "@context": "https://schema.org",
    "@type": "BlogPosting",
    headline: p.titulo,
    description: p.descricao,
    mainEntityOfPage: { "@type": "WebPage", "@id": `${p.base}/blog/${p.slug}` },
    author: { "@type": "Person", name: p.autor },
    publisher: { "@type": "Organization", name: p.site, url: p.base },
    inLanguage: "pt-BR",
  };

  if (p.publicado_em) o.datePublished = p.publicado_em;
  if (p.atualizado_em) o.dateModified = p.atualizado_em;
  if (p.figura) o.image = [p.figura.startsWith("http") ? p.figura : `${p.base}${p.figura}`];

  return o;
}

/**
 * O JSON-LD virando texto seguro para dentro de um `<script>`.
 *
 * O `<` escapado é a defesa inteira. Sem ela, um título que contivesse
 * `</script>` fecharia a tag no meio do JSON e o que viesse depois seria lido
 * como marcação da página — que é exatamente a porta que a 0051 fechou.
 *
 * E é por isso que este projeto emite JSON-LD como **filho de texto** do
 * `<script>`, e não por `dangerouslySetInnerHTML`: o React trata filho de texto
 * como texto, e a defesa acima é cinto além do suspensório.
 */
export function jsonLdSeguro(o: Record<string, unknown>): string {
  return JSON.stringify(o)
    .replace(/</g, "\\u003c")
    .replace(/>/g, "\\u003e")
    .replace(/\u2028/g, "\\u2028")
    .replace(/\u2029/g, "\\u2029");
}

/** Quantos blocos o texto tem — a prévia usa para dizer se o corpo mudou de forma. */
export function contaBlocos(corpo: string): number {
  return blocos(corpo).length;
}

/**
 * A frase da vitrine — a mesma nas duas listagens.
 *
 * Sem resumo, cai no primeiro parágrafo **sem marcação**, e nunca no corpo cru:
 * colar o corpo mandaria asterisco e cerquilha para a listagem, que é o defeito
 * clássico de vitrine de blog com editor de marcação.
 *
 * Mora aqui, e não em `lib/blog.ts`, porque precisa do interpretador — e
 * `lib/marcacao.ts` já importa de `lib/blog.ts`. Duas listagens com dois
 * recortes diferentes é o começo de a landing e o /blog mostrarem frases
 * distintas para o mesmo texto.
 */
export function chamadaDaVitrine(
  p: { resumo: string | null; corpo: string; formato: string },
  limite = 180,
): string {
  if (p.resumo) return p.resumo;
  const t = primeiroParagrafo(lerCorpo(p.corpo, p.formato));
  return t.length > limite ? `${t.slice(0, limite - 3).trimEnd()}…` : t;
}
