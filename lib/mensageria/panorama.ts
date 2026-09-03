import { cronSuspeito } from "./entrega";

/**
 * O painel do canal — o lado puro. (B56)
 *
 * **Um sistema de mensagens falha calado.** Não há tela vermelha, não há
 * exceção, não há linha de log: a mensagem simplesmente não chega, e quem
 * descobre é a paciente que não foi avisada. Cada silêncio tem um sintoma
 * diferente, e é por isso que este arquivo é uma lista de silêncios e não um
 * gráfico de volume.
 *
 * A ordem das perguntas é a ordem da urgência, e ela não é alfabética:
 *
 *   **cego**      — o instrumento não está medindo. Nada do que o painel diz
 *                   sobre entrega vale enquanto isto durar.
 *   **degradado** — está medindo, e o que mede está ruim.
 *   **parado**    — nem está rodando.
 *
 * Cego vem primeiro porque **envenena o resto**: sem confirmação nenhuma, a
 * varredura não conclui perda (é a trava de `instrumentoConfiavel`), então
 * "zero perdidas" no painel não significa "está tudo bem" — significa "não sei".
 * Mostrar isso como saúde seria a mesma mentira que a B43 e a B50 consertaram
 * em outras telas.
 *
 * Cada achado diz **o que fazer**, e não só o que houve. Linha de painel que
 * não sugere ação é enfeite — e enfeite em tela de operação é o que faz ninguém
 * abrir a tela de novo.
 */

export type Gravidade = "cego" | "degradado" | "parado" | "quieto";

export type Achado = {
  gravidade: Gravidade;
  titulo: string;
  frase: string;
};

export type Panorama = {
  em: string;
  varreduras: { nome: string; em: string; cega: boolean; detalhe?: unknown }[];
  disjuntores: { canal: string; conta_id: string | null; estado: string; motivo: string; desde: string }[];
  saida: { canal: string; estado: string; n: number }[];
  na_mao_dela: { conta_id: string; n: number; mais_antiga: string }[];
  entrada: { recebidas_24h: number; nao_entendidas_24h: number };
  /** A cascata configurada, por classe e em ordem (B57). */
  rota?: { classe: string; posicao: number; canal: string; motivo: string | null }[];
  /** O preço vigente de cada canal, em milésimos de centavo. */
  precos?: { canal: string; centavos_milesimos: number; fonte: string | null }[];
};

const ORDEM: Record<Gravidade, number> = { cego: 0, degradado: 1, parado: 2, quieto: 3 };

/**
 * "mensagem" faz plural em **-ns**, não em -s.
 *
 * O `${n > 1 ? "s" : ""}` que se usa para "conta" produz *mensagems* aqui, e o
 * teste pegou isso antes da tela. Vale para toda palavra terminada em -m: nuvem,
 * viagem, garagem.
 */
function plural(n: number, singular: string): string {
  if (n === 1) return singular;
  return singular.endsWith("m") ? `${singular.slice(0, -1)}ns` : `${singular}s`;
}

function soma(saida: Panorama["saida"], estado: string): number {
  return saida.filter((s) => s.estado === estado).reduce((t, s) => t + s.n, 0);
}

