import Link from "next/link";
import { notFound } from "next/navigation";
import { db } from "@/lib/db";
import { supabaseServer } from "@/lib/supabase/server";
import { Confirmacao } from "@/components/publico/Confirmacao";
import { PixCopia } from "@/components/publico/PixCopia";
import { Meses } from "@/components/app/Meses";
import { fraseDosMeses } from "@/lib/meses";
import {
  saudacao,
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
  PAGINA_VAZIA,
  type PaginaDoPaciente,
} from "@/lib/pagina-do-paciente";

/**
 * Título neutro e `noindex`, pelas mesmas duas razões da B19 e da B21.
 *
 * O título é o que aparece na prévia do link dentro do WhatsApp, na aba do
 * navegador e no histórico — três telas que outra pessoa pode estar olhando. E
 * um token vazado que também estivesse indexado deixaria de ser um acidente
 * para virar uma página pública.
 *
 * **"Sua página" é o mais neutro que dá para escrever.** "Seus horários"
 * contaria uma parte, "Pagamentos" contaria outra, e qualquer palavra que
 * remeta a consultório na tela de bloqueio de alguém é a fronteira D3 do doc
 * 11 — a mesma que faz o modo discreto existir.
 */
export const metadata = {
  title: "Sua página",
  robots: { index: false, follow: false },
  openGraph: { title: "Sua página", description: "" },
};

export const dynamic = "force-dynamic";

/**
 * A página transacional única (P7).
 *
 * **É uma janela, não um arquivo.** Ela responde "o que está esperando por
 * mim agora?" — nunca "o que já aconteceu comigo?". Os três recortes vêm
 * prontos do banco (`pagina_do_paciente`, migração 0066) e esta tela não
 * filtra nada: se ela filtrasse, existiriam dois lugares decidindo o que o
 * paciente vê, e o dia em que discordassem seria o dia em que alguém veria o
 * que não devia.
 *
 * O que esta tela acrescenta ao que o banco devolve é **a explicação do
 * recorte**. Sem ela, quem procurar um recibo antigo aqui conclui que o recibo
 * sumiu — e depois que o consultório perdeu os documentos dele. Dizer o
 * recorte transforma uma ausência numa regra, e regra a pessoa entende.
 */
