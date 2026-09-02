/**
 * O blog — do lado do app.
 *
 * Tudo o que mora aqui **espelha uma regra que já está no banco** (migração
 * 0051), e nenhuma delas depende deste arquivo para valer. O motivo de existir
 * mesmo assim é o de sempre neste projeto: a tela precisa recusar antes de
 * enviar, com frase em português, e precisa **não oferecer** o botão que a
 * função vai negar.
 *
 * A regra de leitura é a inversa da do resto do sistema. Em toda outra tela, a
 * pergunta é "isto é da minha conta?". Aqui é **"eu escolhi publicar isto?"** —
 * e o padrão é não. Um texto nasce rascunho e continua rascunho até alguém
 * decidir o contrário.
 *
 * O QUE NÃO ESTÁ AQUI, E É DELIBERADO
 *
 * Não existe função que transforme o corpo em HTML. `paragrafos()` devolve
 * **texto**, e a tela renderiza texto — a linha entre as duas coisas é a linha
 * entre um blog e um `<script>` de outra pessoa na página inicial do produto.
 * Há teste de estrutura que reprova `dangerouslySetInnerHTML` no repositório
 * inteiro, e ele existe porque essa tentação chega num dia em que eu vou querer
 * negrito.
 */

export type PostLink = { rotulo: string; url: string };

export type Post = {
  id: string;
  slug: string;
  titulo: string;
  resumo: string | null;
  corpo: string;
  figura_url: string | null;
  figura_alt: string | null;
  publicado_em: string | null;
  visivel: boolean;
  atualizado_em?: string;
};

export type PostNoPainel = Omit<Post, "corpo" | "figura_alt"> & { links: number };

// ============================================ o endereço

/**
 * O endereço a partir do título — sugestão, nunca imposição.
 *
 * Ele é sugerido no formulário e continua editável **enquanto é rascunho**,
 * porque depois de publicado o banco congela (invariante 2 da 0051): o
 * endereço está em links que outras pessoas guardaram.
 *
 * Acento vira letra sem acento em vez de sumir: "sessão" precisa virar
 * `sessao`, e não `sesso`.
 */
export function slugDe(titulo: string): string {
  return titulo
    .normalize("NFD")
    .replace(/[\u0300-\u036f]/g, "")
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, "-")
    .replace(/^-+|-+$/g, "")
    .slice(0, 80)
    .replace(/-+$/g, "");
}

/** O mesmo `check` da coluna `posts.slug`, para a tela recusar antes de enviar. */
export function slugValido(s: string): boolean {
  return /^[a-z0-9]+(-[a-z0-9]+)*$/.test(s) && s.length >= 3 && s.length <= 80;
}

/**
 * O mesmo `check` das colunas de URL — e ele não é formalidade.
 *
 * `javascript:` num link, ou `data:` numa figura, é XSS armazenado numa página
 * que estranhos abrem. Hoje só eu escrevo aqui, e a defesa continua valendo:
 * ela não é contra um invasor, é contra eu colar num dia cansado uma URL que
 * veio de outro lugar.
 *
 * Figura é mais estreita que link de propósito: `http://` simples numa página
 * servida por https vira conteúdo misto e o navegador bloqueia — a imagem
 * some, e o defeito aparece só em produção.
 */
export function urlDeLinkSegura(u: string): boolean {
  return /^(\/|https:\/\/|http:\/\/)/.test(u.trim());
}

export function urlDeFiguraSegura(u: string): boolean {
  return /^(\/|https:\/\/)/.test(u.trim());
}

// ============================================ o estado de um texto

export type EstadoDoPost = "rascunho" | "no_ar" | "fora_do_ar";

/**
 * Três estados, e não dois — é a invariante 1 da 0051 aparecendo na tela.
 *
 * "Rascunho" (nunca estreou) e "fora do ar" (estreou e foi tirado) parecem a
 * mesma coisa para quem olha a vitrine, e são coisas diferentes para quem
 * administra: o primeiro ainda pode ganhar outro endereço e pode ser apagado;
 * o segundo, nenhum dos dois.
 */
export function estadoDoPost(p: { publicado_em: string | null; visivel: boolean }): EstadoDoPost {
  if (p.publicado_em === null) return "rascunho";
  return p.visivel ? "no_ar" : "fora_do_ar";
}

export function rotuloDoEstado(e: EstadoDoPost): string {
  return e === "no_ar" ? "no ar" : e === "rascunho" ? "rascunho" : "fora do ar";
}

/**
 * O que cada estado significa em consequência, não em definição.
 *
 * A pergunta que se faz na tela não é "o que é fora do ar"; é "o que acontece
 * com quem tem o link".
 */
export function explicaEstado(e: EstadoDoPost): string {
  if (e === "rascunho") {
    return "Só você vê. O endereço ainda pode mudar, e este texto ainda pode ser apagado.";
  }
  if (e === "no_ar") {
    return "Qualquer pessoa lê, e o endereço está valendo.";
  }
  return "Fora da vitrine, e o endereço não responde mais. O texto continua guardado, com a data em que estreou.";
}

/** Invariante 3: o que já esteve no ar não se apaga pelo app. */
export function podeApagar(p: { publicado_em: string | null }): boolean {
  return p.publicado_em === null;
}

