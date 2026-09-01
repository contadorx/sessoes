import { paraCentavos, formatar } from "@/lib/dinheiro";
import { rotuloCategoria } from "@/lib/financeiro";

/**
 * A pasta do contador (F3) — o lado puro.
 *
 * Duas coisas moram aqui: as **regras do CSV**, que precisam bater exatamente
 * com as do banco (`csv_campo` e `csv_valor`, na 0039), e o **resumo em
 * português** que a tela mostra e que vai no corpo do e-mail.
 *
 * A regra que atravessa o arquivo é a mesma da migração: **o contador recebe
 * dinheiro, nunca gente.** Não há neste arquivo nenhuma função que receba nome
 * de paciente, e o tipo do retrato não tem onde guardar um.
 */

// ------------------------------------------------------------------- o CSV

/**
 * Um campo de texto no CSV — espelho de `public.csv_campo`.
 *
 * Sempre entre aspas, aspas internas dobradas (RFC 4180). "Sempre" porque a
 * descrição de uma despesa é texto que ela digitou: um ponto e vírgula ali
 * dentro quebraria a coluna, e ninguém descobre isso olhando — descobre-se
 * quando a soma do contador não bate.
 */
export function escaparCsv(v: string | null | undefined): string {
  return `"${(v ?? "").replace(/"/g, '""')}"`;
}

/** 1234.50 → "1234,50" — espelho de `public.csv_valor`. Vírgula, sem milhar. */
export function valorCsv(centavos: number): string {
  if (!Number.isInteger(centavos)) throw new Error(`Centavos precisa ser inteiro: ${centavos}`);
  const negativo = centavos < 0;
  const abs = negativo ? -centavos : centavos;
  const texto = `${Math.trunc(abs / 100)},${String(abs % 100).padStart(2, "0")}`;
  return negativo ? `-${texto}` : texto;
}

/**
 * O BOM do UTF-8, na frente do arquivo.
 *
 * Sem ele o Excel em português abre "Supervisão" como "SupervisÃ£o". É três
 * bytes que decidem se a pasta chega legível ou se volta com pergunta — e
 * pergunta de contador chega no dia 5, quando ela está atendendo.
 *
 * Fica só no download: o que está guardado no banco é UTF-8 limpo.
 */
export function comBom(csv: string): string {
  return `﻿${csv}`;
}

// --------------------------------------------------------------- o retrato

export type RetratoPasta = {
  competencia: string;
  de: string;
  ate: string;
  versao?: number;
  substitui?: string | null;
  conta: { nome: string; cidade: string | null };
  profissional: { nome: string | null; documento: string | null };
  receitas: {
    total: string;
    lancamentos: number;
    pessoas: number;
    por_tipo: Record<string, string>;
  };
  despesas: {
    total: string;
    lancamentos: number;
    por_categoria: Record<string, string>;
  };
  sobra: string;
  fiscal: {
    recibos_pendentes: number;
    recibos_emitidos: number;
    prazo_receita_saude: string;
  };
  aviso: string;
};

export type PastaLinha = {
  id: string;
  competencia: string;
  versao: number;
  estado: "gerada" | "enviada" | "falhou";
  destino: string | null;
  enviada_em: string | null;
  erro: string | null;
  retrato: RetratoPasta;
};

const MESES = [
  "janeiro", "fevereiro", "março", "abril", "maio", "junho",
  "julho", "agosto", "setembro", "outubro", "novembro", "dezembro",
];

/** "2026-07" → "julho de 2026". */
export function nomeDoMes(competencia: string): string {
  const m = /^(\d{4})-(\d{2})$/.exec(competencia.trim());
  if (!m) return competencia;
  return `${MESES[Number(m[2]) - 1] ?? m[2]} de ${m[1]}`;
}

/** O nome do arquivo que o contador recebe. Espelho do que a fila monta. */
export function nomeDoArquivo(competencia: string, versao: number): string {
  return `sessoes-${competencia}${versao > 1 ? `-v${versao}` : ""}.csv`;
}

/**
 * O resumo em texto — o que o contador lê em dez segundos, antes de abrir o
 * anexo.
 *
 * Repare que ele diz de onde vem cada número e o que **não** está ali. Um
 * arquivo financeiro sem essa frase faz o contador supor, e supor errado sobre
 * regime de caixa é retrabalho de mês inteiro.
 */
