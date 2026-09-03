import Link from "next/link";
import { db } from "@/lib/db";
import { supabaseSessao } from "@/lib/supabase/server";
import { sessaoAtual } from "@/lib/conta";
import { hoje } from "@/lib/tempo-servidor";
import { formatar } from "@/lib/dinheiro";
import { duracao } from "@/lib/capacidade";
import {
  lerLivro,
  causasComPeso,
  fraseDaReceita,
  fraseDaCompletude,
  fraseDoUso,
  tituloDaCausa,
  explicaCausa,
  acaoDaCausa,
  rotuloAgenda,
  type LivroBruto,
  type EixoAgenda,
} from "@/lib/livro";

export const metadata = { title: "O que aconteceu com cada hora" };

const MESES = [
  "janeiro", "fevereiro", "março", "abril", "maio", "junho",
  "julho", "agosto", "setembro", "outubro", "novembro", "dezembro",
];

/** O mês pedido, ou o corrente. `AAAA-MM` na barra do navegador. */
function mesDe(pedido: string | undefined, agora: string) {
  const m = /^(\d{4})-(\d{2})$/.exec(pedido ?? "");
  const a = m ? Number(m[1]) : Number(agora.slice(0, 4));
  const mes = m ? Number(m[2]) : Number(agora.slice(5, 7));
  const seguro = mes >= 1 && mes <= 12 && a >= 2000 && a <= 2100;
  const aa = seguro ? a : Number(agora.slice(0, 4));
  const mm = seguro ? mes : Number(agora.slice(5, 7));
  const ultimo = new Date(Date.UTC(aa, mm, 0)).getUTCDate();
  const p = String(mm).padStart(2, "0");

  const anterior = mm === 1 ? `${aa - 1}-12` : `${aa}-${String(mm - 1).padStart(2, "0")}`;
  const proximo = mm === 12 ? `${aa + 1}-01` : `${aa}-${String(mm + 1).padStart(2, "0")}`;

  return {
    de: `${aa}-${p}-01`,
    ate: `${aa}-${p}-${String(ultimo).padStart(2, "0")}`,
    rotulo: `${MESES[mm - 1]} de ${aa}`,
    chave: `${aa}-${p}`,
    anterior,
    proximo,
  };
}

const ORDEM: EixoAgenda[] = ["realizada", "ausente", "cancelada", "reservada"];

/**
 * O livro-razão do mês.
 *
 * A tela que responde **quanto da capacidade virou receita, e por onde o resto
 * foi** — a pergunta que o produto inteiro existe para responder, e que nenhum
 * concorrente responde.
 *
 * TRÊS COISAS QUE ELA DELIBERADAMENTE NÃO MOSTRA
 *
 * **Não mostra percentual de ocupação.** Ocupação é quatro números lado a lado
 * (realizada, paga, receita por hora, perda por causa), e juntá-los é trabalho
 * do P5. Um número solitário aqui seria manipulável — reduzindo horas
 * declaradas ou deixando de reservar tempo de registro ele sobe sem nada ter
 * melhorado — e empurraria contra o descanso.
 *
 * **Não mostra botão na última causa.** "Hora nunca vendida" aparece como fato
 * e não gera sugestão de contato com ninguém. O Código de Ética veda induzir
 * pessoa a recorrer a serviços; uma lista de horas vazias com botão de oferecer
 * é isso com outro nome.
 *
 * **Não esconde a completude.** Se o sistema não conseguiu classificar tudo
 * sozinho, a tela diz — porque um livro-razão com metade das linhas em branco
 * não mede nada, e quem olha precisa saber se pode confiar no que vê.
 */
