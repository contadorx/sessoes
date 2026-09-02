import Link from "next/link";
import { lerTrilha } from "./dados";
import { hoje } from "@/lib/tempo-servidor";
import { somarDias } from "@/lib/semana";
import {
  ACOES_CLINICAS,
  rotuloDaAcao,
  ehClinica,
  fraseDaLinha,
  fraseDoTamanho,
  fraseDaImutabilidade,
  type LinhaDaTrilha,
} from "@/lib/trilha";

export const metadata = { title: "A sua trilha de acesso" };

/** Hora civil de São Paulo, nunca a do servidor (que na Vercel é UTC). */
const DIA_E_HORA = new Intl.DateTimeFormat("pt-BR", {
  timeZone: "America/Sao_Paulo",
  day: "2-digit",
  month: "2-digit",
  year: "numeric",
  hour: "2-digit",
  minute: "2-digit",
});

const DATA = /^\d{4}-\d{2}-\d{2}$/;
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

/** Os últimos 30 dias, contando hoje. */
function periodoPadrao(): { de: string; ate: string } {
  const ate = hoje();
  return { de: somarDias(ate, -29), ate };
}

/**
 * A trilha de acesso, lida por quem ela protege (B33, metade 1).
 *
 * A `trilha_acesso` é gravada desde a B13, é carimbada pelo servidor e não
 * aceita edição nem exclusão — nem pela conta que a gerou. O que nunca existiu
 * foi esta tela, e sem ela a propriedade era promessa de documento: em 02/09 a
 * exportação da conta ficou três horas sem deixar rastro e só uma suíte notou.
 * **Registro que ninguém lê é registro que só serve depois do problema.**
 *
 * Três decisões de tela, e todas são a mesma decisão:
 *
 *   · **a frase da imutabilidade fica no topo**, e não em nota de rodapé. É ela
 *     que transforma a lista em defesa, e o dia em que a psicóloga precisar da
 *     trilha é o dia em que ela vai estar aqui — não relendo a política;
 *   · **nada é filtrado nem escondido.** As linhas clínicas ganham peso visual
 *     e ficam no mesmo lugar das outras; o `detalhe` cru aparece junto;
 *   · **a recusa do banco aparece como texto.** Zero linhas em silêncio numa
 *     tela de auditoria é indistinguível de "ninguém acessou nada".
 */
export default async function Trilha({
  searchParams,
}: {
  searchParams: Promise<{ de?: string; ate?: string; paciente?: string }>;
}) {
  const { de: dePedido, ate: atePedido, paciente: pacientePedido } = await searchParams;

  const padrao = periodoPadrao();
  const de = DATA.test(dePedido ?? "") ? dePedido! : padrao.de;
  const ate = DATA.test(atePedido ?? "") ? atePedido! : padrao.ate;
  const paciente = UUID.test(pacientePedido ?? "") ? pacientePedido! : null;

  const leitura = await lerTrilha(de, ate, paciente);

  return (
    <div className="mx-auto max-w-3xl">
      <Link href="/perfil" className="text-[12.5px] text-tinta3 hover:text-vaga">
        ← perfil
      </Link>

      <h1 className="mt-2 font-serif text-[28px] leading-tight tracking-[-0.015em]">
        A sua trilha de acesso
      </h1>

      {/* ------------------------------------------------- a frase que a torna defesa

          No topo, em destaque, e não numa nota no fim da página. Ela não
          descreve uma funcionalidade: ela descreve por que esta lista vale
          alguma coisa numa discussão em que alguém está sendo acusado. */}
      <p className="mt-4 max-w-[68ch] rounded-cartao border border-linha2 bg-folha px-5 py-4 text-[13.5px] leading-relaxed text-tinta">
        {fraseDaImutabilidade()}
      </p>

      {leitura.estado === "recusada" ? (
        /* A mensagem do banco, inteira. A 0063 recusa em voz alta justamente
           para esta tela não conseguir mostrar uma lista vazia no lugar. */
        <section className="mt-6 rounded-cartao border border-vaga-linha bg-vaga-bg px-5 py-4">
          <p className="max-w-[62ch] text-[13.5px] leading-relaxed text-tinta">
            {leitura.motivo}
          </p>
          <p className="mt-2 max-w-[62ch] text-[12px] leading-relaxed text-tinta2">
            Esta tela não mostra uma lista vazia quando não consegue ler: numa
            trilha de acesso, nenhuma linha e nenhuma leitura são a mesma
            imagem, e só uma delas é verdade.
          </p>
        </section>
      ) : (
        <>
          <p className="mt-3 max-w-[68ch] text-[13px] leading-relaxed text-tinta2">
            {fraseDoTamanho(leitura.tamanho)} Aqui embaixo está o período
            escolhido, do mais recente para o mais antigo.
          </p>

          {/* --------------------------------------------------------- o recorte

              Um formulário `GET` simples: o período vira `?de=` e `?ate=` na
              URL, do mesmo jeito que a agenda guarda a semana. Assim um recorte
              se compartilha por link — e um link é o que se manda para quem
              está perguntando.

              **Não há filtro por ação, e isso é a decisão principal desta
              tela.** Uma tela de auditoria com filtro por tipo de evento é uma
              tela onde o evento inconveniente é o que ninguém marca: quem
              procura alguma coisa recorta por *quando* e por *quem*, e nunca
              sabe de antemão o nome do que está procurando. A função do banco
              também não oferece esse filtro (0063), e a tela não inventa um. */}
          <form method="get" className="mt-5 flex flex-wrap items-end gap-3 rounded-cartao border border-linha bg-folha2 px-5 py-4">
            {paciente && <input type="hidden" name="paciente" value={paciente} />}
            <div>
              <label htmlFor="de" className="block text-[12px] font-medium text-tinta2">
                de
              </label>
              <input
                type="date"
                id="de"
                name="de"
                defaultValue={de}
                className="mt-1 rounded border border-linha2 bg-folha px-2 py-1.5 text-[12.5px] text-tinta"
              />
            </div>
            <div>
              <label htmlFor="ate" className="block text-[12px] font-medium text-tinta2">
                até
              </label>
              <input
                type="date"
                id="ate"
                name="ate"
                defaultValue={ate}
                className="mt-1 rounded border border-linha2 bg-folha px-2 py-1.5 text-[12.5px] text-tinta"
              />
            </div>
            <button
              type="submit"
              className="rounded-full border border-linha2 px-4 py-2 text-[12.5px] font-medium text-tinta2 transition-colors hover:bg-folha"
            >
              Ver o período
            </button>
            {paciente && (
              <Link
                href="/perfil/trilha"
                className="pb-1 text-[12.5px] text-tinta3 underline underline-offset-2 hover:text-vaga"
              >
                mostrando só uma pessoa — ver todas
              </Link>
            )}
          </form>

          {/* ------------------------------------------------------- as linhas */}
          {leitura.linhas.length === 0 ? (
            <p className="mt-6 rounded-cartao border border-linha bg-folha px-5 py-4 text-[13px] leading-relaxed text-tinta2">
              Nenhum acesso registrado neste período. A trilha foi lida — o que
              não houve foi acesso entre {diaBR(de)} e {diaBR(ate)}.
            </p>
          ) : (
            <>
              <ol className="mt-6 overflow-hidden rounded-cartao border border-linha bg-folha">
                {leitura.linhas.map((l, i) => (
                  <Linha key={`${l.em}-${i}`} l={l} />
                ))}
              </ol>
              <Legenda />
            </>
          )}

          {leitura.linhas.length >= 500 && (
            <p className="mt-3 text-[12px] leading-relaxed text-tinta3">
              São 500 linhas — o máximo que sai de uma vez. Encurte o período
              para ver o que ficou de fora; nada foi descartado.
            </p>
          )}
        </>
      )}

      <p className="mt-8 max-w-[68ch] border-t border-linha pt-5 text-[11.5px] leading-relaxed text-tinta3">
        A trilha inteira também sai no arquivo de{" "}
        <Link href="/perfil" className="underline underline-offset-2 hover:text-vaga">
          exportar a conta
        </Link>
        , desde sempre. Ela não é apagada por retenção nem por limpeza: dura o
        que a conta durar.
      </p>
    </div>
  );
}

