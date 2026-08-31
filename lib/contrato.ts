import { formatar } from "@/lib/dinheiro";
import { rotuloHorario, rotuloPolitica } from "@/lib/enquadre";

/**
 * O contrato terapêutico — o lado puro.
 *
 * Aqui mora **só a pré-visualização**. O texto que vale é montado no banco, na
 * `montar_contrato` da 0031, porque é o banco que o congela: se a string viesse
 * pronta do navegador, "o contrato aceito" seria o que o navegador disse que
 * era, e a prova valeria o que vale um print.
 *
 * Isso obriga a duas implementações da mesma substituição. Duas implementações
 * divergem caladas — então cada uma tem, na sua suíte, **os mesmos casos com as
 * mesmas strings esperadas**, inclusive o espaço fino (U+00A0) que o Intl põe
 * depois do "R$" e que ninguém enxerga num diff.
 */

/** Os marcadores, com o que cada um vira. É esta lista que a tela mostra. */
export const MARCADORES = [
  { chave: "{{nome}}", vira: "o nome do paciente" },
  { chave: "{{profissional}}", vira: "como você assina" },
  { chave: "{{crp}}", vira: "seu CRP" },
  { chave: "{{horario}}", vira: "o dia e a hora combinados" },
  { chave: "{{duracao}}", vira: "a duração do encontro" },
  { chave: "{{valor}}", vira: "o valor combinado" },
  { chave: "{{politica}}", vira: "a regra de desmarcação" },
  { chave: "{{cidade}}", vira: "a cidade da conta" },
  { chave: "{{data}}", vira: "a data em que o link é preparado" },
] as const;

/**
 * Os dois que **não** são opcionais.
 *
 * Portão ético da fase 2, no doc 07: *"política de falta visível ao paciente no
 * contrato aceito"*. O banco recusa publicar sem eles; aqui a checagem existe
 * só para a pessoa descobrir enquanto escreve, e não depois de clicar em
 * publicar. A tranca é a de lá — esta é a cortesia.
 */
export const OBRIGATORIOS = ["{{politica}}", "{{valor}}"] as const;

export type DadosDoContrato = {
  nome: string;
  profissional: string;
  crp: string;
  diaSemana: number;
  hora: string;
  duracaoMin: number;
  /** Em centavos inteiros, como em toda a base. */
  valorCentavos: number;
  politicaHoras: number;
  politicaPercentual: number;
  cidade: string;
  /** ISO curta (AAAA-MM-DD). Vira DD/MM/AAAA, como no banco. */
  data: string;
};

/** Espelho de `montar_contrato`. Só para a pré-visualização. */
export function montar(corpo: string, d: DadosDoContrato): string {
  const troca: Record<string, string> = {
    "{{nome}}": d.nome,
    "{{profissional}}": d.profissional.trim() || "—",
    "{{crp}}": d.crp.trim() || "—",
    "{{horario}}": rotuloHorario(d.diaSemana, d.hora),
    "{{duracao}}": `${d.duracaoMin} minutos`,
    "{{valor}}": formatar(d.valorCentavos),
    "{{politica}}": rotuloPolitica({
      horas: d.politicaHoras,
      percentual: d.politicaPercentual,
    }),
    "{{cidade}}": d.cidade.trim() || "—",
    "{{data}}": diaBrasileiro(d.data),
  };

  let t = corpo;
  for (const [chave, valor] of Object.entries(troca)) {
    t = t.split(chave).join(valor);
  }
  return t;
}

/** "2026-03-03" → "03/03/2026". Sem `new Date`: data civil não tem fuso. */
export function diaBrasileiro(iso: string): string {
  const m = /^(\d{4})-(\d{2})-(\d{2})/.exec(iso.trim());
  if (!m) return iso;
  return `${m[3]}/${m[2]}/${m[1]}`;
}

/** Quais obrigatórios faltam. Vazio = pode publicar. */
export function faltamObrigatorios(corpo: string): string[] {
  return OBRIGATORIOS.filter((m) => !corpo.includes(m));
}

/** Marcadores escritos no texto que o sistema não conhece — erro de digitação. */
export function marcadoresDesconhecidos(corpo: string): string[] {
  const conhecidos = new Set<string>(MARCADORES.map((m) => m.chave));
  const achados = corpo.match(/\{\{[^}]*\}\}/g) ?? [];
  return [...new Set(achados.filter((a) => !conhecidos.has(a)))];
}

