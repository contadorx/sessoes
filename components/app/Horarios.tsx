"use client";

import { useActionState, useState } from "react";
import { useFormStatus } from "react-dom";
import { salvarSemana, type Resultado } from "@/app/(app)/perfil/horarios/acoes";
import { DIAS } from "@/lib/enquadre";
import {
  DESTINOS,
  duracao,
  fraseDaSemana,
  problemaNaSemana,
  semanaEmMinutos,
  semanaSugerida,
  type Faixa,
  type Destino,
} from "@/lib/capacidade";

const INICIAL: Resultado = { estado: "ok", mensagem: "" };

const CAMPO =
  "rounded-[5px] border border-linha2 bg-folha px-2 py-1.5 text-[13px] text-tinta";

function Botao({ children }: { children: React.ReactNode }) {
  const { pending } = useFormStatus();
  return (
    <button
      type="submit"
      disabled={pending}
      className="rounded-full border border-linha2 px-4 py-2 text-[12.5px] font-medium text-tinta2 transition-colors hover:bg-folha2 disabled:opacity-45"
    >
      {pending ? "…" : children}
    </button>
  );
}

/**
 * A semana declarada.
 *
 * **Três destinos por faixa, e não um interruptor de "atende ou não".** O
 * destino é o que impede o número mais importante do produto de mentir para
 * cima: sem ele, a hora de prontuário sumiria da declaração e a ocupação subiria
 * sozinha toda vez que alguém deixasse de reservar tempo para escrever.
 *
 * **A conferência de sobreposição roda enquanto se digita**, e não no envio. Ela
 * é a mesma do banco, e descobrir o encavalamento depois de clicar em guardar
 * seria mandar a pessoa procurar num formulário de trinta campos.
 *
 * E o rodapé diz **dois números com dois nomes** — atendimento e protegido —,
 * nunca um só. Um número solitário aqui empurra contra o descanso, que é a
 * fronteira 4 do doc 11.
 */
export function Horarios({
  profissional,
  faixas,
}: {
  profissional: string;
  faixas: Faixa[];
}) {
  const [r, salvar] = useActionState(salvarSemana, INICIAL);
  const [lista, setLista] = useState<Faixa[]>(faixas);

  const problema = problemaNaSemana(lista);
  const s = semanaEmMinutos(lista);

  const mudar = (i: number, campo: keyof Faixa, valor: string) => {
    const c = [...lista];
    c[i] = { ...c[i], [campo]: campo === "dia" ? Number(valor) : valor } as Faixa;
    setLista(c);
  };

  const acrescentar = (dia: number) =>
    setLista([...lista, { dia, inicio: "09:00", fim: "10:00", destino: "atendimento" }]);

  return (
    <form action={salvar}>
      <input type="hidden" name="profissional" value={profissional} />

      <div className="flex flex-col gap-4">
        {[1, 2, 3, 4, 5, 6, 0].map((dia) => {
          const doDia = lista
            .map((f, i) => ({ f, i }))
            .filter((x) => x.f.dia === dia);

          return (
            <div key={dia} className="rounded-cartao border border-linha bg-folha px-4 py-3">
              <div className="flex flex-wrap items-baseline gap-3">
                <span className="text-[13px] font-medium text-tinta">{DIAS[dia]}</span>
                {doDia.length === 0 && (
                  <span className="text-[12px] text-tinta3">sem hora declarada</span>
                )}
                <button
                  type="button"
                  onClick={() => acrescentar(dia)}
                  className="ml-auto text-[12px] text-tinta3 underline decoration-linha2 underline-offset-4 hover:text-vaga"
                >
                  acrescentar faixa
                </button>
              </div>

              {doDia.length > 0 && (
                <div className="mt-2.5 flex flex-col gap-2">
                  {doDia.map(({ f, i }) => (
                    <div key={i} className="flex flex-wrap items-center gap-2">
                      <input type="hidden" name="faixa_dia" value={f.dia} />
                      <input
                        type="time"
                        name="faixa_inicio"
                        value={f.inicio}
                        onChange={(e) => mudar(i, "inicio", e.target.value)}
                        aria-label={`Começo da faixa de ${DIAS[dia]}`}
                        className={CAMPO}
                      />
                      <span className="text-[12px] text-tinta3">às</span>
                      <input
                        type="time"
                        name="faixa_fim"
                        value={f.fim}
                        onChange={(e) => mudar(i, "fim", e.target.value)}
                        aria-label={`Fim da faixa de ${DIAS[dia]}`}
                        className={CAMPO}
                      />
                      <select
                        name="faixa_destino"
                        value={f.destino}
                        onChange={(e) => mudar(i, "destino", e.target.value as Destino)}
                        aria-label={`Para que serve a faixa de ${DIAS[dia]}`}
                        className={CAMPO}
                      >
                        {DESTINOS.map((d) => (
                          <option key={d.valor} value={d.valor}>
                            {d.rotulo}
                          </option>
                        ))}
                      </select>
                      <span className="font-mono text-[11.5px] tabular-nums text-tinta3">
                        {duracao(
                          Math.max(
                            0,
                            (Number(f.fim.slice(0, 2)) * 60 + Number(f.fim.slice(3, 5))) -
                              (Number(f.inicio.slice(0, 2)) * 60 + Number(f.inicio.slice(3, 5))),
                          ),
                        )}
                      </span>
                      <button
                        type="button"
                        onClick={() => setLista(lista.filter((_, k) => k !== i))}
                        className="ml-auto text-[11.5px] text-tinta3 underline decoration-linha2 underline-offset-4 hover:text-vaga"
                      >
                        tirar
                      </button>
                    </div>
                  ))}
                </div>
              )}
            </div>
          );
        })}
      </div>

      {lista.length === 0 && (
        <button
          type="button"
          onClick={() => setLista(semanaSugerida())}
          className="mt-4 rounded-full border border-linha2 px-4 py-2 text-[12.5px] font-medium text-tinta2 hover:bg-folha2"
        >
          Começar de uma semana comum
        </button>
      )}

      {/* ------------------------------------------------------------ o rodapé */}
      <div className="mt-6 rounded-cartao border border-linha bg-folha2 px-5 py-4">
        <p className="text-[13px] leading-relaxed text-tinta">{fraseDaSemana(lista)}</p>

        {s.registro + s.descanso > 0 && (
          <p className="mt-1.5 max-w-[62ch] text-[12px] leading-relaxed text-tinta3">
            As {duracao(s.registro + s.descanso)} de registro e descanso são hora
            declarada e protegida: elas não entram na conta de ocupação, e o
            sistema nunca vai apresentá-las como hora vaga a preencher.
          </p>
        )}

        {problema && (
          <p className="mt-3 text-[12.5px] leading-relaxed text-vaga">{problema}</p>
        )}

        <div className="mt-4">
          <Botao>Guardar a semana</Botao>
        </div>

        {r.mensagem && (
          <p
            className={`mt-2 text-[12px] leading-relaxed ${
              r.estado === "erro" ? "text-vaga" : "text-cheia"
            }`}
          >
            {r.mensagem}
          </p>
        )}

        <p className="mt-3 max-w-[62ch] border-t border-linha pt-3 text-[11.5px] leading-relaxed text-tinta3">
          O que você guardar vale <b className="font-medium">de hoje em diante</b>. Os
          dias que já passaram continuam com a declaração que estava valendo na
          época — é isso que faz a ocupação de um mês fechado não mudar quando
          você mexe na agenda de amanhã.
        </p>
      </div>
    </form>
  );
}
