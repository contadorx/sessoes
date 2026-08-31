/**
 * As sete famílias de mensagem, e o modo discreto (D3).
 *
 * Quatro coisas que precisam ficar claras antes de ler o código:
 *
 * **1. Discrição é template diferente, não texto trocado em tempo de execução.**
 * A Meta aprova o corpo do template, não o valor das variáveis. Então "discreto"
 * e "completo" são dois templates aprovados separadamente lá — o que muda entre
 * eles é a frase, e a frase é fixa. Trocar palavra na hora do envio faria o
 * WhatsApp recusar a mensagem.
 *
 * **2. O modo é do paciente, não da conta.** Ele viaja gravado na própria
 * mensagem (`params.modo`, congelado pelo gatilho da 0017). Quem editar o
 * cadastro depois não muda o que já foi enfileirado.
 *
 * **3. Nenhum corpo começa ou termina em variável, e o número de variáveis é
 * fixo por template.** As duas são regras da Meta, e desrespeitá-las é
 * reprovação — que reinicia dias de espera (risco R4).
 *
 * **4. Na dúvida, cai para o mais discreto.** Faltou o nome do profissional
 * numa mensagem em modo completo? Sai a discreta. O erro de revelar de menos se
 * conserta com um telefonema; o de revelar demais, não.
 *
 * A regra do modo discreto está escrita como teste em `templates.test.ts`.
 */

import { FUSO } from "@/lib/tempo";
import { formatar } from "@/lib/dinheiro";

export const FAMILIAS = [
  "oferta_de_vaga",
  "encaixe_confirmado",
  "lembrete_de_sessao",
  "aviso_de_desmarque",
  "aviso_de_cobranca",
  "lembrete_de_pagamento",
  "oferta_de_vaga_fixa",
] as const;

export type Familia = (typeof FAMILIAS)[number];
export type Modo = "discreto" | "completo";

export type Parametros = {
  /** Nome do paciente, congelado no enfileiramento. */
  nome?: string;
  modo?: string;
  /** Início da sessão ou da vaga, em ISO. */
  inicio?: string;
  /** Até quando a oferta vale, em ISO. */
  expira_em?: string;
  /** Nome do profissional. Sem ele, o modo completo não acontece. */
  profissional?: string;
  /** Quantos horários o lembrete de pagamento cobre. */
  quantidade?: number;
  /**
   * O rótulo do horário recorrente — "terça, 15h" —, já montado pelo banco
   * (`rotulo_horario`, da 0031). Vem pronto de propósito: quem decide como um
   * horário fixo se escreve é uma função só, e ela é a mesma que monta o
   * contrato.
   */
  horario_fixo?: string;
  /**
   * O valor vem em centavos inteiros, e é `lib/dinheiro` que o formata — a
   * mesma função que a tela usa. Mandar a string pronta do banco criaria uma
   * segunda formatação de dinheiro no projeto, e duas formatações divergem.
   */
  valor_centavos?: number;
  [k: string]: unknown;
};

export type Renderizado = {
  familia: Familia;
  /** O modo **efetivo** — pode ser mais discreto do que o pedido. */
  modo: Modo;
  /** O nome aprovado na Meta. Discreto e completo são templates distintos. */
  nomeDoTemplate: string;
  /** As variáveis posicionais, na ordem em que o template as espera. */
  variaveis: string[];
  /** Corpo montado: é o que sai por SMS, por e-mail e no adaptador de registro. */
  texto: string;
  /** Assunto — só o canal e-mail usa. */
  assunto: string;
};

/** Palavras que jamais entram numa mensagem discreta. */
export const PROIBIDAS_NO_DISCRETO = [
  "terapia",
  "psicoterapia",
  "psicólog",
  "psicanáli",
  "consultório",
  "clínica",
  "paciente",
  "sessão",
  "sessões",
  "atendimento",
  "consulta",
] as const;

function ehFamilia(v: string): v is Familia {
  return (FAMILIAS as readonly string[]).includes(v);
}

const DIA_E_HORA = new Intl.DateTimeFormat("pt-BR", {
  timeZone: FUSO,
  weekday: "long",
  day: "numeric",
  month: "long",
  hour: "2-digit",
  minute: "2-digit",
});