export type EstadoDoAceite =
  | "sem_contrato"
  | "sem_combinado"
  | "nunca_preparado"
  | "pendente"
  | "expirado"
  | "aceito"
  | "revogado";

export type AceiteLinha = {
  id: string;
  token: string;
  aceito_em: string | null;
  aceito_por: string | null;
  parentesco: string | null;
  origem: string | null;
  criado_em: string;
  expira_em: string;
  revogado_em: string | null;
  retrato: { contrato_versao?: number | string; valor?: string | number } | null;
};

export function estadoDoAceite(
  a: AceiteLinha | null,
  agora: Date = new Date(),
): EstadoDoAceite {
  if (!a) return "nunca_preparado";
  if (a.revogado_em) return "revogado";
  if (a.aceito_em) return "aceito";
  if (new Date(a.expira_em) < agora) return "expirado";
  return "pendente";
}

/**
 * A frase da ficha.
 *
 * Diz o que aconteceu e **não** diz o que fazer a respeito: um combinado sem
 * aceite não é uma pendência do sistema, é uma escolha dela. Transformar isso
 * num alerta vermelho seria o produto opinando sobre a condução de uma relação
 * clínica — a fronteira do doc 11 que não se atravessa nem a pedido.
 */
export function rotuloDoAceite(e: EstadoDoAceite): string {
  return {
    sem_contrato: "Você ainda não escreveu o texto do combinado.",
    sem_combinado: "Sem combinado aberto — o aceite é sempre de um combinado.",
    nunca_preparado: "Ainda não foi enviado para aceite.",
    pendente: "Enviado, aguardando o aceite.",
    expirado: "O link venceu. Prepare outro quando quiser.",
    aceito: "Aceito.",
    revogado: "Aceite revogado. O que já foi cobrado sob ele continua registrado.",
  }[e];
}

/**
 * O texto inicial.
 *
 * Existe porque um campo em branco vira um contrato que nunca é escrito — e
 * porque a política de falta precisa estar no papel antes da primeira cobrança
 * automática. É um **ponto de partida**, não um modelo jurídico: quem responde
 * pelo que está escrito é ela, e a tela diz isso ao lado do botão.
 *
 * O que está aqui de propósito: o enquadre em números, a regra de desmarcação
 * pelo marcador (nunca escrita à mão, que é como ela desatualiza), o sigilo com
 * as exceções que o CFP prevê, a guarda do registro, e o direito de encerrar de
 * qualquer lado. O que não está: cláusula de multa por rescisão, prazo mínimo
 * de permanência, autorização de imagem, qualquer coisa que transforme um
 * acompanhamento em fidelidade contratual.
 */
export const TEXTO_PADRAO = `Combinado de atendimento

Entre {{profissional}}, CRP {{crp}}, e {{nome}}.

**Os encontros.** Acontecem {{horario}}, com duração de {{duracao}}. O horário é reservado para você: enquanto este combinado valer, ele não é oferecido a mais ninguém.

**O valor.** Cada encontro custa {{valor}}. Qualquer mudança de valor é conversada antes e vira um combinado novo — nunca um reajuste silencioso.

**Desmarcar.** {{politica}}. A regra vale para os dois lados: se eu precisar desmarcar dentro do mesmo prazo, o encontro seguinte não é cobrado.

**Faltas e imprevistos.** Avisar cedo não precisa de justificativa. Se algo acontecer e você quiser conversar sobre a cobrança, é só dizer — a regra existe para não termos de negociar toda vez, não para impedir a conversa.

**Sigilo.** O que você me conta é sigiloso. As exceções são as previstas no Código de Ética Profissional do Psicólogo: risco à vida ou à integridade de alguém, e determinação judicial. Se alguma delas acontecer, eu falo com você antes, sempre que for possível.

**Seu registro.** Guardo um registro do acompanhamento, como o Conselho exige, com acesso restrito. Ele é seu: você pode pedir uma cópia quando quiser.

**Encerrar.** Qualquer um de nós pode encerrar o acompanhamento. Peço só que o encerramento seja conversado numa sessão — não por não poder ser de outro jeito, mas porque terminar bem faz parte do trabalho.

Combinado a partir de {{data}}, em {{cidade}}.`;
