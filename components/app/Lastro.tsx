"use client";

import Link from "next/link";
import { useActionState, useState } from "react";
import { useFormStatus } from "react-dom";
import {
  prepararAceite,
  registrarPresencial,
  revogarAceite,
  type Resultado,
} from "@/app/(app)/perfil/contrato/acoes";
import {
  estadoDoAceite,
  rotuloDoAceite,
  type AceiteLinha,
} from "@/lib/contrato";

const INICIAL: Resultado = { estado: "inicial" };

const DATA_HORA = new Intl.DateTimeFormat("pt-BR", {
  timeZone: "America/Sao_Paulo",
  day: "2-digit",
  month: "2-digit",
  year: "numeric",
  hour: "2-digit",
  minute: "2-digit",
});

const DIA = new Intl.DateTimeFormat("pt-BR", {
  timeZone: "America/Sao_Paulo",
  day: "2-digit",
  month: "2-digit",
  year: "numeric",
});

function Botao({
  children,
  destaque = false,
}: {
  children: React.ReactNode;
  destaque?: boolean;
}) {
  const { pending } = useFormStatus();
  return (
    <button
      type="submit"
      disabled={pending}
      className={
        destaque
          ? "rounded-full bg-tinta px-4 py-1.5 text-[12.5px] font-medium text-papel transition-opacity hover:opacity-90 disabled:opacity-45"
          : "rounded-full border border-linha2 px-4 py-1.5 text-[12.5px] font-medium text-tinta2 transition-colors hover:bg-folha2 disabled:opacity-45"
      }
    >
      {pending ? "…" : children}
    </button>
  );
}

function Recado({ r }: { r: Resultado }) {
  if (r.estado === "ok") return <p className="mt-2 text-[12.5px] text-cheia">{r.mensagem}</p>;
  if (r.estado === "erro")
    return (
      <ul className="mt-2 space-y-1">
        {r.erros.map((e, i) => (
          <li key={i} className="text-[12.5px] leading-relaxed text-vaga">
            {e}
          </li>
        ))}
      </ul>
    );
  return null;
}

/**
 * O lastro do combinado, na ficha.
 *
 * A escolha de desenho que importa aqui: **o link não é enfileirado no outbox**.
 * Quem manda é ela, de um toque, do próprio WhatsApp — e o texto pré-preenchido
 * é neutro. Duas razões, nesta ordem.
 *
 * A primeira é de discrição (D3, doc 11): um documento chamado "contrato
 * terapêutico" chegando de um número desconhecido aparece na tela de bloqueio
 * de um celular que outra pessoa pode estar segurando. Mandado por ela, no fio
 * de conversa que já existe, é só mais uma mensagem dela.
 *
 * A segunda é prática: mandar por template exigiria uma sétima família aprovada
 * na Meta, e o ciclo de aprovação é o risco R4 do doc 12 — o que faria um build
 * de dois dias esperar uma semana por um botão.
 */
