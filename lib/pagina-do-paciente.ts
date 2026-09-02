/**
 * A página transacional do paciente — do lado do app (P7).
 *
 * A regra que este módulo carrega, e que vale mais que qualquer função daqui:
 *
 *     **É uma janela, não um arquivo.**
 *     Um portal responde "o que já aconteceu comigo?".
 *     Esta página responde "o que está esperando por mim agora?".
 *
 * O `claude/30` matou o portal do paciente (D18) com três palavras — *"vira
 * produto paralelo"* — e pôs no lugar isto. A diferença não é de tamanho: um
 * portal cresce sozinho, porque toda tela nova parece pertencer a ele. Uma
 * janela tem três recortes escritos, e recorte é coisa que uma suíte cobra:
 * sessão futura com confirmação **pedida**, cobrança **aberta**, documento dos
 * últimos **90 dias**. O resto não está aqui, e a página diz isso em voz alta
 * em vez de deixar o silêncio parecer defeito.
 *
 * Gêmeo de `pagina_do_paciente` no banco, com os mesmos valores esperados da
 * suíte 0066.
 *
 * ---
 *
 * **Três coisas que este módulo deliberadamente não sabe fazer**, e cada uma
 * evita uma tela que já vi produto de saúde ter:
 *
 * 1. **Não sabe dizer "você deve".** Nenhuma frase daqui usa vocabulário de
 *    cobrança. A régua da B18 não endurece porque o devedor é um paciente, e
 *    esta página é lida pela mesma pessoa. `PROIBIDAS_NA_PAGINA` está no teste.
 * 2. **Não sabe falar de tratamento.** Nenhum rótulo, nenhuma contagem de
 *    sessões, nenhuma frequência, nenhuma evolução. É a fronteira 6 do doc 11,
 *    e aqui ela é mais estreita que de costume: nem o próprio paciente lê
 *    prontuário por link.
 * 3. **Não sabe cancelar.** Recusar é dizer que não vem; o que isso faz com a
 *    hora é decisão dela, com a política congelada na sessão.
 */

import { FUSO } from "@/lib/tempo";
import { formatar } from "@/lib/dinheiro";

export type EstadoDaPagina = "aberta" | "expirada" | "revogada" | "inexistente";

/** Espelha `sessoes.eixo_confirmacao`, e só os valores que a página vê. */
export type JaConfirmou = "pendente" | "confirmada" | "recusada" | "silenciosa" | "nao_pedida";

export type ItemDeConfirmacao = { sessao: string; inicio: string; ja: JaConfirmou };
export type ItemDePagamento = {
  cobranca: string;
  valor: number | string;
  tipo: string;
  criado_em: string;
  /** `null` quando o Pix ainda não foi cunhado. Ver `fraseDoPix`. */
  pix: string | null;
};
export type DocumentoNaPagina = {
  documento: string;
  tipo: string;
  numero: number;
  emitido_em: string;
  periodo_de: string | null;
  periodo_ate: string | null;
  valor_total: number | string | null;
};

export type PaginaDoPaciente = {
  estado: EstadoDaPagina;
  nome?: string | null;
  confirmar?: ItemDeConfirmacao[];
  pagar?: ItemDePagamento[];
  documentos?: DocumentoNaPagina[];
};

/** A página vazia — o que a tela mostra quando a leitura falha. */
export const PAGINA_VAZIA: PaginaDoPaciente = { estado: "inexistente" };

const DIA_E_HORA = new Intl.DateTimeFormat("pt-BR", {
  timeZone: FUSO,
  weekday: "long",
  day: "numeric",
  month: "long",
  hour: "2-digit",
  minute: "2-digit",
});

const SO_DIA = new Intl.DateTimeFormat("pt-BR", {
  timeZone: FUSO,
  day: "2-digit",
  month: "2-digit",
  year: "numeric",
});

/** "terça-feira, 3 de março às 15:00" — fuso de São Paulo sempre (lei nº 3). */
export function quando(iso: string | null | undefined): string {
  if (!iso) return "no horário combinado";
  const d = new Date(iso);
  if (Number.isNaN(d.getTime())) return "no horário combinado";
  return DIA_E_HORA.format(d);
}

/** "02/09/2026". Sem data utilizável, devolve travessão em vez de mentir. */
export function dia(iso: string | null | undefined): string {
  if (!iso) return "—";
  const d = new Date(iso);
  if (Number.isNaN(d.getTime())) return "—";
  return SO_DIA.format(d);
}

/**
 * A saudação, e só o primeiro nome.
 *
 * Mesma escolha da B19 e da B21, e o motivo não é economia de bytes: a página
 * é aberta num celular que outra pessoa pode estar olhando, e o nome inteiro
 * de alguém numa tela que fala de consultório é a fronteira D3 do doc 11.
 */
export function saudacao(nome: string | null | undefined): string {
  const limpo = (nome ?? "").trim();
  if (!limpo) return "Oi.";
  return `Oi, ${limpo.split(/\s+/)[0]}.`;
}

/**
 * O que a página diz quando o link não serve mais.
 *
 * As três recusas dizem **o que fazer em seguida**, e nenhuma delas explica o
 * motivo técnico. "Este link expirou" sozinho deixa a pessoa sem próximo
 * passo, e o próximo passo aqui é sempre o mesmo: falar com quem mandou.
 */
export function rotuloDoEstado(estado: EstadoDaPagina): string {
  switch (estado) {
    case "aberta":
      return "";
    case "expirada":
      return "Este link expirou. Peça um novo para quem te enviou — leva um segundo.";
    case "revogada":
      return "Este link foi substituído por outro. Peça o mais recente para quem te enviou.";
    default:
      return "Não encontramos esta página.";
  }
}

