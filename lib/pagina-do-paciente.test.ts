import { describe, it, expect } from "vitest";
import * as Pagina from "./pagina-do-paciente";
import {
  saudacao,
  quando,
  dia,
  rotuloDoEstado,
  temAlgoAberto,
  fraseDoVazio,
  fraseDaJanela,
  fraseDoPix,
  valorEmReais,
  rotuloDoMotivo,
  rotuloDoDocumento,
  numeroDoDocumento,
  rotuloDaResposta,
  esperaResposta,
  PROIBIDAS_NA_PAGINA,
  PAGINA_VAZIA,
  type PaginaDoPaciente,
  type ItemDePagamento,
} from "./pagina-do-paciente";

const pagina = (p: Partial<PaginaDoPaciente> = {}): PaginaDoPaciente => ({
  estado: "aberta",
  nome: "Ana",
  confirmar: [],
  pagar: [],
  documentos: [],
  ...p,
});

const cobranca = (p: Partial<ItemDePagamento> = {}): ItemDePagamento => ({
  cobranca: "c1",
  valor: 200,
  tipo: "sessao",
  criado_em: "2026-09-01T12:00:00.000Z",
  pix: null,
  ...p,
});

describe("é uma janela, e não um arquivo", () => {
  it("sem nada aberto, a página diz isso em vez de ficar em branco", () => {
    // Página em branco se lê como defeito, e quem acha que o sistema quebrou
    // liga para a psicóloga — que é exatamente o telefonema que o produto
    // existe para não gerar.
    expect(temAlgoAberto(pagina())).toBe(false);
    expect(fraseDoVazio()).toMatch(/Não há nada esperando/);
    expect(fraseDoVazio()).toMatch(/esta mesma página vai mostrar/);
  });

  it("qualquer um dos três recortes já enche a página", () => {
    expect(temAlgoAberto(pagina({ confirmar: [{ sessao: "s", inicio: "x", ja: "pendente" }] }))).toBe(true);
    expect(temAlgoAberto(pagina({ pagar: [cobranca()] }))).toBe(true);
    expect(
      temAlgoAberto(
        pagina({
          documentos: [
            {
              documento: "d",
              tipo: "recibo",
              numero: 1,
              emitido_em: "2026-09-01T12:00:00.000Z",
              periodo_de: null,
              periodo_ate: null,
              valor_total: 200,
            },
          ],
        }),
      ),
    ).toBe(true);
  });

  it("link morto nunca tem conteúdo, mesmo que venha lixo junto", () => {
    // Defesa de profundidade: se um dia a função do banco devolver estado
    // fechado E uma lista preenchida, a tela não pode mostrar a lista.
    for (const estado of ["expirada", "revogada", "inexistente"] as const) {
      expect(temAlgoAberto(pagina({ estado, pagar: [cobranca()] }))).toBe(false);
    }
  });

  it("a página diz o que ela NÃO mostra", () => {
    // Sem esta frase, quem procura um recibo antigo conclui que o recibo sumiu
    // — e depois que o consultório perdeu os documentos dele.
    const f = fraseDaJanela();
    expect(f).toMatch(/só o que está em aberto/);
    expect(f).toMatch(/últimos três meses/);
    expect(f).toMatch(/é só pedir/);
  });
});

describe("as recusas dizem o próximo passo", () => {
  it("cada estado fechado manda falar com quem enviou", () => {
    expect(rotuloDoEstado("expirada")).toMatch(/Peça um novo/);
    expect(rotuloDoEstado("revogada")).toMatch(/Peça o mais recente/);
    expect(rotuloDoEstado("inexistente")).toMatch(/Não encontramos/);
  });

  it("expirada e revogada são frases diferentes", () => {
    // Um link substituído e um link vencido pedem coisas diferentes de quem
    // está do outro lado, e tratar os dois como "expirou" faz a pessoa pedir a
    // coisa errada.
    expect(rotuloDoEstado("expirada")).not.toBe(rotuloDoEstado("revogada"));
  });

  it("nenhuma recusa explica o motivo técnico", () => {
    for (const estado of ["expirada", "revogada", "inexistente"] as const) {
      expect(rotuloDoEstado(estado)).not.toMatch(/token|erro|inválid|servidor/i);
    }
  });

  it("a página aberta não tem rótulo de recusa", () => {
    expect(rotuloDoEstado("aberta")).toBe("");
  });

  it("a página vazia é 'inexistente', e não 'aberta' sem dados", () => {
    expect(PAGINA_VAZIA.estado).toBe("inexistente");
  });
});

describe("só o primeiro nome", () => {
  it("a saudação corta o sobrenome", () => {
    // A página é aberta num celular que outra pessoa pode estar olhando.
    expect(saudacao("Ana Maria Souza")).toBe("Oi, Ana.");
  });

  it("sem nome, cumprimenta assim mesmo", () => {
    expect(saudacao(null)).toBe("Oi.");
    expect(saudacao("   ")).toBe("Oi.");
  });
});

describe("o Pix é lido, nunca montado — e a ausência é dita", () => {
  it("com código, ensina o que fazer com ele", () => {
    expect(fraseDoPix(cobranca({ pix: "00020126..." }))).toMatch(/Copia e Cola/);
  });

  it("sem código, informa em vez de mostrar campo vazio", () => {
    // Campo vazio faz a pessoa tentar copiar o nada.
    expect(fraseDoPix(cobranca({ pix: null }))).toMatch(/ainda não está aqui/);
    expect(fraseDoPix(cobranca({ pix: "   " }))).toMatch(/ainda não está aqui/);
  });

  it("a frase da ausência não culpa ninguém e não pede nada", () => {
    const f = fraseDoPix(cobranca({ pix: null }));
    expect(f).not.toMatch(/erro|falha|indisponível|tente/i);
  });
});