/** "12/03/2026" a partir de "2026-03-12", sem passar por `Date` com fuso. */
function diaBR(iso: string): string {
  const [a, m, d] = iso.split("-");
  return `${d}/${m}/${a}`;
}

/**
 * Uma linha da trilha.
 *
 * As de conteúdo clínico ganham uma barra à esquerda no rosa da hora vazia e o
 * verbo em tinta cheia. É **peso visual, não recorte**: elas estão na mesma
 * lista, na mesma ordem, e nada aqui as separa em outra aba. Destacar sem
 * separar é a diferença entre ajudar a achar e decidir o que a pessoa vê.
 */
function Linha({ l }: { l: LinhaDaTrilha }) {
  const clinica = ehClinica(l.acao);
  const detalhes = Object.entries(l.detalhe ?? {});

  return (
    <li
      className={`border-t border-linha px-5 py-3 first:border-t-0 ${
        clinica ? "border-l-2 border-l-vaga bg-vaga-bg/30" : ""
      }`}
    >
      <div className="flex flex-wrap items-baseline gap-x-3 gap-y-1">
        <time
          dateTime={l.em}
          className="tabular shrink-0 font-mono text-[12px] text-tinta3"
        >
          {DIA_E_HORA.format(new Date(l.em))}
        </time>
        <span className={`text-[13.5px] leading-relaxed ${clinica ? "text-tinta" : "text-tinta2"}`}>
          {/* A frase inteira vem de `lib/trilha`: "quem fez o quê, com quem",
              no passado e com sujeito. Substantivo abstrato é o jeito mais
              rápido de uma linha de auditoria não responder a pergunta que
              alguém veio fazer. */}
          {fraseDaLinha(l)}
        </span>
        {l.saiu && (
          <span className="rounded-full bg-folha2 px-2 py-0.5 text-[11px] text-tinta3">
            não está mais na conta
          </span>
        )}
      </div>

      {/* O `detalhe` cru, como o banco gravou. Feio e pequeno, e presente: é
          onde mora o que a tela não sabia nomear no dia em que gravou. */}
      {detalhes.length > 0 && (
        <p className="mt-1 font-mono text-[11px] leading-relaxed text-tinta3">
          {detalhes
            .map(([k, v]) => `${k}: ${typeof v === "object" ? JSON.stringify(v) : String(v)}`)
            .join(" · ")}
        </p>
      )}
    </li>
  );
}

/**
 * O que a barra rosa quer dizer.
 *
 * A legenda existe para o destaque não virar mistério — e é onde
 * `rotuloDaAcao` mostra o segundo serviço que ele presta: uma ação que esta
 * versão da tela não conhece aparece com o nome cru, em vez de sumir. O evento
 * novo é justamente o que ninguém previu, e é o que se procura quando se
 * procura alguma coisa.
 */
function Legenda() {
  return (
    <p className="mt-3 max-w-[68ch] text-[11.5px] leading-relaxed text-tinta3">
      A barra rosa marca o que toca conteúdo clínico —{" "}
      {ACOES_CLINICAS.map(rotuloDaAcao).join(", ")}. É só peso visual: as linhas
      continuam na mesma lista, na mesma ordem, e não há como esconder as
      outras.
    </p>
  );
}