/** Há alguma coisa esperando? Decide entre a página e o estado vazio. */
export function temAlgoAberto(p: PaginaDoPaciente): boolean {
  if (p.estado !== "aberta") return false;
  return (
    (p.confirmar?.length ?? 0) > 0 ||
    (p.pagar?.length ?? 0) > 0 ||
    (p.documentos?.length ?? 0) > 0
  );
}

/**
 * O estado vazio, e ele é a frase mais importante do módulo.
 *
 * Uma página em branco se lê como defeito, e uma pessoa que acha que o sistema
 * quebrou liga para a psicóloga. "Não há nada esperando você agora" é
 * informação; espaço vazio não é.
 */
export function fraseDoVazio(): string {
  return "Não há nada esperando por você agora. Quando houver, esta mesma página vai mostrar.";
}

/**
 * O que a página **não** mostra, dito nela mesma.
 *
 * Sem esta frase, quem procurar um recibo antigo aqui vai concluir que o
 * recibo sumiu — e depois que o consultório perdeu os documentos dele. Dizer o
 * recorte transforma uma ausência em uma regra, e regra a pessoa entende.
 */
export function fraseDaJanela(): string {
  return (
    "Esta página mostra só o que está em aberto: horários esperando a sua confirmação, " +
    "pagamentos ainda não feitos e documentos dos últimos três meses. " +
    "Para qualquer coisa mais antiga, é só pedir."
  );
}

/**
 * O texto do Pix — e a ausência dele é dita, não escondida.
 *
 * O código só existe depois que ela o gera, porque montá-lo exige a chave Pix
 * dela e chave Pix não passa por caminho anônimo (o cabeçalho da migração 0066
 * escreve o porquê). Quando não existe, a página informa em vez de mostrar um
 * campo vazio — um campo vazio faz a pessoa tentar copiar o nada.
 */
export function fraseDoPix(item: ItemDePagamento): string {
  if (item.pix && item.pix.trim().length > 0) {
    return "Copie o código abaixo e cole no aplicativo do seu banco, em Pix Copia e Cola.";
  }
  return "O código do Pix ainda não está aqui. Quem te enviou este link vai mandar a chave.";
}

/** "R$ 200,00" a partir de reais — o banco guarda `numeric(12,2)`. */
export function valorEmReais(v: number | string | null | undefined): string {
  const n = typeof v === "string" ? Number(v) : v;
  if (typeof n !== "number" || !Number.isFinite(n)) return "o valor combinado";
  return formatar(Math.round(n * 100));
}

/**
 * O motivo da cobrança, na língua do paciente.
 *
 * `falta` vira **"horário reservado e não utilizado"**, e isso não é eufemismo
 * de conveniência: é a mesma decisão que fez a palavra "faltou" sair do
 * `aviso_de_cobranca` na B11. A cobrança existe porque a hora foi separada
 * para ele e ninguém mais pôde usá-la — dizer isso é mais exato do que dizer
 * que ele faltou, e não carrega juízo.
 */
export const MOTIVOS: Record<string, string> = {
  sessao: "sessão realizada",
  falta: "horário reservado e não utilizado",
  mensalidade: "mensalidade combinada",
  pacote: "pacote de sessões",
  avulsa: "combinado",
};

export function rotuloDoMotivo(tipo: string): string {
  return MOTIVOS[tipo] ?? "o combinado";
}

/** Os três documentos que a Res. CFP 06/2019 e a B17 produzem. */
export const DOCUMENTOS: Record<string, string> = {
  recibo: "Recibo",
  declaracao_comparecimento: "Declaração de comparecimento",
  informe_anual: "Informe anual",
};

export function rotuloDoDocumento(tipo: string): string {
  return DOCUMENTOS[tipo] ?? tipo;
}

/** "000123" — o número queimado da 0029, do jeito que sai no papel. */
export function numeroDoDocumento(numero: number): string {
  return String(numero).padStart(6, "0");
}

/**
 * O rótulo do que já foi respondido.
 *
 * `recusada` **não** vira "cancelada", e a diferença é a build inteira do P3:
 * dizer que não vem é uma coisa; cancelar a hora, com a política de falta que
 * isso aciona, é outra, e é dela.
 */
export function rotuloDaResposta(ja: JaConfirmou): string {
  switch (ja) {
    case "confirmada":
      return "Você confirmou.";
    case "recusada":
      return "Você avisou que não vai.";
    default:
      return "";
  }
}

/** Ainda dá para responder? */
export function esperaResposta(ja: JaConfirmou): boolean {
  return ja === "pendente" || ja === "silenciosa";
}

/**
 * Palavras que jamais entram nesta página.
 *
 * Duas famílias, e as duas têm dono. As de cobrança são as da B11 e da B18 —
 * quem lê aqui é a mesma pessoa que leria a mensagem, e a régua não endurece
 * por mudar de tela. As clínicas são a fronteira 6 do doc 11: esta página não
 * tem vocabulário de tratamento porque não tem assunto de tratamento.
 *
 * O teste varre **as frases que este módulo produz**, e não o código — um
 * comentário citando a palavra proibida para explicar por que ela é proibida
 * não pode reprovar o arquivo. Foi a lição do `dangerouslySetInnerHTML` na
 * 0051, e a quinta vez que uma varredura larga acusou código certo.
 */
export const PROIBIDAS_NA_PAGINA = [
  "faltou",
  "multa",
  "penalidade",
  "devedor",
  "dívida",
  "atraso",
  "pendência",
  "inadimpl",
  "urgente",
  "prazo final",
  "evolução",
  "anamnese",
  "prontuário",
  "diagnóstic",
  "tratamento",
  "terapia",
  "psicólog",
] as const;
