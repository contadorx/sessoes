import { describe, it, expect } from "vitest";
import {
  abasDoPaciente,
  ROTULO_ABA,
  destinos,
  barraDoCelular,
  pendencias,
  fraseDasPendencias,
  acoesNovas,
  ondeBuscar,
  buscavel,
  fraseDoVazio,
  acoesDaSessao,
  destinoAtivo,
  SECOES,
  type PrazosDoMes,
} from "./navegacao";
import {
  podeClinico,
  podeFinanceiro,
  podeConceder,
  fraseDoAcesso,
  PADRAO,
  type Acessos,
  type Papel,
} from "./permissao";

const quem = (papel: Papel, c: boolean | null = null, f: boolean | null = null): Acessos => ({
  papel,
  acessoClinico: c,
  acessoFinanceiro: f,
});

const dona = quem("dona");
const psi = quem("profissional");
const adm = quem("administradora");
const sec = quem("secretaria");

// ============================================ a permissão

describe("o acesso clínico não vem com o cargo", () => {
  it("o padrão de cada papel é o do banco (0049)", () => {
    expect(podeClinico(dona)).toBe(true);
    expect(podeFinanceiro(dona)).toBe(true);

    // Atende, e o dinheiro é da clínica.
    expect(podeClinico(psi)).toBe(true);
    expect(podeFinanceiro(psi)).toBe(false);

    // O espelho — é este par que prova que os dois eixos são independentes, e
    // não dois nomes para a mesma escada de cargos.
    expect(podeClinico(adm)).toBe(false);
    expect(podeFinanceiro(adm)).toBe(true);

    expect(podeClinico(sec)).toBe(false);
    expect(podeFinanceiro(sec)).toBe(false);
  });

  it("a concessão explícita vence o padrão nos DOIS sentidos", () => {
    expect(podeClinico(quem("secretaria", true))).toBe(true);
    expect(podeClinico(quem("profissional", false))).toBe(false);
    expect(podeFinanceiro(quem("secretaria", null, true))).toBe(true);
    expect(podeFinanceiro(quem("dona", null, false))).toBe(false);
  });

  it("nulo não é falso: é 'ninguém decidiu ainda'", () => {
    // Se `null` virasse `false` em algum refactor, toda dona perderia o
    // próprio prontuário no deploy seguinte, em silêncio.
    expect(quem("dona").acessoClinico).toBeNull();
    expect(podeClinico(quem("dona"))).toBe(true);
  });

  it("só a dona concede, e nunca a si mesma", () => {
    expect(podeConceder(dona, { eu: false })).toBe(true);
    expect(podeConceder(dona, { eu: true })).toBe(false);
    expect(podeConceder(adm, { eu: false })).toBe(false);
    expect(podeConceder(sec, { eu: false })).toBe(false);
  });

  it("a frase descreve a regra, não uma suspeita sobre a pessoa", () => {
    const todas = [dona, psi, adm, sec].map(fraseDoAcesso).join(" ");
    expect(todas).not.toMatch(/não pode|não deve|proibid|restrit|bloquead/i);
    expect(fraseDoAcesso(sec)).toMatch(/agenda/i);
    expect(fraseDoAcesso(adm)).toMatch(/prontuário/i);
  });

  it("todo papel tem padrão — um papel novo sem linha aqui seria acesso por acidente", () => {
    const papeis: Papel[] = ["dona", "profissional", "administradora", "secretaria"];
    for (const p of papeis) expect(PADRAO[p]).toBeDefined();
  });
});

// ============================================ os cinco destinos

