"use client";

import { useActionState, useState } from "react";
import { useFormStatus } from "react-dom";
import { ESTADOS, ROTULO_ESTADO, CANAIS, ROTULO_CANAL } from "@/lib/paciente";
import { DIAS } from "@/lib/enquadre";
import type { Resultado } from "@/app/(app)/pacientes/acoes";
import type { PacienteLinha, EnquadreLinha } from "@/app/(app)/pacientes/dados";
import { Campo, Erros, Secao, ENTRADA } from "./campos";

const INICIAL: Resultado = { estado: "inicial" };

function Salvar({ rotulo }: { rotulo: string }) {
  const { pending } = useFormStatus();
  return (
    <button
      type="submit"
      disabled={pending}
      className="rounded-full bg-vaga px-6 py-2.5 text-[13.5px] font-semibold text-white transition-opacity hover:opacity-90 disabled:opacity-45"
    >
      {pending ? "Salvando…" : rotulo}
    </button>
  );
}

export function FormPaciente({
  acao,
  paciente,
  comEnquadre,
  rotuloBotao,
}: {
  acao: (anterior: Resultado, form: FormData) => Promise<Resultado>;
  paciente?: PacienteLinha;
  comEnquadre?: boolean;
  rotuloBotao: string;
}) {
  const [estado, despachar] = useActionState(acao, INICIAL);
  const [canal, setCanal] = useState(paciente?.msg_canal ?? "whatsapp");
  const erros = estado.estado === "erro" ? estado.erros : [];

  return (
    <form action={despachar} className="rounded-cartao border border-linha bg-folha p-6">
      {paciente && <input type="hidden" name="id" value={paciente.id} />}

      <Secao titulo="Quem é">
        <div className="grid gap-3 sm:grid-cols-2">
          <Campo rotulo="Nome">
            <input name="nome" required defaultValue={paciente?.nome} className={ENTRADA} />
          </Campo>
          <Campo rotulo="Situação">
            <select name="estado" defaultValue={paciente?.estado ?? "interessado"} className={ENTRADA}>
              {ESTADOS.map((e) => (
                <option key={e} value={e}>
                  {ROTULO_ESTADO[e]}
                </option>
              ))}
            </select>
          </Campo>
          <Campo rotulo="Telefone">
            <input
              name="telefone"
              inputMode="tel"
              placeholder="(11) 98765-4321"
              defaultValue={paciente?.telefone ?? ""}
              className={ENTRADA}
            />
          </Campo>
          <Campo rotulo="E-mail">
            <input type="email" name="email" defaultValue={paciente?.email ?? ""} className={ENTRADA} />
          </Campo>
          <Campo rotulo="CPF" dica="Só se for emitir recibo — Receita Saúde exige.">
            <input
              name="cpf"
              inputMode="numeric"
              defaultValue={paciente?.cpf ?? ""}
              className={ENTRADA}
            />
          </Campo>
        </div>
      </Secao>

      <Secao
        titulo="Como avisar"
        nota="O modo discreto é o padrão: remetente neutro, sem o seu nome profissional e sem a palavra terapia na tela bloqueada."
      >
        <div className="grid gap-3 sm:grid-cols-2">
          <Campo rotulo="Canal">
            <select
              name="msg_canal"
              value={canal}
              onChange={(e) => setCanal(e.target.value as typeof canal)}
              className={ENTRADA}
            >
              {CANAIS.map((c) => (
                <option key={c} value={c}>
                  {ROTULO_CANAL[c]}
                </option>
              ))}
            </select>
          </Campo>
          <Campo rotulo="Modo">
            <select
              name="msg_modo"
              defaultValue={paciente?.msg_modo ?? "discreto"}
              disabled={canal === "nao_avisar"}
              className={`${ENTRADA} disabled:opacity-50`}
            >
              <option value="discreto">discreto (padrão)</option>
              <option value="completo">completo — só se ele pediu</option>
            </select>
          </Campo>
        </div>
      </Secao>

      {comEnquadre && <CamposEnquadre />}

      <Secao titulo="Anotação administrativa" nota="Nada clínico aqui — prontuário é outra camada, com outro sigilo.">
        <textarea
          name="observacao"
          rows={2}
          defaultValue={paciente?.observacao ?? ""}
          className={ENTRADA}
        />
      </Secao>

      <Erros erros={erros} />

      <div className="mt-6">
        <Salvar rotulo={rotuloBotao} />
      </div>
    </form>
  );
}

export function CamposEnquadre({ base }: { base?: EnquadreLinha }) {
  return (
    <Secao
      titulo="O combinado"
      nota="Dia, hora, valor e a política de falta. É deste combinado que nascem as sessões, a cobrança e, depois, o contrato."
    >
      <div className="grid gap-3 sm:grid-cols-3">
        <Campo rotulo="Dia">
          <select name="dia_semana" defaultValue={base?.dia_semana ?? 2} className={ENTRADA}>
            {DIAS.map((d, i) => (
              <option key={d} value={i}>
                {d}
              </option>
            ))}
          </select>
        </Campo>
        <Campo rotulo="Hora">
          <input type="time" name="hora" defaultValue={base?.hora?.slice(0, 5) ?? ""} className={ENTRADA} />
        </Campo>
        <Campo rotulo="Duração (min)">
          <input
            type="number"
            name="duracao_min"
            min={15}
            max={240}
            step={5}
            defaultValue={base?.duracao_min ?? 50}
            className={ENTRADA}
          />
        </Campo>
        <Campo rotulo="Valor (R$)">
          <input
            name="valor"
            inputMode="decimal"
            placeholder="200,00"
            defaultValue={base?.valor ?? ""}
            className={ENTRADA}
          />
        </Campo>
        <Campo rotulo="Cobrança">
          <select name="modelo_cobranca" defaultValue={base?.modelo_cobranca ?? "avulso"} className={ENTRADA}>
            <option value="avulso">por sessão</option>
            <option value="mensal">mensalidade</option>
            <option value="pacote">pacote</option>
          </select>
        </Campo>
        <label className="flex items-end gap-2 pb-2.5 text-[13px] text-tinta2">
          <input type="checkbox" name="social" defaultChecked={base?.social} className="accent-vaga" />
          valor social
        </label>
      </div>

      <div className="mt-4 grid gap-3 sm:grid-cols-2">
        <Campo rotulo="Avisar com antecedência de (horas)">
          <input
            type="number"
            name="politica_horas"
            min={0}
            max={168}
            defaultValue={base?.politica_horas ?? 24}
            className={ENTRADA}
          />
        </Campo>
        <Campo rotulo="Senão, cobra (%)">
          <input
            type="number"
            name="politica_percentual"
            min={0}
            max={100}
            defaultValue={base?.politica_percentual ?? 50}
            className={ENTRADA}
          />
        </Campo>
      </div>
    </Secao>
  );
}
