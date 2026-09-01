import { lerHora, lerValor } from "@/lib/importacao";
import { inicioDoDiaSP } from "@/lib/tempo";

/**
 * A agenda que já existe, do lado do app.
 *
 * Duas metades, e as duas espelham SQL — os mesmos valores esperados dos dois
 * lados, porque é assim que se descobre que um dos dois mudou:
 *
 * - `iniciaisDoNome` e `tituloDoEvento` são gêmeas de `public.iniciais_do_nome`
 *   e `public.titulo_do_evento`. A tela mostra a **prévia** do que vai sair
 *   antes de ela ligar o calendário, e uma prévia que mente é pior que prévia
 *   nenhuma: ela decide o modo olhando essa frase.
 *
 * - `lerHistorico` é a fronteira com dado de fora. Vale aqui a lei da B14:
 *   **erro é por linha, com o número da linha e o motivo**, e nada entra sem
 *   ela ver — o resultado desta função é pré-visualização, quem grava é a ação
 *   do servidor.
 */

export type ModoTitulo = "discreto" | "iniciais" | "completo";
export type Direcao = "ler" | "escrever" | "duas_vias";
export type EstadoCalendario = "ligado" | "pausado" | "expirado" | "revogado";

export type PainelCalendario = {
  ligado: boolean;
  profissional_id?: string;
  calendario_id?: string;
  estado?: EstadoCalendario;
  direcao?: Direcao;
  modo_titulo?: ModoTitulo;
  email_externo?: string | null;
  sincronizado_em?: string | null;
  lido_ate?: string | null;
  erro?: string | null;
  ocupacoes?: number;
  pendentes?: number;
  falhados?: number;
  espelhados?: number;
};

// ======================================================== o que sai daqui

/**
 * As partículas que não viram inicial.
 *
 * "Maria de Souza" tem duas iniciais, não três — "M. D. S." não identifica
 * ninguém e ainda por cima parece erro.
 */
const PARTICULAS = new Set(["de", "da", "do", "dos", "das", "e"]);

/** "Maria Fernanda de Souza" → "M. F. S." — gêmea de `iniciais_do_nome`. */
export function iniciaisDoNome(nome: string): string {
  return (nome ?? "")
    .split(/\s+/)
    .filter((p) => p !== "" && !PARTICULAS.has(p.toLowerCase()))
    .map((p) => `${p.slice(0, 1).toUpperCase()}.`)
    .join(" ")
    .trim();
}

/**
 * O que o evento diz na agenda dela — gêmea de `titulo_do_evento`.
 *
 * O padrão é `discreto` porque a Google é um terceiro fora da nossa fronteira,
 * e num consultório de psicologia a lista de quem tem hora marcada **é** a
 * lista de quem faz terapia.
 */
export function tituloDoEvento(modo: ModoTitulo, nome: string): string {
  if (modo === "completo") {
    const limpo = (nome ?? "").trim();
    return limpo === "" ? "Sessão" : `Sessão · ${limpo}`;
  }
  if (modo === "iniciais") {
    const iniciais = iniciaisDoNome(nome);
    return iniciais === "" ? "Sessão" : `Sessão · ${iniciais}`;
  }
  return "Sessão";
}

export function rotuloDoModo(modo: ModoTitulo): { titulo: string; explica: string } {
  if (modo === "completo") {
    return {
      titulo: "Nome completo",
      explica:
        "Quem abrir sua agenda vê quem tem hora marcada. Escolha consciente: numa clínica de psicologia essa lista é dado sensível.",
    };
  }
  if (modo === "iniciais") {
    return {
      titulo: "Só as iniciais",
      explica: "Você reconhece; quem olhar por cima do seu ombro, não.",
    };
  }
  return {
    titulo: "Só “Sessão”",
    explica: "Nada sai daqui que identifique alguém. É o padrão.",
  };
}

export function rotuloDaDirecao(d: Direcao): { titulo: string; explica: string } {
  if (d === "ler") {
    return {
      titulo: "Só ler",
      explica:
        "Trago os seus compromissos para cá, e a fila deixa de oferecer essas horas. Nada é escrito na sua agenda.",
    };
  }
  if (d === "escrever") {
    return {
      titulo: "Só escrever",
      explica:
        "Suas sessões aparecem na sua agenda. Mas eu não vejo o resto dela — e a fila pode oferecer uma hora que você já tem ocupada.",
    };
  }
  return {
    titulo: "Nos dois sentidos",
    explica: "As suas sessões vão para lá, e o que está lá deixa de ser oferecido aqui.",
  };
}

// ==================================================== o estado e a defasagem