describe("destinos — o menu nomeia o trabalho, não as tabelas", () => {
  it("são cinco, e são estes", () => {
    // Doze itens de mesmo peso é o defeito que esta lista existe para não
    // deixar voltar: cada tela nova acrescentava um link no cabeçalho, e
    // ninguém decidiu por doze.
    expect(destinos(dona).map((d) => d.rotulo)).toEqual([
      "Agenda",
      "Encaixes",
      "Pacientes",
      "Recebimentos",
      "Fechamento",
    ]);
  });

  it("nenhum rótulo descreve mecanismo — 'Fila' e 'Vagas' eram vizinhos e ninguém acertava", () => {
    const rotulos = destinos(dona).map((d) => d.rotulo);
    expect(rotulos).not.toContain("Fila");
    expect(rotulos).not.toContain("Vagas");
    expect(rotulos).not.toContain("Em aberto");
    // "Receita" era ambíguo entre faturamento e Receita Federal.
    expect(rotulos).not.toContain("Receita");
    expect(rotulos).not.toContain("Calendário");
  });

  it("quem não tem o eixo financeiro não vê Recebimentos nem Fechamento", () => {
    expect(destinos(sec).map((d) => d.rotulo)).toEqual(["Agenda", "Encaixes", "Pacientes"]);
    expect(destinos(psi).map((d) => d.rotulo)).toEqual(["Agenda", "Encaixes", "Pacientes"]);
  });

  it("...mas ninguém perde Agenda, Encaixes e Pacientes", () => {
    // Tirar isto da secretária devolve o trabalho para a psicóloga, que é o
    // oposto do produto. Foi o contra-argumento da própria auditoria, e vale.
    for (const p of [dona, psi, adm, sec]) {
      const h = destinos(p).map((d) => d.href);
      expect(h).toContain("/agenda");
      expect(h).toContain("/encaixes");
      expect(h).toContain("/pacientes");
    }
  });

  it("a administradora vê o dinheiro sem ser psicóloga", () => {
    expect(destinos(adm).map((d) => d.href)).toContain("/recebimentos");
  });

  it("todo destino tem descrição — o rótulo curto não pode ser a única pista", () => {
    for (const d of destinos(dona)) {
      expect(d.descricao.length).toBeGreaterThan(10);
      expect(d.curto.length).toBeLessThanOrEqual(d.rotulo.length);
    }
  });
});

describe("barraDoCelular — cinco cadeiras, e o polegar decide", () => {
  it("nunca passa de cinco", () => {
    for (const p of [dona, psi, adm, sec]) {
      expect(barraDoCelular(p).length).toBeLessThanOrEqual(5);
    }
  });

  it("o Fechamento desce para o Mais: é mensal, e o polegar é diário", () => {
    const b = barraDoCelular(dona).map((i) => i.rotulo);
    expect(b).toEqual(["Agenda", "Encaixes", "Pacientes", "Recebimentos", "Mais"]);
  });

  it("no celular 'Recebimentos' vira 'Receber' — é o que cabe", () => {
    const r = barraDoCelular(dona).find((i) => i.href === "/recebimentos");
    expect(r?.curto).toBe("Receber");
  });

  it("Mais existe sempre — é onde moram perfil, ajuda e sair", () => {
    for (const p of [dona, psi, adm, sec]) {
      expect(barraDoCelular(p).at(-1)?.rotulo).toBe("Mais");
    }
  });
});

// ============================================ as pendências com prazo

const prazos = (p: Partial<PrazosDoMes> = {}): PrazosDoMes => ({
  recibosPendentes: 0,
  recibosAte: null,
  recibosUrgente: false,
  contadorAberto: false,
  contadorAte: null,
  contadorUrgente: false,
  ...p,
});

