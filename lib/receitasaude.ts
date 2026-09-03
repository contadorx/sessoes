import { paraCentavos, formatar } from "@/lib/dinheiro";
import { cpfValido } from "@/lib/paciente";

/**
 * O modo Receita Saúde (F2a) — o lado puro.
 *
 * Duas coisas moram aqui: o **prazo** (espelho de `prazo_do_ano`, na 0038) e as
 * **frases** que a tela usa para dizer quanto tempo resta sem assustar mais do
 * que o necessário nem tranquilizar mais do que é verdade.
 *
 * A regra que atravessa o arquivo: **o sistema não emite e não estima multa.**
 * Não há função aqui que calcule um valor de multa; há uma que calcula o
 * **piso** — R$ 100 por recibo, o mínimo legal — e o nome dela diz isso.
 */

/** R$ 100 por mês-calendário ou fração, por recibo. O piso é um mês. */
export const PISO_POR_RECIBO = 10000;

export type EstadoRecibo = "pendente" | "emitido" | "dispensado" | "vencido" | "cancelado";

const ROTULO: Record<EstadoRecibo, string> = {
  pendente: "a emitir",
  emitido: "emitido",
  dispensado: "dispensado",
  vencido: "fora do prazo",
  cancelado: "cancelado",
};

export function rotuloEstado(e: string): string {
  return ROTULO[e as EstadoRecibo] ?? e;
}

// ------------------------------------------------------------------ o prazo

/**
 * O último dia de fevereiro do ano seguinte — espelho exato de
 * `public.prazo_do_ano`.
 *
 * `Date.UTC(ano + 1, 2, 0)` é o dia 0 de março, ou seja, o último de fevereiro.
 * Em ano bissexto isso dá 29 sozinho, sem nenhum `if`. Tudo em UTC: data civil
 * não tem fuso, e usar o relógio de quem abriu a tela faria o prazo mudar de
 * dia conforme o navegador.
 */
export function prazoDoAno(ano: number): string {
  if (!Number.isInteger(ano) || ano < 2000 || ano > 2100) {
    throw new Error(`Ano fora de faixa: ${ano}`);
  }
  const d = new Date(Date.UTC(ano + 1, 2, 0));
  const mes = String(d.getUTCMonth() + 1).padStart(2, "0");
  const dia = String(d.getUTCDate()).padStart(2, "0");
  return `${d.getUTCFullYear()}-${mes}-${dia}`;
}

/** Dias civis entre dois "AAAA-MM-DD". Negativo quando o prazo já passou. */
export function diasEntre(de: string, ate: string): number {
  const a = Date.parse(`${de}T00:00:00Z`);
  const b = Date.parse(`${ate}T00:00:00Z`);
  if (Number.isNaN(a) || Number.isNaN(b)) throw new Error(`Data inválida: ${de} / ${ate}`);
  return Math.round((b - a) / 86_400_000);
}

export type Fase = "tranquilo" | "atencao" | "urgente" | "fechado";

/**
 * Quanto barulho a tela deve fazer.
 *
 * A escada é deliberadamente lenta: alarme que grita o ano inteiro vira
 * paisagem, e aí não grita no dia em que precisa. Só a partir de 60 dias do
 * prazo — ou seja, a partir do começo de janeiro — a coisa muda de cor.
 */
export function faseDoPrazo(dias: number, pendentes: number): Fase {
  if (dias < 0) return "fechado";
  if (pendentes === 0) return "tranquilo";
  if (dias <= 15) return "urgente";
  if (dias <= 60) return "atencao";
  return "tranquilo";
}

/**
 * A frase do prazo.
 *
 * Nunca diz "está tudo em dia" quando há pendência, e nunca diz "você vai ser
 * multada" — diz o que falta, até quando, e qual é o piso da exposição.
 */