/** Horas inteiras entre o carimbo e agora. `null` quando nunca sincronizou. */
export function horasDesde(quando: string | null | undefined, agora: Date = new Date()): number | null {
  if (!quando) return null;
  const t = new Date(quando).getTime();
  if (Number.isNaN(t)) return null;
  return Math.floor((agora.getTime() - t) / 3_600_000);
}

/**
 * Há quanto tempo não se lê a agenda dela.
 *
 * A frase existe porque a decisão 4 da 0040 é contraintuitiva e precisa estar
 * escrita na tela: **calendário defasado continua bloqueando**. Se ela não vir
 * "última leitura há dois dias", vai achar que a fila está oferecendo com
 * informação de hoje.
 */
export function fraseDaDefasagem(
  painel: PainelCalendario,
  agora: Date = new Date(),
): string {
  if (!painel.ligado) return "";
  if (painel.direcao === "escrever") return "Você pediu para eu só escrever — não leio a sua agenda.";

  const h = horasDesde(painel.sincronizado_em, agora);
  if (h === null) return "Ainda não li a sua agenda nenhuma vez.";
  if (h < 1) return "Li a sua agenda há menos de uma hora.";
  if (h < 24) return `Li a sua agenda há ${h} ${h === 1 ? "hora" : "horas"}.`;

  const dias = Math.floor(h / 24);
  return `Li a sua agenda pela última vez há ${dias} ${dias === 1 ? "dia" : "dias"} — o que estava ocupado continua bloqueado aqui, mas o que apareceu depois eu não vi.`;
}

export function fraseDoEstado(painel: PainelCalendario): string {
  if (!painel.ligado) return "Nenhuma agenda ligada.";
  if (painel.estado === "expirado") {
    return "A autorização venceu. Ligue de novo — enquanto isso, as horas que eu já conhecia continuam bloqueadas.";
  }
  if (painel.estado === "pausado") {
    return "Pausado. Não leio nem escrevo, e o que eu já sabia continua valendo.";
  }
  return "Ligado.";
}

/** O que está na fila para sair — e o que desistiu de sair. */
export function fraseDaFila(painel: PainelCalendario): string {
  const p = painel.pendentes ?? 0;
  const f = painel.falhados ?? 0;
  const e = painel.espelhados ?? 0;

  if (p === 0 && f === 0 && e === 0) return "Nada foi para a sua agenda ainda.";

  const partes: string[] = [];
  if (e > 0) partes.push(`${e} ${e === 1 ? "sessão está" : "sessões estão"} lá`);
  if (p > 0) partes.push(`${p} esperando para ir`);
  if (f > 0) partes.push(`${f} que eu desisti de mandar`);
  return `${partes.join(" · ")}.`;
}

export function rotuloDaAcao(acao: "criar" | "atualizar" | "remover"): string {
  if (acao === "criar") return "criar o evento";
  if (acao === "atualizar") return "atualizar o evento";
  return "tirar o evento";
}

// ================================================= o histórico que veio de fora

export type EstadoHistorico = "realizada" | "falta" | "cancelada_cedo" | "cancelada_tarde";

export type LinhaHistorico = {
  linha: number;
  paciente: string;
  dia: string;
  hora: string;
  estado: EstadoHistorico;
  valorCentavos: number | null;
};

export type ErroHistorico = { linha: number; texto: string; motivo: string };

export type LeituraHistorico = {
  sessoes: LinhaHistorico[];
  erros: ErroHistorico[];
};

/** Ponto e vírgula, tabulação ou vírgula — o que aparecer primeiro. */
function partir(linha: string): string[] {
  const sep = linha.includes(";") ? ";" : linha.includes("\t") ? "\t" : ",";
  return linha.split(sep).map((c) => c.trim());
}

const SEM_ACENTO = (s: string) =>
  s
    .normalize("NFD")
    .replace(/[̀-ͯ]/g, "")
    .toLowerCase()
    .trim();

/**
 * "compareceu", "realizada", "ok" → realizada; "faltou" → falta; e por aí.
 *
 * Ninguém exporta de outro sistema com os nossos nomes de estado. Recusar por
 * causa disso seria devolver o trabalho para quem já está migrando.
 */
export function lerEstadoHistorico(bruto: string): EstadoHistorico | null {
  const s = SEM_ACENTO(bruto);
  if (s === "") return "realizada";

  if (["realizada", "realizado", "compareceu", "atendida", "atendido", "ok", "sim", "feita"].includes(s)) {
    return "realizada";
  }
  if (["falta", "faltou", "nao compareceu", "no-show", "no show", "ausente"].includes(s)) {
    return "falta";
  }
  if (["cancelada", "cancelado", "cancelada cedo", "cancelou", "desmarcou", "desmarcada"].includes(s)) {
    return "cancelada_cedo";
  }
  if (["cancelada tarde", "cancelamento tardio", "cancelou em cima", "tardia"].includes(s)) {
    return "cancelada_tarde";
  }
  return null;
}

