import { describe, it, expect } from "vitest";
import {
  DIAS_DE_VALIDADE,
  apagarRascunho,
  chaveDoRascunho,
  guardarRascunho,
  lerRascunho,
  limparRascunhos,
  expirarRascunhos,
} from "./rascunho";

/** Um `Storage` de mentira, com o mesmo contrato do de verdade. */
function storageFalso(inicial: Record<string, string> = {}): Storage {
  const mapa = new Map(Object.entries(inicial));
  return {
    get length() {
      return mapa.size;
    },
    key: (i: number) => [...mapa.keys()][i] ?? null,
    getItem: (k: string) => mapa.get(k) ?? null,
    setItem: (k: string, v: string) => void mapa.set(k, v),
    removeItem: (k: string) => void mapa.delete(k),
    clear: () => mapa.clear(),
  } as Storage;
}

/** Um que estoura em tudo — janela anônima, cota cheia, site bloqueado. */
function storageQueEstoura(): Storage {
  const explode = () => {
    throw new Error("QuotaExceededError");
  };
  return {
    get length(): number {
      throw new Error("SecurityError");
    },
    key: explode,
    getItem: explode,
    setItem: explode,
    removeItem: explode,
    clear: explode,
  } as unknown as Storage;
}

const DIA = 24 * 60 * 60 * 1000;

describe("o rascunho guarda e devolve", () => {
  it("o que ela digitou volta inteiro", () => {
    const s = storageFalso();
    guardarRascunho(s, "sessao-1", "Trabalhamos o retorno ao trabalho.");
    expect(lerRascunho(s, "sessao-1")).toBe("Trabalhamos o retorno ao trabalho.");
  });

  it("cada sessão tem a sua chave — é o S1 desta build, pelo outro lado", () => {
    const s = storageFalso();
    guardarRascunho(s, "sessao-A", "texto da Helena");
    guardarRascunho(s, "sessao-B", "texto do João");

    expect(lerRascunho(s, "sessao-A")).toBe("texto da Helena");
    expect(lerRascunho(s, "sessao-B")).toBe("texto do João");
    expect(chaveDoRascunho("sessao-A")).not.toBe(chaveDoRascunho("sessao-B"));
  });

  it("sem rascunho, devolve nulo — e não string vazia", () => {
    expect(lerRascunho(storageFalso(), "sessao-1")).toBeNull();
  });
});

describe("o rascunho some quando serviu", () => {
  it("apagar tira do aparelho", () => {
    const s = storageFalso();
    guardarRascunho(s, "sessao-1", "texto");
    apagarRascunho(s, "sessao-1");
    expect(lerRascunho(s, "sessao-1")).toBeNull();
  });

  it("esvaziar a textarea apaga, em vez de guardar vazio", () => {
    const s = storageFalso();
    guardarRascunho(s, "sessao-1", "texto");
    guardarRascunho(s, "sessao-1", "   ");
    expect(s.getItem(chaveDoRascunho("sessao-1"))).toBeNull();
  });

  /**
   * Sem validade, uma evolução começada e abandonada em março continuaria no
   * aparelho em setembro — e o aparelho pode ser o da recepção, onde senta a
   * segunda persona do produto, que não tem acesso clínico.
   */
  it("vence, e a leitura seguinte já não o encontra", () => {
    const s = storageFalso();
    const agora = Date.now();
    guardarRascunho(s, "sessao-1", "texto", agora);

    expect(lerRascunho(s, "sessao-1", agora + (DIAS_DE_VALIDADE - 1) * DIA)).toBe("texto");
    expect(lerRascunho(s, "sessao-1", agora + (DIAS_DE_VALIDADE + 1) * DIA)).toBeNull();
  });

  it("o vencido é removido, não só escondido", () => {
    const s = storageFalso();
    const agora = Date.now();
    guardarRascunho(s, "sessao-1", "texto", agora);
    lerRascunho(s, "sessao-1", agora + (DIAS_DE_VALIDADE + 1) * DIA);
    expect(s.getItem(chaveDoRascunho("sessao-1"))).toBeNull();
  });

  /**
   * Sair da conta e deixar evolução pela metade no aparelho é o caminho por
   * onde alguém lê o que não pode ler. A varredura é por prefixo — lista
   * escrita à mão é a que esquece a chave nova (lei 7).
   */
  it("sair da conta leva todos os rascunhos junto, e só eles", () => {
    const s = storageFalso({ "outra-coisa": "fica", "tema": "escuro" });
    guardarRascunho(s, "a", "1");
    guardarRascunho(s, "b", "2");
    guardarRascunho(s, "c", "3");

    expect(limparRascunhos(s)).toBe(3);
    expect(lerRascunho(s, "a")).toBeNull();
    expect(lerRascunho(s, "c")).toBeNull();
    expect(s.getItem("outra-coisa")).toBe("fica");
    expect(s.getItem("tema")).toBe("escuro");
  });
});

