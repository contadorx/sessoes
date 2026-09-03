#!/usr/bin/env node
/**
 * Confere se as colunas que as telas pedem existem no banco.
 *
 * ## Por que este arquivo existe
 *
 * A B44 trocou a consulta do livro-razão por
 * `.from("profissionais").select("id, nome")`. **`profissionais` não tem coluna
 * `nome`** — o nome de uma profissional mora em `usuarios.nome`, pela FK. O
 * PostgREST recusa a coluna, `db()` lança (lei 1), e "o que aconteceu com cada
 * hora" — uma das quatro telas-núcleo — deixou de abrir para toda conta, na
 * hora em que a correção entrou.
 *
 * E ficou assim até a B51, porque o defeito mora exatamente no vão entre as
 * verificações que existem:
 *
 *   · `tsc` não conhece o schema: `select("id, nome")` é uma string;
 *   · o ESLint idem;
 *   · as suítes SQL testam funções do banco, e não veem tela nenhuma;
 *   · os testes de `lib/` não fazem consulta;
 *   · nenhuma verificação renderiza a rota.
 *
 * É o mesmo formato do defeito que a `nenhuma-acao-sem-porta` fecha do outro
 * lado — ação sem tela — e do que a `0053` sofreu por dois meses: um rename no
 * banco que ninguém propagou, vermelho em silêncio.
 *
 * ## Como se usa
 *
 *     SUPABASE_DB_URL='postgresql://…' node supabase/conferir-colunas.mjs
 *     node supabase/conferir-colunas.mjs --catalogo=catalogo.json
 *
 * A segunda forma serve ao CI, que pode guardar o catálogo, e a quem tem o
 * catálogo mas não tem `psql` na mão. O formato é
 * `{"tabela": ["coluna", …], …}`.
 *
 * ## O que ela NÃO faz, e é decisão
 *
 * **Não confere consulta montada com template.** `select(`${a}, ${b}`)` é
 * decidido em tempo de execução, e adivinhar seria pior que não olhar: ela
 * conta essas e diz quantas ficaram de fora, para o número não passar por
 * cobertura total.
 *
 * **Não confere relação embutida que não seja nome de tabela.** PostgREST
 * aceita apelido e dica de FK (`paciente:pacientes`, `pacientes!inner`), e as
 * duas formas são resolvidas aqui; o que não casar com tabela nenhuma é
 * relatado como não conferido, nunca como erro.
 *
 * **Não lê lista de tabelas escrita à mão** (lei 7): o catálogo vem do
 * `information_schema`, e as consultas vêm de uma varredura da pasta.
 */

import { readdirSync, readFileSync, existsSync } from "node:fs";
import { join, relative, dirname } from "node:path";
import { spawnSync } from "node:child_process";

const RAIZ = join(dirname(new URL(import.meta.url).pathname), "..");
const PASTAS = ["app", "lib", "components"];

// ------------------------------------------------------------------ catálogo

function catalogoDoArquivo(caminho) {
  if (!existsSync(caminho)) {
    console.error(`Catálogo não encontrado: ${caminho}`);
    process.exit(2);
  }
  return JSON.parse(readFileSync(caminho, "utf8"));
}

function catalogoDoBanco(url) {
  const consulta = `select coalesce(jsonb_object_agg(t, cols), '{}'::jsonb)::text
    from (select table_name as t, jsonb_agg(column_name order by column_name) as cols
            from information_schema.columns
           where table_schema = 'public' group by table_name) x;`;

  const r = spawnSync("psql", [url, "--quiet", "--no-psqlrc", "--tuples-only",
                               "--no-align", "--command", consulta],
                      { encoding: "utf8" });

  if (r.status !== 0) {
    console.error(`psql falhou:\n${r.stderr ?? ""}`);
    process.exit(2);
  }
  return JSON.parse(r.stdout.trim());
}

const soListar = process.argv.includes("--listar");

const arg = process.argv.find((a) => a.startsWith("--catalogo="));
const catalogo = soListar
  ? new Proxy({}, { get: () => ["__qualquer__"], has: () => true })
  : arg
  ? catalogoDoArquivo(arg.slice("--catalogo=".length))
  : process.env.SUPABASE_DB_URL
    ? catalogoDoBanco(process.env.SUPABASE_DB_URL)
    : (console.error(
        "Falta SUPABASE_DB_URL (ou --catalogo=arquivo.json).\n\n" +
          "Esta verificação compara a tela com o BANCO, então precisa de um dos dois.",
      ),
      process.exit(2));

// -------------------------------------------------------------- as consultas