export default async function PaginaDoPaciente({
  params,
}: {
  params: Promise<{ token: string }>;
}) {
  const { token } = await params;
  const supabase = supabaseServer();

  const visto =
    ((await db(
      "paciente.pagina",
      supabase.rpc("pagina_do_paciente", { p_token: token }),
    )) as unknown as PaginaDoPaciente) ?? PAGINA_VAZIA;

  if (!visto || visto.estado === "inexistente") notFound();

  const confirmar = visto.confirmar ?? [];
  const pagar = visto.pagar ?? [];
  const documentos = visto.documentos ?? [];
  const meses = visto.meses ?? [];

  return (
    <main className="mx-auto max-w-lg px-5 py-10 sm:px-8 sm:py-16">
      <h1 className="font-serif text-[26px] leading-tight tracking-[-0.015em]">
        {saudacao(visto.nome)}
      </h1>

      {visto.estado !== "aberta" && (
        <p className="mt-4 rounded-cartao border border-linha bg-folha2 px-5 py-4 text-[14.5px] leading-relaxed text-tinta2">
          {rotuloDoEstado(visto.estado)}
        </p>
      )}

      {visto.estado === "aberta" && !temAlgoAberto(visto) && (
        <p className="mt-4 rounded-cartao border border-linha bg-folha2 px-5 py-4 text-[14.5px] leading-relaxed text-tinta2">
          {fraseDoVazio()}
        </p>
      )}

      {visto.estado === "aberta" && confirmar.length > 0 && (
        <section className="mt-8">
          <h2 className="rotulo">
            {confirmar.length === 1 ? "Um horário para confirmar" : "Horários para confirmar"}
          </h2>
          <div className="mt-3 flex flex-col gap-3">
            {confirmar.map((c) => (
              <Confirmacao key={c.sessao} token={token} item={c} />
            ))}
          </div>
        </section>
      )}

      {visto.estado === "aberta" && pagar.length > 0 && (
        <section className="mt-9">
          <h2 className="rotulo">Para pagar</h2>
          <div className="mt-3 flex flex-col gap-3">
            {pagar.map((p) => (
              <div key={p.cobranca} className="rounded-cartao border border-linha bg-folha p-5">
                <p className="tabular font-mono text-[20px] font-medium leading-none text-tinta">
                  {valorEmReais(p.valor)}
                </p>
                <p className="mt-1.5 text-[13px] leading-relaxed text-tinta2">
                  {rotuloDoMotivo(p.tipo)}
                </p>

                <p className="mt-3 text-[12.5px] leading-relaxed text-tinta2">
                  {fraseDoPix(p)}
                </p>

                {p.pix && p.pix.trim().length > 0 && <PixCopia codigo={p.pix} />}
              </div>
            ))}
          </div>

          {/* Nenhuma palavra de cobrança, e é a mesma régua da B18: quem lê
              aqui é a mesma pessoa que leria a mensagem, e a régua não endurece
              por mudar de tela. O que a linha faz é devolver a palavra a ele. */}
          <p className="mt-3 text-[12.5px] leading-relaxed text-tinta3">
            Se quiser conversar sobre qualquer um desses valores, é só falar com
            quem te enviou este link.
          </p>
        </section>
      )}

      {visto.estado === "aberta" && documentos.length > 0 && (
        <section className="mt-9">
          <h2 className="rotulo">Seus documentos</h2>
          <div className="mt-3 flex flex-col gap-2">
            {documentos.map((d) => (
              <Link
                key={d.documento}
                href={`/p/agora/${token}/documento/${d.documento}`}
                className="flex items-baseline justify-between gap-3 rounded-cartao border border-linha bg-folha px-5 py-4 transition-colors hover:border-tinta3 hover:bg-folha2"
              >
                <span>
                  <span className="text-[14.5px] text-tinta">{rotuloDoDocumento(d.tipo)}</span>
                  <span className="mt-0.5 block text-[12px] text-tinta3">
                    nº {numeroDoDocumento(d.numero)} · {dia(d.emitido_em)}
                  </span>
                </span>
                <span className="shrink-0 text-[12.5px] font-medium text-vaga">abrir</span>
              </Link>
            ))}
          </div>
        </section>
      )}

      {/* Os meses (B54, §5.4).

          **O que esta seção resolve é uma conversa por WhatsApp.** Quem precisa
          pedir reembolso ao plano pergunta à psicóloga o que pagou em agosto e
          se já tem recibo; ela procura, responde, e as duas gastam a semana
          nisso. Aqui está escrito, com as mesmas três marcas que ela vê do
          lado dela — a mesma função monta as duas.

          O recorte é dito em voz alta pelo mesmo motivo dos outros três: quem
          procurar março e não achar conclui que o consultório perdeu, não que a
          página tem tamanho. */}
      {visto.estado === "aberta" && meses.length > 0 && (
        <section className="mt-9">
          <h2 className="rotulo">Os seus meses</h2>
          <Meses
            linhas={meses}
            comJanela
            linkDoRecibo={(l) => (l.recibo ? `/p/agora/${token}/documento/${l.recibo}` : null)}
          />
          <p className="mt-3 text-[12px] leading-relaxed text-tinta3">{fraseDosMeses()}</p>
        </section>
      )}

      {/* A pré-ficha (PR4).
          
          Fica **sempre** à vista, e não só quando falta preencher: telefone
          trocado e CPF que faltava são as duas coisas que a pessoa quer
          corrigir sozinha, e um caminho que só existe uma vez obriga a pedir
          outro link por WhatsApp para arrumar um dígito.

          A frase diz o que há do outro lado antes do toque. Quem recebe um
          link de consultório antes da primeira sessão espera um questionário —
          é o que os outros mandam —, e a pessoa que abre esperando falar de si
          e encontra um formulário de cadastro fica com a impressão errada nas
          duas direções. */}
      {visto.estado === "aberta" && (
        <section className="mt-9 border-t border-linha pt-6">
          <h2 className="rotulo">Seu cadastro</h2>
          <Link
            href={`/p/agora/${token}/ficha`}
            className="mt-3 flex items-center justify-between gap-4 rounded-cartao border border-linha bg-folha px-5 py-4 transition-colors hover:bg-folha2"
          >
            <span>
              <span className="text-[14.5px] text-tinta">Conferir os seus dados</span>
              <span className="mt-0.5 block text-[12px] leading-relaxed text-tinta3">
                Nome, nascimento, contato e como prefere ser avisada. Nenhuma
                pergunta sobre você.
              </span>
            </span>
            <span className="shrink-0 text-[12.5px] font-medium text-vaga">abrir</span>
          </Link>
        </section>
      )}

      {visto.estado === "aberta" && (
        <p className="mt-10 border-t border-linha pt-5 text-[12.5px] leading-relaxed text-tinta3">
          {fraseDaJanela()}
        </p>
      )}

      {/* O mesmo rodapé das outras duas páginas de `/p/`, e ele é a promessa
          que o desenho cumpre: a página não pede login, não pede cadastro e não
          guarda nada de quem abre.

          A frase mudou nesta build, e a mudança é honestidade: com a pré-ficha,
          a página passou a **pedir** uma coisa — os dados do cadastro. Deixar
          escrito "não pede nada" ao lado de um formulário seria a promessa que
          o software não cumpre, ao contrário. */}
      <p className="mt-4 text-[12px] leading-relaxed text-tinta3">
        Esta página existe só para você e só enquanto houver algo em aberto. O
        único dado que ela pede é o do seu cadastro, e ela não mostra nada além
        do que está aqui.
      </p>
    </main>
  );
}
