/**
 * A entrega se confere — o lado puro.
 *
 * A TESE, QUE VEM DE FORA E VALE PARA OS TRÊS CANAIS
 *
 * O provedor responde `success` quando a mensagem entra **na fila dele**, não
 * quando o destino recebe. Entre "aceita" e "chegou" existe um vão, e é dentro
 * dele que mora a pior classe de defeito de um produto assim: a falha
 * silenciosa. Não quebra nada, não aparece em log de erro, e o prejuízo é uma
 * pasta do contador que ela jurou ter mandado.
 *
 * Este arquivo é onde a decisão mora — a leitura do banco e a escrita ficam
 * fora. É de propósito: as três regras abaixo são as que precisam ser provadas
 * sem depender de banco nenhum, porque errar qualquer uma delas faz o remédio
 * matar o paciente.
 *
 * AS TRÊS REGRAS, EM UMA FRASE CADA
 *
 * 1 · **Sem instrumento não há conclusão.** Nenhuma confirmação na janela, com
 *     saídas maiores que zero, não é prova de perda: é prova de que ninguém
 *     está medindo.
 * 2 · **O disjuntor abre por taxa e fecha por evidência.** Nunca pelo relógio.
 * 3 · **O que o tempo autoriza é sondar**, que é outra coisa.
 */

/** A janela entre aceitar e confirmar. Passou disso sem notícia, é candidata a perdida. */
export const JANELA_CONFIRMACAO_MIN = 20;

/** Reenviar em laço transforma problema de entrega em problema de reputação. */
export const TENTATIVAS_MAX = 2;

/** Três mensagens não fazem uma taxa. Abaixo disso o disjuntor não se mexe. */
export const AMOSTRA_MINIMA = 5;

/** Perda acima disso na janela recente abre o disjuntor. */
export const LIMITE_PERDA = 0.4;

/** Depois disso vale arriscar uma mensagem pelo caminho suspeito, para haver amostra. */
export const HORAS_ATE_SONDAR = 6;

/** Três ciclos de um cron de 15 minutos. Passou, o cron é suspeito. */
export const MINUTOS_ATE_SUSPEITAR_DO_CRON = 45;

export type Amostra = {
  /** Quantas saíram na janela — distingue silêncio de vazio. */
  total: number;
  /** Quantas o provedor confirmou. */
  confirmadas: number;
  /** Quantas saíram e não confirmaram. */
  semConfirmacao: number;
};

export type Disjuntor = {
  estado: "fechado" | "aberto";
  motivo: string;
  desde: string | null;
};

/**
 * O instrumento está funcionando?
 *
 * **A regra mais importante do arquivo, e a que quase passou batida no produto
 * de origem.** Toda a garantia depende de o webhook confirmar entrega. Se ele
 * não estiver ligado — segredo ausente, URL não cadastrada, endpoint mudado —
 * nenhuma confirmação chega, e aí a leitura do sistema fica assim, toda
 * plausível e toda errada:
 *
 *   1. nenhuma mensagem confirma → todas viram perdidas na janela;
 *   2. a varredura reenvia a base inteira pelo caminho de queda, a cada passada;
 *   3. a taxa de perda dá 100% → o disjuntor abre e desliga o canal **que
 *      estava funcionando**.
 *
 * Um webhook desconfigurado derrubaria o servidor bom, duplicaria todo e-mail e
 * queimaria a cota do segundo provedor — sem uma linha de erro em lugar nenhum.
 *
 * Base vazia é caso legítimo e **diferente**: não há o que concluir e também não
 * há o que reenviar. Confiável por vacuidade.
 *
 * A trava impede o sistema de fazer besteira. Ela **não devolve a proteção**:
 * enquanto o webhook estiver mudo, mensagem pode se perder sem ninguém saber. É
 * por isso que o estado cego precisa doer na tela de operação, e não virar uma
 * linha no retorno do cron.
 */
export function instrumentoConfiavel(a: Pick<Amostra, "total" | "confirmadas">): boolean {
  if (a.total === 0) return true;
  return a.confirmadas > 0;
}

/**
 * O disjuntor, e por que ele nunca fecha sozinho no relógio.
 *
 * Fechar por tempo devolve todo o tráfego a um caminho quebrado e refaz o
 * estrago em silêncio. Fechar exige **prova do contrário**: uma amostra recente
 * sem perda nenhuma.
 *
 * Abaixo da amostra mínima ele não se mexe em direção nenhuma — nem abre nem
 * fecha. Duas mensagens perdidas de duas não são 100% de perda, são duas
 * mensagens.
 */