describe("o rascunho nunca derruba a tela", () => {
  it("sem storage nenhum, tudo segue em silêncio", () => {
    expect(() => guardarRascunho(null, "s", "t")).not.toThrow();
    expect(lerRascunho(null, "s")).toBeNull();
    expect(() => apagarRascunho(undefined, "s")).not.toThrow();
    expect(limparRascunhos(null)).toBe(0);
  });

  /**
   * `localStorage` estoura de verdade: janela anônima, cota cheia, navegador
   * com dados de site bloqueados. Rascunho é conveniência — derrubar a tela de
   * evolução por causa dele inverteria a troca.
   */
  it("com storage que estoura, também", () => {
    const s = storageQueEstoura();
    expect(() => guardarRascunho(s, "s", "t")).not.toThrow();
    expect(lerRascunho(s, "s")).toBeNull();
    expect(() => apagarRascunho(s, "s")).not.toThrow();
    expect(limparRascunhos(s)).toBe(0);
  });

  it("conteúdo corrompido não vira rascunho — e é limpo", () => {
    const s = storageFalso({ [chaveDoRascunho("s")]: "{isto não é json" });
    expect(lerRascunho(s, "s")).toBeNull();

    const s2 = storageFalso({ [chaveDoRascunho("s")]: '{"texto":123}' });
    expect(lerRascunho(s2, "s")).toBeNull();
    expect(s2.getItem(chaveDoRascunho("s"))).toBeNull();
  });
});


/**
 * A promessa nº 3 do cabeçalho, que não estava sendo cumprida.
 *
 * *"Rascunho que ninguém retomou em `DIAS_DE_VALIDADE` é descartado na primeira
 * leitura seguinte."* — e a leitura seguinte só existia para a sessão que ela
 * reabrisse. O rascunho **abandonado**, que é o caso que a frase descreve, era
 * o único que nunca era lido de novo, e portanto o único que nunca vencia.
 */
describe("o rascunho abandonado vence sozinho", () => {
  const DIA = 24 * 60 * 60 * 1000;
  const AGORA = 1_800_000_000_000;

  function storageFalso(itens: Record<string, string>): Storage {
    const mapa = new Map(Object.entries(itens));
    return {
      get length() {
        return mapa.size;
      },
      key: (i: number) => [...mapa.keys()][i] ?? null,
      getItem: (k: string) => mapa.get(k) ?? null,
      setItem: (k: string, v: string) => void mapa.set(k, v),
      removeItem: (k: string) => void mapa.delete(k),
      clear: () => mapa.clear(),
    } as unknown as Storage;
  }

  const rascunho = (dias: number) =>
    JSON.stringify({ texto: "conteúdo de evolução", em: AGORA - dias * DIA });

  it("apaga o vencido e deixa o recente, sem ninguém reabrir a sessão", () => {
    const s = storageFalso({
      "sessoes:rascunho:evolucao:velho": rascunho(30),
      "sessoes:rascunho:evolucao:novo": rascunho(1),
      "outra-coisa": "não é minha",
    });

    expect(expirarRascunhos(s, AGORA)).toBe(1);
    expect(s.getItem("sessoes:rascunho:evolucao:velho")).toBeNull();
    expect(s.getItem("sessoes:rascunho:evolucao:novo")).not.toBeNull();
    // Varre por prefixo: o que não é nosso não se toca.
    expect(s.getItem("outra-coisa")).toBe("não é minha");
  });

  it("na fronteira, o que está no prazo fica", () => {
    const s = storageFalso({
      "sessoes:rascunho:evolucao:a": rascunho(DIAS_DE_VALIDADE - 1),
      "sessoes:rascunho:evolucao:b": rascunho(DIAS_DE_VALIDADE + 1),
    });
    expect(expirarRascunhos(s, AGORA)).toBe(1);
    expect(s.getItem("sessoes:rascunho:evolucao:a")).not.toBeNull();
    expect(s.getItem("sessoes:rascunho:evolucao:b")).toBeNull();
  });

  /**
   * JSON ilegível conta como vencido: guardar texto clínico que ninguém
   * consegue ler é ficar com o risco sem ficar com a utilidade.
   */
  it("o ilegível também sai", () => {
    const s = storageFalso({ "sessoes:rascunho:evolucao:x": "{isto não é json" });
    expect(expirarRascunhos(s, AGORA)).toBe(1);
    expect(s.getItem("sessoes:rascunho:evolucao:x")).toBeNull();
  });

  it("sem storage, não lança", () => {
    expect(expirarRascunhos(null)).toBe(0);
    expect(expirarRascunhos(undefined)).toBe(0);
  });
});