/** "2024-03-05", "05/03/2024", "5/3/24" → "2024-03-05". */
export function lerDia(bruto: string): string | null {
  const s = bruto.trim();
  if (s === "") return null;

  const iso = /^(\d{4})-(\d{1,2})-(\d{1,2})$/.exec(s);
  if (iso) return montarDia(Number(iso[1]), Number(iso[2]), Number(iso[3]));

  const br = /^(\d{1,2})[/.-](\d{1,2})[/.-](\d{2}|\d{4})$/.exec(s);
  if (br) {
    const ano = Number(br[3]) < 100 ? 2000 + Number(br[3]) : Number(br[3]);
    return montarDia(ano, Number(br[2]), Number(br[1]));
  }
  return null;
}

function montarDia(ano: number, mes: number, dia: number): string | null {
  if (ano < 1900 || ano > 2999 || mes < 1 || mes > 12 || dia < 1 || dia > 31) return null;
  // O mês de 31 dias que não tem: `Date` acomoda 31/02 virando 02/03, e uma
  // data que se conserta sozinha é pior do que uma recusada.
  const d = new Date(Date.UTC(ano, mes - 1, dia));
  if (d.getUTCMonth() !== mes - 1 || d.getUTCDate() !== dia) return null;
  return `${ano}-${String(mes).padStart(2, "0")}-${String(dia).padStart(2, "0")}`;
}

/**
 * Lê o histórico colado.
 *
 * Formato: `paciente; data; hora; estado; valor`. Paciente e data são
 * obrigatórios — os dois são os únicos que não dá para preencher depois sem
 * adivinhar. Sem hora, assume 12:00 (não muda o dia em São Paulo, e é o mesmo
 * carimbo que a `registrar_recebimento` usa desde a B23).
 */
export function lerHistorico(texto: string, hoje: string): LeituraHistorico {
  const sessoes: LinhaHistorico[] = [];
  const erros: ErroHistorico[] = [];

  const linhas = texto.split(/\r?\n/);
  const limite = inicioDoDiaSP(hoje).getTime();

  linhas.forEach((bruta, i) => {
    const n = i + 1;
    const texto1 = bruta.trim();
    if (texto1 === "") return;

    const campos = partir(texto1);
    const nome = (campos[0] ?? "").trim();

    // Cabeçalho de planilha: descarta em silêncio, sem virar erro de linha.
    if (i === 0 && /^(paciente|nome)$/i.test(nome)) return;

    if (nome === "" || nome.length > 120) {
      erros.push({ linha: n, texto: texto1, motivo: "sem nome de paciente" });
      return;
    }

    const dia = lerDia(campos[1] ?? "");
    if (dia === null) {
      erros.push({ linha: n, texto: texto1, motivo: "não entendi a data" });
      return;
    }

    const hora = campos[2] !== undefined && campos[2] !== "" ? lerHora(campos[2]) : "12:00";
    if (hora === null) {
      erros.push({ linha: n, texto: texto1, motivo: "não entendi a hora" });
      return;
    }

    const estado = lerEstadoHistorico(campos[3] ?? "");
    if (estado === null) {
      erros.push({ linha: n, texto: texto1, motivo: "não entendi o que houve na sessão" });
      return;
    }

    // Histórico é passado. Sessão futura se marca na agenda, não se importa —
    // e o banco recusa de novo, porque a fronteira não pode morar só aqui.
    if (inicioDoDiaSP(dia).getTime() >= limite) {
      erros.push({ linha: n, texto: texto1, motivo: "histórico é passado" });
      return;
    }

    sessoes.push({
      linha: n,
      paciente: nome,
      dia,
      hora,
      estado,
      valorCentavos: campos[4] !== undefined ? lerValor(campos[4]) : null,
    });
  });

  return { sessoes, erros };
}

/** Quantas linhas lidas trazem valor — a tela diz isso antes de gravar. */
export function comValor(leitura: LeituraHistorico): number {
  return leitura.sessoes.filter((s) => s.valorCentavos !== null).length;
}

export function rotuloEstadoHistorico(e: EstadoHistorico): string {
  if (e === "realizada") return "realizada";
  if (e === "falta") return "falta";
  if (e === "cancelada_cedo") return "cancelada";
  return "cancelada em cima da hora";
}

/** "2026-03-05" → "05/03/2026". */
export function diaBr(dia: string): string {
  const [a, m, d] = dia.split("-");
  return `${d}/${m}/${a}`;
}
