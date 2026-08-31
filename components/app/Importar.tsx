"use client";

import { useActionState, useMemo, useState } from "react";
import { useFormStatus } from "react-dom";
import { importarPacientes, type ResultadoImport } from "@/app/(app)/comecar/acoes";
import { lerColagem, comHorario } from "@/lib/importacao";
import { rotuloHorario } from "@/lib/enquadre";
import { formatar } from "@/lib/dinheiro";

const INICIAL: ResultadoImport = { estado: "inicial" };

const EXEMPLO = `Maria Fernanda Reis; 11 90000-0001; terça; 15h; 200
Caio Nogueira; 11 90000-0002; quinta; 9h; 200
João Pedro Salles; 11 90000-0003; segunda; 18h30; 180
Bia Nogueira; 11 90000-0004`;

function Enviar({ quantos }: { quantos: number }) {
  const { pending } = useFormStatus();
  return (
    <button
      type="submit"
      disabled={pending || quantos === 0}
      className="rounded-full bg-vaga px-5 py-2 text-[13px] font-semibold text-white transition-opacity hover:opacity-90 disabled:opacity-40"
    >
      {pending
        ? "importando…"
        : quantos === 0
          ? "cole a lista acima"
          : `Importar ${quantos} pessoa${quantos > 1 ? "s" : ""}`}
    </button>
  );
}

/**
 * A importação, com a pré-visualização acontecendo enquanto ela digita.
 *
 * A leitura roda **duas vezes**: aqui, para mostrar; e no servidor, para gravar.
 * Não é desperdício — é a regra de nunca confiar no que a tela mandou. O que se
 * ganha com a cópia daqui é a pessoa ver o erro da linha 12 antes de mandar, em
 * vez de depois.
 */
