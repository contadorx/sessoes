/**
 * O registro que o CFP pede — do lado do app (PR2, PR6).
 *
 * Duas coisas moram aqui, e as duas espelham SQL:
 *
 * 1. **O prazo de guarda**, gêmeo de `elegiveis_para_eliminacao`. É a única
 *    aritmética desta build, e é a que decide quando um prontuário pode deixar
 *    de existir — errar para menos apaga documento dentro do prazo legal.
 *
 * 2. **As frases dos quatro blocos**, que dizem o que falta sem preencher nada.
 *    O Manual de nov/2025 pede que se evitem espaços em branco no registro; num
 *    prontuário eletrônico isso não vira campo obrigatório (obrigar a escrever
 *    produz texto de fachada), vira **buraco anunciado**: a tela diz o que está
 *    vazio, e quem decide se aquilo precisa ser preenchido é ela.
 */

export type Camada = "prontuario" | "documental";
export type Modalidade = "presencial" | "remoto" | "misto";
export type TipoEncerramento = "alta" | "abandono" | "encaminhamento";

export type BlocoDemanda = {
  texto: string | null;
  objetivos: string | null;
  frequencia: string | null;
  modalidade: Modalidade | null;
  em: string | null;
};

export type EvolucaoLinha = {
  id: string;
  sessao_id: string | null;
  dia: string;
  texto: string;
  camada: Camada;
  criado_em: string;
  editado_em: string | null;
};

export type RegistroDoPaciente = {
  identificacao: { nome: string; nascimento: string | null; documento: string | null; responsaveis: unknown[] };
  demanda: BlocoDemanda | null;
  encerramento: { em: string; tipo: TipoEncerramento } | null;
  registro_id: string | null;
  sem_evolucao: { sessao_id: string; dia: string }[];
  evolucoes: EvolucaoLinha[];
};

// ==================================================== as camadas do CFP

export const MODALIDADES: { valor: Modalidade; rotulo: string }[] = [
  { valor: "presencial", rotulo: "presencial" },
  { valor: "remoto", rotulo: "remoto" },
  { valor: "misto", rotulo: "os dois" },
];

/**
 * As frequências, e por que elas viraram lista.
 *
 * O campo era texto livre de 200 caracteres, e o Leandro pediu seleção. A
 * mudança é boa por um motivo prático — "semanal", "Semanal", "1x semana" e
 * "1 vez por semana" são a mesma coisa escrita de quatro jeitos, e um campo
 * livre garante os quatro na mesma base — e tem um limite que importa mais.
 *
 * **A lista não vai para o banco como `check`.** A coluna `registros.frequencia`
 * continua sendo texto livre, e isto aqui é decisão de tela.
 *
 * O motivo é a fronteira do doc 11 e a linha do doc 07 que a B27 guarda com
 * teste: *o sistema não opina sobre frequência de atendimento*. Uma restrição
 * no banco transformaria esta lista no conjunto das frequências que existem —
 * e quem decide o ritmo de um caso é quem atende, não o software que o
 * registra. Por isso existe "outra", com campo aberto ao lado: a lista é
 * atalho para os casos comuns, e nunca o vocabulário permitido.
 *
 * A ordem é a do que aparece mais, não a do intervalo — quem está preenchendo
 * quer achar "semanal" no primeiro olhar.
 */
export const FREQUENCIAS = [
  "semanal",
  "duas vezes por semana",
  "quinzenal",
  "mensal",
  "sob demanda",
] as const;

/** A frequência já registrada está na lista, ou é texto que veio de antes? */
export function frequenciaNaLista(v: string | null): boolean {
  return v !== null && (FREQUENCIAS as readonly string[]).includes(v);
}

export function rotuloCamada(c: Camada): string {
  return c === "documental" ? "gaveta" : "prontuário";
}

/**
 * O que cada camada significa — em consequência, não em definição.
 *
 * A pergunta que a psicóloga faz na hora de escolher não é "o que é Registro
 * Documental"; é "o paciente vai ver isto?".
 */
export function explicaCamada(c: Camada): string {
  return c === "documental"
    ? "Fica só com você. Não sai na cópia que o paciente pode pedir — é onde entram teste, protocolo e o que não se entrega."
    : "Faz parte do prontuário: se o paciente pedir a cópia dele, isto vai junto. É o direito de acesso da Res. CFP 001/2009.";
}

// ============================================ os quatro blocos, e o que falta

export type Bloco = { n: number; nome: string; completo: boolean; onde: string };

/**
 * Os quatro blocos do conteúdo mínimo, e quais estão vazios.
 *
 * O bloco 1 mora no cadastro e o 3 nas evoluções — a tela mostra os quatro
 * juntos porque é assim que o CFP lê o documento, mesmo que o banco os guarde
 * em três lugares.
 */
