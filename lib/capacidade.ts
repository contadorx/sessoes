import { DIAS } from "@/lib/enquadre";

/**
 * A capacidade declarada — o lado puro.
 *
 * Espelha a aritmética da migração 0055 com os **mesmos valores esperados** da
 * suíte `0055_capacidade_declarada.sql`. Se as duas contas divergirem, uma das
 * duas falha — que é o único jeito de um espelho servir para alguma coisa.
 *
 * A REGRA QUE ATRAVESSA O ARQUIVO
 *
 * **Não existe função aqui que devolva "hora ociosa".** Registro e descanso são
 * capacidade declarada e protegida (fronteira 4 do doc 11), e somá-los ao
 * vendável — ou subtraí-los para "descobrir o desperdício" — é o que faz um
 * painel empurrar psicóloga a preencher todas as horas. `declarado` e
 * `vendavel` são dois números com dois nomes, e a distância entre eles tem
 * dono.
 *
 * E não existe função que **sugira preencher** hora nenhuma. O Código de Ética
 * veda induzir pessoa a recorrer a serviços; uma lista de horários vazios com
 * botão de contato é isso com outro nome.
 */

export type Destino = "atendimento" | "registro" | "descanso";

export const DESTINOS: { valor: Destino; rotulo: string; ajuda: string }[] = [
  {
    valor: "atendimento",
    rotulo: "Atender",
    ajuda: "A hora que pode virar sessão. É esta que entra na conta de ocupação.",
  },
  {
    valor: "registro",
    rotulo: "Registro",
    ajuda:
      "Prontuário, evolução, o que vem depois da sessão. Hora declarada e protegida — nunca aparece como hora vaga.",
  },
  {
    valor: "descanso",
    rotulo: "Descanso",
    ajuda:
      "Almoço, intervalo, respiro entre atendimentos. Também é hora declarada, e também não é hora vaga.",
  },
];

export function rotuloDoDestino(d: string): string {
  return DESTINOS.find((x) => x.valor === d)?.rotulo ?? d;
}

export function eProtegido(d: string): boolean {
  return d === "registro" || d === "descanso";
}

// ============================================================ os minutos

/** "09:00" → 540. Recusa o que não é hora, em vez de devolver NaN silencioso. */
export function emMinutos(hhmm: string): number {
  const m = /^(\d{1,2}):(\d{2})/.exec(hhmm.trim());
  if (!m) throw new Error(`Hora inválida: ${hhmm}`);
  const h = Number(m[1]);
  const min = Number(m[2]);
  if (h > 23 || min > 59) throw new Error(`Hora inválida: ${hhmm}`);
  return h * 60 + min;
}

/** 540 → "09:00". */
export function emHhmm(minutos: number): string {
  const h = Math.floor(minutos / 60);
  const m = minutos % 60;
  return `${String(h).padStart(2, "0")}:${String(m).padStart(2, "0")}`;
}

/**
 * "3h" · "3h30" · "45min" — a forma que a pessoa reconhece.
 *
 * Nunca "3.5h": meia hora escrita como decimal é a forma de quem soma planilha,
 * não a de quem olha a própria semana.
 */
export function duracao(minutos: number): string {
  if (minutos <= 0) return "0";
  const h = Math.floor(minutos / 60);
  const m = minutos % 60;
  if (h === 0) return `${m}min`;
  if (m === 0) return `${h}h`;
  return `${h}h${String(m).padStart(2, "0")}`;
}

// ============================================================ a faixa

export type Faixa = {
  dia: number;
  inicio: string;
  fim: string;
  destino: Destino;
};

export function minutosDaFaixa(f: { inicio: string; fim: string }): number {
  return emMinutos(f.fim) - emMinutos(f.inicio);
}

/**
 * O primeiro problema de uma semana, ou null — para a tela recusar antes de
 * enviar, com a mesma frase que o banco usaria.
 *
 * A ordem das conferências é a ordem em que dá para resolver: a faixa invertida
 * antes da sobreposição, porque quem escreveu 14h–09h ainda não tem duas faixas
 * para comparar.
 */
export function problemaNaSemana(faixas: Faixa[]): string | null {
  for (const f of faixas) {
    let ini: number;
    let fim: number;
    try {
      ini = emMinutos(f.inicio);
      fim = emMinutos(f.fim);
    } catch {
      return "Escreva os horários como 09:00.";
    }
    if (fim <= ini) {
      return `Em ${DIAS[f.dia] ?? "um dos dias"}, a faixa termina antes de começar (${f.inicio}–${f.fim}).`;
    }
  }

  // Invariante 4 da 0055: a mesma hora contada duas vezes infla a capacidade e
  // faz a ocupação parecer menor do que é. Encostar não é sobrepor — 13–14 e
  // 14–15 não dividem minuto nenhum.
  for (let i = 0; i < faixas.length; i++) {
    for (let k = i + 1; k < faixas.length; k++) {
      const a = faixas[i];
      const b = faixas[k];
      if (a.dia !== b.dia) continue;
      if (emMinutos(a.inicio) < emMinutos(b.fim) && emMinutos(b.inicio) < emMinutos(a.fim)) {
        return `Em ${DIAS[a.dia] ?? "um dos dias"}, duas faixas se sobrepõem (${a.inicio}–${a.fim} e ${b.inicio}–${b.fim}). A mesma hora contada duas vezes infla a capacidade.`;
      }
    }
  }

  return null;
}

