import { describe, it, expect } from "vitest";
import { readdirSync, readFileSync } from "node:fs";
import { join, relative } from "node:path";

/**
 * Nenhuma tela afirma envio que ela não conferiu.
 *
 * O DEFEITO, EM QUATRO VERSÕES NA MESMA SESSÃO DE USO
 *
 * A cascata devolvia **sempre** *"Oferta enviada. A fila anda sozinha a partir
 * daqui"*, sem ler resultado nenhum. Com a janela de silêncio ativa isso é
 * falso em todo caso noturno: a oferta criada às 2h só tenta sair às 8h. A
 * fila dizia *"Você não pede nada a ninguém"*; a régua, *"o sistema lembra por
 * você"*; e a caixa "Na sua mão", na mesma tela, admitia que a mensagem sai do
 * WhatsApp **dela**. Quatro afirmações sobre o mesmo fato, três delas falsas
 * enquanto não houver provedor.
 *
 * E a trilha da fila afirmava o mesmo: `eventos_fila` tinha **onze** linhas
 * `oferta_enviada`, e em **nenhuma** delas a mensagem havia chegado a `enviada`
 * ou `entregue` — o evento era gravado no instante em que a oferta nascia. A
 * 0089 separou `oferta_preparada` de `oferta_enviada` e reetiquetou as onze por
 * derivação.
 *
 * Por que uma varredura e não quatro consertos: *"a promessa que o software não
 * cumpre"* é antipadrão nomeado deste projeto e **já aconteceu quatro vezes**
 * antes desta. O conserto que dura nunca foi a frase — é a verificação que
 * reprova a quinta.
 *
 * COMO ELA DECIDE
 *
 * Cada afirmação de envio automático encontrada no texto de tela obriga o
 * arquivo a **também** ler o estado: `envioAutomatico`, `envioAutomaticoLigado`
 * ou uma das frases de `lib/canal.ts` que já derivam dele. Arquivo que afirma
 * sem ler reprova, e a frase nova de amanhã nasce dentro da varredura.
 */

const RAIZ = join(import.meta.dirname, "..");

function arquivos(dir: string, res: string[] = []): string[] {
  for (const e of readdirSync(dir, { withFileTypes: true })) {
    const caminho = join(dir, e.name);
    if (e.isDirectory()) {
      if (e.name === "node_modules" || e.name === ".next") continue;
      arquivos(caminho, res);
    } else if (/\.tsx?$/.test(e.name) && !/\.test\.tsx?$/.test(e.name)) {
      res.push(caminho);
    }
  }
  return res;
}

function semComentarios(fonte: string): string {
  return fonte
    .replace(/\/\*[\s\S]*?\*\//g, "")
    .replace(/(^|[^:"'`\\])\/\/[^\n]*/g, (_, antes) => antes);
}

/** As afirmações que só são verdade com provedor ligado. */
const AFIRMACOES = [
  /n[ãa]o pede nada a ningu[ée]m/i,
  /o sistema lembra/i,
  /sistema est[áa] lembrando/i,
  /remetente neutro/i,
  /sa(?:em|i) sozinh[oa]s?/i,
  /a fila anda sozinha/i,
  /oferta enviada/i,
  /mensagem (?:foi )?enviada/i,
];

/*
  `avisamos` esteve nesta lista e saiu. O único achado dele foi a
  `/seguranca`, dizendo "avisamos quem foi afetado" sobre incidente de dado —
  compromisso de LGPD, não envio de mensagem a paciente. Padrão que produz
  achado falso é padrão que vira exceção, e varredura com lista de exceções é a
  que ninguém lê depois.
*/

/** Ler o estado é uma destas — todas descem do mesmo `envioAutomaticoLigado`. */
const LE_O_ESTADO =
  /envioAutomatico|envioAutomaticoLigado|envioPorEmail|adaptadorPara|fraseDoEnvioAutomatico|fraseDaOferta|ofertaSaiu|fraseDaFila|fraseDaRegua|notaDoComoAvisar|oferta_enviada|estado_da_mensagem|mensagens/;

describe("nenhuma tela afirma envio que ela não conferiu", () => {
  const telas = arquivos(join(RAIZ, "app")).concat(arquivos(join(RAIZ, "components")));

  it("toda afirmação de envio automático mora em arquivo que lê o estado", () => {
    const sem: string[] = [];

    for (const arquivo of telas) {
      const fonte = semComentarios(readFileSync(arquivo, "utf8"));
      const achadas = AFIRMACOES.filter((r) => r.test(fonte));
      if (achadas.length === 0) continue;
      if (LE_O_ESTADO.test(fonte)) continue;

      sem.push(
        `${relative(RAIZ, arquivo)} afirma ${achadas
          .map((r) => (fonte.match(r) ?? [""])[0])
          .map((t) => `"${t}"`)
          .join(", ")} e não lê o estado do canal`,
      );
    }

    expect(sem, sem.join("\n")).toEqual([]);
  });

  /*
    A outra metade, e ela é sobre o banco: `oferta_enviada` é o rótulo do fato
    consumado. Quem grava tem de ser quem viu a mensagem sair — hoje
    `registrar_oferta_enviada`, chamada por `marcar_enviada` e por
    `marcar_enviada_a_mao`. Se alguém voltar a gravá-lo junto da criação da
    oferta, é aqui que aparece.
  */
  it("nenhuma migração grava oferta_enviada ao criar a oferta", () => {
    const migracoes = readdirSync(join(RAIZ, "supabase", "migrations"))
      .filter((f) => f.endsWith(".sql"))
      .sort();

    // A última migração que mexe em `avancar_fila` é a que vale — as antigas
    // são história, e reprovar por elas seria reprovar o passado.
    const ultima = migracoes
      .filter((f) => /create or replace function public\.avancar_fila\b/i.test(
        readFileSync(join(RAIZ, "supabase", "migrations", f), "utf8"),
      ))
      .pop();

    expect(ultima, "nenhuma migração define avancar_fila").toBeTruthy();

    const corpo = readFileSync(join(RAIZ, "supabase", "migrations", ultima!), "utf8");
    const trecho = corpo.slice(
      corpo.search(/create or replace function public\.avancar_fila\b/i),
    );
    const ate = trecho.indexOf("$function$;");
    const avancar = ate > 0 ? trecho.slice(0, ate) : trecho;

    expect(avancar).toContain("'oferta_preparada'");
    expect(avancar).not.toContain("'oferta_enviada'");
  });
});
