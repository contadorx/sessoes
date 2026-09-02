import { describe, it, expect } from "vitest";
import * as negocio from "./negocio";
import {
  porMes,
  reais,
  fraseDaOrigem,
  rotuloEstado,
  margemPct,
  ltv,
  fraseDoLtv,
  custoDeMensagens,
  churnPct,
  margemDaConta,
  sinaisDaConta,
  mesPorExtenso,
  type ContaNoPainel,
  acoesDaAssinatura,
  ROTULO_ACAO_ASSINATURA,
  acoesDaFatura,
  rotuloFatura,
  motivoValido,
  somaDosCustos,
  precoVigente,
  CAUSAS,
  causasParaEscolher,
  eChurn,
  rotuloCausa,
  proximoPassoDaRegua,
  oQueASuspensaoNaoTira,
  fraseDaRetencao,
  causaQueMaisPesa,
  DEGRAUS_DA_REGUA,
  DIAS_PARA_SUSPENDER,
  type Retencao,
} from "./negocio";

const conta = (p: Partial<ContaNoPainel> = {}): ContaNoPainel => ({
  conta_id: "c1",
  nome: "Ana",
  plano: "solo",
  is_teste: false,
  criada_em: "2026-01-10T12:00:00Z",
  estado_assinatura: "ativa",
  valor_centavos: 6900,
  origem_do_valor: "fatura",
  divergencia: null,
  proximo_vencimento: "2026-09-20",
  fatura_vencida: false,
  sessoes_no_mes: 40,
  mensagens_no_mes: 90,
  custo_centavos: 900,
  ultima_atividade: "2026-09-01T12:00:00Z",
  ...p,
});

// ================================================ a fronteira do doc 11

describe("o painel do negócio é ferramenta de suporte, e prova isso pelo que NÃO tem", () => {
  it("não exporta nada que nomeie dado clínico", () => {
    // A fronteira 9: "dado clínico não vai para ambiente de teste, prompt de
    // IA externa sem contrato, ou ferramenta de suporte." Este módulo é a
    // ferramenta de suporte. O teste é de nome porque é o que sobrevive a um
    // acréscimo distraído daqui a seis meses.
    const proibidos = [
      "paciente", "prontuario", "prontuário", "registro", "evolucao", "evolução",
      "anamnese", "nota", "clinic", "diagnost", "medicacao", "medicação",
    ];
    for (const nome of Object.keys(negocio)) {
      for (const p of proibidos) {
        expect(
          nome.toLowerCase().includes(p),
          `o módulo exporta "${nome}" — o painel do negócio não alcança dado clínico (fronteira 9)`,
        ).toBe(false);
      }
    }
  });

  it("o tipo da conta no painel não tem campo de conteúdo clínico", () => {
    // Se um dia alguém acrescentar `ultima_evolucao` ao retorno da RPC, o
    // objeto de teste abaixo passa a ter a chave e este teste cai.
    const chaves = Object.keys(conta());
    for (const k of chaves) {
      expect(k).not.toMatch(/nota|evolu|anamnes|registro|prontu|diagnos/i);
    }
    // conta sessões, não sabe de quem
    expect(chaves).toContain("sessoes_no_mes");
    expect(chaves).not.toContain("pacientes");
  });
});

// ================================================ a aritmética do dinheiro

describe("porMes — gêmeo de valor_da_conta (verificação 19 da suíte)", () => {
  it("mensal é ele mesmo", () => {
    expect(porMes(6900, "mensal")).toBe(6900);
  });

  it("anual de 69000 vira 5750 — o mesmo número da verificação 19", () => {
    expect(porMes(69000, "anual")).toBe(5750);
  });

  it("somar anuidade a mensalidade dobraria o MRR sem ninguém notar", () => {
    // O erro é plausível justamente porque o resultado continua parecendo
    // dinheiro. Doze contas anuais a R$ 690 somariam R$ 8.280 de "MRR".
    const doze = Array.from({ length: 12 }, () => 69000);
    const errado = doze.reduce((a, b) => a + b, 0);
    const certo = doze.reduce((a, b) => a + porMes(b, "anual"), 0);
    expect(errado).toBe(828000);
    expect(certo).toBe(69000);
  });
});

describe("fraseDaOrigem — o número tem procedência", () => {
  it("cada origem tem frase própria", () => {
    const vistas = new Set(
      (["fatura", "assinatura", "tabela", "trial"] as const).map(fraseDaOrigem),
    );
    expect(vistas.size).toBe(4);
  });

  it("o trial diz que não entra no MRR — é o caso que engana", () => {
    expect(fraseDaOrigem("trial")).toMatch(/não entra no MRR/);
  });

  it("nenhuma frase afirma mais do que sabe", () => {
    for (const o of ["fatura", "assinatura", "tabela", "trial"] as const) {
      expect(fraseDaOrigem(o)).not.toMatch(/garantid|certo|confirmad/i);
    }
  });
});