/** O que a semana soma, por destino. Espelho do que a 0055 grava. */
export function semanaEmMinutos(faixas: Faixa[]): {
  vendavel: number;
  registro: number;
  descanso: number;
  declarado: number;
} {
  let vendavel = 0;
  let registro = 0;
  let descanso = 0;

  for (const f of faixas) {
    const m = minutosDaFaixa(f);
    if (f.destino === "atendimento") vendavel += m;
    else if (f.destino === "registro") registro += m;
    else descanso += m;
  }

  return { vendavel, registro, descanso, declarado: vendavel + registro + descanso };
}

// ============================================================ o período

/** O que `capacidade_vendavel` devolve. */
export type CapacidadeBruta = {
  de: string;
  ate: string;
  dias: number;
  sem_janela: boolean;
  vendavel_min: number;
  registro_min: number;
  descanso_min: number;
  declarado_min: number;
  fora: { ferias: number; feriado: number; bloqueio: number; total: number };
};

export type Capacidade = {
  de: string;
  ate: string;
  dias: number;
  semJanela: boolean;
  vendavel: number;
  registro: number;
  descanso: number;
  declarado: number;
  fora: { ferias: number; feriado: number; bloqueio: number; total: number };
};

export function lerCapacidade(b: CapacidadeBruta): Capacidade {
  const c = {
    de: b.de,
    ate: b.ate,
    dias: b.dias,
    semJanela: b.sem_janela,
    vendavel: b.vendavel_min,
    registro: b.registro_min,
    descanso: b.descanso_min,
    declarado: b.declarado_min,
    fora: b.fora,
  };

  // Recalculado de propósito, como o piso da multa da B24: se o espelho
  // divergir do banco, quem descobre é o teste, e não a psicóloga na tela.
  const soma = c.vendavel + c.registro + c.descanso;
  if (soma !== c.declarado) {
    throw new Error(
      `A capacidade veio incoerente: ${c.vendavel}+${c.registro}+${c.descanso} não é ${c.declarado}`,
    );
  }

  return c;
}

/** O tempo protegido — declarado menos vendável. Tem nome, e o nome não é ócio. */
export function protegido(c: Capacidade): number {
  return c.registro + c.descanso;
}

// ============================================================ as frases

/**
 * A frase do período.
 *
 * Ela conta e não adjetiva: diz quanto foi declarado, quanto é vendável e o que
 * ficou de fora, **com o motivo**. Não há "você poderia atender mais", não há
 * comparação com uma média inventada, e não há sugestão de preencher nada.
 */
export function fraseDaCapacidade(c: Capacidade): string {
  if (c.semJanela) {
    return "Você ainda não declarou seus horários. Sem isso o sistema não tem como dizer quanto da sua capacidade virou receita — e um zero aqui não significa que você não trabalhou.";
  }

  const partes: string[] = [];
  partes.push(`${duracao(c.vendavel)} de atendimento em ${c.dias} dias.`);

  const p = protegido(c);
  if (p > 0) {
    partes.push(
      `Mais ${duracao(p)} que você reservou para registro e descanso — hora declarada, e não hora vaga.`,
    );
  }

  if (c.fora.total > 0) {
    const motivos: string[] = [];
    if (c.fora.ferias > 0) motivos.push(`${duracao(c.fora.ferias)} de férias`);
    if (c.fora.feriado > 0) motivos.push(`${duracao(c.fora.feriado)} de feriado`);
    if (c.fora.bloqueio > 0) motivos.push(`${duracao(c.fora.bloqueio)} bloqueada`);
    partes.push(`${motivos.join(", ")} — fora da conta, e é isso mesmo.`);
  }

  return partes.join(" ");
}

/** A frase da semana declarada, no rodapé do formulário. */
export function fraseDaSemana(faixas: Faixa[]): string {
  const s = semanaEmMinutos(faixas);
  if (s.declarado === 0) return "Nenhuma faixa ainda.";

  const partes = [`${duracao(s.vendavel)} de atendimento por semana`];
  const p = s.registro + s.descanso;
  if (p > 0) partes.push(`${duracao(p)} de registro e descanso`);
  return `${partes.join(" · ")}.`;
}

/** Os dias que têm faixa, na ordem da semana — para a tela agrupar. */
export function porDia(faixas: Faixa[]): { dia: number; nome: string; faixas: Faixa[] }[] {
  return [0, 1, 2, 3, 4, 5, 6]
    .map((d) => ({
      dia: d,
      nome: DIAS[d] ?? String(d),
      faixas: faixas
        .filter((f) => f.dia === d)
        .sort((a, b) => emMinutos(a.inicio) - emMinutos(b.inicio)),
    }))
    .filter((g) => g.faixas.length > 0);
}

/**
 * A semana sugerida para quem está começando, e por que ela tem registro.
 *
 * Um padrão que fosse só atendimento ensinaria, no primeiro minuto de uso, que
 * tempo de prontuário não é tempo de trabalho. O padrão é o lugar mais barato
 * de dizer o contrário — e ele fica visível e editável, não escondido.
 */
export function semanaSugerida(): Faixa[] {
  const uteis = [1, 2, 3, 4, 5];
  const faixas: Faixa[] = [];
  for (const d of uteis) {
    faixas.push({ dia: d, inicio: "09:00", fim: "12:00", destino: "atendimento" });
    faixas.push({ dia: d, inicio: "12:00", fim: "13:00", destino: "descanso" });
    faixas.push({ dia: d, inicio: "13:00", fim: "17:00", destino: "atendimento" });
    faixas.push({ dia: d, inicio: "17:00", fim: "18:00", destino: "registro" });
  }
  return faixas;
}
