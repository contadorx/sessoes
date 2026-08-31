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
  suporta(canal: Canal): boolean;
  enviar(envio: Envio): Promise<ResultadoEnvio>;
}

/**
 * O adaptador que existe antes do BSP existir.
 *
 * Não é mock de teste: é o modo de operação legítimo enquanto a verificação da
 * Meta não sai. A mensagem percorre a fila inteira, é reservada, marcada como
 * enviada e aparece na trilha — só não sai do prédio. É o que permite construir
 * a B10 sem esperar dias de aprovação.
 */
export const registro: Adaptador = {
  nome: "registro",
  suporta: () => true,
  async enviar({ canal, destino, conteudo }) {
    console.info("[mensageria] (registro, sem envio real)", {
      canal,
      // Destino mascarado: log não é lugar de dado de contato completo (LGPD).
      destino: mascarar(destino),
      template: conteudo.nomeDoTemplate,
      modo: conteudo.modo,
      texto: conteudo.texto,
    });
    return { ok: true, provedor: "registro", idExterno: `registro:${Date.now()}` };
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
 * Sem provedor configurado, cai no `registro` **de propósito** e diz isso no
 * log. A alternativa — estourar — deixaria a fila parada em silêncio, que é
 * pior: mensagem que não sai e ninguém sabe.
 *
 * Quando o BSP entrar (B10), é aqui que ele é plugado, e só aqui.
 */
export function adaptadorPara(canal: Canal): Adaptador {
  void canal;
  return registro;
}