describe("margemPct", () => {
  it("R$ 69 de receita e R$ 10 de custo dá 85,5%", () => {
    expect(margemPct(6900, 1000)).toBe(85.5);
  });

  it("custo maior que receita dá margem negativa, e ela aparece", () => {
    expect(margemPct(6900, 9000)).toBe(-30.4);
  });

  it("sem receita a margem é nula, não zero", () => {
    // "0%" seria uma afirmação falsa sobre um mês em que não houve o que
    // dividir.
    expect(margemPct(0, 500)).toBeNull();
  });
});

describe("ltv — o infinito não vai para a tela", () => {
  it("ticket de 6900 com churn de 5% dá 138000", () => {
    expect(ltv(6900, 5)).toBe(138000);
  });

  it("churn zero devolve nulo, não infinito (verificação 24 da suíte)", () => {
    expect(ltv(6900, 0)).toBeNull();
    expect(ltv(6900, null)).toBeNull();
  });

  it("e a frase explica que é desconhecido, não infinito", () => {
    expect(fraseDoLtv(null)).toMatch(/não é infinito, é desconhecido/);
    expect(fraseDoLtv(null)).not.toMatch(/∞/);
  });
});

describe("custoDeMensagens — milésimos de centavo existem por um motivo", () => {
  it("uma mensagem de WhatsApp a 4500 milésimos custa 4 centavos", () => {
    // O mesmo número da verificação 20 da suíte.
    expect(custoDeMensagens(1, 4500)).toBe(4);
  });

  it("mil e-mails a 200 milésimos custam 200 centavos — e não zero", () => {
    // Se o preço fosse guardado em centavos, um e-mail custaria 0 e mil
    // e-mails custariam nada. É por isso que a coluna é em milésimos.
    expect(custoDeMensagens(1000, 200)).toBe(200);
    expect(custoDeMensagens(1, 200)).toBe(0);
  });

  it("225 mensagens de WhatsApp por mês dão ~R$ 10 — o número do doc 10", () => {
    expect(custoDeMensagens(225, 4500)).toBe(1012);
  });
});

describe("churnPct — o denominador é a base do início", () => {
  it("uma saída em vinte contas é 5%", () => {
    expect(churnPct(20, 1)).toBe(5);
  });

  it("base zero devolve nulo", () => {
    expect(churnPct(0, 0)).toBeNull();
  });

  it("a base do início e a do fim dão números diferentes — e é por isso que importa", () => {
    // Doze contas, uma sai. Pela definição certa: 1/12 = 8,3%.
    // Pela dos dois apps lidos (cancelados ÷ ativos restantes + cancelados):
    // ainda 1/12. Mas quando entram três no mês, o denominador deles vira 15
    // e o churn "melhora" para 6,7% sem ninguém ter ficado.
    expect(churnPct(12, 1)).toBe(8.3);
    expect(churnPct(15, 1)).toBe(6.7);
  });
});

describe("margemDaConta — a subtração que decide o preço", () => {
  it("Solo a R$ 69 com R$ 10 de custo sobra R$ 59", () => {
    const m = margemDaConta(6900, 1000);
    expect(m.sobra).toBe(5900);
    expect(m.pct).toBe(85.5);
  });

  it("uma conta grátis que manda mensagem tem sobra negativa", () => {
    // 45 mensagens/mês numa conta gratuita ≈ R$ 2 do nosso bolso. É o número
    // do doc 10 e o motivo de o teto de mensagens existir — na OP2, junto com
    // quem o aplica.
    const m = margemDaConta(0, 200);
    expect(m.sobra).toBe(-200);
    expect(m.pct).toBeNull();
  });
});

// ================================================ os sinais