describe("o dinheiro e o motivo, na língua do paciente", () => {
  it("reais viram texto com centavos", () => {
    // O banco guarda `numeric(12,2)` em reais; `formatar` recebe centavos.
    expect(valorEmReais(200)).toBe(formatarEsperado(20000));
    expect(valorEmReais("230.50")).toBe(formatarEsperado(23050));
  });

  it("valor ausente não vira R$ 0,00", () => {
    // "R$ 0,00" numa cobrança é uma afirmação; "o valor combinado" é a verdade
    // quando o número não veio.
    expect(valorEmReais(null)).toBe("o valor combinado");
    expect(valorEmReais("abacaxi")).toBe("o valor combinado");
  });

  it("falta vira 'horário reservado e não utilizado'", () => {
    // Mesma decisão que tirou a palavra "faltou" do aviso de cobrança na B11:
    // a hora foi separada para ele e ninguém mais pôde usá-la — isso é mais
    // exato do que dizer que ele faltou, e não carrega juízo.
    expect(rotuloDoMotivo("falta")).toBe("horário reservado e não utilizado");
    expect(rotuloDoMotivo("falta")).not.toMatch(/falt/i);
  });

  it("tipo desconhecido não some nem inventa", () => {
    expect(rotuloDoMotivo("coisa_nova")).toBe("o combinado");
  });
});

describe("os documentos", () => {
  it("os três tipos da B17 têm nome de gente", () => {
    expect(rotuloDoDocumento("recibo")).toBe("Recibo");
    expect(rotuloDoDocumento("declaracao_comparecimento")).toBe("Declaração de comparecimento");
    expect(rotuloDoDocumento("informe_anual")).toBe("Informe anual");
  });

  it("um tipo novo aparece cru, em vez de sumir", () => {
    expect(rotuloDoDocumento("laudo_que_alguem_criar")).toBe("laudo_que_alguem_criar");
  });

  it("o número sai com seis dígitos, como no papel", () => {
    expect(numeroDoDocumento(123)).toBe("000123");
    expect(numeroDoDocumento(1)).toBe("000001");
  });
});

describe("confirmar não é cancelar", () => {
  it("recusada é 'avisou que não vai', nunca 'cancelada'", () => {
    // A build inteira do P3: dizer que não vem é uma coisa; cancelar a hora,
    // com a política de falta que isso aciona, é outra, e é dela.
    expect(rotuloDaResposta("recusada")).toBe("Você avisou que não vai.");
    expect(rotuloDaResposta("recusada")).not.toMatch(/cancel/i);
  });

  it("confirmada agradece sem alarde", () => {
    expect(rotuloDaResposta("confirmada")).toBe("Você confirmou.");
  });

  it("pendente e silenciosa ainda esperam resposta", () => {
    expect(esperaResposta("pendente")).toBe(true);
    expect(esperaResposta("silenciosa")).toBe(true);
    expect(esperaResposta("confirmada")).toBe(false);
    expect(esperaResposta("recusada")).toBe(false);
  });
});

describe("as datas são de São Paulo", () => {
  it("o horário sai por extenso", () => {
    expect(quando("2026-09-10T18:00:00.000Z")).toMatch(/quinta|10 de setembro/);
  });

  it("data ausente não vira 'Invalid Date'", () => {
    expect(quando(null)).toBe("no horário combinado");
    expect(quando("não é data")).toBe("no horário combinado");
    expect(dia(null)).toBe("—");
    expect(dia("não é data")).toBe("—");
  });
});

describe("as palavras que não entram nesta página", () => {
  /**
   * A varredura olha **as frases que o módulo produz**, e não o código-fonte.
   * Um comentário que cita a palavra proibida para explicar por que ela é
   * proibida não pode reprovar o arquivo — foi a lição do
   * `dangerouslySetInnerHTML` na 0051, e a quinta vez neste projeto que uma
   * varredura larga acusou código correto.
   */
  const frases = (): string[] => [
    fraseDoVazio(),
    fraseDaJanela(),
    fraseDoPix(cobranca({ pix: null })),
    fraseDoPix(cobranca({ pix: "x" })),
    saudacao("Ana Souza"),
    ...(["aberta", "expirada", "revogada", "inexistente"] as const).map(rotuloDoEstado),
    ...(["pendente", "confirmada", "recusada", "silenciosa", "nao_pedida"] as const).map(
      rotuloDaResposta,
    ),
    ...Object.values(Pagina.MOTIVOS),
    ...Object.values(Pagina.DOCUMENTOS),
  ];

  it("nenhuma frase tem vocabulário de cobrança", () => {
    // A régua da B18 não endurece por mudar de tela: quem lê aqui é a mesma
    // pessoa que leria a mensagem.
    for (const f of frases()) {
      for (const proibida of PROIBIDAS_NA_PAGINA) {
        expect(f.toLowerCase(), `"${f}" contém "${proibida}"`).not.toContain(proibida);
      }
    }
  });

  it("...e a varredura não passa a vazio", () => {
    // Se `frases()` um dia devolver lista vazia por refatoração, o teste acima
    // passaria sem provar nada.
    expect(frases().filter((f) => f.length > 0).length).toBeGreaterThan(8);
  });

  it("nenhuma frase promete o que a página não faz", () => {
    for (const f of frases()) {
      expect(f).not.toMatch(/cancelar|desmarcar|remarcar/i);
    }
  });
});

// `formatar` importado só aqui, para o teste do dinheiro comparar com a mesma
// fonte que o módulo usa em vez de com uma string escrita à mão.
function formatarEsperado(centavos: number): string {
  return (centavos / 100).toLocaleString("pt-BR", { style: "currency", currency: "BRL" });
}