export function resumoDoRetrato(r: RetratoPasta): string {
  const receitas = paraCentavos(r.receitas.total);
  const despesas = paraCentavos(r.despesas.total);
  const sobra = paraCentavos(r.sobra);

  const linhas: string[] = [];

  linhas.push(`${nomeDoMes(r.competencia)} — ${r.conta.nome}`);
  if (r.versao && r.versao > 1) {
    linhas.push(`Versão ${r.versao}. Substitui a anterior; use este arquivo.`);
  }
  linhas.push("");
  linhas.push(
    `Entradas: ${formatar(receitas)} em ${r.receitas.lancamentos} lançamento` +
      `${r.receitas.lancamentos === 1 ? "" : "s"}, de ${r.receitas.pessoas} ` +
      `${r.receitas.pessoas === 1 ? "pessoa" : "pessoas"}.`,
  );

  const tipos = Object.entries(r.receitas.por_tipo ?? {});
  if (tipos.length > 0) {
    linhas.push(
      "  " + tipos.map(([t, v]) => `${rotuloTipo(t)}: ${formatar(paraCentavos(v))}`).join(" · "),
    );
  }

  linhas.push(`Saídas: ${formatar(despesas)} em ${r.despesas.lancamentos} lançamento${
    r.despesas.lancamentos === 1 ? "" : "s"
  }.`);

  const cats = Object.entries(r.despesas.por_categoria ?? {});
  if (cats.length > 0) {
    linhas.push(
      "  " + cats.map(([c, v]) => `${rotuloCategoria(c)}: ${formatar(paraCentavos(v))}`).join(" · "),
    );
  }

  linhas.push(`Saldo do mês: ${formatar(sobra)}.`);
  linhas.push("");
  linhas.push(
    "Regime de caixa: a data de cada linha é a do pagamento, não a do atendimento.",
  );
  linhas.push(
    "Sem identificação de pacientes, por minimização de dado sensível (LGPD, art. 5º, II).",
  );

  return linhas.join("\n");
}

const ROTULO_TIPO: Record<string, string> = {
  sessao: "atendimentos",
  mensalidade: "mensalidades",
  pacote: "pacotes",
  falta: "compensações por cancelamento",
};

export function rotuloTipo(t: string): string {
  return ROTULO_TIPO[t] ?? t;
}

/** A frase do fiscal — o gancho entre a pasta e o Receita Saúde (B24). */
export function fraseDoFiscal(r: RetratoPasta): string {
  const p = r.fiscal?.recibos_pendentes ?? 0;
  const e = r.fiscal?.recibos_emitidos ?? 0;
  if (p === 0 && e === 0) return "";
  if (p === 0) {
    return `Os ${e} recibo${e > 1 ? "s" : ""} do Receita Saúde deste mês já foram emitidos.`;
  }
  return (
    `${p} recibo${p > 1 ? "s" : ""} do Receita Saúde ainda por emitir neste mês` +
    `${e > 0 ? `, ${e} já emitido${e > 1 ? "s" : ""}` : ""}. ` +
    "Quem emite é você, no app da Receita."
  );
}

/** O estado da pasta, em português de tela. */
export function rotuloEstado(p: PastaLinha, temEmail: boolean): string {
  if (p.estado === "enviada") return "enviada ao contador";
  if (p.estado === "falhou") return `não consegui enviar${p.erro ? ` — ${p.erro}` : ""}`;
  return temEmail ? "pronta, aguardando envio" : "pronta — baixe e encaminhe";
}

/** O mês anterior ao de hoje, que é o que a pasta fecha. "2026-08-31" → "2026-07". */
export function mesAFechar(hoje: string): string {
  const m = /^(\d{4})-(\d{2})-\d{2}$/.exec(hoje.trim());
  if (!m) throw new Error(`Dia inválido: ${hoje}`);
  const ano = Number(m[1]);
  const mes = Number(m[2]);
  return mes === 1 ? `${ano - 1}-12` : `${ano}-${String(mes - 1).padStart(2, "0")}`;
}

/** "2026-07" → "2026-07-01", que é o que a função do banco espera. */
export function primeiroDia(competencia: string): string {
  if (!/^\d{4}-(0[1-9]|1[0-2])$/.test(competencia.trim())) {
    throw new Error(`Competência inválida: ${competencia}`);
  }
  return `${competencia}-01`;
}