export function avaliarDisjuntor(atual: Disjuntor, a: Amostra, agoraISO: string): Disjuntor {
  if (a.total < AMOSTRA_MINIMA) return atual;

  const taxa = a.semConfirmacao / a.total;

  if (atual.estado === "fechado" && taxa >= LIMITE_PERDA) {
    return {
      estado: "aberto",
      motivo: `${a.semConfirmacao} de ${a.total} mensagens não confirmaram entrega (${Math.round(taxa * 100)}%)`,
      desde: agoraISO,
    };
  }

  if (atual.estado === "aberto" && a.semConfirmacao === 0) {
    return {
      estado: "fechado",
      motivo: `${a.total} mensagens seguidas confirmaram entrega`,
      desde: agoraISO,
    };
  }

  return atual;
}

/**
 * O que a passagem do tempo autoriza: **sondar**, nunca fechar.
 *
 * Sem tráfego pelo caminho suspeito nunca haverá amostra provando que ele
 * voltou — e o disjuntor ficaria aberto para sempre, com o custo do caminho de
 * queda, por falta de evidência que ninguém foi buscar.
 */
export function deveSondar(d: Disjuntor, agora: Date, horas = HORAS_ATE_SONDAR): boolean {
  if (d.estado !== "aberto" || !d.desde) return false;
  const desde = new Date(d.desde);
  if (Number.isNaN(desde.getTime())) return false;
  return (agora.getTime() - desde.getTime()) / 3_600_000 >= horas;
}

/**
 * O quarto silêncio: o cron parar.
 *
 * Se ele morrer, nada muda em lugar nenhum — não há erro, não há estado novo, a
 * ausência é o próprio sintoma. Só a data da última passada denuncia, e ela é
 * gravada **inclusive quando a varredura se declara cega**, que é justamente
 * quando alguém precisa saber.
 */
export function cronSuspeito(
  ultima: string | null,
  agora: Date,
  minutos = MINUTOS_ATE_SUSPEITAR_DO_CRON,
): boolean {
  if (!ultima) return true;
  const em = new Date(ultima);
  if (Number.isNaN(em.getTime())) return true;
  return (agora.getTime() - em.getTime()) / 60_000 > minutos;
}

/** Reenviar de novo, ou desistir? Desistir é visível e não manda mais nada. */
export function podeReenviar(tentativas: number): boolean {
  return tentativas < TENTATIVAS_MAX;
}

// ======================================== o que o provedor diz, no nosso nome

/**
 * A tradução do evento do provedor.
 *
 * Dois provedores, duas nomenclaturas, e nenhuma delas é a nossa. O que entra
 * aqui é texto de fora; o que sai são as **três** decisões que o banco conhece.
 *
 * O desconhecido vira `ignorado` de propósito — e o webhook responde 200 para
 * ele. Devolver erro faria o provedor reentregar o mesmo evento para sempre,
 * que é como uma integração vira incidente. Mas ignorar em silêncio esconderia
 * um `delivered` escrito de um jeito que ninguém previu: por isso a rota
 * **conta** os ignorados, e a contagem é leitura do painel do canal — taxa alta
 * de ignorado é a tradução ficando velha, não o provedor ficando quieto.
 */
export type EventoDeEntrega = "entregue" | "falhou" | "ignorado";

const ENTREGUE = new Set([
  "delivered", "messagesent", "message_sent", "sent", "deliver", "entregue",
]);

const FALHOU = new Set([
  "bounce", "hard_bounce", "hardbounce", "soft_bounce", "softbounce",
  "messagebounced", "message_bounced", "messagedeliveryfailed",
  "message_delivery_failed", "failed", "blocked", "spam", "complaint",
  "invalid_email", "unsubscribed", "error",
]);

export function eventoDoProvedor(bruto: string | null | undefined): EventoDeEntrega {
  const nome = String(bruto ?? "").trim().toLowerCase().replace(/[\s-]+/g, "_");
  if (nome === "") return "ignorado";

  // A comparação é sobre o nome cru e sobre a versão sem separador: `Message
  // Sent`, `MessageSent` e `message_sent` são o mesmo evento em três provedores.
  const semSeparador = nome.replace(/_/g, "");
  if (ENTREGUE.has(nome) || ENTREGUE.has(semSeparador)) return "entregue";
  if (FALHOU.has(nome) || FALHOU.has(semSeparador)) return "falhou";
  return "ignorado";
}