describe("pendências — alarme que só toca quando é para tocar", () => {
  it("mês limpo não mostra faixa nenhuma", () => {
    // Um aviso que aparece o ano inteiro é um aviso que se aprende a não ler.
    // É o motivo de Receita Saúde e Contador terem deixado de ser itens de
    // menu permanentes.
    expect(pendencias(prazos(), dona)).toEqual([]);
    expect(fraseDasPendencias([])).toBe("");
  });

  it("com prazo, diz o quê e até quando — sem gráfico e sem percentual", () => {
    const ps = pendencias(
      prazos({
        recibosPendentes: 2,
        recibosAte: "10/09",
        contadorAberto: true,
        contadorAte: "05/09",
      }),
      dona,
    );
    expect(ps).toHaveLength(2);
    const f = fraseDasPendencias(ps);
    expect(f).toBe("2 pendências com prazo neste mês: 2 recibos até 10/09 · fechamento do contador até 05/09.");
    expect(f).not.toMatch(/%|gráfico|meta|desempenho/i);
  });

  it("um só, no singular, dos dois lados", () => {
    const ps = pendencias(prazos({ recibosPendentes: 1, recibosAte: "10/09" }), dona);
    expect(fraseDasPendencias(ps)).toMatch(/^1 pendência com prazo neste mês: 1 recibo até 10\/09\.$/);
  });

  it("cada item leva direto para a lista correspondente", () => {
    const ps = pendencias(
      prazos({ recibosPendentes: 1, recibosAte: "10/09", contadorAberto: true, contadorAte: "05/09" }),
      dona,
    );
    expect(ps.find((p) => p.chave === "recibos")?.href).toBe("/fechamento/receita-saude");
    expect(ps.find((p) => p.chave === "contador")?.href).toBe("/fechamento/contador");
  });

  it("a urgência vem de fora — a faixa não inventa prazo", () => {
    const ps = pendencias(prazos({ recibosPendentes: 1, recibosAte: "03/09", recibosUrgente: true }), dona);
    expect(ps[0].urgente).toBe(true);
  });

  it("quem não vê financeiro não recebe faixa — ela levaria a uma tela vazia", () => {
    const p = prazos({ recibosPendentes: 3, recibosAte: "10/09", contadorAberto: true, contadorAte: "05/09" });
    expect(pendencias(p, sec)).toEqual([]);
    expect(pendencias(p, psi)).toEqual([]);
    expect(pendencias(p, adm)).toHaveLength(2);
  });

  it("pendência sem data não vira faixa — 'algo vence' sem quando é ruído", () => {
    expect(pendencias(prazos({ recibosPendentes: 4, recibosAte: null }), dona)).toEqual([]);
    expect(pendencias(prazos({ contadorAberto: true, contadorAte: null }), dona)).toEqual([]);
  });
});

// ============================================ Novo, busca, sessão

describe("o botão Novo", () => {
  it("oferece o que nasce no produto, e nada além", () => {
    expect(acoesNovas(dona).map((a) => a.rotulo)).toEqual([
      "Sessão",
      "Paciente",
      "Pedido de encaixe",
      "Recebimento",
    ]);
  });

  it("sem eixo financeiro, não oferece lançar recebimento", () => {
    expect(acoesNovas(sec).map((a) => a.rotulo)).not.toContain("Recebimento");
  });
});

describe("a busca global", () => {
  it("procura nas quatro coisas que a pessoa procura", () => {
    expect(ondeBuscar(dona)).toEqual(["paciente", "sessao", "documento", "pagamento"]);
  });

  it("não procura onde a RLS vai esvaziar", () => {
    // "Nenhum resultado" onde a resposta certa é "não é para você" faz a
    // pessoa procurar de novo, e concluir que o produto perdeu o documento.
    expect(ondeBuscar(sec)).toEqual(["paciente", "sessao"]);
    expect(fraseDoVazio("mari", sec)).toBe("Nada encontrado em paciente, sessão.");
  });

  it("uma letra não busca", () => {
    expect(buscavel("a")).toBe(false);
    expect(buscavel("  a ")).toBe(false);
    expect(buscavel("ma")).toBe(true);
    expect(fraseDoVazio("a", dona)).toMatch(/duas letras/);
  });
});

describe("acoesDaSessao — a sessão deixa de estar espalhada em seis telas", () => {
  it("o painel responde por tudo o que se faz com uma sessão", () => {
    expect(acoesDaSessao(dona)).toEqual([
      "registrar",
      "cobranca",
      "lembrete",
      "reposicao",
      "documento",
      "fechamento",
    ]);
  });

  it("registrar o que aconteceu não pede eixo financeiro nem clínico", () => {
    // Marcar realizada ou falta é fato administrativo — quem marca a agenda
    // marca isso. O que pede o eixo clínico é a evolução, e ela mora dentro
    // do paciente.
    expect(acoesDaSessao(sec)).toContain("registrar");
    expect(acoesDaSessao(sec)).toContain("lembrete");
    expect(acoesDaSessao(sec)).not.toContain("cobranca");
    expect(acoesDaSessao(sec)).not.toContain("documento");
  });
});