export function fraseDoPrazo(dias: number, pendentes: number, prazo: string): string {
  const quando = diaBr(prazo);

  if (dias < 0) {
    return pendentes === 0
      ? `O prazo deste ano fechou em ${quando}. Nada ficou pendente.`
      : `O prazo fechou em ${quando}. A emissão retroativa já não é aceita — o caminho agora é com o seu contador.`;
  }

  if (pendentes === 0) {
    return `Nada a emitir. O prazo deste ano vai até ${quando}.`;
  }

  const r = `${pendentes} recibo${pendentes > 1 ? "s" : ""} a emitir`;
  if (dias === 0) return `${r}, e o prazo é hoje.`;
  if (dias === 1) return `${r}, e o prazo é amanhã, ${quando}.`;
  return `${r}. O retroativo fecha em ${quando} — faltam ${dias} dias.`;
}

/**
 * O piso da exposição, e só o piso.
 *
 * R$ 100 por mês-calendário **ou fração**, por recibo: o mínimo é um mês. O
 * valor real depende de quanto cada um atrasou, e estimar isso seria dar
 * parecer fiscal com cara de conta. A tela diz "pelo menos".
 */
export function pisoDaMulta(pendentes: number, vencidos: number = 0): number {
  const n = pendentes + vencidos;
  if (!Number.isInteger(n) || n < 0) throw new Error(`Contagem inválida: ${n}`);
  return n * PISO_POR_RECIBO;
}

export function frasePisoDaMulta(pendentes: number, vencidos: number = 0): string {
  const piso = pisoDaMulta(pendentes, vencidos);
  if (piso === 0) return "";
  return (
    `A multa prevista é de R$ 100 por mês-calendário ou fração, por recibo — ` +
    `ou seja, no mínimo ${formatar(piso)} se nada for emitido.`
  );
}

// ------------------------------------------------------------------ o painel

export type PainelBruto = {
  ano: number;
  ligado: boolean;
  prazo: string;
  dias_ate_o_prazo: number;
  pendentes: { n: number; valor: string };
  emitidos: { n: number; valor: string };
  dispensados: { n: number; valor: string };
  vencidos: { n: number; valor: string };
  divergentes: number;
  sem_cpf: number;
  piso_multa: number;
  faltas_de_fora: { n: number; valor: string };
  por_mes: { mes: string; pendentes: number; emitidos: number; vencidos: number; valor: string }[];
};

export type Painel = {
  ano: number;
  ligado: boolean;
  prazo: string;
  dias: number;
  fase: Fase;
  pendentes: { n: number; centavos: number };
  emitidos: { n: number; centavos: number };
  dispensados: { n: number; centavos: number };
  vencidos: { n: number; centavos: number };
  divergentes: number;
  semCpf: number;
  pisoMulta: number;
  faltasDeFora: { n: number; centavos: number };
  porMes: { mes: string; pendentes: number; emitidos: number; vencidos: number; centavos: number }[];
};

export function lerPainel(b: PainelBruto): Painel {
  const pendentes = { n: b.pendentes.n, centavos: paraCentavos(b.pendentes.valor) };
  const vencidos = { n: b.vencidos.n, centavos: paraCentavos(b.vencidos.valor) };

  return {
    ano: b.ano,
    ligado: b.ligado,
    prazo: b.prazo,
    dias: b.dias_ate_o_prazo,
    fase: faseDoPrazo(b.dias_ate_o_prazo, pendentes.n + vencidos.n),
    pendentes,
    emitidos: { n: b.emitidos.n, centavos: paraCentavos(b.emitidos.valor) },
    dispensados: { n: b.dispensados.n, centavos: paraCentavos(b.dispensados.valor) },
    vencidos,
    divergentes: b.divergentes,
    semCpf: b.sem_cpf,
    // Recalculado aqui de propósito: se o espelho divergir do banco, é o teste
    // que descobre, não a psicóloga na frente da tela.
    pisoMulta: pisoDaMulta(pendentes.n, vencidos.n),
    faltasDeFora: { n: b.faltas_de_fora.n, centavos: paraCentavos(b.faltas_de_fora.valor) },
    porMes: (b.por_mes ?? []).map((m) => ({
      mes: m.mes,
      pendentes: m.pendentes,
      emitidos: m.emitidos,
      vencidos: m.vencidos,
      centavos: paraCentavos(m.valor),
    })),
  };
}