export function Importar() {
  const [texto, setTexto] = useState("");
  const [resultado, despachar] = useActionState(importarPacientes, INICIAL);

  const leitura = useMemo(() => lerColagem(texto), [texto]);
  const comHora = comHorario(leitura);

  if (resultado.estado === "ok") {
    return (
      <div className="rounded-cartao border border-cheia-linha bg-cheia-bg px-5 py-4">
        <p className="text-[13px] leading-relaxed text-tinta">
          <b className="font-semibold text-cheia">
            {resultado.criados} pessoa{resultado.criados > 1 ? "s" : ""}
          </b>{" "}
          no cadastro, {resultado.comHorario} com horário fixo — e a agenda das
          próximas oito semanas já foi montada a partir deles.
        </p>

        {resultado.ignorados.length > 0 && (
          <div className="mt-3">
            <p className="text-[12.5px] font-medium text-tinta2">
              Ficaram de fora ({resultado.ignorados.length}):
            </p>
            <ul className="mt-1 space-y-0.5">
              {resultado.ignorados.slice(0, 10).map((m, i) => (
                <li key={i} className="font-mono text-[11.5px] text-tinta3">
                  {m}
                </li>
              ))}
            </ul>
            <p className="mt-2 text-[12px] leading-relaxed text-tinta2">
              Cole só essas linhas de novo, corrigidas — quem já entrou não
              duplica.
            </p>
          </div>
        )}
      </div>
    );
  }

  return (
    <form action={despachar}>
      <textarea
        name="colagem"
        value={texto}
        onChange={(e) => setTexto(e.target.value)}
        rows={7}
        spellCheck={false}
        placeholder={EXEMPLO}
        className="w-full rounded-cartao border border-linha2 bg-folha px-3 py-2 font-mono text-[12.5px] leading-relaxed text-tinta placeholder:text-tinta3 focus:border-tinta3 focus:outline-none"
      />

      <p className="mt-1 text-[11.5px] text-tinta3">
        nome; telefone; dia; hora; valor — separado por ponto e vírgula, vírgula
        ou tabulação. Só o nome é obrigatório.
      </p>

      {/* ------------------------------------------------ pré-visualização */}
      {leitura.pacientes.length > 0 && (
        <div className="mt-3 overflow-x-auto rounded-cartao border border-linha">
          <table className="w-full text-[12.5px]">
            <thead>
              <tr className="border-b border-linha bg-folha2">
                <th className="px-3 py-1.5 text-left font-medium text-tinta3">nome</th>
                <th className="px-3 py-1.5 text-left font-medium text-tinta3">avisar</th>
                <th className="px-3 py-1.5 text-left font-medium text-tinta3">horário</th>
                <th className="px-3 py-1.5 text-right font-medium text-tinta3">valor</th>
              </tr>
            </thead>
            <tbody>
              {leitura.pacientes.slice(0, 12).map((p) => (
                <tr key={p.linha} className="border-b border-linha last:border-0">
                  <td className="px-3 py-1.5 text-tinta">{p.nome}</td>
                  <td className="px-3 py-1.5 font-mono text-[11.5px] text-tinta2">
                    {p.telefone ?? "—"}
                  </td>
                  <td className="px-3 py-1.5 text-tinta2">
                    {p.diaSemana !== null && p.hora
                      ? rotuloHorario(p.diaSemana, p.hora)
                      : "—"}
                  </td>
                  <td className="px-3 py-1.5 text-right font-mono text-[11.5px] tabular-nums text-tinta2">
                    {p.valorCentavos ? formatar(p.valorCentavos) : "—"}
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
          {leitura.pacientes.length > 12 && (
            <p className="border-t border-linha px-3 py-1.5 text-[11.5px] text-tinta3">
              e mais {leitura.pacientes.length - 12}…
            </p>
          )}
        </div>
      )}

      {/* ------------------------------------------------------- os erros */}
      {leitura.erros.length > 0 && (
        <div className="mt-2 rounded-cartao border border-vaga-linha bg-vaga-bg px-4 py-3">
          <p className="text-[12.5px] font-medium text-tinta">
            {leitura.erros.length} linha{leitura.erros.length > 1 ? "s" : ""} que
            eu não consigo ler:
          </p>
          <ul className="mt-1 space-y-0.5">
            {leitura.erros.slice(0, 6).map((e) => (
              <li key={e.linha} className="font-mono text-[11.5px] text-tinta2">
                linha {e.linha}: {e.motivo}
              </li>
            ))}
          </ul>
          <p className="mt-2 text-[12px] leading-relaxed text-tinta2">
            As outras entram normalmente. Corrija estas e cole de novo depois.
          </p>
        </div>
      )}

      {resultado.estado === "erro" && (
        <ul className="mt-2 space-y-0.5">
          {resultado.erros.map((e, i) => (
            <li key={i} className="text-[12.5px] text-vaga">
              {e}
            </li>
          ))}
        </ul>
      )}

      {/* ---------------------------------------------- a política padrão */}
      {comHora > 0 && (
        <fieldset className="mt-4 rounded-cartao border border-linha bg-folha2 px-4 py-3">
          <legend className="px-1 text-[11px] font-semibold uppercase tracking-wider text-tinta3">
            política de cancelamento
          </legend>
          <p className="text-[12.5px] leading-relaxed text-tinta2">
            Vale para os {comHora} horário{comHora > 1 ? "s" : ""} que vão ser
            criados. Dá para mudar depois, uma a uma — mas o que vale para cada
            sessão é a política do dia em que ela foi marcada.
          </p>
          <div className="mt-2 flex flex-wrap items-center gap-2 text-[12.5px] text-tinta2">
            <span>desmarcar com menos de</span>
            <select
              name="politica_horas"
              defaultValue="24"
              className="rounded border border-linha2 bg-folha px-2 py-1 text-[12.5px] text-tinta"
            >
              <option value="12">12 horas</option>
              <option value="24">24 horas</option>
              <option value="48">48 horas</option>
            </select>
            <span>cobra</span>
            <select
              name="politica_percentual"
              defaultValue="50"
              className="rounded border border-linha2 bg-folha px-2 py-1 text-[12.5px] text-tinta"
            >
              <option value="0">nada</option>
              <option value="50">50%</option>
              <option value="100">a sessão inteira</option>
            </select>
          </div>
        </fieldset>
      )}

      <div className="mt-4">
        <Enviar quantos={leitura.pacientes.length} />
      </div>

      <p className="mt-2 text-[11.5px] leading-relaxed text-tinta3">
        Todo mundo entra no modo discreto: as mensagens não dizem que é terapia
        nem citam o seu nome. Quem quiser receber diferente, muda na ficha.
      </p>
    </form>
  );
}
