import { Fragment } from "react";
import Link from "next/link";
import { copiaDoPaciente } from "./dados";
import { Imprimir } from "@/components/app/Imprimir";
import { formatar, paraCentavos } from "@/lib/dinheiro";
import {
  SECOES,
  FORA_DAS_SECOES,
  MARCA_PADRAO,
  AUSENCIA_PADRAO,
  rotuloDoCampo,
  ehOculto,
} from "@/lib/trilha";

export const metadata = { title: "Cópia do registro" };

const DIA_E_HORA = new Intl.DateTimeFormat("pt-BR", {
  timeZone: "America/Sao_Paulo",
  day: "2-digit",
  month: "2-digit",
  year: "numeric",
  hour: "2-digit",
  minute: "2-digit",
});

const SO_DATA = /^\d{4}-\d{2}-\d{2}$/;
const DATA_E_HORA = /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}/;

/**
 * As colunas que são dinheiro.
 *
 * `formatar` recebe **centavos inteiros**, e o banco devolve `numeric(12,2)`
 * como string — por isso a conversão passa sempre por `paraCentavos`, que é a
 * fronteira onde a lei nº 4 do doc 05 é obedecida. Escrever `R$ 200.00` num
 * documento que a pessoa leva ao convênio seria estrago pequeno; somar float
 * seria estrago grande, e nenhum dos dois acontece aqui.
 */
const DINHEIRO = new Set([
  "valor",
  "valor_reconhecido",
  "valor_total",
  "valor_anterior",
  "mensalidade_valor",
  "taxa",
]);

/**
 * A cópia legível do registro (B33, metade 2).
 *
 * O direito de acesso da Res. CFP 001/2009 não se exerce com um arquivo que a
 * pessoa não sabe abrir. A rota irmã (`../route.ts`) continua existindo e
 * continua devolvendo o mesmo jsonb: **portabilidade é direito de máquina,
 * legibilidade é direito de pessoa, e as duas coisas não são a mesma.** Quem
 * troca de sistema quer o JSON; quem quer ler o próprio prontuário quer uma
 * folha. Trocar um pelo outro tira um direito para dar o outro.
 *
 * O PDF é do navegador, como todo documento daqui (ver `Imprimir`): o motor de
 * impressão respeita a tipografia da página e nunca sai torto num mês com dez
 * sessões, que é onde um layout de posição fixa quebra.
 */