const SO_HORA = new Intl.DateTimeFormat("pt-BR", {
  timeZone: FUSO,
  hour: "2-digit",
  minute: "2-digit",
});

/**
 * "terça-feira, 3 de março às 15:00". Fuso de São Paulo sempre — a lei nº 3.
 * Sem data utilizável, devolve uma expressão que não mente.
 */
function quando(iso: string | undefined): string {
  if (!iso) return "no horário combinado";
  const d = new Date(iso);
  if (Number.isNaN(d.getTime())) return "no horário combinado";
  return DIA_E_HORA.format(d);
}

/** O prazo já vem como sintagma pronto: "às 16:20" ou "o fim do dia". */
function prazo(iso: string | undefined): string {
  if (!iso) return "o fim do dia";
  const d = new Date(iso);
  if (Number.isNaN(d.getTime())) return "o fim do dia";
  return `às ${SO_HORA.format(d)}`;
}

/** "R$ 100,00", ou uma expressão honesta quando não há número. */
function dinheiro(centavos: unknown): string {
  if (typeof centavos !== "number" || !Number.isFinite(centavos) || centavos <= 0) {
    return "o valor combinado";
  }
  return formatar(Math.round(centavos));
}

/** "um horário", "dois horários"… — número por extenso lê melhor que dígito. */
function horarios(quantidade: unknown): string {
  const n =
    typeof quantidade === "number" && Number.isInteger(quantidade) && quantidade > 0
      ? quantidade
      : 1;

  const extenso = ["", "um", "dois", "três", "quatro", "cinco", "seis", "sete", "oito", "nove"];
  const numero = n < extenso.length ? extenso[n] : String(n);
  return n === 1 ? "um horário" : `${numero} horários`;
}

/**
 * "às terças, 15h" — o horário que se repete.
 *
 * O banco manda "terça, 15h" e aqui vira plural: a diferença entre "terça, 15h"
 * e "às terças, 15h" é a diferença entre uma hora e um compromisso semanal, e é
 * exatamente o que esta família de mensagem precisa deixar claro.
 */
function horarioFixo(rotulo: string | undefined): string {
  const limpo = (rotulo ?? "").trim();
  // Sem rótulo não se inventa um dia. O banco sempre manda o dele; esta saída
  // existe para o texto continuar legível se um dia não mandar.
  if (!limpo) return "no dia e hora combinados";
  const [dia, ...resto] = limpo.split(", ");
  const plural = dia.endsWith("s") ? dia : `${dia}s`;
  return resto.length > 0 ? `às ${plural}, ${resto.join(", ")}` : `às ${plural}`;
}

/** Só o primeiro nome. Mensagem não é cadastro. */
function primeiroNome(nome: string | undefined): string {
  const limpo = (nome ?? "").trim();
  if (!limpo) return "tudo bem";
  return limpo.split(/\s+/)[0];
}

/** Palavras que jamais entram numa cobrança. */
export const PROIBIDAS_NA_COBRANCA = [
  "faltou",
  "falta",
  "ausência",
  "ausente",
  "não compareceu",
  "multa",
  "penalidade",
  "infelizmente",
  "lamento",
  "pendência",
  "devedor",
  "dívida",
  "em aberto",
  "atraso",
] as const;

/**
 * Palavras que jamais entram num lembrete de pagamento.
 *
 * Além das da cobrança: nada de ameaça, nada de prazo final, nada de
 * consequência. Uma régua que endurece a cada passo é cobrador; o que se repete
 * aqui é o fato, nunca a intensidade.
 */
export const PROIBIDAS_NA_REGUA = [
  "urgente",
  "última",
  "ultimo aviso",
  "último aviso",
  "prazo final",
  "regulariz",
  "negativ",
  "spc",
  "serasa",
  "protesto",
  "juros",
  "suspens",
  "cancelaremos",
  "providências",
  "cobrança judicial",
] as const;