describe("sinaisDaConta — relata fatos, não conclui sobre pessoas", () => {
  const hoje = new Date("2026-09-01T12:00:00Z");

  it("conta saudável não gera sinal", () => {
    expect(sinaisDaConta(conta(), hoje)).toHaveLength(0);
  });

  it("fatura vencida é grave", () => {
    const s = sinaisDaConta(conta({ fatura_vencida: true }), hoje);
    expect(s.some((x) => x.grave && /vencida/.test(x.texto))).toBe(true);
  });

  it("sem sessão há 40 dias é grave; há 20, é só aviso", () => {
    const longe = sinaisDaConta(
      conta({ ultima_atividade: "2026-07-23T12:00:00Z" }), hoje);
    expect(longe.some((x) => x.grave && /sem sessão/.test(x.texto))).toBe(true);

    const perto = sinaisDaConta(
      conta({ ultima_atividade: "2026-08-17T12:00:00Z" }), hoje);
    expect(perto.some((x) => !x.grave && /sem sessão/.test(x.texto))).toBe(true);
  });

  it("a divergência de valor vira sinal em vez de sumir", () => {
    const s = sinaisDaConta(
      conta({ divergencia: "a assinatura diz 5000 e a tabela do plano diz 6900" }), hoje);
    expect(s.some((x) => /5000/.test(x.texto))).toBe(true);
  });

  it("custar mais do que paga é sinal numa conta paga, e NÃO numa grátis", () => {
    // Numa conta gratuita o custo exceder a receita é o modelo, não um
    // problema — e um painel que gritasse a cada conta grátis viraria ruído
    // que se aprende a ignorar.
    const paga = sinaisDaConta(conta({ valor_centavos: 6900, custo_centavos: 9000 }), hoje);
    expect(paga.some((x) => /custa mais/.test(x.texto))).toBe(true);

    const gratis = sinaisDaConta(conta({ valor_centavos: 0, custo_centavos: 900 }), hoje);
    expect(gratis.some((x) => /custa mais/.test(x.texto))).toBe(false);
  });

  it("nenhum sinal julga a pessoa — fala do estado da conta", () => {
    const casos = [
      conta({ fatura_vencida: true, ultima_atividade: "2026-06-01T12:00:00Z" }),
      conta({ valor_centavos: 0, custo_centavos: 5000, ultima_atividade: null }),
    ];
    for (const c of casos) {
      for (const s of sinaisDaConta(c, hoje)) {
        expect(s.texto).not.toMatch(
          /desleixad|relaxad|ruim|fraca|problemática|desistiu|abandonou|não se importa/i,
        );
      }
    }
  });
});

describe("rótulos e datas", () => {
  it("todo estado tem rótulo em português", () => {
    const estados = ["ativa", "trial", "em_atraso", "cancelada", "sem_assinatura"] as const;
    for (const e of estados) {
      expect(rotuloEstado(e)).toMatch(/^[a-zç ]+$/);
    }
    expect(rotuloEstado("trial")).toBe("em teste");
  });

  it("mesPorExtenso", () => {
    expect(mesPorExtenso("2026-09-01")).toBe("setembro de 2026");
    expect(mesPorExtenso("2026-03-01T00:00:00Z")).toBe("março de 2026");
  });

  it("reais formata sem asserção de string literal", () => {
    // `formatar` usa U+00A0 depois do "R$" — asserção literal quebra por um
    // caractere invisível. Lição antiga da casa.
    expect(reais(6900)).toContain("69,00");
    expect(reais(0)).toContain("0,00");
  });
});

// ============================================ a operação (OP5)

describe("acoesDaAssinatura — a tela não oferece o que o banco vai recusar", () => {
  it("sem assinatura, só abrir", () => {
    expect(acoesDaAssinatura("sem_assinatura")).toEqual(["abrir"]);
  });

  it("cancelada, só abrir outra — cancelada não revive", () => {
    // O gatilho `assinatura_carimba` levanta exceção em cancelada → ativa
    // desde a 0045. Oferecer "reativar" seria um botão que só sabe falhar.
    expect(acoesDaAssinatura("cancelada")).toEqual(["abrir"]);
    expect(acoesDaAssinatura("cancelada")).not.toContain("mudar_plano");
  });

  it("viva, nunca oferece abrir — o índice barra a segunda", () => {
    for (const e of ["trial", "ativa", "em_atraso"] as const) {
      expect(acoesDaAssinatura(e), e).not.toContain("abrir");
      expect(acoesDaAssinatura(e)).toContain("cancelar");
      expect(acoesDaAssinatura(e)).toContain("emitir_fatura");
    }
  });

  it("toda ação tem rótulo", () => {
    for (const a of acoesDaAssinatura("ativa")) {
      expect(ROTULO_ACAO_ASSINATURA[a].length).toBeGreaterThan(3);
    }
  });
});

