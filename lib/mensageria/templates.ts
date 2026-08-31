/**
 * As quatro famílias de mensagem, e o modo discreto (D3).
 *
 * Duas coisas que precisam ficar claras antes de ler o código:
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
 * A regra do modo discreto está escrita como teste em `templates.test.ts`, e é
 * ela que impede a boa intenção de "só desta vez põe o nome da clínica".
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
  /** Nome do profissional — só aparece no modo completo. */
  profissional?: string;
  [k: string]: unknown;
};

export type Renderizado = {
  familia: Familia;
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

function modoDe(params: Parametros): Modo {
  return params.modo === "completo" ? "completo" : "discreto";
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

function ate(iso: string | undefined): string {
  if (!iso) return "";
  const d = new Date(iso);
  if (Number.isNaN(d.getTime())) return "";
  return SO_HORA.format(d);
}

/** Só o primeiro nome. Mensagem não é cadastro. */
function primeiroNome(nome: string | undefined): string {
  const limpo = (nome ?? "").trim();
  if (!limpo) return "Oi";
  return limpo.split(/\s+/)[0];
}

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

  const modo = modoDe(params);
  const nome = primeiroNome(params.nome);
  const hora = quando(params.inicio);
  const limite = ate(params.expira_em);
  const prof = (params.profissional ?? "").trim();

  const nomeDoTemplate = `sessoes_${template}_${modo}`;

  // As variáveis posicionais que o template aprovado espera. O modo completo
  // acrescenta o profissional como última variável.
  const base: Record<Familia, string[]> = {
    oferta_de_vaga: [nome, hora, limite || "o fim do dia"],
    encaixe_confirmado: [nome, hora],
    lembrete_de_sessao: [nome, hora],
    aviso_de_desmarque: [nome, hora],
  };

  const variaveis =
    modo === "completo" && prof ? [...base[template], prof] : base[template];

  const texto = corpo(template, modo, { nome, hora, limite, prof });

  return {
    familia: template,
    modo,
    nomeDoTemplate,
    variaveis,
    texto,
    assunto: assunto(template, modo),
  };
}

function corpo(
  familia: Familia,
  modo: Modo,
  v: { nome: string; hora: string; limite: string; prof: string },
): string {
  const com = modo === "completo" && v.prof ? ` com ${v.prof}` : "";
  const prazo = v.limite ? ` até às ${v.limite}` : "";

  if (modo === "discreto") {
    switch (familia) {
      case "oferta_de_vaga":
        return (
          `${v.nome}, abriu um horário ${v.hora}. ` +
          `Quer ficar com ele? Responda SIM${prazo}. ` +
          `Sem resposta, ele segue para a próxima pessoa da lista.`
        );
      case "encaixe_confirmado":
        return `${v.nome}, confirmado: ${v.hora}. Até lá.`;
      case "lembrete_de_sessao":
        return `${v.nome}, lembrete do seu horário ${v.hora}.`;
      case "aviso_de_desmarque":
        return (
          `${v.nome}, precisei desmarcar o horário ${v.hora}. ` +
          `Já já falo com você para remarcar.`
        );
    }
  }

  switch (familia) {
    case "oferta_de_vaga":
      return (
        `${v.nome}, abriu um horário${com} ${v.hora}. ` +
        `Quer ficar com ele? Responda SIM${prazo}. ` +
        `Sem resposta, a vaga segue para a próxima pessoa da lista de espera.`
      );
    case "encaixe_confirmado":
      return `${v.nome}, sua sessão${com} está confirmada para ${v.hora}. Até lá.`;
    case "lembrete_de_sessao":
      return `${v.nome}, lembrete da sua sessão${com} ${v.hora}.`;
    case "aviso_de_desmarque":
      return (
        `${v.nome}, a sessão${com} ${v.hora} precisou ser desmarcada. ` +
        `Entro em contato para remarcar.`
      );
  }
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