/**
 * Os corpos, exatamente como vão para a Meta.
 *
 * `{{1}}` é sempre quem recebe, `{{2}}` sempre o horário. Nenhum começa nem
 * termina em variável, e a ordem de cada um está na tabela `VARIAVEIS`.
 *
 * ⚠️ **`aviso_de_cobranca` tem um portão que não é técnico.** A tese inteira do
 * produto é cobrar sem constrangimento — a psicóloga não cobra porque a conversa
 * é humilhante para as duas. Uma palavra errada aqui não gera um bug: gera o
 * problema que o produto existe para resolver. Por isso o texto não diz
 * "faltou", não diz "multa", não pede desculpa e não explica a regra de novo:
 * remete ao que já foi combinado, informa o valor e devolve a palavra à pessoa.
 *
 * Este texto é **rascunho até uma psicóloga lê-lo** (critério de pronto da B11
 * no doc 12, não item de QA). As proibições acima estão no teste; o julgamento
 * sobre o tom, não — esse é dela.
 */
export const CORPOS: Record<Modo, Record<Familia, string>> = {
  discreto: {
    oferta_de_vaga:
      "Oi, {{1}}. Abriu um horário {{2}}. Quer ficar com ele? " +
      "Responda SIM até {{3}} para confirmar. " +
      "Sem resposta, o horário segue para a próxima pessoa da lista.",
    encaixe_confirmado: "Oi, {{1}}. Seu horário {{2}} está confirmado. Até lá.",
    lembrete_de_sessao:
      "Oi, {{1}}. Passando para lembrar do seu horário {{2}}. Até lá.",
    aviso_de_desmarque:
      "Oi, {{1}}. Precisei desmarcar o horário {{2}}. Entro em contato para remarcar.",
    aviso_de_cobranca:
      "Oi, {{1}}. Sobre o horário {{2}}: pelo combinado, fica {{3}} referente a ele. " +
      "Se quiser conversar sobre isso, é só responder aqui.",
    lembrete_de_pagamento:
      "Oi, {{1}}. Passando para lembrar do combinado de {{2}}, referente a {{3}}. " +
      "Se quiser conversar sobre isso, é só responder aqui.",
    oferta_de_vaga_fixa:
      "Oi, {{1}}. Abriu um horário fixo {{2}}, toda semana. Quer ficar com ele? " +
      "Responda SIM até {{3}} e eu falo com você para combinar o começo. " +
      "Sem resposta, o horário segue para a próxima pessoa da lista.",
  },
  completo: {
    oferta_de_vaga:
      "Oi, {{1}}. Abriu um horário {{2}} na agenda de {{4}}. Quer ficar com ele? " +
      "Responda SIM até {{3}} para confirmar. " +
      "Sem resposta, a vaga segue para a próxima pessoa da lista de espera.",
    encaixe_confirmado:
      "Oi, {{1}}. Sua sessão {{2}} com {{3}} está confirmada. Até lá.",
    lembrete_de_sessao:
      "Oi, {{1}}. Passando para lembrar da sua sessão {{2}} com {{3}}. Até lá.",
    aviso_de_desmarque:
      "Oi, {{1}}. A sessão {{2}} com {{3}} precisou ser desmarcada. " +
      "Entro em contato para remarcar.",
    aviso_de_cobranca:
      "Oi, {{1}}. Sobre a sessão {{2}} com {{3}}: pelo combinado, fica {{4}} referente a ela. " +
      "Se quiser conversar sobre isso, é só responder aqui.",
    lembrete_de_pagamento:
      "Oi, {{1}}. Passando para lembrar do combinado de {{2}} com {{3}}, referente a {{4}}. " +
      "Se quiser conversar sobre isso, é só responder aqui.",
    oferta_de_vaga_fixa:
      "Oi, {{1}}. Abriu um horário fixo {{2}}, toda semana, na agenda de {{4}}. " +
      "Quer ficar com ele? Responda SIM até {{3}} e eu falo com você para combinar " +
      "o começo. Sem resposta, o horário segue para a próxima pessoa da lista.",
  },
};

/**
 * As variáveis de cada família, na ordem exata em que o corpo acima as usa.
 *
 * Ficam numa tabela, e não numa cadeia de condicionais, por um motivo prático:
 * variável fora de ordem não quebra nada — só troca o horário pelo valor no
 * celular de alguém. O teste confere que a contagem bate com o corpo; a ordem
 * é responsabilidade desta tabela, que dá para conferir a olho.
 */
