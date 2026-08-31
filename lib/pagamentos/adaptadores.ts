import "server-only";
import { montarBrCode } from "@/lib/pix";

/**
 * A costura do recebimento.
 *
 * Mesma forma da mensageria, pelo mesmo motivo: o doc 10 lista o Asaas como
 * escolha da fase 2 e a Woovi como plano B para PJ na fase 4. Manter dois
 * adaptadores um dia só é viável se o primeiro nascer atrás de uma interface.
 *
 * Dois adaptadores previstos, e a ordem entre eles é uma decisão de produto:
 *
 *  · **`pix_direto`** — o BR Code da chave dela. Sem tarifa, sem KYC, sem
 *    intermediário. Funciona hoje e continua funcionando no dia em que a conta
 *    dela travar no provedor. O doc 10 exige que este caminho exista sempre.
 *  · **`asaas`** — cobrança com link, e o pagamento se concilia sozinho. Custa
 *    R$ 1,99 por PIX e traz o peso regulatório inteiro: conta nominal por
 *    recebedora, KYC herdado, MED em quatro dias.
 *
 * A diferença entre os dois, do ponto de vista de quem usa, é uma só: no
 * primeiro **ela** confirma que recebeu; no segundo o sistema confirma. Tudo o
 * mais — a cobrança, o valor, a política, o aviso — é igual, e é por isso que
 * trocar de um para o outro não mexe em nada acima desta linha.
 */

export type Recebedor = {
  pixChave: string | null;
  pixNome: string | null;
  pixCidade: string | null;
};

export type PedidoDeCobranca = {
  cobrancaId: string;
  valorCentavos: number;
  txid: string;
  /** Nome de quem paga. Alguns provedores exigem; o PIX direto ignora. */
  pagador?: string;
  vencimento?: string;
};

export type CobrancaCriada = {
  provedor: "pix_direto" | "asaas";
  /** O "copia e cola". No PIX direto é tudo o que existe. */
  pixCopiaCola: string | null;
  /** Página de pagamento do provedor, quando há. */
  link: string | null;
  /** Id no provedor — é por ele que o webhook casa o pagamento. */
  provedorCobrancaId: string | null;
};

export interface Adaptador {
  readonly nome: "pix_direto" | "asaas";
  criar(pedido: PedidoDeCobranca, recebedor: Recebedor): Promise<CobrancaCriada>;
}

/**
 * O PIX direto.
 *
 * Não fala com ninguém: monta o código e devolve. Por isso não falha por rede,
 * não tem tarifa e não tem estado no meio do caminho — o que também significa
 * que ele **não sabe** quando o dinheiro caiu. Quem sabe é ela, olhando o
 * extrato, e é ela que aperta "já recebi".
 *
 * Vale dizer o que isso custa: sem conciliação automática, a régua de
 * inadimplência da B18 vai depender de ela marcar. Foi por isso que o Asaas
 * entrou no roadmap — mas cobrar dez pessoas por mês à mão é perfeitamente
 * possível, e cobrar zero por não ter provedor não é.
 */
export const pixDireto: Adaptador = {
  nome: "pix_direto",

  async criar(pedido, recebedor) {
    if (!recebedor.pixChave) {
      throw new Error(
        "Sua chave PIX ainda não está no sistema. Cadastre em Conta para gerar a cobrança.",
      );
    }

    const codigo = montarBrCode({
      chave: recebedor.pixChave,
      nome: recebedor.pixNome ?? "",
      cidade: recebedor.pixCidade ?? "",
      valorCentavos: pedido.valorCentavos,
      txid: pedido.txid,
    });

    return {
      provedor: "pix_direto",
      pixCopiaCola: codigo,
      link: null,
      // Sem provedor não há id de provedor — e é justamente por isso que esta
      // cobrança nunca entra na fila de conciliação diária.
      provedorCobrancaId: null,
    };
  },
};

/**
 * Escolhe o adaptador.
 *
 * O provedor só é usado quando a conta dele está **ativa**. Em análise,
 * bloqueada ou sem conta, cai no PIX direto — que é o comportamento certo: a
 * psicóloga não pode ficar sem cobrar porque um terceiro está avaliando o
 * cadastro dela.
 */
export function adaptadorPara(
  provedor: string | null,
  estado: string | null,
): Adaptador {
  if (provedor === "asaas" && estado === "ativa") {
    // Entra quando a B16 tiver conta de verdade — ver lib/pagamentos/asaas.ts.
    throw new Error("O adaptador do Asaas ainda não está ligado nesta conta.");
  }
  return pixDireto;
}