describe("abasDoPaciente — os dois eixos na mesma tela", () => {
  it("a dona vê a ficha inteira", () => {
    expect(abasDoPaciente(dona)).toEqual(["cadastro", "combinado", "clinico", "financeiro"]);
  });

  it("a psicóloga vê o registro clínico e não os pagamentos", () => {
    expect(abasDoPaciente(psi)).toEqual(["cadastro", "combinado", "clinico"]);
  });

  it("a administradora vê os pagamentos e não o registro clínico", () => {
    expect(abasDoPaciente(adm)).toEqual(["cadastro", "combinado", "financeiro"]);
  });

  it("a secretária vê quem é e o que foi combinado — o que ela precisa para marcar", () => {
    expect(abasDoPaciente(sec)).toEqual(["cadastro", "combinado"]);
  });

  it("cadastro e combinado nunca somem — sem eles não se marca uma sessão", () => {
    for (const p of [dona, psi, adm, sec]) {
      expect(abasDoPaciente(p)[0]).toBe("cadastro");
      expect(abasDoPaciente(p)[1]).toBe("combinado");
    }
  });

  it("toda aba tem rótulo", () => {
    for (const aba of abasDoPaciente(dona)) {
      expect(ROTULO_ABA[aba].length).toBeGreaterThan(3);
    }
  });
});

// ============================================ o grifo e as seções

describe("destinoAtivo — grifa um, e só um", () => {
  it("a sub-rota grifa o destino que a contém", () => {
    expect(destinoAtivo("/fechamento/receita-saude", "/fechamento")).toBe(true);
    expect(destinoAtivo("/encaixes/fixos", "/encaixes")).toBe(true);
    expect(destinoAtivo("/recebimentos/movimentacoes", "/recebimentos")).toBe(true);
  });

  it("não grifa por acidente de prefixo", () => {
    expect(destinoAtivo("/recebimentos-antigos", "/recebimentos")).toBe(false);
    expect(destinoAtivo("/agenda-do-mes", "/agenda")).toBe(false);
  });

  it("em qualquer caminho, no máximo um dos cinco fica grifado", () => {
    const caminhos = [
      "/agenda",
      "/encaixes",
      "/encaixes/fixos",
      "/pacientes",
      "/pacientes/abc",
      "/recebimentos",
      "/recebimentos/movimentacoes",
      "/fechamento",
      "/fechamento/contador",
      "/perfil",
    ];
    for (const c of caminhos) {
      const n = destinos(dona).filter((d) => destinoAtivo(c, d.href)).length;
      expect(n, `${c} grifou ${n} destinos`).toBeLessThanOrEqual(1);
    }
  });
});

describe("SECOES — a lista que dá para contar", () => {
  it("toda seção aponta para dentro do próprio destino", () => {
    for (const [destino, secoes] of Object.entries(SECOES)) {
      for (const s of secoes) {
        expect(destinoAtivo(s.href, destino), `${s.href} não pertence a ${destino}`).toBe(true);
      }
    }
  });

  it("nenhum destino tem mais de quatro seções", () => {
    // Quatro é onde a sub-navegação ainda se lê de relance. A quinta é o
    // começo de outros doze itens.
    for (const [destino, secoes] of Object.entries(SECOES)) {
      expect(secoes.length, destino).toBeLessThanOrEqual(4);
    }
  });

  it("as antigas telas de menu viraram seções, não sumiram", () => {
    const todas = Object.values(SECOES).flatMap((s) => s.map((x) => x.href));
    expect(todas).toContain("/encaixes/fixos"); // era "Vagas"
    expect(todas).toContain("/recebimentos/movimentacoes"); // era "Financeiro"
    expect(todas).toContain("/fechamento/receita-saude"); // era "Receita"
    expect(todas).toContain("/fechamento/contador"); // era "Contador"
    expect(todas).toContain("/fechamento/documentos"); // era "Documentos"
    expect(todas).toContain("/perfil/integracoes"); // era "Calendário"
    expect(todas).toContain("/perfil/contrato"); // era "Contratos"
  });
});
