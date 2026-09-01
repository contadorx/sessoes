import Link from "next/link";
import { db } from "@/lib/db";
import { supabaseSessao } from "@/lib/supabase/server";
import { formatar, paraCentavos, somar } from "@/lib/dinheiro";
import { PausarRegua } from "@/components/app/PausarRegua";

export const metadata = { title: "A receber" };

type LinhaRegua = {
  paciente_id: string;
  nome: string;
  aberto_desde: string;
  dias: number;
  quantidade: number;
  total: string;
  passo: number | null;
  enviados: number;
  pausada: boolean;
  motivo_pausa: string | null;
};

type ContaRegua = { regua_ativa: boolean; regua_dias: number[] };

const DIA = new Intl.DateTimeFormat("pt-BR", { timeZone: "America/Sao_Paulo" });

export default async function AReceber() {
  const supabase = await supabaseSessao();

  const [linhas, contas] = await Promise.all([
    db("regua.pendente", supabase.rpc("regua_pendente")) as Promise<unknown>,
    db(
      "regua.conta",
      supabase.from("contas").select("regua_ativa, regua_dias").limit(1),
    ) as Promise<unknown>,
  ]);

  const regua = ((linhas ?? []) as LinhaRegua[]).sort((a, b) => b.dias - a.dias);
  const conta = ((contas ?? []) as ContaRegua[])[0];

  const total = regua.reduce((soma, l) => somar(soma, paraCentavos(l.total)), 0);
  const emAndamento = regua.filter((l) => !l.pausada).length;

  return (
    <div className="mx-auto max-w-3xl">
      <h1 className="font-serif text-[28px] leading-tight tracking-[-0.015em]">
        A receber
      </h1>

      {regua.length === 0 ? (
        <p className="mt-4 rounded-cartao border border-linha bg-folha2 px-5 py-4 text-[13px] leading-relaxed text-tinta2">
          Nada a receber. Quando houver, é aqui que você vê — e o sistema lembra
          por você, no texto neutro, sem você precisar puxar o assunto.
        </p>
      ) : (
        <>
          <p className="mt-2 max-w-xl text-[14px] leading-relaxed text-tinta2">
            <b className="font-semibold text-tinta">{formatar(total)}</b> de{" "}
            {regua.length} pessoa{regua.length > 1 ? "s" : ""}.{" "}
            {emAndamento === 0
              ? "Nenhum lembrete vai sair — os motivos estão abaixo."
              : `O sistema está lembrando ${emAndamento} delas.`}
          </p>

          <div className="mt-6 space-y-3">
            {regua.map((l) => (
              <div
                key={l.paciente_id}
                className={`rounded-cartao border px-5 py-4 ${
                  l.pausada ? "border-linha bg-folha2" : "border-vaga-linha bg-vaga-bg"
                }`}
              >
                <div className="flex flex-wrap items-baseline gap-x-3 gap-y-1">
                  <Link
                    href={`/pacientes/${l.paciente_id}`}
                    className="font-serif text-[17px] text-tinta hover:text-vaga"
                  >
                    {l.nome}
                  </Link>
                  <span className="font-mono text-[13px] tabular-nums text-tinta">
                    {formatar(paraCentavos(l.total))}
                  </span>
                  <span className="text-[12px] text-tinta3">
                    {l.quantidade} horário{l.quantidade > 1 ? "s" : ""} · desde{" "}
                    {DIA.format(new Date(`${l.aberto_desde}T12:00:00Z`))} ({l.dias}{" "}
                    dias)
                  </span>
                </div>

                <p className="mt-2 text-[12.5px] leading-relaxed text-tinta2">
                  {l.pausada ? (
                    <>
                      <b className="font-medium text-tinta">Nenhum lembrete vai sair</b>{" "}
                      — {l.motivo_pausa}.
                    </>
                  ) : l.enviados === 0 ? (
                    <>
                      Nenhum lembrete enviado ainda. O primeiro sai{" "}
                      {l.passo !== null ? "na próxima passada" : `aos ${conta?.regua_dias?.[0] ?? 7} dias`}.
                    </>
                  ) : (
                    <>
                      {l.enviados} de {conta?.regua_dias?.length ?? 2} lembrete
                      {(conta?.regua_dias?.length ?? 2) > 1 ? "s" : ""} enviado
                      {l.enviados > 1 ? "s" : ""}
                      {l.passo !== null
                        ? " — o próximo sai na próxima passada."
                        : " — o próximo espera o degrau seguinte."}
                    </>
                  )}
                </p>

                <div className="mt-3">
                  <PausarRegua pacienteId={l.paciente_id} pausada={l.pausada} />
                </div>
              </div>
            ))}
          </div>
        </>
      )}

      {/* ------------------------------------------------- o que a régua não faz */}
      <section className="mt-10 border-t border-linha pt-6">
        <h2 className="rotulo">O que os lembretes fazem — e o que não fazem</h2>
        <ul className="mt-3 space-y-2 text-[13px] leading-relaxed text-tinta2">
          <li>
            <b className="font-medium text-tinta">Não endurecem.</b> O segundo
            lembrete tem exatamente o mesmo texto do primeiro. Quem escalona é
            cobrador; aqui o que se repete é o fato, não a pressão.
          </li>
          <li>
            <b className="font-medium text-tinta">Param sozinhos.</b> No máximo{" "}
            {conta?.regua_dias?.length ?? 2}, e depois disso o assunto volta para
            você — a essa altura já não é falta de lembrete, é uma conversa que
            precisa acontecer.
          </li>
          <li>
            <b className="font-medium text-tinta">Calam quando a pessoa responde.</b>{" "}
            Qualquer mensagem dela nos últimos dias suspende os lembretes.
          </li>
          <li>
            <b className="font-medium text-tinta">Uma mensagem por pessoa</b>, com o
            total — nunca uma por cobrança.
          </li>
          <li>
            <b className="font-medium text-tinta">Não ameaçam e não suspendem
            atendimento.</b> Não há juros, não há prazo final, não há sessão
            cancelada por débito. Interromper um acompanhamento é decisão sua, e
            o sistema não opina.
          </li>
        </ul>
        <p className="mt-3 text-[12.5px] text-tinta3">
          O ritmo dos lembretes está em{" "}
          <Link href="/perfil" className="underline underline-offset-2 hover:text-vaga">
            Conta
          </Link>
          .
        </p>
      </section>
    </div>
  );
}
