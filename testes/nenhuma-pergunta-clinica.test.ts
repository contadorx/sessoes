import { describe, it, expect } from "vitest";
import { readdirSync, readFileSync } from "node:fs";
import { join, relative } from "node:path";
import { CAMPOS, VOCABULARIO_CLINICO } from "@/lib/ficha";

/**
 * Nenhuma pergunta clínica chega ao paciente por formulário.
 *
 * É a **fronteira 6**, e ela não é preferência de escopo: pergunta clínica
 * respondida numa caixa de texto, sem ninguém do outro lado, é dado de saúde
 * escrito por quem não sabe que está escrevendo prontuário. Cinco dos oito
 * concorrentes atravessaram essa linha, e é uma das razões pelas quais este
 * produto existe.
 *
 * O arquivo da B34 diz como se atravessa: *"aproveitar o formulário para 'já ir
 * adiantando' a anamnese — e ele começa com um campo só"*. O campo tem sempre
 * uma boa razão. "O que te traz aqui" ia ser perguntado na sessão de qualquer
 * jeito; adiantar parece economia de tempo.
 *
 * **Por que a varredura é sobre as telas de `/p/`, e não sobre a pré-ficha.**
 * A pré-ficha já tem lista fechada em `lib/ficha.ts` e recusa no banco. O risco
 * não é ela: é a **próxima** página por link, escrita daqui a seis meses por
 * alguém que não leu nenhum dos dois. Toda página de `app/p/` entra aqui
 * sozinha no dia em que for criada.
 */

const RAIZ = join(import.meta.dirname, "..");

function arquivos(dir: string, res: string[] = []): string[] {
  for (const e of readdirSync(dir, { withFileTypes: true })) {
    const caminho = join(dir, e.name);
    if (e.isDirectory()) arquivos(caminho, res);
    else if (/\.tsx?$/.test(e.name) && !/\.test\.tsx?$/.test(e.name)) res.push(caminho);
  }
  return res;
}

/**
 * Comentário fora antes de varrer — a quarta vez nesta fila.
 *
 * Este arquivo é o caso extremo do problema: ele **precisa** citar
 * "o que te traz aqui" e "anamnese" para explicar o que está proibindo. Sem
 * apagar comentário, a varredura acusaria a própria explicação e, pior, passaria
 * no dia em que o campo voltasse acompanhado de um comentário que o justifica.
 */
