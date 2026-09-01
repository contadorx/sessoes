import "server-only";

/**
 * A costura do provedor de calendário.
 *
 * Mesma ideia da `lib/mensageria/adaptadores.ts`: nada acima daqui sabe o nome
 * de um provedor, nada abaixo daqui sabe o que é uma sessão. No dia em que as
 * credenciais da Google existirem, é este arquivo que muda — e só ele.
 *
 * **Uma diferença importante em relação à mensageria.** Lá, o adaptador
 * `registro` é um modo de operação legítimo: a mensagem percorre a fila inteira
 * e é marcada como enviada, porque o que se está exercitando é a fila. Aqui
 * isso seria mentira com consequência: marcar um espelho como `espelhada` sem
 * ter um id de evento do outro lado quebra a atualização e a remoção seguintes
 * — o sistema passaria a achar que existe lá fora um evento que nunca existiu,
 * e a sessão remarcada nunca acertaria o calendário dela.
 *
 * Por isso o adaptador ausente **recusa** em vez de fingir, e recusa de forma
 * não definitiva: a linha continua pendente, a tela diz "esperando para ir", e
 * no dia em que o provedor entrar a fila sai inteira, na ordem.
 */

/**
 * Quantos dias à frente se lê da agenda dela.
 *
 * A agenda materializada vive numa janela rolante de 8 semanas (`janela_semanas`
 * da B5). Ler menos que isso deixaria o fim da janela sem proteção — e é
 * justamente lá que a fila oferece as vagas mais distantes.
 */
export const DIAS_A_LER = 60;

export type AcaoEspelho = "criar" | "atualizar" | "remover";

export type PedidoEspelho = {
  acao: AcaoEspelho;
  calendarioExterno: string;
  eventoExterno: string | null;
  titulo: string | null;
  inicio: string | null;
  fim: string | null;
};

export type ResultadoEspelho =
  | { ok: true; eventoExterno: string | null }
  /**
   * `definitivo` separa "tenta de novo" de "não adianta insistir" — igual ao da
   * mensageria. Evento apagado à mão lá fora é definitivo; rede fora não é.
   */
  | { ok: false; erro: string; definitivo: boolean; expirou?: boolean };

export type Ocupacao = {
  id: string;
  inicio: string;
  fim: string;
  dia_inteiro?: boolean;
};

export type LeituraExterna =
  | { ok: true; ocupacoes: Ocupacao[]; syncToken: string | null }
  | { ok: false; erro: string; expirou: boolean };

export interface AdaptadorCalendario {
  readonly nome: string;
  /** Falso enquanto não há provedor: a tela precisa poder dizer isso. */
  readonly disponivel: boolean;

  ler(entrada: {
    calendarioExterno: string;
    refreshToken: string;
    syncToken: string | null;
    de: string;
    ate: string;
  }): Promise<LeituraExterna>;

  escrever(pedido: PedidoEspelho, refreshToken: string): Promise<ResultadoEspelho>;
}

/**
 * O adaptador que existe antes do provedor existir.
 *
 * Não é mock de teste — é o estado real do sistema enquanto o cadastro do app
 * no console da Google não sai. Ele registra o que sairia e **não** marca nada
 * como feito.
 */
export const registro: AdaptadorCalendario = {
  nome: "registro",
  disponivel: false,

  async ler() {
    console.info("[calendario] (registro) leitura pedida, sem provedor configurado");
    return { ok: false, erro: "sem provedor de calendário configurado", expirou: false };
  },

  async escrever(pedido) {
    console.info("[calendario] (registro, sem envio real)", {
      acao: pedido.acao,
      // Título de propósito: no modo discreto ele é a palavra "Sessão", e é
      // isso que se quer conferir no log. Nos outros modos ele carrega nome de
      // paciente — por isso só o comprimento sai daqui.
      titulo: pedido.titulo === "Sessão" ? "Sessão" : `«${pedido.titulo?.length ?? 0} caracteres»`,
      inicio: pedido.inicio,
      evento: pedido.eventoExterno,
    });
    return {
      ok: false,
      erro: "sem provedor de calendário configurado",
      // Não definitivo: a linha fica pendente e sai inteira quando o provedor
      // entrar. Desistir aqui perderia a agenda de semanas.
      definitivo: false,
    };
  },
};

/**
 * Escolhe o adaptador.
 *
 * Sem provedor, cai no `registro` e diz isso. Quando a Google entrar, é aqui
 * que ela é plugada — e nada mais no sistema precisa saber.
 */
export function adaptadorDoCalendario(): AdaptadorCalendario {
  return registro;
}