export function blocos(r: RegistroDoPaciente): Bloco[] {
  return [
    {
      n: 1,
      nome: "Identificação",
      completo: Boolean(r.identificacao?.nome),
      onde: "cadastro",
    },
    {
      n: 2,
      nome: "Avaliação da demanda",
      completo: Boolean(r.demanda?.texto),
      onde: "aqui",
    },
    {
      n: 3,
      nome: "Evolução do trabalho",
      completo: (r.evolucoes?.length ?? 0) > 0,
      onde: "a cada sessão",
    },
    {
      n: 4,
      nome: "Encaminhamento ou encerramento",
      completo: Boolean(r.encerramento),
      onde: "no fim",
    },
  ];
}

/** "Faltam os blocos 2 e 4." — fato, e nenhuma cobrança. */
export function fraseDosBlocos(r: RegistroDoPaciente): string {
  const faltam = blocos(r).filter((b) => !b.completo);
  if (faltam.length === 0) return "Os quatro blocos do conteúdo mínimo estão preenchidos.";
  if (faltam.length === 4) return "O registro ainda está em branco.";

  const ns = faltam.map((b) => b.n);
  const lista =
    ns.length === 1 ? `o bloco ${ns[0]}` : `os blocos ${ns.slice(0, -1).join(", ")} e ${ns[ns.length - 1]}`;
  return `Falta ${lista}.`;
}

/** As horas que aconteceram e não têm registro. Buraco anunciado, não silencioso. */
export function fraseSemEvolucao(r: RegistroDoPaciente): string {
  const n = r.sem_evolucao?.length ?? 0;
  if (n === 0) return "";
  return n === 1
    ? "Uma sessão aconteceu e ainda não tem evolução escrita."
    : `${n} sessões aconteceram e ainda não têm evolução escrita.`;
}

export function rotuloModalidade(m: Modalidade | null): string {
  if (m === null) return "não registrada";
  return MODALIDADES.find((x) => x.valor === m)?.rotulo ?? m;
}

// ================================================== o prazo de guarda

export type Prazo = {
  guardarAte: string;
  motivo: "ultimo_registro" | "maioridade";
};

/**
 * Até quando guardar — gêmea de `elegiveis_para_eliminacao`.
 *
 * Duas contas, e a maior manda:
 *
 *   · último registro + retenção (a regra geral da Res. 001/2009);
 *   · maioridade + retenção, quando houve menor de idade — o Manual de nov/2025
 *     recomenda guardar até os 18 e olhar as prescrições (civil 10 anos, penal
 *     até 20).
 *
 * Sem a segunda, a ficha de quem foi atendido aos 9 anos ficaria elegível aos
 * 14. A conta é feita em UTC de propósito: prazo de guarda é uma data de
 * calendário, e somar anos com fuso no meio é como se erra por um dia.
 */
export function prazoDeGuarda(
  ultimoRegistro: string,
  nascimento: string | null,
  retencaoAnos = 5,
): Prazo {
  const pelaUltima = somarAnos(ultimoRegistro, retencaoAnos);
  if (!nascimento) return { guardarAte: pelaUltima, motivo: "ultimo_registro" };

  const pelaMaioridade = somarAnos(nascimento, 18 + retencaoAnos);
  return pelaMaioridade > pelaUltima
    ? { guardarAte: pelaMaioridade, motivo: "maioridade" }
    : { guardarAte: pelaUltima, motivo: "ultimo_registro" };
}

/** "2026-09-01" + 5 → "2031-09-01". 29/02 + 1 vira 28/02, como manda o calendário. */
export function somarAnos(dia: string, anos: number): string {
  const [a, m, d] = dia.split("-").map(Number);
  // Dia 0 do mês seguinte é o último dia do mês — é como se descobre que
  // 29/02/2024 + 1 ano não é 29/02/2025.
  const ultimoDoMes = new Date(Date.UTC(a + anos, m, 0)).getUTCDate();
  const dia2 = Math.min(d, ultimoDoMes);
  return `${a + anos}-${String(m).padStart(2, "0")}-${String(dia2).padStart(2, "0")}`;
}

/** O prazo dito com o motivo. Prazo sem motivo não se obedece. */
export function fraseDoPrazo(p: Prazo): string {
  const quando = diaBr(p.guardarAte);
  return p.motivo === "maioridade"
    ? `Guardar até ${quando} — a conta corre da maioridade, e não do último registro, porque o atendimento começou antes dos 18.`
    : `Guardar até ${quando}, contados do último registro.`;
}

/** "2026-03-05" → "05/03/2026". */
export function diaBr(dia: string): string {
  const [a, m, d] = dia.split("-");
  return `${d}/${m}/${a}`;
}

export function rotuloEncerramento(t: TipoEncerramento): string {
  if (t === "alta") return "alta";
  if (t === "abandono") return "abandono";
  return "encaminhamento";
}