export function Lastro({
  pacienteId,
  pacienteNome,
  telefone,
  enquadreId,
  temContrato,
  aceite,
}: {
  pacienteId: string;
  pacienteNome: string;
  telefone: string | null;
  enquadreId: string | null;
  temContrato: boolean;
  aceite: AceiteLinha | null;
}) {
  const [rPreparar, preparar] = useActionState(prepararAceite, INICIAL);
  const [rPresencial, presencial] = useActionState(registrarPresencial, INICIAL);
  const [rRevogar, revogar] = useActionState(revogarAceite, INICIAL);

  const [copiado, setCopiado] = useState(false);
  const [assinando, setAssinando] = useState(false);
  const [revogando, setRevogando] = useState(false);

  const estado = !temContrato
    ? "sem_contrato"
    : !enquadreId
      ? "sem_combinado"
      : estadoDoAceite(aceite);

  const link =
    aceite && typeof window !== "undefined"
      ? `${window.location.origin}/p/contrato/${aceite.token}`
      : "";

  const primeiroNome = pacienteNome.trim().split(/\s+/)[0];
  const convite =
    `Oi, ${primeiroNome}. Segue o nosso combinado por escrito, ` +
    `para você ler e confirmar quando puder: ${link}`;

  const zap = telefone
    ? `https://wa.me/${telefone.replace(/\D/g, "")}?text=${encodeURIComponent(convite)}`
    : null;

  return (
    <div className="rounded-cartao border border-linha bg-folha2 px-5 py-4">
      <p className="text-[13px] leading-relaxed text-tinta">
        {rotuloDoAceite(estado)}
      </p>

      {/* ------------------------------------------------------ sem contrato */}
      {estado === "sem_contrato" && (
        <p className="mt-2 text-[12.5px] leading-relaxed text-tinta2">
          Escreva uma vez e vale para todo mundo, com os números de cada um.{" "}
          <Link href="/perfil/contrato" className="underline underline-offset-2 hover:text-vaga">
            escrever agora
          </Link>
        </p>
      )}

      {/* ------------------------------------------------------- já aceito */}
      {estado === "aceito" && aceite && (
        <>
          <p className="mt-1 text-[12.5px] leading-relaxed text-tinta2">
            Por <b className="font-medium text-tinta">{aceite.aceito_por}</b>
            {aceite.parentesco && ` (${aceite.parentesco})`} em{" "}
            {DATA_HORA.format(new Date(aceite.aceito_em!))}
            {aceite.origem === "presencial" ? ", presencialmente" : ", pelo link"}
            {aceite.retrato?.contrato_versao != null &&
              ` · versão ${aceite.retrato.contrato_versao}`}
            .
          </p>

          <div className="mt-3 flex flex-wrap items-center gap-3">
            <a
              href={`/p/contrato/${aceite.token}`}
              target="_blank"
              rel="noreferrer"
              className="text-[12.5px] text-tinta2 underline underline-offset-2 hover:text-vaga"
            >
              ver o texto aceito
            </a>
            <button
              type="button"
              onClick={() => setRevogando((v) => !v)}
              className="text-[12.5px] text-tinta3 underline underline-offset-2 hover:text-vaga"
            >
              revogar
            </button>
          </div>

          {revogando && (
            <form action={revogar} className="mt-3 border-t border-linha pt-3">
              <input type="hidden" name="aceite" value={aceite.id} />
              <input type="hidden" name="paciente" value={pacienteId} />
              <label htmlFor="motivo" className="text-[12px] text-tinta2">
                Motivo (opcional, fica só para você)
              </label>
              <input
                id="motivo"
                name="motivo"
                className="mt-1 w-full rounded-cartao border border-linha2 bg-folha px-3 py-2 text-[13px] text-tinta focus:border-tinta3 focus:outline-none"
              />
              <p className="mt-2 text-[11.5px] leading-relaxed text-tinta3">
                Revogar encerra a validade daqui para a frente. O registro fica —
                apagá-lo tiraria o lastro das cobranças que já foram feitas sob
                ele, e essas aconteceram.
              </p>
              <div className="mt-2">
                <Botao>Revogar o aceite</Botao>
              </div>
              <Recado r={rRevogar} />
            </form>
          )}
        </>
      )}

      {/* --------------------------------------- pendente, expirado, revogado */}
      {(estado === "pendente" || estado === "expirado" || estado === "revogado" ||
        estado === "nunca_preparado") &&
        enquadreId &&
        temContrato && (
          <div className="mt-3">
            {estado === "pendente" && aceite && (
              <>
                <div className="flex flex-wrap items-center gap-2">
                  {zap && (
                    <a
                      href={zap}
                      target="_blank"
                      rel="noreferrer"
                      className="rounded-full bg-tinta px-4 py-1.5 text-[12.5px] font-medium text-papel transition-opacity hover:opacity-90"
                    >
                      Abrir no WhatsApp
                    </a>
                  )}
                  <button
                    type="button"
                    onClick={async () => {
                      try {
                        await navigator.clipboard.writeText(link);
                        setCopiado(true);
                        setTimeout(() => setCopiado(false), 2500);
                      } catch {
                        setCopiado(false);
                      }
                    }}
                    className="rounded-full border border-linha2 px-4 py-1.5 text-[12.5px] font-medium text-tinta2 transition-colors hover:bg-folha2"
                  >
                    {copiado ? "copiado" : "Copiar o link"}
                  </button>
                  <button
                    type="button"
                    onClick={() => setAssinando((v) => !v)}
                    className="text-[12.5px] text-tinta3 underline underline-offset-2 hover:text-vaga"
                  >
                    assinou aqui na sala
                  </button>
                </div>

                <p className="mt-2 text-[11.5px] leading-relaxed text-tinta3">
                  O link vale até {DIA.format(new Date(aceite.expira_em))}. A
                  mensagem sai de você, do seu número, com um texto que não
                  nomeia nada — a tela de bloqueio de um celular é lida por quem
                  passa.
                </p>
              </>
            )}

            {estado !== "pendente" && (
              <form action={preparar}>
                <input type="hidden" name="enquadre" value={enquadreId} />
                <input type="hidden" name="paciente" value={pacienteId} />
                <Botao destaque>
                  {estado === "nunca_preparado" ? "Preparar o link" : "Preparar outro link"}
                </Botao>
                <Recado r={rPreparar} />
              </form>
            )}

            {estado === "pendente" && assinando && aceite && (
              <form action={presencial} className="mt-3 border-t border-linha pt-3">
                <input type="hidden" name="enquadre" value={enquadreId} />
                <input type="hidden" name="paciente" value={pacienteId} />
                <div className="grid gap-2 sm:grid-cols-2">
                  <div>
                    <label htmlFor="quem" className="text-[12px] text-tinta2">
                      Quem assinou
                    </label>
                    <input
                      id="quem"
                      name="quem"
                      defaultValue={pacienteNome}
                      className="mt-1 w-full rounded-cartao border border-linha2 bg-folha px-3 py-2 text-[13px] text-tinta focus:border-tinta3 focus:outline-none"
                    />
                  </div>
                  <div>
                    <label htmlFor="parentesco" className="text-[12px] text-tinta2">
                      Parentesco, se for responsável
                    </label>
                    <input
                      id="parentesco"
                      name="parentesco"
                      placeholder="mãe, pai, tutor…"
                      className="mt-1 w-full rounded-cartao border border-linha2 bg-folha px-3 py-2 text-[13px] text-tinta focus:border-tinta3 focus:outline-none"
                    />
                  </div>
                </div>
                <p className="mt-2 text-[11.5px] leading-relaxed text-tinta3">
                  Fica registrado com a data e a hora de agora, marcado como
                  presencial. Não há campo de data: um aceite que se antedata não
                  serve de lastro para nada.
                </p>
                <div className="mt-2">
                  <Botao>Registrar o aceite</Botao>
                </div>
                <Recado r={rPresencial} />
              </form>
            )}
          </div>
        )}
    </div>
  );
}
