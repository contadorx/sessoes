/**
 * O rascunho da evolução — e por que ele é do aparelho, e temporário.
 *
 * Ela escreve a evolução **de pé, entre uma sessão e outra**, num celular que
 * descarta PWA em segundo plano. Até esta build o produto não tinha rascunho
 * em forma nenhuma: busca por `localStorage`, `sessionStorage`, `indexedDB`,
 * `beforeunload` e `autosave` no repositório inteiro dava **zero**. Sair da
 * tela perdia o texto sem aviso.
 *
 * Três decisões, e as três são sobre o que isto **não** é:
 *
 * **1. Não é cache de prontuário.** Guarda o texto de uma evolução em curso, e
 * nada mais. Não guarda nome de paciente, não guarda a agenda, não guarda o que
 * já foi salvo — a chave é o id da sessão, que sozinho não diz de quem é.
 *
 * **2. Some assim que serve.** Gravou, apagou. Um rascunho que sobrevive ao
 * salvamento é texto clínico parado no aparelho sem ninguém precisar dele.
 *
 * **3. Vence.** Rascunho que ninguém retomou em `DIAS_DE_VALIDADE` é
 * descartado na primeira leitura seguinte. Sem isso, uma evolução que ela
 * começou e abandonou em março continuaria no aparelho em setembro — e o
 * aparelho pode ser o da recepção, onde a segunda persona do produto (a
 * secretária, sem acesso clínico) também senta.
 *
 * O módulo é puro: recebe o `Storage` em vez de alcançar `window`. É o que
 * permite testá-lo, e é o que impede que ele funcione por acidente no servidor.
 */

const PREFIXO = "sessoes:rascunho:evolucao:";

/** Depois disto, o rascunho não retomado é lixo clínico — e some. */
export const DIAS_DE_VALIDADE = 7;

export type Rascunho = {
  texto: string;
  /** Milissegundos desde a época, do relógio do aparelho. */
  em: number;
};

export function chaveDoRascunho(sessaoId: string): string {
  return `${PREFIXO}${sessaoId}`;
}

/**
 * Guarda, ou apaga quando o texto ficou vazio.
 *
 * Nunca lança: `localStorage` estoura em janela anônima, com cota cheia e em
 * navegador com dados de site bloqueados. Um rascunho é conveniência — derrubar
 * a tela de evolução por causa dele inverteria a troca.
 */
export function guardarRascunho(
  storage: Storage | null | undefined,
  sessaoId: string,
  texto: string,
  agora: number = Date.now(),
): void {
  if (!storage) return;
  try {
    if (texto.trim() === "") {
      storage.removeItem(chaveDoRascunho(sessaoId));
      return;
    }
    const r: Rascunho = { texto, em: agora };
    storage.setItem(chaveDoRascunho(sessaoId), JSON.stringify(r));
  } catch {
    // Sem rascunho ela perde o texto ao sair, que é o comportamento de antes
    // desta build. Com exceção aqui, ela perderia a tela.
  }
}

/**
 * Lê o rascunho, se ele ainda vale. Vencido, apaga e devolve `null`.
 *
 * Devolve `null` também para conteúdo corrompido — se o que está lá não é o que
 * este módulo escreveu, não é rascunho.
 */
export function lerRascunho(
  storage: Storage | null | undefined,
  sessaoId: string,
  agora: number = Date.now(),
): string | null {
  if (!storage) return null;
  try {
    const cru = storage.getItem(chaveDoRascunho(sessaoId));
    if (!cru) return null;

    const r = JSON.parse(cru) as Partial<Rascunho>;
    if (typeof r?.texto !== "string" || typeof r?.em !== "number") {
      storage.removeItem(chaveDoRascunho(sessaoId));
      return null;
    }

    if (agora - r.em > DIAS_DE_VALIDADE * 24 * 60 * 60 * 1000) {
      storage.removeItem(chaveDoRascunho(sessaoId));
      return null;
    }

    return r.texto === "" ? null : r.texto;
  } catch {
    return null;
  }
}

export function apagarRascunho(
  storage: Storage | null | undefined,
  sessaoId: string,
): void {
  if (!storage) return;
  try {
    storage.removeItem(chaveDoRascunho(sessaoId));
  } catch {
    /* ver `guardarRascunho` */
  }
}

/**
 * Apaga **todos** os rascunhos. É o que a saída da conta chama.
 *
 * Sair da conta e deixar evolução pela metade no aparelho é o caminho por onde
 * a segunda persona — a secretária, que não tem acesso clínico — lê o que não
 * pode ler. Varre por prefixo em vez de por lista guardada: lista escrita à mão
 * é a que esquece a chave nova (lei 7).
 */
export function limparRascunhos(storage: Storage | null | undefined): number {
  if (!storage) return 0;
  try {
    const alvos: string[] = [];
    for (let i = 0; i < storage.length; i++) {
      const chave = storage.key(i);
      if (chave && chave.startsWith(PREFIXO)) alvos.push(chave);
    }
    for (const chave of alvos) storage.removeItem(chave);
    return alvos.length;
  } catch {
    return 0;
  }
}

/**
 * Apaga os rascunhos **vencidos**, varrendo o prefixo.
 *
 * A promessa nº 3 do cabeçalho deste arquivo — *"rascunho que ninguém retomou
 * em `DIAS_DE_VALIDADE` é descartado"* — **não estava acontecendo**, e a falha
 * tinha a forma mais desagradável possível: a expiração só era avaliada dentro
 * de `lerRascunho`, que só roda para a sessão que ela **reabre**.
 *
 * Ou seja: o rascunho abandonado, que é exatamente o caso que a promessa
 * descreve — *"uma evolução que ela começou e abandonou em março"* —, é o único
 * que nunca é lido de novo, e portanto o único cuja expiração nunca rodava. Ele
 * ficava no `localStorage` sem prazo.
 *
 * O único sweep que existia era `limparRascunhos`, e ele tinha **um** chamador:
 * o botão Sair. Quem fecha a aba, ou cuja sessão expira sozinha e volta para
 * `/entrar`, nunca passava por lá — e no computador da recepção quem senta
 * depois é a secretária, que a RLS impede de ler evolução no banco e nada
 * impedia de ler no `localStorage`.
 *
 * Roda ao entrar na área logada, varrendo por prefixo. Nunca lança: rascunho é
 * conveniência, e conveniência não derruba tela.
 */
export function expirarRascunhos(
  storage: Storage | null | undefined,
  agora: number = Date.now(),
): number {
  if (!storage) return 0;
  try {
    const vencidos: string[] = [];

    for (let i = 0; i < storage.length; i++) {
      const chave = storage.key(i);
      if (!chave || !chave.startsWith(PREFIXO)) continue;

      const cru = storage.getItem(chave);
      if (cru === null) continue;

      // Ilegível conta como vencido. Guardar um JSON que ninguém consegue ler
      // é guardar texto clínico que nem serve para retomar o trabalho.
      let vence = true;
      try {
        const r = JSON.parse(cru) as { em?: unknown };
        vence =
          typeof r?.em !== "number" ||
          agora - r.em > DIAS_DE_VALIDADE * 24 * 60 * 60 * 1000;
      } catch {
        vence = true;
      }

      if (vence) vencidos.push(chave);
    }

    for (const chave of vencidos) storage.removeItem(chave);
    return vencidos.length;
  } catch {
    return 0;
  }
}