export function lerPanorama(p: Panorama, agora = new Date()): Achado[] {
  const achados: Achado[] = [];

  // ---------------------------------------------------------------- cego
  for (const v of p.varreduras) {
    if (!v.cega) continue;
    achados.push({
      gravidade: "cego",
      titulo: `${v.nome} está cega`,
      frase:
        "Saíram mensagens e nenhuma confirmou entrega. Isso é o webhook mudo, " +
        "não perda: enquanto durar, ninguém é marcado como perdido e o disjuntor " +
        "não se mexe. Confira o segredo e a URL cadastrada no provedor.",
    });
  }

  // -------------------------------------------------------------- parado
  //
  // Se o cron morrer, nada muda em lugar nenhum — não há erro, não há estado
  // novo, a ausência é o próprio sintoma. Só a data da última passada denuncia.
  if (p.varreduras.length === 0) {
    achados.push({
      gravidade: "parado",
      titulo: "a varredura da entrega nunca rodou",
      frase:
        "Não há batimento nenhum registrado. Ou o cron não está agendado, ou " +
        "nunca chegou a passar — e enquanto isso nada é conferido nem reenviado.",
    });
  } else {
    for (const v of p.varreduras) {
      if (!cronSuspeito(v.em, agora)) continue;
      achados.push({
        gravidade: "parado",
        titulo: `${v.nome} não passa há mais de três ciclos`,
        frase: `A última passada foi em ${v.em}. Sem ela nada é conferido nem reenviado, e nada mais denuncia isso.`,
      });
    }
  }

  // ----------------------------------------------------------- degradado
  for (const d of p.disjuntores) {
    if (d.estado !== "aberto") continue;
    achados.push({
      gravidade: "degradado",
      titulo: `o disjuntor do ${d.canal} está aberto`,
      frase:
        `${d.motivo}. Desde ${d.desde}. Ele só fecha com uma amostra recente sem ` +
        "perda nenhuma — nunca pelo relógio —, e o tráfego está saindo pelo caminho de queda.",
    });
  }

  const barradas = soma(p.saida, "barrada_no_teto");
  if (barradas > 0) {
    achados.push({
      gravidade: "degradado",
      titulo: `${barradas} ${plural(barradas, "mensagem")} ${plural(barradas, "barrada")} no teto`,
      frase:
        "Bateu num freio técnico ou na cota do plano. É o caminho mais silencioso " +
        "de todos: a fila continua andando e ninguém recebe nada.",
    });
  }

  const perdidas = soma(p.saida, "perdida");
  if (perdidas > 0) {
    achados.push({
      gravidade: "degradado",
      titulo: `${perdidas} sem confirmação além da janela`,
      frase: "O provedor aceitou e não confirmou entrega. Estão na fila de reenvio.",
    });
  }

  const presas = soma(p.saida, "enviando");
  if (presas > 0) {
    achados.push({
      gravidade: "degradado",
      titulo: `${presas} ${plural(presas, "presa")} em envio`,
      frase:
        "Reservadas e não resolvidas. Processo morto no meio deixa exatamente " +
        "este rastro, e o destravamento roda junto com o despacho.",
    });
  }

  const { recebidas_24h: recebidas, nao_entendidas_24h: naoEntendidas } = p.entrada;
  if (recebidas > 0 && naoEntendidas / recebidas >= 0.2) {
    achados.push({
      gravidade: "degradado",
      titulo: `${naoEntendidas} de ${recebidas} respostas não foram entendidas`,
      frase:
        "A paciente respondeu e o sistema não soube o que fazer com o texto. " +
        "Para ela, a fila parece quebrada — e do nosso lado tudo parece bem.",
    });
  }

  // A cascata sem degrau nenhum não é "econômica": é mensagem que só tem um
  // caminho, e vai para a mão dela assim que ele falhar.
  if (p.rota && p.rota.length === 0) {
    achados.push({
      gravidade: "degradado",
      titulo: "nenhuma cascata configurada",
      frase:
        "Sem degrau em `rota_do_canal`, toda mensagem tem um caminho só: falhou, " +
        "espera o dedo dela. É configuração ausente, não economia.",
    });
  }

  // -------------------------------------------------------------- quieto
  //
  // Mensagem na mão dela **não é defeito**: é o desenho enquanto não há
  // provedor. Aparece porque um monte parado há dias é justamente o que ninguém
  // vê — e some quando não há nenhuma.
  const naMao = p.na_mao_dela.reduce((t, c) => t + c.n, 0);
  if (naMao > 0) {
    achados.push({
      gravidade: "quieto",
      titulo: `${naMao} ${plural(naMao, "mensagem")} esperando o dedo dela`,
      frase:
        `Em ${p.na_mao_dela.length} conta${p.na_mao_dela.length > 1 ? "s" : ""}. ` +
        "Sem provedor configurado é o caminho normal, e não uma falha — o que " +
        "importa é há quanto tempo a mais antiga está lá.",
    });
  }

  return achados.sort((a, b) => ORDEM[a.gravidade] - ORDEM[b.gravidade]);
}

/** A frase de topo. Vazia quando não há nada — silêncio bom também é resposta. */
export function fraseDoPanorama(achados: Achado[]): string {
  const cegos = achados.filter((a) => a.gravidade === "cego").length;
  const parados = achados.filter((a) => a.gravidade === "parado").length;
  const degradados = achados.filter((a) => a.gravidade === "degradado").length;

  if (cegos > 0) {
    return "O instrumento não está medindo. Nada do que este painel diz sobre entrega vale enquanto isso durar.";
  }
  if (parados > 0) return "A varredura não está passando. Nada é conferido nem reenviado.";
  if (degradados > 0) {
    return `${degradados} ${plural(degradados, "coisa")} para olhar. O instrumento está medindo.`;
  }
  return "";
}