export default async function CopiaImpressa({
  params,
  searchParams,
}: {
  params: Promise<{ id: string }>;
  searchParams: Promise<{ ciente?: string }>;
}) {
  const { id } = await params;
  const { ciente } = await searchParams;

  const copia = await copiaDoPaciente(id, ciente === "1");

  if (copia.estado === "erro") {
    return (
      <div className="nao-imprime rounded-cartao border border-vaga-linha bg-vaga-bg px-5 py-4">
        <p className="max-w-[62ch] text-[13.5px] leading-relaxed text-tinta">{copia.motivo}</p>
        {copia.restrito && (
          <>
            <p className="mt-2 max-w-[62ch] text-[12.5px] leading-relaxed text-tinta2">
              Responsáveis de menor têm acesso mesmo sem a guarda — <b>salvo</b>{" "}
              decisão judicial. Ao continuar, você declara que conhece a decisão
              e que a entrega respeita o que ela determina.
            </p>
            <Link
              href={`/pacientes/${id}/exportar/imprimir?ciente=1`}
              className="mt-3 inline-block rounded-full border border-linha2 bg-folha px-4 py-2 text-[12.5px] font-medium text-tinta2 transition-colors hover:bg-folha2"
            >
              Conheço a decisão, gerar a cópia
            </Link>
          </>
        )}
      </div>
    );
  }

  const d = copia.dados;

  // A marca e a nota vêm do banco; as constantes de `lib/trilha` são rede, e
  // não a fonte. A mesma frase precisa estar no JSON e no papel — senão são
  // dois documentos diferentes com o mesmo nome.
  const marca = texto(d.aviso) ?? MARCA_PADRAO;
  const ausencia = texto(d.nota_sobre_o_que_nao_esta_aqui) ?? AUSENCIA_PADRAO;
  const geradoEm = texto(d.gerado_em);
  const nome =
    texto((d.paciente as Record<string, unknown> | null | undefined)?.nome) ?? "—";

  const conhecidas = new Set<string>([
    ...SECOES.map((s) => s.chave),
    ...FORA_DAS_SECOES,
  ]);
  const extras = Object.keys(d).filter((k) => !conhecidas.has(k));

  const urlJson =
    ciente === "1" ? `/pacientes/${id}/exportar?ciente=1` : `/pacientes/${id}/exportar`;

  return (
    <div>
      {/* -------------------------------------------- o que não vai para o papel */}
      <div className="nao-imprime">
        <div className="rounded-cartao border border-linha bg-folha2 px-4 py-3">
          <p className="max-w-[62ch] text-[13px] leading-relaxed text-tinta2">
            Esta é a cópia que a pessoa lê. Imprima, ou salve em PDF pela própria
            janela de impressão do navegador.
          </p>
          {/* A rota JSON **continua existindo e não muda**. Ela está aqui ao
              lado, e não substituída: portabilidade é direito de máquina —
              levar o registro para outro sistema sem perder estrutura —, e
              legibilidade é direito de pessoa. Um arquivo que a pessoa não
              sabe abrir cumpre o primeiro e não cumpre o segundo. */}
          <p className="mt-2 max-w-[62ch] text-[12px] leading-relaxed text-tinta3">
            Para levar os dados a outro sistema, o formato é outro:{" "}
            <a href={urlJson} className="underline underline-offset-2 hover:text-vaga">
              baixar em JSON
            </a>
            . Os dois documentos têm o mesmo conteúdo e servem a direitos
            diferentes.
          </p>
        </div>

        <div className="mt-4">
          <Imprimir />
        </div>
      </div>

      {/* ------------------------------------------------------------- o papel */}
      <article className="papel mt-6 rounded-cartao border border-linha bg-folha px-8 py-10">
        {/* A marca de sigilo abre o documento. No fim, ela chegaria depois de
            quem lê já ter lido tudo — e quem recebe uma folha solta na mão
            precisa saber o que ela é antes de ler a primeira linha. */}
        <p className="border-b border-linha2 pb-3 text-[11px] font-semibold uppercase tracking-wider text-tinta2">
          {marca}
        </p>

        <h1 className="mt-6 font-serif text-[23px] leading-tight tracking-[-0.01em] text-tinta">
          Cópia do registro de {nome}
        </h1>
        {geradoEm && (
          <p className="mt-1 font-mono text-[12px] text-tinta3">
            gerada em {DIA_E_HORA.format(new Date(geradoEm))}
          </p>
        )}

        {/* As seções na ordem em que o leitor pergunta: quem ele é aqui, o que
            foi combinado, o que aconteceu, o que foi escrito. Uma seção que a
            função deixar de devolver não aparece. */}
        {SECOES.filter((s) => s.chave in d).map((s) => (
          <Secao key={s.chave} titulo={s.titulo} nota={s.nota} valor={d[s.chave]} />
        ))}

        {/* Uma seção nova, que a função passou a devolver e esta tela ainda não
            sabe nomear, **aparece no fim com o rótulo cru**. Sumir seria pior:
            é a mesma escolha de `rotuloDaAcao` na trilha — o que a tela não
            conhece é justamente o que ninguém previu. */}
        {extras.map((chave) => (
          <Secao key={chave} titulo={chave} valor={d[chave]} crua />
        ))}

        {/* O que **não** está aqui, dito aqui. É o que impede a cópia de
            parecer completa quando não é — a diferença entre uma omissão e uma
            fronteira. */}
        <p className="mt-10 border-t border-linha pt-3 text-[10.5px] leading-relaxed text-tinta3">
          {ausencia}
        </p>
      </article>
    </div>
  );
}

