import { describe, it, expect } from "vitest";
import {
  eixoAgenda,
  rotuloAgenda,
  rotuloFinanceiro,
  eHoraPerdida,
  tituloDaCausa,
  explicaCausa,
  acaoDaCausa,
  lerLivro,
  causasComPeso,
  fraseDaReceita,
  fraseDaCompletude,
  fraseDoUso,
  type LivroBruto,
  type Causa,
} from "@/lib/livro";
import * as modulo from "@/lib/livro";
import { formatar } from "@/lib/dinheiro";

/**
 * Os números são **os mesmos da suíte SQL `0056_livro_razao.sql`**: a hora
 * reposta de R$ 200 e a hora nova de R$ 200, que somam **uma** receita de 200 e
 * **duas** horas de capacidade. Se as duas contas divergirem, uma das duas
 * falha.
 *
 * O teste que decide o arquivo é o do grupo "as duas fronteiras": a sétima
 * causa não pode ganhar ação, e nada aqui pode somar a hora reposta com a hora
 * que a repôs.
 */

const TODAS: Causa[] = [
  "falta_sem_cobranca",
  "falta_com_cobranca",
  "cancelada_nao_revendida",
  "reposta",
  "atendida_nao_recebida",
  "abaixo_do_valor",
  "hora_nunca_vendida",
];

const BRUTO: LivroBruto = {
  de: "2026-08-26",
  ate: "2026-08-26",
  capacidade: {
    de: "2026-08-26",
    ate: "2026-08-26",
    dias: 1,
    sem_janela: false,
    vendavel_min: 180,
    registro_min: 60,
    descanso_min: 60,
    declarado_min: 300,
    fora: { ferias: 0, feriado: 0, bloqueio: 0, total: 0 },
  },
  horas: { realizada: 1, cancelada: 1 },
  minutos_usados: 50,
  receita_reconhecida: "200.00",
  causas: [
    { causa: "falta_sem_cobranca", n: 0, valor: "0", acao: "propor_cobranca" },
    { causa: "falta_com_cobranca", n: 0, valor: "0", acao: null },
    { causa: "cancelada_nao_revendida", n: 0, valor: "0", acao: "ver_ofertas" },
    { causa: "reposta", n: 1, valor: "200.00", acao: "rever_politica" },
    { causa: "atendida_nao_recebida", n: 0, valor: "0", acao: "regua" },
    { causa: "abaixo_do_valor", n: 0, valor: "0", acao: "ver_contrato" },
    { causa: "hora_nunca_vendida", n: null, valor: null, minutos: 130, acao: null },
  ],
  completude: { sessoes: 2, completas: 2, resolvidas: 2, repostas: 1 },
};

describe("o eixo agenda", () => {
  it("colapsa o que não é agenda — o mesmo mapa da 0056", () => {
    expect(eixoAgenda("prevista")).toBe("reservada");
    expect(eixoAgenda("confirmada")).toBe("reservada");
    expect(eixoAgenda("realizada")).toBe("realizada");
    expect(eixoAgenda("falta")).toBe("ausente");
    expect(eixoAgenda("cancelada_cedo")).toBe("cancelada");
    expect(eixoAgenda("cancelada_tarde")).toBe("cancelada");
  });

  it("um estado desconhecido cai no seguro, e não estoura na tela", () => {
    expect(eixoAgenda("coisa_nova")).toBe("reservada");
  });

  it("tem rótulo em português para os quatro", () => {
    expect(rotuloAgenda("realizada")).toBe("atendidas");
    expect(rotuloAgenda("ausente")).toBe("faltas");
  });

  it("perdão não vira estorno na tela", () => {
    expect(rotuloFinanceiro("perdoada")).toBe("perdoada");
    expect(rotuloFinanceiro("perdoada")).not.toContain("estorn");
    expect(rotuloFinanceiro("credito")).toContain("mensalidade");
  });

  it("hora entregue não é hora perdida, mesmo sem pagamento", () => {
    expect(eHoraPerdida("vendida")).toBe(false);
    expect(eHoraPerdida("perdida")).toBe(true);
    expect(eHoraPerdida("reposta")).toBe(true);
    expect(eHoraPerdida(null)).toBe(false);
  });
});

describe("as sete causas", () => {
  it("todas têm título e explicação", () => {
    for (const c of TODAS) {
      expect(tituloDaCausa(c).length).toBeGreaterThan(3);
      expect(explicaCausa(c).length).toBeGreaterThan(10);
    }
  });

  it("a falta com cobrança é dita como política funcionando, não como perda", () => {
    const t = explicaCausa("falta_com_cobranca");
    expect(t).toContain("política funcionando");
    // "perda de receita" pode aparecer — mas só negada, e a negação é o ponto:
    // a hora se perdeu e o dinheiro entrou, o que é a política fazendo o que
    // ela existe para fazer.
    expect(t).toMatch(/Não é perda de receita/);
    expect(t).not.toMatch(/preju/i);
  });

  it("a reposta explica as duas horas e a receita única", () => {
    const t = explicaCausa("reposta");
    expect(t).toContain("duas horas");
    expect(t).toContain("uma receita");
  });
});

