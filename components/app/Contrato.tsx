"use client";

import { useActionState, useState } from "react";
import { useFormStatus } from "react-dom";
import { publicarContrato, type Resultado } from "@/app/(app)/perfil/contrato/acoes";
import {
  MARCADORES,
  TEXTO_PADRAO,
  faltamObrigatorios,
  marcadoresDesconhecidos,
  montar,
} from "@/lib/contrato";

const INICIAL: Resultado = { estado: "inicial" };

/** Um combinado de exemplo, só para a pré-visualização ter o que mostrar. */
const EXEMPLO = {
  nome: "Maria Reis",
  profissional: "",
  crp: "",
  diaSemana: 2,
  hora: "15:00",
  duracaoMin: 50,
  valorCentavos: 20_000,
  politicaHoras: 24,
  politicaPercentual: 50,
  cidade: "",
  data: new Date().toISOString().slice(0, 10),
};

function Publicar() {
  const { pending } = useFormStatus();
  return (
    <button
      type="submit"
      disabled={pending}
      className="rounded-full bg-tinta px-5 py-2 text-[12.5px] font-medium text-papel transition-opacity hover:opacity-90 disabled:opacity-45"
    >
      {pending ? "…" : "Publicar esta versão"}
    </button>
  );
}

export function EditorDeContrato({
  titulo,
  corpo,
  versao,
  assinaComo,
  crp,
  cidade,
  podeEditar,
}: {
  titulo: string;
  corpo: string;
  versao: number | null;
  assinaComo: string | null;
  crp: string | null;
  cidade: string | null;
  podeEditar: boolean;
}) {
  const [r, despachar] = useActionState(publicarContrato, INICIAL);
  const [texto, setTexto] = useState(corpo || TEXTO_PADRAO);
  const [vendo, setVendo] = useState(false);

  const faltam = faltamObrigatorios(texto);
  const errados = marcadoresDesconhecidos(texto);

  const previa = montar(texto, {
    ...EXEMPLO,
    profissional: assinaComo ?? "",
    crp: crp ?? "",
    cidade: cidade ?? "",
  });

  return (
    <form action={despachar} className="mt-4">
      <fieldset disabled={!podeEditar} className="space-y-4">
        <div>
          <label htmlFor="titulo" className="text-[12px] font-medium text-tinta2">
            Título do documento
          </label>
          <input
            id="titulo"
            name="titulo"
            defaultValue={titulo || "Combinado de atendimento"}
            maxLength={120}
            className="mt-1 w-full rounded-cartao border border-linha2 bg-folha px-3 py-2 text-[13px] text-tinta focus:border-tinta3 focus:outline-none"
          />
        </div>

        <div className="grid gap-4 lg:grid-cols-[1fr_260px]">
          <div>
            <div className="flex items-baseline justify-between gap-3">
              <label htmlFor="corpo" className="text-[12px] font-medium text-tinta2">
                O texto
              </label>
              <button
                type="button"
                onClick={() => setVendo((v) => !v)}
                className="text-[12px] text-tinta3 underline underline-offset-2 hover:text-vaga"
              >
                {vendo ? "voltar a escrever" : "ver como fica"}
              </button>
            </div>

            {vendo ? (
              <div className="mt-1 min-h-[420px] whitespace-pre-wrap rounded-cartao border border-linha bg-folha px-4 py-3 font-serif text-[14.5px] leading-relaxed text-tinta">
                {previa}
              </div>
            ) : (
              <textarea
                id="corpo"
                name="corpo"
                value={texto}
                onChange={(e) => setTexto(e.target.value)}
                rows={22}
                spellCheck
                className="mt-1 w-full rounded-cartao border border-linha2 bg-folha px-3 py-2 font-mono text-[12.5px] leading-relaxed text-tinta focus:border-tinta3 focus:outline-none"
              />
            )}

            {vendo && (
              <p className="mt-2 text-[11.5px] leading-relaxed text-tinta3">
                Pré-visualização com um combinado de exemplo (terça, 15h, R$ 200,
                política 24h/50%). No documento de cada pessoa entram os números
                dela.
              </p>
            )}
          </div>

          {/* ------------------------------------------------ os marcadores */}
          <aside className="lg:pt-6">
            <h3 className="rotulo">O que o sistema preenche</h3>
            <ul className="mt-2 space-y-1.5">
              {MARCADORES.map((m) => {
                const usado = texto.includes(m.chave);
                const obrigatorio = m.chave === "{{politica}}" || m.chave === "{{valor}}";
                return (
                  <li key={m.chave} className="text-[11.5px] leading-relaxed">
                    <code
                      className={`font-mono ${
                        usado ? "text-cheia" : obrigatorio ? "text-vaga" : "text-tinta3"
                      }`}
                    >
                      {m.chave}
                    </code>{" "}
                    <span className="text-tinta3">{m.vira}</span>
                    {obrigatorio && !usado && (
                      <span className="text-vaga"> · obrigatório</span>
                    )}
                  </li>
                );
              })}
            </ul>

            <p className="mt-4 text-[11.5px] leading-relaxed text-tinta3">
              Escreva a regra de desmarcação como <code className="font-mono">{"{{politica}}"}</code>,
              nunca com o número na mão. Um &ldquo;24 horas&rdquo; digitado no texto
              desatualiza no primeiro paciente com outra política — e o contrato
              passa a dizer uma coisa enquanto o sistema cobra outra.
            </p>
          </aside>
        </div>

        {faltam.length > 0 && (
          <div className="rounded-cartao border border-vaga-linha bg-vaga-bg px-4 py-3">
            <p className="text-[12.5px] leading-relaxed text-vaga">
              {faltam.includes("{{politica}}") && (
                <>
                  Falta <code className="font-mono">{"{{politica}}"}</code> no texto.
                  É a regra que a cobrança automática aplica — cobrar por uma regra
                  que não estava escrita é exatamente o constrangimento que este
                  produto existe para tirar da sala.{" "}
                </>
              )}
              {faltam.includes("{{valor}}") && (
                <>
                  Falta <code className="font-mono">{"{{valor}}"}</code> no texto.
                </>
              )}
            </p>
          </div>
        )}

        {errados.length > 0 && (
          <p className="text-[12.5px] text-aviso">
            Não conheço {errados.join(", ")} — vai sair no texto do jeito que está.
          </p>
        )}

        <div className="flex flex-wrap items-center gap-3">
          {podeEditar && <Publicar />}
          {versao !== null && (
            <span className="text-[12px] text-tinta3">
              publicando a versão {versao + 1}
            </span>
          )}
        </div>
      </fieldset>

      {r.estado === "ok" && (
        <p className="mt-3 text-[12.5px] text-cheia">{r.mensagem}</p>
      )}
      {r.estado === "erro" && (
        <ul className="mt-3 space-y-1">
          {r.erros.map((e, i) => (
            <li key={i} className="text-[12.5px] leading-relaxed text-vaga">
              {e}
            </li>
          ))}
        </ul>
      )}
    </form>
  );
}
