import { describe, it, expect } from "vitest";
import {
  ACOES,
  rotuloDaAcao,
  ehClinica,
  fraseDaLinha,
  fraseDoTamanho,
  fraseDaImutabilidade,
  SECOES,
  FORA_DAS_SECOES,
  MARCA_PADRAO,
  AUSENCIA_PADRAO,
  rotuloDoCampo,
  ehOculto,
  type LinhaDaTrilha,
} from "./trilha";

const linha = (p: Partial<LinhaDaTrilha> = {}): LinhaDaTrilha => ({
  em: "2026-09-02T14:30:00Z",
  acao: "leu_ficha",
  quem: "Ana",
  saiu: false,
  paciente: "Bia",
  detalhe: {},
  ...p,
});

describe("as ações têm nome de coisa que alguém fez", () => {
  it("as doze do check do banco estão aqui", () => {
    // Se a migração acrescentar uma décima terceira e ninguém puser aqui, o
    // rótulo cru aparece — mas este teste é o lembrete de que ela existe.
    expect(Object.keys(ACOES).sort()).toEqual(
      [
        "anotou_ausencia",
        "arquivou",
        "contrato_aceito",
        "contrato_enviado",
        "contrato_revogado",
        "editou_ficha",
        "editou_registro",
        "escreveu_evolucao",
        "esqueceu_contato",
        "exportou_conta",
        "exportou_paciente",
        "leu_ficha",
      ].sort(),
    );
  });

  it("são verbos no passado, e não substantivos abstratos", () => {
    // "leitura de ficha" não responde quem fez o quê. "abriu a ficha" responde.
    expect(rotuloDaAcao("leu_ficha")).toBe("abriu a ficha");
    expect(rotuloDaAcao("exportou_conta")).toBe("exportou a conta inteira");
    for (const rotulo of Object.values(ACOES)) {
      expect(rotulo).not.toMatch(/^(leitura|edição|exportação|acesso) /i);
    }
  });

  it("uma ação desconhecida APARECE, em vez de sumir", () => {
    // O que some seria exatamente o evento novo — o que ninguém previu, que é o
    // que se procura quando se procura alguma coisa.
    expect(rotuloDaAcao("fez_algo_que_ninguem_previu")).toBe("fez algo que ninguem previu");
    expect(rotuloDaAcao("x")).toBe("x");
  });
});

describe("o peso clínico é para a tela, não para filtrar", () => {
  it("quatro ações tocam conteúdo clínico", () => {
    expect(ehClinica("leu_ficha")).toBe(true);
    expect(ehClinica("escreveu_evolucao")).toBe(true);
    expect(ehClinica("contrato_aceito")).toBe(false);
    expect(ehClinica("arquivou")).toBe(false);
  });
});

describe("a frase da linha responde quem fez o quê", () => {
  it("com paciente, o nome dele entra", () => {
    expect(fraseDaLinha(linha())).toBe("Ana abriu a ficha — Bia");
  });

  it("sem paciente, não sobra travessão solto", () => {
    expect(fraseDaLinha(linha({ acao: "exportou_conta", paciente: null }))).toBe(
      "Ana exportou a conta inteira",
    );
  });

  it("quem saiu da conta continua nomeado como saiu, e não como uuid", () => {
    const l = linha({ quem: "quem não está mais na conta", saiu: true });
    expect(fraseDaLinha(l)).toMatch(/quem não está mais na conta/);
    expect(fraseDaLinha(l)).not.toMatch(/[0-9a-f]{8}-[0-9a-f]{4}/);
  });
});

describe("o tamanho é dito antes de alguém perguntar", () => {
  it("vazia diz que vai gravar sozinha", () => {
    const f = fraseDoTamanho({ linhas: 0, primeira: null });
    expect(f).toMatch(/vazia/);
    expect(f).toMatch(/grava sozinha/);
  });

  it("cheia diz quantas e desde quando", () => {
    // Uma tela que mostra cinquenta linhas sem dizer que há dezoito mil parece
    // uma tela que esconde — e a trilha é a peça que não pode parecer isso.
    const f = fraseDoTamanho({ linhas: 18234, primeira: "2026-08-31T12:00:00Z" });
    expect(f).toMatch(/18\.234 registros/);
    expect(f).toMatch(/31\/08\/2026/);
  });

  it("uma só é registro, não registros", () => {
    expect(fraseDoTamanho({ linhas: 1, primeira: null })).toMatch(/^1 registro\./);
  });
});

describe("a frase que torna a trilha uma defesa", () => {
  it("diz que nem a dona edita — é o ponto inteiro", () => {
    const f = fraseDaImutabilidade();
    expect(f).toMatch(/nem por você/);
    expect(f).toMatch(/não é editável por quem está sendo acusado/);
  });
});

describe("a cópia legível do registro", () => {
  it("as seções vêm na ordem em que o paciente pergunta", () => {
    // Quem ele é aqui, o que foi combinado, o que aconteceu, o que foi escrito.
    expect(SECOES.map((s) => s.chave)).toEqual([
      "paciente",
      "enquadres",
      "sessoes",
      "cobrancas",
      "registro",
      "anamnese",
      "anamnese_adendos",
      "evolucoes",
    ]);
  });

  it("nenhuma seção é a camada documental — e isso é fronteira, não esquecimento", () => {
    // O Registro Documental (testes, protocolos, material de acesso exclusivo)
    // não integra a cópia do paciente. A função no banco já filtra
    // `camada = 'prontuario'`; aqui não existe seção para ele nem por acidente.
    const chaves = SECOES.map((s) => s.chave).join(" ");
    expect(chaves).not.toMatch(/documental|exclusiv|teste|protocolo/i);
  });

  it("...e a ausência é dita no próprio documento", () => {
    expect(AUSENCIA_PADRAO).toMatch(/Registro Documental/);
    expect(AUSENCIA_PADRAO).toMatch(/não integra esta cópia/);
    expect(FORA_DAS_SECOES).toContain("nota_sobre_o_que_nao_esta_aqui");
  });

  it("a marca do documento é a mesma do banco", () => {
    // A mesma frase precisa estar no JSON e no papel, senão são dois documentos
    // diferentes com o mesmo nome.
    expect(MARCA_PADRAO).toBe("Cópia de documento sigiloso. Res. CFP 001/2009.");
  });

  it("o cabeçalho e o rodapé não viram seção", () => {
    for (const chave of FORA_DAS_SECOES) {
      expect(SECOES.map((s) => s.chave)).not.toContain(chave);
    }
  });
});

describe("os campos", () => {
  it("um campo conhecido tem rótulo humano", () => {
    expect(rotuloDoCampo("valor_reconhecido")).toBe("Valor reconhecido");
    expect(rotuloDoCampo("cpf")).toBe("CPF");
  });

  it("um campo novo fica legível em vez de sumir", () => {
    expect(rotuloDoCampo("coluna_que_alguem_criar")).toBe("Coluna que alguem criar");
  });

  it("ids não vão para o papel", () => {
    expect(ehOculto("id")).toBe(true);
    expect(ehOculto("paciente_id")).toBe(true);
    expect(ehOculto("enquadre_id")).toBe(true);
    expect(ehOculto("nome")).toBe(false);
  });

  it("token NUNCA vai para o papel — é a terceira vez desta família", () => {
    // A 0059c tirou `remarcacoes.token` da exportação da conta pelo mesmo
    // motivo: um link mágico num arquivo que a pessoa guarda no computador.
    expect(ehOculto("token")).toBe(true);
    expect(ehOculto("chave_idem")).toBe(true);
  });
});