describe("as duas fronteiras", () => {
  it("a hora nunca vendida NÃO tem ação — e nunca vai ter", () => {
    expect(acaoDaCausa("hora_nunca_vendida")).toBeNull();
  });

  it("a falta com cobrança também não tem, porque não é problema", () => {
    expect(acaoDaCausa("falta_com_cobranca")).toBeNull();
  });

  it("as outras cinco têm ação, e nenhuma delas manda procurar paciente", () => {
    const outras: Causa[] = [
      "falta_sem_cobranca", "cancelada_nao_revendida", "reposta",
      "atendida_nao_recebida", "abaixo_do_valor",
    ];
    for (const c of outras) {
      const a = acaoDaCausa(c);
      expect(a).not.toBeNull();
      expect(a!.rotulo).not.toMatch(/ofere|convid|divulg|captar|prospect|preench/i);
    }
  });

  it("nenhum texto do módulo sugere preencher agenda ou contatar alguém", () => {
    const tudo = [
      ...TODAS.map((c) => `${tituloDaCausa(c)} ${explicaCausa(c)}`),
      fraseDaReceita(lerLivro(BRUTO)),
      fraseDoUso(lerLivro(BRUTO)),
      fraseDaCompletude(lerLivro(BRUTO)),
    ].join(" ");
    expect(tudo).not.toMatch(/preench|divulg|convid|captar|prospect|entre em contato/i);
    expect(tudo).not.toMatch(/ocios|desperdi|subutiliz/i);
  });

  it("o módulo não exporta nada que some as duas horas da reposta", () => {
    for (const nome of Object.keys(modulo)) {
      expect(nome).not.toMatch(/somaHoras|totalDeHoras|ocupacao|ociosidade/i);
    }
  });
});

describe("o livro", () => {
  const l = lerLivro(BRUTO);

  it("traduz sem mexer nos números", () => {
    expect(l.receita).toBe(200);
    expect(l.horas.realizada).toBe(1);
    expect(l.horas.cancelada).toBe(1);
    expect(l.horas.ausente).toBe(0);
    expect(l.capacidade.vendavel).toBe(180);
  });

  it("duas horas de capacidade, uma receita — a conta que decide o build", () => {
    const reposta = l.causas.find((c) => c.causa === "reposta")!;
    expect(reposta.n).toBe(1);
    expect(reposta.valor).toBe(200);
    // a hora reposta e a hora que a repôs: duas linhas de agenda...
    expect(l.horas.realizada + l.horas.cancelada).toBe(2);
    // ...e uma receita só.
    expect(l.receita).toBe(200);
  });

  it("a frase avisa que a mesma capacidade foi usada duas vezes", () => {
    const f = fraseDaReceita(l);
    // `formatar` usa espaço não separável entre "R$" e o número — comparar
    // com o próprio formatador evita um teste que falha por um byte invisível.
    expect(f).toContain(formatar(20000));
    expect(f).toContain("duas vezes");
    expect(f).toContain("uma vez só");
  });

  it("sem reposta, a frase não inventa a ressalva", () => {
    const sem = lerLivro({
      ...BRUTO,
      causas: BRUTO.causas.map((c) =>
        c.causa === "reposta" ? { ...c, n: 0, valor: "0" } : c,
      ),
    });
    expect(fraseDaReceita(sem)).not.toContain("duas vezes");
  });

  it("só mostra as causas que têm o que dizer", () => {
    const com = causasComPeso(l).map((c) => c.causa);
    expect(com).toContain("reposta");
    expect(com).toContain("hora_nunca_vendida");
    expect(com).not.toContain("falta_sem_cobranca");
  });

  it("a hora nunca vendida vem em minutos, e bate com a capacidade", () => {
    const h = l.causas.find((c) => c.causa === "hora_nunca_vendida")!;
    expect(h.minutos).toBe(l.capacidade.vendavel - l.minutosUsados);
    expect(h.valor).toBeNull();
    expect(h.acao).toBeNull();
  });

  it("a frase do uso diz o que sobrou sem adjetivar", () => {
    const f = fraseDoUso(l);
    expect(f).toContain("50min");
    expect(f).toContain("3h");
    expect(f).toContain("não viraram sessão");
  });

  it("sem horários declarados, a frase não acusa ninguém", () => {
    const sem = lerLivro({
      ...BRUTO,
      capacidade: { ...BRUTO.capacidade, sem_janela: true, vendavel_min: 0, registro_min: 0, descanso_min: 0, declarado_min: 0 },
    });
    expect(fraseDoUso(sem)).toContain("Sem horários declarados");
    expect(fraseDoUso(sem)).not.toContain("0%");
  });
});

describe("a completude", () => {
  it("diz que ninguém digitou quando está inteira", () => {
    const f = fraseDaCompletude(lerLivro(BRUTO));
    expect(f).toContain("nenhuma precisou de digitação");
  });

  it("mostra a fração e o percentual quando falta alguma", () => {
    const f = fraseDaCompletude(
      lerLivro({ ...BRUTO, completude: { sessoes: 10, completas: 9, resolvidas: 9, repostas: 1 } }),
    );
    expect(f).toContain("9 de 10");
    expect(f).toContain("90%");
  });

  it("não inventa frase para período vazio", () => {
    const f = fraseDaCompletude(
      lerLivro({ ...BRUTO, completude: { sessoes: 0, completas: 0, resolvidas: 0, repostas: 0 } }),
    );
    expect(f).toBe("Nenhuma sessão no período.");
  });
});
