import "server-only";
import type { Renderizado } from "./templates";

/**
 * A costura do provedor.
 *
 * O risco R4 do doc 11 é simples de enunciar: um dia a Meta reprova um template,
 * ou o BSP cai, ou o preço muda e o Gupshup deixa de fazer sentido. A mitigação
 * não é escolher o provedor certo — é fazer com que trocar de provedor seja
 * **editar um arquivo**. Este é o arquivo.
 *
 * Nada acima daqui (regra de negócio, cascata, cobrança) sabe o nome de um
 * provedor. Nada abaixo daqui sabe o que é uma vaga.
 */

export type Canal = "whatsapp" | "sms" | "email";

export type Envio = {
  canal: Canal;
  destino: string;
  conteudo: Renderizado;
};

export type ResultadoEnvio =
  | { ok: true; provedor: string; idExterno?: string }
  /**
   * `definitivo` é a diferença entre "tenta de novo daqui a pouco" e "não
   * adianta insistir". Número inválido é definitivo; timeout não é. Insistir no
   * definitivo queima dinheiro e reputação do número.
   */
  | { ok: false; provedor: string; erro: string; definitivo: boolean };

export interface Adaptador {
  readonly nome: string;
  /**
   * Falso enquanto não há provedor — o mesmo campo que
   * `lib/calendario/adaptadores.ts` declara, e pela mesma razão: quem chama
   * precisa **poder perguntar** antes de agir, em vez de descobrir pelo
   * resultado. O calendário acertou primeiro; a mensageria copiou tarde.
   */
  readonly disponivel: boolean;
  /** Por que não está disponível. Vai para a trilha e daí para a tela. */
  readonly motivo: string | null;
  suporta(canal: Canal): boolean;
  enviar(envio: Envio): Promise<ResultadoEnvio>;
}

/** O motivo, escrito uma vez: ele vai para a trilha, para o log e para a tela. */
export const SEM_PROVEDOR = "sem provedor de mensagem configurado";

/**
 * O adaptador que existe antes do BSP existir — e que **recusa**.
 *
 * Ele já existiu com outro nome e outro comportamento, e foi o pior defeito
 * que este produto teve no ar: chamava-se `registro`, devolvia `ok: true` com
 * um `idExterno` inventado (`registro:1788346982148`), e o worker então
 * carimbava `marcar_enviada`. O comentário de então dizia a verdade sem
 * perceber o tamanho dela — *"a mensagem percorre a fila inteira, é reservada,
 * marcada como enviada e aparece na trilha: só não sai do prédio"*.
 *
 * O que isso significava na mesa dela: a tela afirmava que a paciente tinha
 * sido avisada, e a paciente não tinha recebido nada. É um fato sobre outra
 * pessoa, afirmado por um sistema que não observou fato nenhum, e que ela não
 * tinha como conferir. Valia para as quatro mensagens essenciais — lembrete de
 * véspera, aviso de desmarque, encaixe confirmado e pedido de confirmação —
 * que saem automáticas **inclusive no Gratuito**.
 *
 * Não lança, de propósito: estourar deixaria a fila parada em silêncio, que é
 * pior. Recusa com motivo, e o motivo chega até a tela.
 */
export const semProvedor: Adaptador = {
  nome: "sem-provedor",
  disponivel: false,
  motivo: SEM_PROVEDOR,
  suporta: () => false,
  async enviar({ canal, destino, conteudo }) {
    console.info("[mensageria] recusado: sem provedor configurado", {
      canal,
      // Destino mascarado: log não é lugar de dado de contato completo (LGPD).
      destino: mascarar(destino),
      template: conteudo.nomeDoTemplate,
      modo: conteudo.modo,
    });
    return { ok: false, provedor: "sem-provedor", erro: SEM_PROVEDOR, definitivo: false };
  },
};

/** "5511900001234" → "5511*****1234". Suficiente para depurar, insuficiente para vazar. */
export function mascarar(destino: string): string {
  if (destino.includes("@")) {
    const [antes, dominio] = destino.split("@");
    return `${antes.slice(0, 2)}***@${dominio}`;
  }
  if (destino.length <= 8) return "***";
  return `${destino.slice(0, 4)}${"*".repeat(destino.length - 8)}${destino.slice(-4)}`;
}

/**
 * Escolhe o adaptador do canal.
 *
 * Enquanto nenhum provedor estiver plugado aqui, todo canal recebe o adaptador
 * que recusa — e quem chama tem que olhar `disponivel` **antes** de agir. O que
 * acontece com a mensagem nesse caso não é decisão deste arquivo: é do worker,
 * e a resposta dele é pôr a mensagem na mão dela, não marcá-la como enviada.
 *
 * Quando o BSP entrar (B10), é aqui que ele é plugado, e só aqui.
 */
export function adaptadorPara(canal: Canal): Adaptador {
  void canal;
  return semProvedor;
}
