/**
 * As quatro famílias de mensagem, e o modo discreto (D3).
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

export const FAMILIAS = [
  "oferta_de_vaga",
  "encaixe_confirmado",
  "lembrete_de_sessao",
  "aviso_de_desmarque",
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

/** Só o primeiro nome. Mensagem não é cadastro. */
function primeiroNome(nome: string | undefined): string {
  const limpo = (nome ?? "").trim();
  if (!limpo) return "tudo bem";
  return limpo.split(/\s+/)[0];
}

/**
 * Os corpos, exatamente como vão para a Meta.
 *
 * `{{1}}` é sempre quem recebe, `{{2}}` sempre o horário. No modo completo,
 * `{{n}}` final é o profissional. Nenhum começa nem termina em variável.
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
  },
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

  const variaveis =
    modo === "discreto"
      ? template === "oferta_de_vaga"
        ? [nome, hora, limite]
        : [nome, hora]
      : template === "oferta_de_vaga"
        ? [nome, hora, limite, prof]
        : [nome, hora, prof];

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
    }[familia];
  }

  return {
    oferta_de_vaga: "Abriu um horário na agenda",
    encaixe_confirmado: "Sua sessão está confirmada",
    lembrete_de_sessao: "Lembrete da sua sessão",
    aviso_de_desmarque: "Sua sessão precisou ser desmarcada",
  }[familia];
}
