import { paraCentavos, formatar, somar } from "@/lib/dinheiro";

/**
 * O financeiro derivado da agenda (F1) — o lado puro.
 *
 * A conta que vale é a do banco (`financeiro_do_mes`, na 0037). Este arquivo
 * existe para duas coisas que o banco não faz: **traduzir** o que ele devolve
 * para centavos inteiros (a lei nº 4 do doc 05), e **escrever a frase** que a
 * tela mostra.
 *
 * A regra que atravessa tudo: **realizado e recebido nunca se somam.** Não há
 * função aqui que devolva o total dos dois, e há teste provando que o objeto do
 * banco também não traz um. Um mês de mensalista tem 4 × R$ 200 em realizado e
 * R$ 750 em recebido — R$ 1.550 seria dinheiro que não existe.
 */

export type Categoria =
  | "aluguel"
  | "supervisao"
  | "formacao"
  | "conselho"
  | "software"
  | "material"
  | "contabilidade"
  | "deslocamento"
  | "impostos"
  | "outra";

/**
 * As dez categorias, fixas.
 *
 * Fixas porque categoria livre vira quarenta em três meses, e a pasta do
 * contador (F3) fica ilegível. E em nenhum lugar aqui se diz que alguma delas
 * abate imposto: **isso é decisão do contador dela**, não rótulo nosso. O doc
 * 07 é explícito — o app não calcula, entrega o número certo a quem calcula.
 */
export const CATEGORIAS: { valor: Categoria; rotulo: string; exemplo: string }[] = [
  { valor: "aluguel", rotulo: "Sala", exemplo: "aluguel, condomínio, coworking por hora" },
  { valor: "supervisao", rotulo: "Supervisão", exemplo: "supervisão clínica" },
  { valor: "formacao", rotulo: "Formação", exemplo: "cursos, congressos, livros" },
  { valor: "conselho", rotulo: "Conselho", exemplo: "anuidade do CRP" },
  { valor: "software", rotulo: "Sistemas", exemplo: "assinaturas, este sistema inclusive" },
  { valor: "material", rotulo: "Material", exemplo: "material de consumo do consultório" },
  { valor: "contabilidade", rotulo: "Contador", exemplo: "honorário da contabilidade" },
  { valor: "deslocamento", rotulo: "Deslocamento", exemplo: "ir e voltar do consultório" },
  { valor: "impostos", rotulo: "Impostos e taxas", exemplo: "DARF, ISS" },
  { valor: "outra", rotulo: "Outra", exemplo: "o que não cabe acima" },
];

export function rotuloCategoria(c: string): string {
  return CATEGORIAS.find((x) => x.valor === c)?.rotulo ?? c;
}

// ------------------------------------------------------------------ o painel

/** O que `financeiro_do_mes` devolve: `numeric` chega como string. */
export type PainelBruto = {
  de: string;
  ate: string;
  realizado: { valor: string; sessoes: number };
  recebido: { valor: string; cobrancas: number; por_tipo: Record<string, string> };
  em_aberto: { valor: string; cobrancas: number };
  perdoado: { valor: string; cobrancas: number };
  despesas: {
    valor: string;
    lancamentos: number;
    por_categoria: { categoria: string; valor: string; lancamentos: number }[];
  };
  sobra: string;
  recuperado: {
    encaixes: number;
    valor_encaixes: string;
    faltas: number;
    valor_faltas: string;
  };
  sem_registro: { sessoes: number; valor: string };
};

export type Painel = {
  de: string;
  ate: string;
  realizado: { centavos: number; sessoes: number };
  recebido: { centavos: number; cobrancas: number; porTipo: { tipo: string; centavos: number }[] };
  emAberto: { centavos: number; cobrancas: number };
  perdoado: { centavos: number; cobrancas: number };
  despesas: {
    centavos: number;
    lancamentos: number;
    porCategoria: { categoria: string; centavos: number; lancamentos: number }[];
  };
  sobra: number;
  recuperado: { encaixes: number; centavosEncaixes: number; faltas: number; centavosFaltas: number };
  semRegistro: { sessoes: number; centavos: number };
};

const ORDEM_TIPO = ["sessao", "mensalidade", "pacote", "falta"];

export function lerPainel(b: PainelBruto): Painel {
  return {
    de: b.de,
    ate: b.ate,
    realizado: { centavos: paraCentavos(b.realizado.valor), sessoes: b.realizado.sessoes },
    recebido: {
      centavos: paraCentavos(b.recebido.valor),
      cobrancas: b.recebido.cobrancas,
      porTipo: Object.entries(b.recebido.por_tipo ?? {})
        .map(([tipo, valor]) => ({ tipo, centavos: paraCentavos(valor) }))
        .sort((x, y) => ORDEM_TIPO.indexOf(x.tipo) - ORDEM_TIPO.indexOf(y.tipo)),
    },
    emAberto: { centavos: paraCentavos(b.em_aberto.valor), cobrancas: b.em_aberto.cobrancas },
    perdoado: { centavos: paraCentavos(b.perdoado.valor), cobrancas: b.perdoado.cobrancas },
    despesas: {
      centavos: paraCentavos(b.despesas.valor),
      lancamentos: b.despesas.lancamentos,
      porCategoria: (b.despesas.por_categoria ?? []).map((c) => ({
        categoria: c.categoria,
        centavos: paraCentavos(c.valor),
        lancamentos: c.lancamentos,
      })),
    },
    // Recalculado aqui de propósito: se o espelho divergir do banco, é o teste
    // que descobre, não a psicóloga na frente da tela.
    sobra: somar(paraCentavos(b.recebido.valor), -paraCentavos(b.despesas.valor)),
    recuperado: {
      encaixes: b.recuperado.encaixes,
      centavosEncaixes: paraCentavos(b.recuperado.valor_encaixes),
      faltas: b.recuperado.faltas,
      centavosFaltas: paraCentavos(b.recuperado.valor_faltas),
    },
    semRegistro: { sessoes: b.sem_registro.sessoes, centavos: paraCentavos(b.sem_registro.valor) },
  };
}