/** Uma seção do documento: um registro só, ou uma lista deles. */
function Secao({
  titulo,
  nota,
  valor,
  crua = false,
}: {
  titulo: string;
  nota?: string;
  valor: unknown;
  crua?: boolean;
}) {
  const lista = Array.isArray(valor) ? (valor as unknown[]) : null;
  const vazia = valor === null || valor === undefined || (lista !== null && lista.length === 0);

  return (
    <section className="mt-8">
      <h2
        className={
          crua
            ? "font-mono text-[13px] text-tinta2"
            : "font-serif text-[17px] leading-tight text-tinta"
        }
      >
        {titulo}
      </h2>
      {crua && (
        <p className="mt-0.5 text-[11px] leading-relaxed text-tinta3">
          Seção nova, ainda sem nome próprio nesta tela. Ela aparece assim mesmo.
        </p>
      )}
      {nota && <p className="mt-0.5 text-[12px] leading-relaxed text-tinta3">{nota}</p>}

      {vazia ? (
        <p className="mt-2 text-[13px] text-tinta3">Nada registrado.</p>
      ) : lista ? (
        <ol className="mt-2 space-y-4">
          {lista.map((item, i) => (
            <li key={i} className="border-t border-linha pt-3 first:border-t-0 first:pt-0">
              <Registro valor={item} />
            </li>
          ))}
        </ol>
      ) : (
        <Registro valor={valor} />
      )}
    </section>
  );
}

/** Um objeto do jsonb, campo a campo. */
function Registro({ valor }: { valor: unknown }) {
  if (typeof valor !== "object" || valor === null) {
    return <p className="mt-2 whitespace-pre-line text-[13px] leading-relaxed text-tinta">{String(valor)}</p>;
  }

  // Campos ocultos não vão para o papel: ids não dizem nada a quem lê, e o
  // `token` está fora pela lição da 0059c — um link mágico dentro de um arquivo
  // que a pessoa guarda no computador.
  const pares = Object.entries(valor as Record<string, unknown>).filter(
    ([k, v]) => !ehOculto(k) && v !== null && v !== undefined && v !== "",
  );

  if (pares.length === 0) {
    return <p className="mt-2 text-[13px] text-tinta3">Sem campos preenchidos.</p>;
  }

  return (
    <dl className="mt-2 grid gap-x-6 gap-y-1.5 sm:grid-cols-[13rem_1fr]">
      {pares.map(([chave, v]) => (
        <Fragment key={chave}>
          <dt className="text-[12px] leading-relaxed text-tinta3">{rotuloDoCampo(chave)}</dt>
          <dd className="whitespace-pre-line text-[13px] leading-relaxed text-tinta">
            {textoDoCampo(chave, v)}
          </dd>
        </Fragment>
      ))}
    </dl>
  );
}

/**
 * O valor como a pessoa lê.
 *
 * A data é reconhecida **pelo formato do valor**, e não por uma lista de nomes
 * de coluna. Lista escrita à mão nunca reprova o item que ninguém pôs nela —
 * foi assim que `exportar_conta` esqueceu dezessete tabelas (0059b) —, e uma
 * coluna de data nova sairia aqui como texto ISO cru.
 */
function textoDoCampo(chave: string, v: unknown): string {
  if (typeof v === "boolean") return v ? "sim" : "não";

  if (DINHEIRO.has(chave) && (typeof v === "string" || typeof v === "number")) {
    try {
      return formatar(paraCentavos(v));
    } catch {
      return String(v);
    }
  }

  if (typeof v === "string") {
    if (SO_DATA.test(v)) {
      const [a, m, dia] = v.split("-");
      return `${dia}/${m}/${a}`;
    }
    if (DATA_E_HORA.test(v)) return DIA_E_HORA.format(new Date(v));
    return v;
  }

  if (typeof v === "number") return v.toLocaleString("pt-BR");

  return JSON.stringify(v);
}

/** String do jsonb, ou nada — sem inventar um valor no lugar. */
function texto(v: unknown): string | null {
  return typeof v === "string" && v.trim() !== "" ? v : null;
}