/** Invariante 2: o endereço de um texto publicado é congelado. */
export function podeTrocarEndereco(p: { publicado_em: string | null }): boolean {
  return p.publicado_em === null;
}

/**
 * A frase que a tela mostra no lugar do botão de apagar.
 *
 * Ela manda para o caminho certo em vez de só negar — é a mesma forma das
 * mensagens da 0050.
 */
export function porQueNaoApaga(): string {
  return "Este texto já esteve no ar e não se apaga: alguém pode tê-lo lido ou citado. Tire do ar — o endereço para de responder e a linha fica.";
}

// ============================================ o corpo

/**
 * O corpo em parágrafos — texto, e só texto.
 *
 * Linha em branco separa parágrafo. É a única formatação que existe, e é
 * deliberado: qualquer coisa a mais (negrito, título, lista) pede um
 * interpretador, e todo interpretador de marcação termina em alguém pedindo
 * "só um `<iframe>`".
 */
export function paragrafos(corpo: string): string[] {
  return corpo
    .replace(/\r\n/g, "\n")
    .split(/\n\s*\n/)
    .map((p) => p.trim())
    .filter((p) => p.length > 0);
}

/**
 * O tempo de leitura, em minutos, por 200 palavras.
 *
 * Serve para a vitrine dizer o tamanho antes de a pessoa abrir. É estimativa e
 * a tela diz "min de leitura" — nunca "você vai levar".
 */
export function minutosDeLeitura(corpo: string): number {
  const palavras = corpo.trim().split(/\s+/).filter(Boolean).length;
  return Math.max(1, Math.round(palavras / 200));
}

// ============================================ os links

/**
 * A mesma filtragem de `definir_links_do_post`: linha pela metade é ignorada.
 *
 * O formulário manda a lista inteira, inclusive as linhas em branco que a
 * pessoa não preencheu. Gravá-las em branco encheria a tabela de lixo; recusar
 * a lista inteira por causa de uma linha vazia faria o formulário brigar com
 * quem o usa.
 */
export function linksValidos(lista: { rotulo: string; url: string }[]): PostLink[] {
  return lista
    .map((l) => ({ rotulo: l.rotulo.trim(), url: l.url.trim() }))
    .filter((l) => l.rotulo !== "" && l.url !== "");
}

/** O primeiro problema de uma lista de links, ou null. Para a tela recusar antes. */
export function problemaNosLinks(lista: { rotulo: string; url: string }[]): string | null {
  for (const l of linksValidos(lista)) {
    if (!urlDeLinkSegura(l.url)) {
      return `O endereço de "${l.rotulo}" precisa começar com https:// ou com / — outros formatos viram código executado na página.`;
    }
    if (l.rotulo.length < 2 || l.rotulo.length > 120) {
      return "O rótulo de um link tem entre 2 e 120 caracteres.";
    }
  }
  return null;
}

// ============================================ o que a tela recusa antes de enviar

/**
 * A conferência do formulário, na ordem em que a pessoa consegue resolver.
 *
 * A ordem importa, e é a lição da 0037b: uma recusa fora de ordem manda
 * procurar o que não falta. Título antes de corpo, corpo antes de figura —
 * porque quem esqueceu o título ainda não escreveu nada.
 */
export function problemaNoPost(p: {
  titulo: string;
  slug: string;
  corpo: string;
  figura_url: string;
  figura_alt: string;
  resumo: string;
}): string | null {
  const titulo = p.titulo.trim();
  if (titulo.length < 3 || titulo.length > 160) return "O título tem entre 3 e 160 caracteres.";

  if (!slugValido(p.slug.trim())) {
    return "O endereço só aceita letras minúsculas, números e hífen — é o que vai depois de /blog/ na barra do navegador.";
  }

  if (p.corpo.trim().length < 20) return "O texto está curto demais para ir ao ar.";

  const resumo = p.resumo.trim();
  if (resumo !== "" && (resumo.length < 3 || resumo.length > 400)) {
    return "O resumo tem entre 3 e 400 caracteres — é a frase que aparece na vitrine.";
  }

  const fig = p.figura_url.trim();
  const alt = p.figura_alt.trim();
  if (fig !== "") {
    if (!urlDeFiguraSegura(fig)) {
      return "A figura precisa ser um arquivo do próprio site (/blog/…) ou um endereço https://.";
    }
    if (alt.length < 3) {
      return "Descreva a figura em poucas palavras. Sem isso, quem usa leitor de tela recebe silêncio no lugar dela.";
    }
  }

  return null;
}

// ============================================ datas

/** 03/09/2026 — a mesma forma do resto do produto. */
export function dataCurta(iso: string | null): string {
  if (!iso) return "—";
  return iso.slice(0, 10).split("-").reverse().join("/");
}

const MESES = [
  "janeiro", "fevereiro", "março", "abril", "maio", "junho",
  "julho", "agosto", "setembro", "outubro", "novembro", "dezembro",
];

/** "3 de setembro de 2026" — para a assinatura do texto publicado. */
export function dataPorExtenso(iso: string | null): string {
  if (!iso) return "";
  const [a, m, d] = iso.slice(0, 10).split("-").map(Number);
  if (!a || !m || !d) return "";
  return `${d} de ${MESES[m - 1]} de ${a}`;
}
