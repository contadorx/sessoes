/**
 * O que sobrou do teto — e o que sobrou é freio, não produto (OP8).
 *
 * **Este módulo mudou de sinal em 02/09/2026.** Ele carregava o teto de
 * mensagens do plano: 60 por mês no Grátis, a fila pausando quando estourava, o
 * aviso de cobrança não saindo. A migração 0060 desfez isso — não por defeito,
 * por decisão —, e a razão está escrita lá inteira. O resumo:
 *
 *     **Não se vende limite de disparo. Vende-se limite de sessão.**
 *
 * A unidade cobrada passou a ser a sessão, e ela mora em `lib/faixa.ts`.
 *
 * A doutrina que este arquivo carregava não foi abandonada — ela **venceu**. O
 * arquivo dizia que um teto de mensagens parece decisão comercial e não é,
 * porque ele decide quem fica sem aviso, e que quem ficaria sem aviso é a
 * paciente, que não escolheu plano nenhum e não sabe que existe um. A conclusão
 * de então foi proteger três templates. A conclusão de agora é que o limite
 * comercial sobre mensagem não devia existir.
 *
 * O que resta aqui:
 *
 *   · **os templates essenciais**, porque a classificação continua existindo e
 *     continua sendo o que impede um template novo de nascer barrável por
 *     acaso;
 *   · **os estados da mensagem**, inclusive o que não saiu — e agora ele diz
 *     "trava de segurança" em vez de "limite do plano", porque é isso que
 *     virou;
 *   · **o limite de pacientes**, que a 0048 desligou e ninguém religou.
 */

/**
 * Quantos pacientes ativos a conta tem — e é **medida, não porteiro**.
 *
 * A OP3 chegou a pôr limite de cinco pacientes no Grátis, e a 0048 desfez: um
 * teto de pacientes limita o **registro**, que é a parte que devia ser livre.
 * Nenhum plano usa desde então; o tipo fica porque o número continua útil (o
 * tamanho da conta é informação do painel do negócio).
 */
export type Pacientes = {
  tem_limite: boolean;
  limite: number | null;
  ativos: number;
  restantes: number | null;
  lotou: boolean;
};

export function fraseDosPacientes(p: Pacientes): string {
  if (!p.tem_limite) return "Seu plano não tem limite de pacientes.";
  if (p.lotou) return `Seu plano vai até ${p.limite} pacientes ativos, e você tem ${p.ativos}.`;
  return `${p.ativos} de ${p.limite} pacientes ativos.`;
}

/**
 * O que fazer quando lota — e há saída, sempre.
 *
 * Um limite sem saída é uma parede, e a saída aqui não é só "pague": arquivar
 * quem encerrou o processo devolve a vaga. É o motivo de o limite ser de
 * pacientes **ativos** e não de pacientes cadastrados — o histórico continua lá
 * inteiro, e ele é obrigação de guarda, não consumo de plano.
 */
export function fraseDaSaida_pacientes(p: Pacientes): string {
  if (!p.lotou) return "";
  return "Arquivar quem encerrou o processo devolve a vaga — a ficha continua guardada, com o histórico inteiro.";
}

/**
 * O teto mensal do plano, que continua existindo no banco e **não é usado**.
 *
 * A máquina fica, provada por suíte, e nenhum plano a configura — mesmo critério
 * da 0048 com o limite de pacientes. O tipo fica pelo mesmo motivo: `tem_teto`
 * hoje responde `false` para todo mundo, e se algum dia um plano precisar de
 * teto mensal, ele volta a valer sem deploy.
 */
export type Teto = {
  tem_teto: boolean;
  limite: number | null;
  usadas: number;
  restantes: number | null;
  estourou: boolean;
  pct: number;
};

export const SEM_TETO: Teto = {
  tem_teto: false,
  limite: null,
  usadas: 0,
  restantes: null,
  estourou: false,
  pct: 0,
};

export type Template = {
  codigo: string;
  descricao: string;
  essencial: boolean;
  motivo: string;
};

/**
 * O que nunca foi barrado por limite comercial — e hoje não há limite comercial
 * nenhum sobre mensagem. Gêmeo de `templates.essencial`.
 *
 * A lista continua importando por uma razão que sobrevive à 0060: ela é a
 * classificação obrigatória. Um template novo sem linha na tabela é recusado
 * pela chave estrangeira, e a recusa obriga alguém a decidir de qual lado ele
 * está antes de mandar a primeira mensagem.
 */
export const ESSENCIAIS = [
  "lembrete_de_sessao",
  "aviso_de_desmarque",
  "encaixe_confirmado",
] as const;

export function ehEssencial(template: string): boolean {
  return (ESSENCIAIS as readonly string[]).includes(template);
}

/**
 * Os freios técnicos — invisíveis, e é assim que devem ficar.
 *
 * Gêmeos de `public.limites_tecnicos`. Não aparecem em tela nenhuma da cliente
 * e não aparecem na página de preços: são proteção contra laço e abuso, não
 * cardápio. Medidos por hora e por dia de propósito — um mês cheio nunca
 * estoura um teto horário, e um laço estoura em segundos.
 *
 * Ficam aqui para que o app saiba **traduzir** o motivo de uma mensagem barrada,
 * e para nada além disso.
 */
export type FreioTecnico = "mensagens_por_conta_hora" | "mensagens_por_paciente_dia";

export function motivoDoFreio(codigo: string): string {
  switch (codigo) {
    case "mensagens_por_conta_hora":
      return "muitas mensagens saíram desta conta na mesma hora";
    case "mensagens_por_paciente_dia":
      return "muitas mensagens para a mesma pessoa hoje";
    default:
      return "trava de segurança";
  }
}

/**
 * O estado de uma mensagem, em português.
 *
 * `barrada_no_teto` tem frase própria e explícita. Uma mensagem que não saiu
 * precisa dizer que não saiu — o modo de falha ruim aqui seria ela sumir da tela
 * e a psicóloga descobrir semanas depois que ninguém foi cobrado.
 *
 * O **valor** do estado continua sendo `barrada_no_teto`, e é histórico: apagar
 * o valor do check apagaria a leitura das mensagens barradas em agosto, que
 * foram barradas de verdade. O **rótulo** mudou, porque o que barra hoje é uma
 * trava de segurança e não um limite de plano — e chamar as duas coisas pelo
 * mesmo nome é o começo de confundi-las.
 */
export type EstadoMensagem =
  | "pendente"
  | "enviando"
  | "enviada"
  | "entregue"
  | "falhou"
  | "cancelada"
  | "barrada_no_teto";

export function rotuloEstadoMensagem(e: EstadoMensagem): string {
  switch (e) {
    case "pendente":
      return "na fila";
    case "enviando":
      return "saindo";
    case "enviada":
      return "enviada";
    case "entregue":
      return "entregue";
    case "falhou":
      return "falhou";
    case "cancelada":
      return "cancelada";
    case "barrada_no_teto":
      return "não saiu — trava de segurança";
  }
}

/** Estados em que a mensagem não vai mais sair, aconteça o que acontecer. */
export function terminal(e: EstadoMensagem): boolean {
  return e === "entregue" || e === "cancelada" || e === "barrada_no_teto";
}