describe("acoesDaFatura — paga não se cancela, estorna", () => {
  it("pendente e vencida: baixar ou cancelar", () => {
    expect(acoesDaFatura("pendente")).toEqual(["baixar", "cancelar"]);
    expect(acoesDaFatura("vencida")).toEqual(["baixar", "cancelar"]);
  });

  it("paga só estorna — e nunca oferece cancelar", () => {
    // Cancelar uma fatura paga apagaria receita que entrou. O caminho honesto
    // é o estorno, que registra que o dinheiro voltou.
    expect(acoesDaFatura("paga")).toEqual(["estornar"]);
    expect(acoesDaFatura("paga")).not.toContain("cancelar");
  });

  it("o que saiu do fluxo não volta", () => {
    expect(acoesDaFatura("cancelada")).toEqual([]);
    expect(acoesDaFatura("estornada")).toEqual([]);
  });

  it("todo estado tem rótulo em português", () => {
    for (const e of ["pendente", "paga", "vencida", "cancelada", "estornada"] as const) {
      expect(rotuloFatura(e)).not.toMatch(/_/);
    }
  });
});

describe("motivoValido — o churn precisa de causa", () => {
  it("menos de cinco caracteres não passa, aqui e no banco", () => {
    expect(motivoValido("")).toBe(false);
    expect(motivoValido("caro")).toBe(false);
    expect(motivoValido("   ok    ")).toBe(false);
  });

  it("cinco passa", () => {
    expect(motivoValido("achou caro")).toBe(true);
  });
});

describe("somaDosCustos e precoVigente", () => {
  it("soma em inteiro — centavo não passa por float", () => {
    expect(somaDosCustos([{ centavos: 12000 }, { centavos: 3390 }, { centavos: 1 }])).toBe(15391);
    expect(somaDosCustos([])).toBe(0);
  });

  it("o preço vigente é o mais recente que já começou", () => {
    const p = [
      { vigencia_inicio: "2026-01-01", centavos_milesimos: 5000 },
      { vigencia_inicio: "2026-06-01", centavos_milesimos: 7000 },
      { vigencia_inicio: "2027-01-01", centavos_milesimos: 9000 },
    ];
    expect(precoVigente(p, "2026-03-15")).toBe(5000);
    expect(precoVigente(p, "2026-06-01")).toBe(7000);
    expect(precoVigente(p, "2026-12-31")).toBe(7000);
  });

  it("sem preço declarado devolve nulo, e nulo NÃO é zero", () => {
    // Zero diria que a mensagem foi de graça, e o painel mostraria margem
    // cheia num mês em que eu só esqueci de cadastrar o preço. É a mesma
    // família do LTV infinito: ausência de dado vestida de resultado.
    expect(precoVigente([{ vigencia_inicio: "2026-06-01", centavos_milesimos: 7000 }], "2026-01-01")).toBeNull();
    expect(precoVigente([], "2026-01-01")).toBeNull();
  });
});

// =====================================================================
// OP6 · a régua da assinatura e o churn com causa
// =====================================================================

describe("a causa do cancelamento", () => {
  it("troca de plano não é churn — é o defeito que a 0052 encontrou", () => {
    // `mudar_plano` cancela a assinatura antiga para preservar a faixa
    // anterior no histórico, e o churn contava essa linha. Uma promoção de
    // Solo para Pro registrava uma perda.
    expect(eChurn("mudanca_de_plano")).toBe(false);
  });

  it("mas inadimplência é", () => {
    // Perder por falta de pagamento é perder. Separar as duas é o que responde
    // a pergunta que muda o roadmap: perco gente ou perco pagamento?
    expect(eChurn("inadimplencia")).toBe(true);
  });

  it("a lista de escolher não oferece troca de plano", () => {
    // Quem grava essa causa é a função `mudar_plano`, sozinha. Oferecê-la num
    // formulário de cancelamento seria convidar a marcar saída como troca — e o
    // churn viraria o número que eu quisesse que ele fosse.
    const valores = causasParaEscolher().map((c) => c.valor);
    expect(valores).not.toContain("mudanca_de_plano");
    expect(valores).toContain("preco");
    expect(valores).toHaveLength(CAUSAS.length - 1);
  });

  it("toda causa explica o que ela significa em consequência", () => {
    for (const c of CAUSAS) {
      expect(c.explica.length, c.valor).toBeGreaterThan(30);
      expect(c.rotulo.length, c.valor).toBeGreaterThan(3);
    }
  });

  it("nenhum rótulo culpa a cliente", () => {
    // "desistiu", "abandonou", "sumiu" são leitura, não fato — e a lista é o
    // que eu vou ler daqui a um ano tentando entender o que aconteceu.
    for (const c of CAUSAS) {
      expect(c.rotulo).not.toMatch(/desist|abandon|sumiu|preguiç/i);
    }
  });

  it("o rótulo é encontrável pela chave", () => {
    expect(rotuloCausa("preco")).toBe("achou caro");
    expect(rotuloCausa("parou_de_atender")).toBe("parou de atender");
  });
});