/** A frase das faltas que ficaram de fora. Aparece só quando existem. */
export function fraseDasFaltas(p: Painel): string {
  if (p.faltasDeFora.n === 0) return "";
  return (
    `${formatar(p.faltasDeFora.centavos)} em ${p.faltasDeFora.n} falta` +
    `${p.faltasDeFora.n > 1 ? "s" : ""} cobrada${p.faltasDeFora.n > 1 ? "s" : ""} ` +
    "não entram aqui: multa de cancelamento não é atendimento prestado. " +
    "Como declarar isso é conversa com o seu contador."
  );
}

/** O aviso do CPF que falta — o motivo nº 1 de a digitação parar no meio. */
export function fraseSemCpf(p: Painel): string {
  if (p.semCpf === 0) return "";
  return (
    `${p.semCpf} ${p.semCpf > 1 ? "pessoas estão" : "pessoa está"} sem CPF no cadastro. ` +
    "O app da Receita exige o CPF de quem pagou, e sem ele o recibo não sai."
  );
}

/** "2026-02-28" → "28/02/2026". Sem `new Date`: data civil não tem fuso. */
export function diaBr(iso: string): string {
  const m = /^(\d{4})-(\d{2})-(\d{2})/.exec(iso.trim());
  return m ? `${m[3]}/${m[2]}/${m[1]}` : iso;
}

// ============================================================ o regime fiscal

/**
 * PF ou PJ — e por que isto é uma coluna e não uma preferência de tela.
 *
 * O Receita Saúde é obrigação **do profissional na qualidade de pessoa
 * física**. Quem atende por CNPJ não emite recibo no app da Receita: emite
 * NFS-e, e o dinheiro que sai da empresa para a pessoa é pró-labore ou
 * distribuição — outro assunto, outra apuração.
 *
 * Enquanto isto não existia, o gatilho do banco olhava só o interruptor
 * `receita_saude` e toda conta PJ acumulava pendência de uma obrigação que
 * não tem. Este tipo é o espelho da coluna `contas.regime`.
 */
export type Regime = "pf" | "pj";

export function fraseDoRegime(r: Regime): string {
  return r === "pj"
    ? "Esta conta atende por CNPJ. O caminho fiscal aqui é a NFS-e, e o Receita Saúde — que é obrigação da pessoa física — fica fora."
    : "Esta conta atende como pessoa física. O recibo do Receita Saúde é obrigatório a cada pagamento recebido.";
}

// ================================================================== o arquivo

/** Código de ocupação de psicólogo na tabela do carnê-leão. */
export const OCUPACAO_PSICOLOGO = "255";

/** Código do rendimento de trabalho não assalariado — profissão liberal. */
export const CODIGO_RENDIMENTO = "R01.001.001";

/** O limite de linhas por importação, no manual v2.1. */
export const LIMITE_LINHAS = 1000;

/** O separador do arquivo. Ponto e vírgula, não vírgula: a vírgula é decimal. */
export const SEPARADOR = ";";

export type LinhaBruta = {
  /** "AAAA-MM-DD" — a data do **pagamento**, não a da sessão. */
  pagoEm: string;
  /** Centavos. */
  centavos: number;
  /** CPF do paciente, como está no cadastro (com ou sem pontuação). */
  cpf: string | null;
};

export type Arquivo = {
  ano: number;
  linhas: number;
  consideradas: number;
  semCpf: number;
  limiteAtingido: boolean;
  texto: string;
};

/** Só os dígitos. O arquivo da Receita não aceita pontuação no CPF. */
export function soDigitos(s: string | null | undefined): string {
  return (s ?? "").replace(/\D/g, "");
}