function arquivos(dir, res = []) {
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

/** O trecho da cadeia, delimitado por parênteses — janela de N chars vazaria. */
function cadeiaDe(fonte, inicio) {
  let profundidade = 0;
  for (let i = inicio; i < fonte.length; i += 1) {
    const c = fonte[i];
    if (c === "(") profundidade += 1;
    else if (c === ")") {
      profundidade -= 1;
      if (profundidade < 0) return fonte.slice(inicio, i);
    }
  }
  return fonte.slice(inicio);
}

/** `"a, b" + "c, d"` → `a, b c, d`. Com `${` no meio, devolve null. */
function literalDe(argumento) {
  if (argumento.includes("${")) return null;
  const pedacos = [...argumento.matchAll(/"([^"]*)"|'([^']*)'/g)].map(
    (m) => m[1] ?? m[2],
  );
  if (pedacos.length === 0) return null;
  // Sobrou algo que não é literal nem `+`? Então não é uma lista estática.
  const resto = argumento.replace(/"[^"]*"|'[^']*'/g, "").replace(/[+\s]/g, "");
  if (resto !== "") return null;
  return pedacos.join("");
}

/** Vírgulas de topo, respeitando os parênteses das relações embutidas. */
function porVirgula(lista) {
  const fora = [];
  let atual = "";
  let profundidade = 0;
  for (const c of lista) {
    if (c === "(") profundidade += 1;
    if (c === ")") profundidade -= 1;
    if (c === "," && profundidade === 0) {
      fora.push(atual);
      atual = "";
    } else {
      atual += c;
    }
  }
  if (atual.trim() !== "") fora.push(atual);
  return fora.map((x) => x.trim()).filter((x) => x !== "");
}

const pedidas = new Set();
const faltando = [];
const naoConferidas = [];
let conferidas = 0;

/** Confere uma lista de colunas contra uma tabela do catálogo. */
function conferir(tabela, lista, onde) {
  const colunas = catalogo[tabela];
  if (!colunas) {
    naoConferidas.push(`${onde} · tabela "${tabela}" não está no catálogo`);
    return;
  }

  for (const bruto of porVirgula(lista)) {
    // `alias:coisa` — o que vale é o lado direito.
    const semAlias = bruto.includes(":") ? bruto.slice(bruto.indexOf(":") + 1).trim() : bruto;

    // Relação embutida: `pacientes ( nome, telefone )`, com `!inner` ou dica de FK.
    const embutida = semAlias.match(/^([A-Za-z0-9_!]+)\s*\(([\s\S]*)\)$/);
    if (embutida) {
      const nome = embutida[1].split("!")[0];
      conferir(nome, embutida[2], onde);
      continue;
    }

    const nome = semAlias
      .split("->")[0]
      .split("::")[0]
      .replace(/\.(count|sum|avg|min|max)$/i, "")
      .trim();

    if (nome === "" || nome === "*" || nome === "count") continue;
    if (!/^[A-Za-z0-9_]+$/.test(nome)) {
      naoConferidas.push(`${onde} · não entendi "${bruto}"`);
      continue;
    }

    conferidas += 1;
    if (soListar) {
      pedidas.add(`${tabela}.${nome}`);
      continue;
    }
    if (!colunas.includes(nome)) {
      faltando.push(`${onde} · ${tabela}.${nome} NÃO EXISTE no banco`);
    }
  }
}

for (const pasta of PASTAS) {
  for (const arquivo of arquivos(join(RAIZ, pasta))) {
    const fonte = readFileSync(arquivo, "utf8");

    for (const achado of fonte.matchAll(/\.from\(\s*["'`]([A-Za-z0-9_]+)["'`]\s*\)/g)) {
      const tabela = achado[1];
      const cadeia = cadeiaDe(fonte, achado.index);

      const select = cadeia.match(/\.select\(([\s\S]*?)\)(?:\s*[.,;)]|\s*$)/);
      const linha = fonte.slice(0, achado.index).split("\n").length;
      const onde = `${relative(RAIZ, arquivo)}:${linha}`;

      if (!select) continue;

      const lista = literalDe(select[1]);
      if (lista === null) {
        naoConferidas.push(`${onde} · select montado em tempo de execução`);
        continue;
      }
      conferir(tabela, lista, onde);
    }
  }
}

// -------------------------------------------------------------------- relato

if (soListar) {
  console.log(JSON.stringify([...pedidas].sort()));
  process.exit(0);
}


console.log(
  `\n${conferidas} coluna(s) conferida(s) contra o banco · ` +
    `${faltando.length} inexistente(s) · ${naoConferidas.length} não conferida(s)\n`,
);

for (const l of naoConferidas) console.log(`  ~ ${l}`);
if (naoConferidas.length > 0) console.log("");

for (const l of faltando) console.log(`  ✗ ${l}`);

if (faltando.length > 0) {
  console.log(
    `\n${faltando.length} coluna(s) que a tela pede e o banco não tem. ` +
      `A tela lança em tempo de execução.\n`,
  );
  process.exit(1);
}

console.log("Nenhuma tela pede coluna que o banco não tem.\n");
