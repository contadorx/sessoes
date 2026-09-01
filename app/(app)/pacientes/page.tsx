import Link from "next/link";
import { listarPacientes, enquadreAberto } from "./dados";
import { ROTULO_ESTADO, ROTULO_CANAL, formatarTelefone } from "@/lib/paciente";
import { rotuloHorario, rotuloPolitica } from "@/lib/enquadre";

export const metadata = { title: "Pacientes" };

const brl = (v: string) =>
  Number(v).toLocaleString("pt-BR", { style: "currency", currency: "BRL" });

export default async function Pacientes() {
  const pacientes = await listarPacientes();

  return (
    <div>
      <div className="flex flex-wrap items-baseline justify-between gap-3">
        <h1 className="font-serif text-[28px] leading-tight tracking-[-0.015em]">Pacientes</h1>
        <Link
          href="/pacientes/novo"
          className="rounded-full bg-vaga px-5 py-2.5 text-[13px] font-semibold text-white transition-opacity hover:opacity-90"
        >
          Cadastrar
        </Link>
      </div>

      {pacientes.length === 0 ? (
        <div className="mt-8 rounded-cartao border border-dashed border-linha2 bg-folha px-6 py-10 text-center">
          <p className="font-serif text-[20px] text-tinta">Ainda não há ninguém aqui.</p>
          <p className="mx-auto mt-2 max-w-[46ch] text-[13.5px] leading-relaxed text-tinta2">
            Comece pelos pacientes de horário fixo. É o combinado de cada um —
            dia, hora, valor e política — que faz a agenda existir.
          </p>
          <Link
            href="/pacientes/novo"
            className="mt-5 inline-block rounded-full bg-vaga px-5 py-2.5 text-[13px] font-semibold text-white"
          >
            Cadastrar o primeiro
          </Link>
        </div>
      ) : (
        <ul className="mt-6 overflow-hidden rounded-cartao border border-linha bg-folha">
          {pacientes.map((p) => {
            const e = enquadreAberto(p);
            return (
              <li key={p.id} className="border-t border-linha first:border-t-0">
                <Link
                  href={`/pacientes/${p.id}`}
                  className="flex flex-wrap items-baseline gap-x-4 gap-y-1 px-5 py-4 transition-colors hover:bg-folha2"
                >
                  <span className="text-[15px] font-medium text-tinta">{p.nome}</span>

                  <span className="rounded-full border border-linha bg-folha2 px-2 py-0.5 text-[10.5px] font-semibold uppercase tracking-wider text-tinta3">
                    {ROTULO_ESTADO[p.estado]}
                  </span>

                  {e ? (
                    <span className="font-mono text-[12.5px] text-cheia">
                      {rotuloHorario(e.dia_semana, e.hora)} · {brl(e.valor)}
                      {e.social && " · social"}
                    </span>
                  ) : (
                    <span className="text-[12.5px] text-vaga">sem combinado</span>
                  )}

                  <span className="ml-auto text-[12px] text-tinta3">
                    {formatarTelefone(p.telefone)} · {ROTULO_CANAL[p.msg_canal]}
                    {p.msg_canal !== "nao_avisar" && ` · ${p.msg_modo}`}
                  </span>
                </Link>
              </li>
            );
          })}
        </ul>
      )}

      {pacientes.length > 0 && (
        <p className="mt-4 text-[12px] text-tinta3">
          {pacientes.filter((p) => enquadreAberto(p)).length} de {pacientes.length} com
          combinado aberto ·{" "}
          {(() => {
            const abertos = pacientes.map(enquadreAberto).filter(Boolean);
            const p = abertos[0];
            return p
              ? `política mais comum: ${rotuloPolitica({ horas: p.politica_horas, percentual: p.politica_percentual })}`
              : "";
          })()}
        </p>
      )}
    </div>
  );
}