/**
 * O CPF que vai para o arquivo — com dígito verificador, não só comprimento.
 *
 * Os dois lados checam, como já acontece com o CPF do paciente: a tela recusa
 * na hora de digitar, e o gerador recusa na hora de montar. O arquivo é
 * conferido de uma vez no e-CAC, e a recusa não diz qual linha está errada.
 */
export function cpfValidoParaArquivo(s: string | null | undefined): boolean {
  return cpfValido(soDigitos(s));
}

/**
 * Centavos → "200,00".
 *
 * Vírgula decimal e **sem separador de milhar**: espelho exato do
 * `to_char(valor, 'FM99999999990.00')` seguido de `replace('.', ',')` que o
 * banco faz. Com ponto, a Receita leria 200.00 como duzentos mil.
 */
export function valorParaCsv(centavos: number): string {
  if (!Number.isInteger(centavos) || centavos < 0) {
    throw new Error(`Centavos inválidos: ${centavos}`);
  }
  const reais = Math.floor(centavos / 100);
  const resto = String(centavos % 100).padStart(2, "0");
  return `${reais},${resto}`;
}

/**
 * Uma linha, nas dezesseis colunas da pergunta 24 do manual.
 *
 * A coluna 6 é a descrição, e ela sai **vazia de propósito**: é campo livre
 * que vai para a Receita Federal, e escrever ali o nome de quem se trata
 * entregaria a lista de pacientes a um terceiro. O que a Receita precisa
 * saber é quanto e de quem veio o CPF — o resto é sigilo.
 */
export function linhaCsv(
  l: LinhaBruta,
  cpfProfissional: string,
  crp: string,
): string {
  const cpf = soDigitos(l.cpf);
  if (!cpfValidoParaArquivo(cpf)) throw new Error("linha sem CPF válido não entra no arquivo");
  const prof = soDigitos(cpfProfissional);
  if (!cpfValidoParaArquivo(prof)) throw new Error("o arquivo exige o CPF do profissional");

  return [
    diaBr(l.pagoEm),           //  1 data do pagamento
    CODIGO_RENDIMENTO,         //  2 código do rendimento
    OCUPACAO_PSICOLOGO,        //  3 código da ocupação
    valorParaCsv(l.centavos),  //  4 valor
    "",                        //  5 dedução
    "",                        //  6 descrição — vazia, e é decisão
    "PF",                      //  7 recebido de
    cpf,                       //  8 CPF do pagador
    cpf,                       //  9 CPF do beneficiário
    "",                        // 10 indicador de CPF não informado
    "",                        // 11 CNPJ
    "",                        // 12 indicador de IRRF
    "",                        // 13 valor do IRRF
    "S",                       // 14 indicador de recibo — é o que faz virar Receita Saúde
    prof,                      // 15 CPF do profissional
    (crp ?? "").trim(),        // 16 registro profissional
  ].join(SEPARADOR);
}

/**
 * O arquivo inteiro — e a contabilidade do que ficou de fora.
 *
 * Espelho de `public.csv_receita_saude`. Devolver só o texto faria a psicóloga
 * importar 40 de 47 achando que importou 47, e as sete que faltaram são
 * exatamente as que geram multa.
 */
export function montarArquivo(
  ano: number,
  brutas: LinhaBruta[],
  cpfProfissional: string,
  crp: string,
  regime: Regime = "pf",
): Arquivo {
  if (regime === "pj") {
    throw new Error(
      "esta conta é PJ: o caminho fiscal aqui é a NFS-e, e o Receita Saúde é dos profissionais na qualidade de pessoa física",
    );
  }

  const linhas: string[] = [];
  let semCpf = 0;
  let limiteAtingido = false;

  for (const b of brutas) {
    if (!cpfValidoParaArquivo(b.cpf)) {
      semCpf += 1;
      continue;
    }
    if (linhas.length >= LIMITE_LINHAS) {
      limiteAtingido = true;
      continue;
    }
    linhas.push(linhaCsv(b, cpfProfissional, crp));
  }

  return {
    ano,
    linhas: linhas.length,
    consideradas: brutas.length,
    semCpf,
    limiteAtingido,
    texto: linhas.join("\n"),
  };
}