const VARIAVEIS: Record<Modo, Record<Familia, (c: Campos) => string[]>> = {
  discreto: {
    oferta_de_vaga: (c) => [c.nome, c.hora, c.limite],
    encaixe_confirmado: (c) => [c.nome, c.hora],
    lembrete_de_sessao: (c) => [c.nome, c.hora],
    aviso_de_desmarque: (c) => [c.nome, c.hora],
    aviso_de_cobranca: (c) => [c.nome, c.hora, c.valor],
    lembrete_de_pagamento: (c) => [c.nome, c.valor, c.quantos],
    oferta_de_vaga_fixa: (c) => [c.nome, c.fixo, c.limite],
  },
  completo: {
    oferta_de_vaga: (c) => [c.nome, c.hora, c.limite, c.prof],
    encaixe_confirmado: (c) => [c.nome, c.hora, c.prof],
    lembrete_de_sessao: (c) => [c.nome, c.hora, c.prof],
    aviso_de_desmarque: (c) => [c.nome, c.hora, c.prof],
    aviso_de_cobranca: (c) => [c.nome, c.hora, c.prof, c.valor],
    lembrete_de_pagamento: (c) => [c.nome, c.valor, c.prof, c.quantos],
    oferta_de_vaga_fixa: (c) => [c.nome, c.fixo, c.limite, c.prof],
  },
};

type Campos = {
  nome: string;
  hora: string;
  limite: string;
  prof: string;
  valor: string;
  quantos: string;
  fixo: string;
};

/**
 * Monta a mensagem.
 *
 * O modo discreto nunca cita o profissional nem a natureza do encontro — não
 * porque seja segredo, mas porque a tela do celular é lida por quem passa. É a
 * fronteira D3 do doc 11, e a violação dela é dano que não se desfaz.
 */
export function renderizar(template: string, params: Parametros): Renderizado {
  if (!ehFamilia(template)) {
    throw new Error(`Template desconhecido: ${template}`);
  }

  const nome = primeiroNome(params.nome);
  const hora = quando(params.inicio);
  const limite = prazo(params.expira_em);
  const prof = (params.profissional ?? "").trim();

  // O modo pedido só vale se houver com que preenchê-lo. Sem o nome do
  // profissional, o template completo ficaria com variável vazia — que a Meta
  // recusa — e a saída certa é a mais discreta, nunca a menos.
  const modo: Modo = params.modo === "completo" && prof ? "completo" : "discreto";

  const valor = dinheiro(params.valor_centavos);
  const quantos = horarios(params.quantidade);
  const fixo = horarioFixo(params.horario_fixo);
  const variaveis = VARIAVEIS[modo][template]({
    nome, hora, limite, prof, valor, quantos, fixo,
  });

  return {
    familia: template,
    modo,
    nomeDoTemplate: `sessoes_${template}_${modo}`,
    variaveis,
    texto: preencher(CORPOS[modo][template], variaveis),
    assunto: assunto(template, modo),
  };
}

/** Troca `{{n}}` pelo n-ésimo valor. É a mesma substituição que a Meta faz. */
function preencher(corpo: string, variaveis: string[]): string {
  return corpo.replace(/\{\{(\d+)\}\}/g, (inteiro, n: string) => {
    const valor = variaveis[Number(n) - 1];
    return valor ?? inteiro;
  });
}

function assunto(familia: Familia, modo: Modo): string {
  if (modo === "discreto") {
    return {
      oferta_de_vaga: "Abriu um horário",
      encaixe_confirmado: "Horário confirmado",
      lembrete_de_sessao: "Lembrete de horário",
      aviso_de_desmarque: "Mudança no horário",
      aviso_de_cobranca: "Sobre um horário",
      lembrete_de_pagamento: "Sobre o combinado",
      oferta_de_vaga_fixa: "Abriu um horário fixo",
    }[familia];
  }

  return {
    oferta_de_vaga: "Abriu um horário na agenda",
    encaixe_confirmado: "Sua sessão está confirmada",
    lembrete_de_sessao: "Lembrete da sua sessão",
    aviso_de_desmarque: "Sua sessão precisou ser desmarcada",
    aviso_de_cobranca: "Sobre uma sessão",
    lembrete_de_pagamento: "Sobre o combinado",
    oferta_de_vaga_fixa: "Abriu um horário fixo na agenda",
  }[familia];
}