function semComentarios(texto: string): string {
  return texto
    .replace(/\/\*[\s\S]*?\*\//g, (b) => b.replace(/[^\n]/g, " "))
    .replace(/(^|[^:])\/\/[^\n]*/g, (l, antes) => antes + " ".repeat(l.length - antes.length));
}

/** As telas que o paciente abre: tudo em `app/p/` e os componentes públicos. */
const PUBLICAS = ["app/p", "components/publico"]
  .flatMap((d) => arquivos(join(RAIZ, d)))
  .map((caminho) => ({
    caminho: relative(RAIZ, caminho),
    texto: semComentarios(readFileSync(caminho, "utf8")),
  }));

describe("nenhuma pergunta clínica vai por formulário ao paciente", () => {
  it("a varredura está lendo as telas do paciente", () => {
    expect(PUBLICAS.length).toBeGreaterThan(5);
    expect(PUBLICAS.some((f) => f.caminho.includes("ficha"))).toBe(true);
  });

  /**
   * Todo campo de entrada de uma tela pública, descoberto — não listado.
   *
   * `name="..."` é o que viaja para o servidor, e é por ele que um campo novo
   * existe. A varredura pega `input`, `select` e `textarea` pelo atributo,
   * porque é o atributo que o formulário manda.
   */
  const campos = PUBLICAS.flatMap((f) =>
    [...f.texto.matchAll(/name="([a-z0-9_]+)"/g)].map((m) => ({
      caminho: f.caminho,
      nome: m[1],
    })),
  );

  it("a varredura acha os campos que existem", () => {
    expect(campos.length).toBeGreaterThan(8);
    expect(campos.map((c) => c.nome)).toContain("nascimento");
  });

  it.each(VOCABULARIO_CLINICO)('nenhum campo se chama "%s"', (palavra) => {
    const achados = campos
      .filter((c) => c.nome.includes(palavra.replace(/[^a-z0-9_]/g, "")))
      .map((c) => `${c.caminho}: name="${c.nome}"`);
    expect(
      achados,
      `campo com nome clínico numa tela de paciente. Anamnese é da sala: o que ` +
        `for de conversa não vira caixa de texto num celular que outra pessoa ` +
        `pode estar olhando.\n${achados.join("\n")}`,
    ).toEqual([]);
  });

  /**
   * O texto que a pessoa lê — e ele não está só entre as tags.
   *
   * A primeira versão desta verificação lia só nó de JSX, e a mutação mostrou o
   * buraco: um campo chamado `queixa` com o rótulo *"O que te traz aqui?"*
   * passou por aqui incólume, porque a pergunta viajava dentro de
   * `rotulo="..."`. O rótulo **é** a pergunta; o nome do campo é só como ela se
   * chama por dentro.
   */
  const fala = (texto: string): string[] => [
    ...[...texto.matchAll(/>([^<>{}]{6,})</g)].map((m) => m[1]),
    ...[...texto.matchAll(/(?:rotulo|dica|placeholder|title|aria-label)="([^"]{6,})"/g)].map(
      (m) => m[1],
    ),
  ].map((t) => t.replace(/\s+/g, " ").trim());

  it.each(VOCABULARIO_CLINICO)('nenhum texto de tela pergunta sobre "%s"', (palavra) => {
    const achados = PUBLICAS.flatMap((f) =>
      fala(f.texto)
        .filter((t) => t.toLowerCase().includes(palavra))
        .map((t) => `${f.caminho}: "${t}"`),
    );
    expect(
      achados,
      `pergunta clínica no texto de uma tela de paciente — o rótulo é a ` +
        `pergunta, mesmo quando o campo tem nome inocente.\n${achados.join("\n")}`,
    ).toEqual([]);
  });

  /**
   * E o contrapeso, que é o que torna esta suíte útil em vez de paranoica: a
   * pré-ficha **existe** e pede os campos que ela precisa pedir. Uma varredura
   * que passasse com o formulário vazio estaria protegendo uma tela morta.
   */
  it("a pré-ficha continua pedindo o que é administrativo", () => {
    const daFicha = campos
      .filter((c) => c.caminho.includes("Ficha"))
      .map((c) => c.nome);

    for (const c of ["nome", "nascimento", "cpf", "telefone", "email", "msg_canal"]) {
      expect(daFicha, `a pré-ficha parou de pedir ${c}`).toContain(c);
    }
  });

  /**
   * O guarda contra a lista de campos crescer sem ninguém decidir: tudo o que a
   * pré-ficha manda tem de estar em `CAMPOS` (ou ser do responsável, que vira
   * `responsaveis` na validação). O banco recusa o resto; aqui a reprovação
   * chega antes, e com o nome do campo.
   */
  it("todo campo da pré-ficha tem lugar em CAMPOS", () => {
    const permitidos = new Set<string>([
      ...CAMPOS,
      "token",
      "responsavel_nome",
      "responsavel_documento",
      "responsavel_telefone",
    ]);

    const sobrando = campos
      .filter((c) => c.caminho.includes("Ficha") && !permitidos.has(c.nome))
      .map((c) => c.nome);

    expect(
      sobrando,
      "campo na pré-ficha que não está em `CAMPOS` de lib/ficha.ts. `salvar_ficha` " +
        "vai recusar a chamada inteira — e antes disso alguém precisa decidir se " +
        "esse campo é mesmo administrativo.",
    ).toEqual([]);
  });
});