export function fraseDoArquivo(a: Arquivo): string {
  const partes: string[] = [];
  partes.push(
    a.linhas === 0
      ? "Nenhuma linha para gerar."
      : `${a.linhas} linha${a.linhas > 1 ? "s" : ""} de ${a.consideradas} pendência${a.consideradas > 1 ? "s" : ""}.`,
  );
  if (a.semCpf > 0) {
    const verbo = a.semCpf > 1 ? "ficaram" : "ficou";
    partes.push(
      `${a.semCpf} ${verbo} de fora por falta de CPF no cadastro — sem CPF a Receita recusa a linha.`,
    );
  }
  if (a.limiteAtingido) {
    partes.push(
      `O arquivo aceita ${LIMITE_LINHAS} linhas por importação: o que passou disso fica para a próxima remessa.`,
    );
  }
  return partes.join(" ");
}

export function nomeDoArquivo(ano: number): string {
  return `receita-saude-${ano}.csv`;
}

// ======================================================= a janela de dez dias

/** Dez dias contados da emissão, para desfazer no e-CAC. */
export const DIAS_PARA_DESFAZER = 10;

/**
 * Quantos dias ainda restam. Espelho de `public.dias_para_desfazer`.
 *
 * `null` para o que não foi emitido; `0` quando a janela fechou — nunca
 * negativo, porque "faltam -3 dias" não é informação, é ruído.
 */
export function diasParaDesfazer(emitidoEm: string | null, hoje: string): number | null {
  if (!emitidoEm) return null;
  return Math.max(0, DIAS_PARA_DESFAZER - diasEntre(emitidoEm, hoje));
}

export function fraseDaJanela(dias: number | null): string {
  if (dias === null) return "";
  if (dias === 0) {
    return "A janela de dez dias para desfazer no e-CAC já fechou. Corrigir agora é assunto do seu contador.";
  }
  if (dias === 1) return "Último dia para desfazer este recibo no e-CAC, se algo saiu errado.";
  return `Ainda dá para desfazer este recibo no e-CAC por ${dias} dias, se algo saiu errado.`;
}

// ================================================== o que a PJ tem no lugar

/**
 * As datas que a conta PJ precisa saber, e as que este produto **não** calcula.
 *
 * A DMED vence no último dia **útil** de fevereiro, e fevereiro é o mês do
 * Carnaval: o dia depende de feriado móvel e de feriado municipal. Chutar essa
 * data seria pior que não dar nenhuma — quem confia num dia errado perde o
 * prazo achando que tinha mais um. A função diz a regra e manda confirmar.
 */
export function fraseDmed(anoBase: number): string {
  return (
    `A DMED do ano-calendário ${anoBase} é entregue até o último dia útil de fevereiro de ${anoBase + 1}. ` +
    "O dia exato depende de feriado móvel — confirme com o seu contador."
  );
}

/** Quando a NFS-e passa a ser exigida no padrão IBS/CBS para estes serviços. */
export const NFSE_IBS_CBS_EXIGIVEL = "2026-10-01";

export function fraseNfse(hoje: string): string {
  const dias = diasEntre(hoje, NFSE_IBS_CBS_EXIGIVEL);
  const quando = diaBr(NFSE_IBS_CBS_EXIGIVEL);
  if (dias < 0) return `A NFS-e no padrão IBS/CBS é exigível desde ${quando}.`;
  if (dias === 0) return `A NFS-e no padrão IBS/CBS passa a ser exigível hoje, ${quando}.`;
  return `A NFS-e no padrão IBS/CBS passa a ser exigível em ${quando} — faltam ${dias} dias.`;
}
