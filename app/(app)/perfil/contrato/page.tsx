import Link from "next/link";
import { db } from "@/lib/db";
import { supabaseSessao } from "@/lib/supabase/server";
import { sessaoAtual } from "@/lib/conta";
import { EditorDeContrato } from "@/components/app/Contrato";

export const metadata = { title: "O combinado por escrito" };

type ContratoLinha = {
  id: string;
  versao: number;
  titulo: string;
  corpo: string;
  publicado_em: string | null;
};

const DIA = new Intl.DateTimeFormat("pt-BR", {
  timeZone: "America/Sao_Paulo",
  day: "2-digit",
  month: "2-digit",
  year: "numeric",
});

export default async function Contratos() {
  const sessao = await sessaoAtual();
  const supabase = await supabaseSessao();

  const [versoes, profs, contas] = await Promise.all([
    db(
      "contratos.listar",
      supabase
        .from("contratos")
        .select("id, versao, titulo, corpo, publicado_em")
        .order("versao", { ascending: false }),
    ) as Promise<unknown>,
    // O contrato sai com o nome e o CRP de quem assina, e quem assina é a
    // profissional da sessão. A consulta era `.limit(1)` sem filtro: numa
    // clínica, a prévia do contrato mostrava o registro de outra pessoa.
    sessao.profissionalId
      ? (db(
          "contratos.profissional",
          supabase
            .from("profissionais")
            .select("assina_como, crp")
            .eq("id", sessao.profissionalId)
            .limit(1),
        ) as Promise<unknown>)
      : Promise.resolve([] as unknown),
    db("contratos.conta", supabase.from("contas").select("cidade").limit(1)) as Promise<unknown>,
  ]);

  const lista = ((versoes ?? []) as ContratoLinha[]).filter((c) => c.publicado_em);
  const atual = lista[0] ?? null;
  const prof = ((profs ?? []) as { assina_como: string | null; crp: string | null }[])[0];
  const conta = ((contas ?? []) as { cidade: string | null }[])[0];

  return (
    <div className="mx-auto max-w-4xl">
      <Link href="/perfil" className="text-[12.5px] text-tinta3 hover:text-vaga">
        ← conta
      </Link>

      <h1 className="mt-2 font-serif text-[28px] leading-tight tracking-[-0.015em]">
        O combinado por escrito
      </h1>

      <p className="mt-3 max-w-2xl text-[14px] leading-relaxed text-tinta2">
        Um texto só, escrito uma vez, que vira o documento de cada pessoa com os
        números dela dentro. <b className="font-semibold text-tinta">É o que dá base
        à cobrança de uma falta</b>: quando você decide cobrar, a regra aplicada é
        uma que a pessoa leu e aceitou com data e hora — não um combinado de boca
        que agora precisa ser relembrado por você.
      </p>

      <EditorDeContrato
        titulo={atual?.titulo ?? ""}
        corpo={atual?.corpo ?? ""}
        versao={atual?.versao ?? 0}
        assinaComo={prof?.assina_como ?? null}
        crp={prof?.crp ?? null}
        cidade={conta?.cidade ?? null}
        podeEditar={sessao.papel === "dona"}
      />

      {/* ------------------------------------------------------- as versões */}
      {lista.length > 0 && (
        <section className="mt-10 border-t border-linha pt-6">
          <h2 className="rotulo">As versões</h2>
          <ul className="mt-3 overflow-hidden rounded-cartao border border-linha bg-folha">
            {lista.map((c, i) => (
              <li
                key={c.id}
                className="flex flex-wrap items-baseline gap-x-3 gap-y-1 border-t border-linha px-5 py-3 first:border-t-0"
              >
                <span className="font-mono text-[13px] text-tinta">v{c.versao}</span>
                <span className="text-[13px] text-tinta2">{c.titulo}</span>
                <span className="text-[12px] text-tinta3">
                  {c.publicado_em ? DIA.format(new Date(c.publicado_em)) : ""}
                </span>
                {i === 0 && (
                  <span className="rounded-full bg-cheia-bg px-2 py-0.5 text-[11px] font-medium text-cheia">
                    em uso
                  </span>
                )}
              </li>
            ))}
          </ul>
          <p className="mt-3 max-w-2xl text-[12px] leading-relaxed text-tinta3">
            Versão publicada não se edita — publicar de novo abre a seguinte, e a
            anterior fica. Quem aceitou a v1 continua tendo aceitado a v1: o
            texto exato que apareceu na tela dela está congelado no aceite, e
            nada aqui o alcança.
          </p>
        </section>
      )}

      {/* --------------------------------------------------- o que isto não é */}
      <section className="mt-10 border-t border-linha pt-6">
        <h2 className="rotulo">O que este aceite é — e o que não é</h2>
        <ul className="mt-3 max-w-2xl space-y-2 text-[13px] leading-relaxed text-tinta2">
          <li>
            <b className="font-medium text-tinta">É um registro datado.</b> Quem
            aceitou, quando, de onde, e o texto exato congelado no instante do
            clique. Assinatura eletrônica simples, na forma da Lei 14.063/2020 —
            que a lei admite entre as partes.
          </li>
          <li>
            <b className="font-medium text-tinta">Não é certificado ICP-Brasil.</b>{" "}
            Não tem carimbo de tempo de autoridade certificadora nem firma
            reconhecida. Para o que este documento serve — combinar honorário,
            horário e regra de falta entre você e quem você atende — isso basta;
            para um contrato que você espere executar em juízo contra alguém,
            converse com um advogado antes de contar com ele.
          </li>
          <li>
            <b className="font-medium text-tinta">Não bloqueia nada.</b> Sem
            aceite, o sistema continua agendando, atendendo e registrando
            cobrança. Ele anota que o combinado não foi aceito e mostra na ficha.
            Condicionar
            atendimento a um clique seria transformar isto aqui em porteiro de
            uma relação clínica.
          </li>
          <li>
            <b className="font-medium text-tinta">O texto é seu.</b> Este é um
            ponto de partida escrito por não-advogados. Quem responde pelo que
            está escrito é você — vale a leitura de alguém da área antes do
            primeiro envio.
          </li>
        </ul>
      </section>
    </div>
  );
}