// ------------------------------------------------------------------ as frases

const ROTULO_TIPO: Record<string, string> = {
  sessao: "sessões",
  mensalidade: "mensalidades",
  pacote: "pacotes",
  falta: "faltas",
};

export function rotuloTipo(t: string): string {
  return ROTULO_TIPO[t] ?? t;
}

/**
 * A frase que impede a soma errada.
 *
 * Ela aparece **entre** as duas colunas, e não num rodapé de ajuda: quem soma
 * as duas está contando a mesma hora duas vezes, e descobrir isso depois de
 * mandar o número para o contador é tarde.
 */
export function fraseDasDuasColunas(p: Painel): string {
  if (p.realizado.centavos === 0 && p.recebido.centavos === 0) {
    return "Mês sem atendimento e sem entrada registrada.";
  }
  return (
    `${formatar(p.realizado.centavos)} em atendimentos e ` +
    `${formatar(p.recebido.centavos)} em entradas são o mesmo mês visto de dois ` +
    "ângulos — não se somam."
  );
}

/**
 * O que voltou para o mês. Vazio quando não voltou nada — sem enfeite.
 *
 * Não é "o sistema trouxe de volta": metade disto é a fila preenchendo o
 * horário, que o sistema faz, e a outra metade é falta cobrada — e desde a 0058
 * quem cobra falta é ela, na caixa "A decidir". O software não cobra ninguém.
 */
export function fraseDoRecuperado(p: Painel): string {
  const total = somar(p.recuperado.centavosEncaixes, p.recuperado.centavosFaltas);
  if (total === 0) return "";

  const partes: string[] = [];
  if (p.recuperado.encaixes > 0) {
    partes.push(
      `${p.recuperado.encaixes} hora${p.recuperado.encaixes > 1 ? "s" : ""} que a fila preencheu`,
    );
  }
  if (p.recuperado.faltas > 0) {
    partes.push(
      `${p.recuperado.faltas} falta${p.recuperado.faltas > 1 ? "s" : ""} que você decidiu cobrar`,
    );
  }
  return `${formatar(total)} — ${partes.join(" e ")}.`;
}

/** As horas que aconteceram e não têm recebimento. O número que impede o painel de mentir por omissão. */
export function fraseSemRegistro(p: Painel): string {
  const n = p.semRegistro.sessoes;
  if (n === 0) return "";
  return (
    `${n} hora${n > 1 ? "s" : ""} sem registro de recebimento, ` +
    `${formatar(p.semRegistro.centavos)} no total.`
  );
}

// --------------------------------------------------------------------- o mês

const MESES = [
  "janeiro", "fevereiro", "março", "abril", "maio", "junho",
  "julho", "agosto", "setembro", "outubro", "novembro", "dezembro",
];

/** "2026-08" → "agosto de 2026". */
export function nomeDoMes(competencia: string): string {
  const m = /^(\d{4})-(\d{2})$/.exec(competencia.trim());
  if (!m) return competencia;
  return `${MESES[Number(m[2]) - 1] ?? m[2]} de ${m[1]}`;
}

/**
 * Os limites do mês, como datas civis.
 *
 * Sem `new Date(...)` local: data civil não tem fuso, e usar o relógio de quem
 * abriu a tela faria o mês mudar conforme o navegador. Tudo em UTC, como no
 * `lib/cobranca`.
 */
export function limitesDoMes(competencia: string): { de: string; ate: string } {
  const { ano, mes } = partes(competencia);
  const ultimo = new Date(Date.UTC(ano, mes, 0)).getUTCDate();
  return {
    de: `${competencia}-01`,
    ate: `${competencia}-${String(ultimo).padStart(2, "0")}`,
  };
}

export function mesAnterior(competencia: string): string {
  const { ano, mes } = partes(competencia);
  return mes === 1 ? `${ano - 1}-12` : `${ano}-${String(mes - 1).padStart(2, "0")}`;
}

export function mesSeguinte(competencia: string): string {
  const { ano, mes } = partes(competencia);
  return mes === 12 ? `${ano + 1}-01` : `${ano}-${String(mes + 1).padStart(2, "0")}`;
}

/** "2026-08-31" → "2026-08". */
export function competenciaDoDia(dia: string): string {
  const m = /^(\d{4}-\d{2})/.exec(dia.trim());
  if (!m) throw new Error(`Dia inválido: ${dia}`);
  return m[1];
}

function partes(competencia: string): { ano: number; mes: number } {
  const m = /^(\d{4})-(\d{2})$/.exec(competencia.trim());
  if (!m) throw new Error(`Competência inválida (esperado AAAA-MM): ${competencia}`);
  const mes = Number(m[2]);
  if (mes < 1 || mes > 12) throw new Error(`Mês inválido: ${competencia}`);
  return { ano: Number(m[1]), mes };
}
