"use client";

import { useActionState, useState } from "react";
import { useFormStatus } from "react-dom";
import { ESTADOS, ROTULO_ESTADO, CANAIS, ROTULO_CANAL } from "@/lib/paciente";
import { DIAS } from "@/lib/enquadre";
import {
  MODELOS,
  previsaoDoMes,
  explicacaoDoMesDeCinco,
  proximoMesDeCinco,
  type Modelo,
} from "@/lib/cobranca";
import { paraCentavos } from "@/lib/dinheiro";
import { OPCOES_DE_HORAS, fraseDoAjuste } from "@/lib/confirmacao";
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
  const [modelo, setModelo] = useState<Modelo>(
    (base?.modelo_cobranca as Modelo) ?? "avulso",
  );
  const [dia, setDia] = useState<number>(base?.dia_semana ?? 2);
  const [valor, setValor] = useState(base?.valor ?? "");
  const [mensal, setMensal] = useState(base?.mensalidade_valor ?? "");
  const [confirma, setConfirma] = useState(
    base?.confirmacao_horas_antes == null ? "" : String(base.confirmacao_horas_antes),
  );

  return (
    <Secao
      titulo="O combinado"
      nota="Dia, hora, valor e a política de falta. É deste combinado que nascem as sessões, a cobrança e, depois, o contrato."
    >
      <div className="grid gap-3 sm:grid-cols-3">
        <Campo rotulo="Dia">
          <select
            name="dia_semana"
            value={dia}
            onChange={(e) => setDia(Number(e.target.value))}
            className={ENTRADA}
          >
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
        <Campo rotulo="Valor da sessão (R$)">
          <input
            name="valor"
            inputMode="decimal"
            placeholder="200,00"
            value={valor}
            onChange={(e) => setValor(e.target.value)}
            className={ENTRADA}
          />
        </Campo>
        <Campo rotulo="Cobrança">
          <select
            name="modelo_cobranca"
            value={modelo}
            onChange={(e) => setModelo(e.target.value as Modelo)}
            className={ENTRADA}
          >
            {MODELOS.map((m) => (
              <option key={m.valor} value={m.valor}>
                {m.rotulo}
              </option>
            ))}
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

      <p className="mt-3 text-[12px] leading-relaxed text-tinta3">
        {MODELOS.find((m) => m.valor === modelo)?.explica}
      </p>

      {/* ------------------------------------------------------ a confirmação

          **Vazio é o padrão, e ele é "não pedir".** O campo existe porque
          confirmar é prática de quem atende, não decisão de software: quem já
          confirma no WhatsApp na véspera ganha isso automático, e quem não
          confirma continua sem ninguém falando com o paciente dela.

          A frase embaixo diz o que acontece com quem **não** responde, porque é
          a parte que assusta — e a resposta é: nada acontece com o horário. */}
      <div className="mt-5">
        <Campo rotulo="Pedir confirmação ao paciente">
          <select
            name="confirmacao_horas_antes"
            value={confirma}
            onChange={(e) => setConfirma(e.target.value)}
            className={ENTRADA}
          >
            <option value="">não pedir</option>
            {OPCOES_DE_HORAS.map((o) => (
              <option key={o.valor} value={String(o.valor)}>
                {o.rotulo}
              </option>
            ))}
          </select>
        </Campo>
        <p className="mt-2 max-w-[62ch] text-[12px] leading-relaxed text-tinta3">
          {fraseDoAjuste(confirma === "" ? null : Number(confirma))}
        </p>
      </div>

      {modelo === "mensal" && (
        <Mensalidade
          dia={dia}
          valor={valor}
          mensal={mensal}
          setMensal={setMensal}
        />
      )}

      {modelo !== "avulso" && (
        <label className="mt-4 flex items-start gap-2.5 text-[13px] text-tinta2">
          <input
            type="checkbox"
            name="falta_cobra_a_parte"
            defaultChecked={base?.falta_cobra_a_parte ?? false}
            className="mt-0.5 accent-vaga"
          />
          <span>
            Cobrar a falta à parte, mesmo assim
            <span className="mt-0.5 block text-[12px] text-tinta3">
              Desmarcado — e é o padrão —, a hora que já foi paga não é cobrada
              duas vezes.
            </span>
          </span>
        </label>
      )}
    </Secao>
  );
}

/**
 * O mês de cinco terças, respondido enquanto ela decide.
 *
 * Esta é a pergunta que todo mensalista responde de um jeito e que nenhum
 * sistema faz. Deixar em branco é uma resposta legítima ("cobro por sessão do
 * mês") — e a frase abaixo diz o que isso significa em reais, com o mês real
 * mais próximo que tem cinco, para ela não descobrir na conta.
 */
function Mensalidade({
  dia,
  valor,
  mensal,
  setMensal,
}: {
  dia: number;
  valor: string;
  mensal: string;
  setMensal: (v: string) => void;
}) {
  let centavos = 0;
  try {
    centavos = valor.trim() === "" ? 0 : paraCentavos(valor.trim().replace(",", "."));
  } catch {
    centavos = 0;
  }

  let fixo: number | null = null;
  try {
    fixo = mensal.trim() === "" ? null : paraCentavos(mensal.trim().replace(",", "."));
  } catch {
    fixo = null;
  }

  const cinco = proximoMesDeCinco(dia);
  const previsao =
    cinco && centavos > 0
      ? previsaoDoMes(
          { modelo: "mensal", diaSemana: dia, valorCentavos: centavos, mensalidadeCentavos: fixo },
          cinco.ano,
          cinco.mes,
        )
      : null;

  return (
    <div className="mt-4 rounded-cartao border border-linha bg-folha2 px-4 py-3">
      <Campo
        rotulo="Valor fixo do mês (R$)"
        dica="Em branco, o mês é a soma das sessões dele."
      >
        <input
          name="mensalidade_valor"
          inputMode="decimal"
          placeholder="deixe em branco para cobrar por sessão do mês"
          value={mensal}
          onChange={(e) => setMensal(e.target.value)}
          className={ENTRADA}
        />
      </Campo>

      <p className="mt-2 text-[12.5px] leading-relaxed text-tinta">
        {explicacaoDoMesDeCinco(fixo)}
      </p>
      {previsao && previsao.frase && (
        <p className="mt-1 text-[12.5px] leading-relaxed text-tinta2">{previsao.frase}</p>
      )}
      <p className="mt-2 text-[11.5px] leading-relaxed text-tinta3">
        A mensalidade nasce sozinha uma vez por mês. Sessão desmarcada com
        antecedência dentro do mensal é conversa de reposição — o sistema não
        estorna por conta própria.
      </p>
    </div>
  );
}