describe("o próximo passo da régua", () => {
  it("diz o que vem, não o que passou", () => {
    // Quem olha o painel quer saber o que vai acontecer com aquela conta.
    expect(proximoPassoDaRegua(1)).toMatch(/próximo aviso em 2 dias/);
    expect(proximoPassoDaRegua(4)).toMatch(/próximo aviso em 6 dias/);
    expect(proximoPassoDaRegua(11)).toMatch(/próximo aviso em 9 dias/);
  });

  it("depois do último degrau, só resta a pausa", () => {
    expect(proximoPassoDaRegua(21)).toBe("pausa em 4 dias");
    expect(proximoPassoDaRegua(24)).toBe("pausa em 1 dia");
  });

  it("e depois dela, diz que já pausou e que a conta está no Grátis", () => {
    expect(proximoPassoDaRegua(25)).toMatch(/já pausou/);
    expect(proximoPassoDaRegua(90)).toMatch(/Grátis/);
  });

  it("os degraus e a suspensão batem com o banco", () => {
    expect([...DEGRAUS_DA_REGUA]).toEqual([3, 10, 20]);
    expect(DIAS_PARA_SUSPENDER).toBe(25);
    // O último aviso vem antes da pausa. Conta que pausa sem ter sido avisada
    // é a versão comercial do 307 mudo do proxy.
    expect(DEGRAUS_DA_REGUA[DEGRAUS_DA_REGUA.length - 1]).toBeLessThan(DIAS_PARA_SUSPENDER);
  });

  it("a frase da suspensão diz o que ela NÃO tira", () => {
    const f = oQueASuspensaoNaoTira();
    expect(f).toMatch(/prontuário/);
    expect(f).toMatch(/exportação/);
    expect(f).toMatch(/Grátis/);
  });
});

describe("a retenção", () => {
  const VAZIA: Retencao = {
    desde: "2026-01-01",
    quantas: 0,
    mrr_perdido_centavos: 0,
    dias_de_vida_mediana: null,
    por_causa: [],
    lista: [],
  };

  it("com ninguém saindo, a frase não vira comemoração", () => {
    // Zero churn com doze contas é base pequena, não resultado. É a mesma
    // disciplina do LTV que devolve nulo em vez de infinito.
    expect(fraseDaRetencao(VAZIA)).toMatch(/base pequena/);
  });

  it("com saídas, diz quantas e a mediana", () => {
    const r: Retencao = { ...VAZIA, quantas: 3, dias_de_vida_mediana: 92 };
    expect(fraseDaRetencao(r)).toMatch(/3 contas saíram/);
    expect(fraseDaRetencao(r)).toMatch(/92 dias/);
  });

  it("uma só sai no singular", () => {
    expect(fraseDaRetencao({ ...VAZIA, quantas: 1 })).toMatch(/1 conta saiu/);
  });

  it("a causa que mais pesa, e null no empate", () => {
    const base = { mrr_perdido_centavos: 0 };
    expect(
      causaQueMaisPesa({
        ...VAZIA,
        quantas: 3,
        por_causa: [
          { causa: "preco", quantas: 2, ...base },
          { causa: "nao_usou", quantas: 1, ...base },
        ],
      }),
    ).toBe("preco");

    // Empate não indica direção nenhuma, e apontar um dos dois seria inventar
    // um sinal onde há ruído.
    expect(
      causaQueMaisPesa({
        ...VAZIA,
        quantas: 2,
        por_causa: [
          { causa: "preco", quantas: 1, ...base },
          { causa: "nao_usou", quantas: 1, ...base },
        ],
      }),
    ).toBeNull();

    expect(causaQueMaisPesa(VAZIA)).toBeNull();
  });
});

describe("a assinatura suspensa continua viva", () => {
  it("e por isso oferece as mesmas ações de uma em atraso", () => {
    // `assinatura_viva_da_conta` (0052d) trata suspensa como viva: ela tem
    // dívida pendurada e volta ao ar quando alguém paga.
    expect(acoesDaAssinatura("suspensa")).toEqual(acoesDaAssinatura("em_atraso"));
  });

  it("e não oferece 'abrir', que é o que criaria a segunda", () => {
    expect(acoesDaAssinatura("suspensa")).not.toContain("abrir");
  });

  it("o rótulo dela existe e é curto", () => {
    expect(rotuloEstado("suspensa")).toBe("suspensa");
  });
});