export default async function LivroRazao({
  searchParams,
}: {
  searchParams: Promise<{ mes?: string }>;
}) {
  const params = await searchParams;
  const mes = mesDe(params.mes, hoje());
  const supabase = await supabaseSessao();

  /*
    De quem é este mês.

    Era `.eq("ativo", true).limit(1)` **sem ordenação**: o Postgres pode
    devolver qualquer linha, e pode devolver uma diferente na próxima consulta.
    Numa clínica com três profissionais, o link "o mês inteiro" levava de um mês
    para outro mês, com o mesmo título e sem dizer de quem era nenhum dos dois.

    O Cockpit sempre usou o profissional da sessão. Aqui passa a ser o mesmo —
    é o que faz as duas telas falarem do mesmo mês — e a ordenação por nome só
    entra como saída, para a conta em que a sessão ainda não tem profissional.
  */
  const sessao = await sessaoAtual();

  const profs = (await db(
    "livro.profissional",
    supabase
      .from("profissionais")
      .select("id, nome")
      .eq("ativo", true)
      .order("nome")
      .order("id"),
  )) as unknown as { id: string; nome: string }[];

  const prof = profs.find((x) => x.id === sessao.profissionalId) ?? profs[0];

  if (!prof) {
    return (
      <div className="mx-auto max-w-3xl">
        <h1 className="font-serif text-[28px] leading-tight tracking-[-0.015em]">
          O que aconteceu com cada hora
        </h1>
        <p className="mt-3 text-[13.5px] text-tinta2">
          Não encontrei um profissional ativo nesta conta.
        </p>
      </div>
    );
  }

  const bruto = (await db(
    "livro.mes",
    supabase.rpc("livro_razao", { p_profissional: prof.id, p_de: mes.de, p_ate: mes.ate }),
  )) as unknown as LivroBruto;

  const l = lerLivro(bruto);
  const causas = causasComPeso(l);

  return (
    <div className="mx-auto max-w-3xl">
      <Link href="/fechamento" className="text-[12.5px] text-tinta3 hover:text-vaga">
        ← fechamento
      </Link>

      <div className="mt-2 flex flex-wrap items-baseline gap-x-4 gap-y-1">
        <h1 className="font-serif text-[28px] leading-tight tracking-[-0.015em]">
          O que aconteceu com cada hora
        </h1>
        <span className="font-mono text-[13px] tabular text-tinta2">{mes.rotulo}</span>
        {/*
          De quem é o mês — e só quando há mais de uma pessoa atendendo. Numa
          conta solo, escrever o nome dela de volta é ruído; numa clínica, a
          ausência do nome era o que fazia dois meses diferentes parecerem o
          mesmo.
        */}
        {profs.length > 1 && (
          <span className="text-[13px] text-tinta2">de {prof.nome}</span>
        )}
        <nav className="ml-auto flex items-center gap-3 text-[12.5px]">
          <Link href={`/fechamento/livro?mes=${mes.anterior}`} className="text-tinta2 hover:text-vaga">
            ← mês anterior
          </Link>
          <Link href={`/fechamento/livro?mes=${mes.proximo}`} className="text-tinta3 hover:text-vaga">
            seguinte →
          </Link>
        </nav>
      </div>

      <p className="mt-3 max-w-[64ch] text-[14px] leading-relaxed text-tinta2">
        Quanto da sua capacidade virou receita, e por onde o resto foi. Cada hora
        é contada de quatro jeitos ao mesmo tempo — o que a agenda diz, se houve
        confirmação, se o dinheiro entrou e se o imposto foi declarado —, e{" "}
        <b className="font-semibold text-tinta">nenhum deles se preenche à mão</b>.
      </p>

      {/* --------------------------------------------------------- a receita */}
      <section className="mt-7 rounded-cartao border border-linha bg-folha2 px-5 py-4">
        <h2 className="rotulo">A receita reconhecida</h2>
        <p className="mt-2 font-mono text-[26px] leading-none tabular-nums text-tinta">
          {formatar(Math.round(l.receita * 100))}
        </p>
        <p className="mt-3 max-w-[60ch] text-[13px] leading-relaxed text-tinta2">
          {fraseDaReceita(l)}
        </p>
        <p className="mt-2 max-w-[60ch] text-[11.5px] leading-relaxed text-tinta3">
          Só entra aqui hora que <b className="font-medium">aconteceu</b>. Dinheiro
          recebido adiantado de sessão futura fica de fora até a sessão acontecer —
          senão este número subiria recebendo por hora que ainda não existiu.
        </p>
      </section>

      {/* ----------------------------------------------------------- os eixos */}
      <section className="mt-8">
        <h2 className="rotulo">As horas do mês</h2>
        <dl className="mt-3 flex flex-wrap gap-x-8 gap-y-3">
          {ORDEM.map((e) => (
            <div key={e}>
              <dt className="text-[11.5px] text-tinta3">{rotuloAgenda(e)}</dt>
              <dd className="font-mono text-[18px] tabular-nums text-tinta">{l.horas[e]}</dd>
            </div>
          ))}
        </dl>
        <p className="mt-3 max-w-[62ch] text-[12.5px] leading-relaxed text-tinta2">
          {fraseDoUso(l)}
        </p>
        {l.capacidade.semJanela && (
          <p className="mt-2 max-w-[62ch] text-[12px] leading-relaxed text-tinta3">
            <Link href="/perfil/horarios" className="underline underline-offset-2 hover:text-vaga">
              Declare os seus horários
            </Link>{" "}
            para o sistema ter com o que comparar.
          </p>
        )}
      </section>

      {/* ---------------------------------------------------- a perda por causa */}
      <section className="mt-9">
        <h2 className="rotulo">Por onde o resto foi</h2>

        {causas.length === 0 ? (
          <p className="mt-3 max-w-[62ch] text-[13px] leading-relaxed text-tinta2">
            Nada a separar neste mês: nenhuma falta, nenhum cancelamento, nenhuma
            hora reposta.
          </p>
        ) : (
          <ul className="mt-3 overflow-hidden rounded-cartao border border-linha bg-folha">
            {causas.map((c) => {
              const acao = acaoDaCausa(c.causa);
              return (
                <li key={c.causa} className="border-t border-linha px-5 py-4 first:border-t-0">
                  <div className="flex flex-wrap items-baseline gap-x-3 gap-y-1">
                    <span className="text-[13.5px] font-medium text-tinta">
                      {tituloDaCausa(c.causa)}
                    </span>
                    {c.n !== null && c.n > 0 && (
                      <span className="text-[12px] text-tinta3">
                        {c.n} hora{c.n > 1 ? "s" : ""}
                      </span>
                    )}
                    {c.minutos != null && c.minutos > 0 && (
                      <span className="text-[12px] text-tinta3">{duracao(c.minutos)}</span>
                    )}
                    {c.valor !== null && c.valor > 0 && (
                      <span className="ml-auto font-mono text-[14px] tabular-nums text-tinta2">
                        {formatar(Math.round(c.valor * 100))}
                      </span>
                    )}
                  </div>

                  <p className="mt-1.5 max-w-[62ch] text-[12.5px] leading-relaxed text-tinta2">
                    {explicaCausa(c.causa)}
                  </p>

                  {acao && (
                    <Link
                      href={acao.href}
                      className="toque mt-2 inline-block text-[12px] text-tinta3 underline decoration-linha2 underline-offset-4 hover:text-vaga"
                    >
                      {acao.rotulo}
                    </Link>
                  )}
                </li>
              );
            })}
          </ul>
        )}

        <p className="mt-3 max-w-[62ch] text-[11.5px] leading-relaxed text-tinta3">
          A <b className="font-medium">hora nunca vendida</b> não tem botão, e é de
          propósito: ela é um fato sobre o mês, não uma lista de gente para
          procurar. Capacidade sem comprador é ausência de demanda — se existe
          alguém que queria aquele horário, quem sabe é a{" "}
          <Link href="/encaixes" className="underline underline-offset-2 hover:text-vaga">
            fila
          </Link>
          , onde a pessoa pediu.
        </p>
      </section>

      {/* -------------------------------------------------------- a completude */}
      <section className="mt-9 border-t border-linha pt-6">
        <h2 className="rotulo">Dá para confiar neste mês?</h2>
        <p className="mt-2 max-w-[62ch] text-[13px] leading-relaxed text-tinta2">
          {fraseDaCompletude(l)}
        </p>
      </section>

      {/*
        Aqui havia 52 palavras explicando que "ainda não há percentual de ocupação
        nesta tela, e é decisão" — e a lista dos quatro números que apareceriam um
        dia. Os quatro **já existem** desde o P5, na agenda, e são exatamente os
        que o parágrafo prometia. A tela negava um recurso do produto para quem
        estava lendo o produto.

        O parágrafo era duas coisas erradas ao mesmo tempo: texto de projeto no
        meio de uma tarefa, e promessa envelhecida ao contrário. As duas saem.
      */}
    </div>
  );
}
