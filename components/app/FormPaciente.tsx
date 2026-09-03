"use client";

import { useActionState, useState } from "react";
import { useFormStatus } from "react-dom";
import { ESTADOS, ROTULO_ESTADO, CANAIS, ROTULO_CANAL } from "@/lib/paciente";
import { DIAS, PADRAO_ENQUADRE } from "@/lib/enquadre";
import { notaDoComoAvisar } from "@/lib/canal";
import {
  MODELOS,
  previsaoDoMes,
  explicacaoDoMesDeCinco,
  proximoMesDeCinco,
  type Modelo,
} from "@/lib/cobranca";
import { lerCentavos, mascaraCpf, mascaraTelefone } from "@/lib/formato";
import { OPCOES_DE_HORAS, fraseDoAjuste } from "@/lib/confirmacao";
import type { Resultado } from "@/app/(app)/pacientes/acoes";
import type { PacienteLinha, EnquadreLinha } from "@/app/(app)/pacientes/dados";
import { BOTAO, Campo, Erros, RodapeDeAcao, Secao, ENTRADA, mascarar } from "./campos";

const INICIAL: Resultado = { estado: "inicial" };

function Salvar({ rotulo }: { rotulo: string }) {
  const { pending } = useFormStatus();
  return (
    <button
      type="submit"
      disabled={pending}
      className={BOTAO}
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
  envioAutomatico,
}: {
  acao: (anterior: Resultado, form: FormData) => Promise<Resultado>;
  paciente?: PacienteLinha;
  comEnquadre?: boolean;
  rotuloBotao: string;
  /**
   * Há provedor de mensageria ligado? Desce por prop porque `lib/promessa.ts`
   * é `server-only` e este é componente de cliente — o mesmo caminho que
   * `NaSuaMao` já usava.
   */
  envioAutomatico: boolean;
}) {
  const [estado, despachar] = useActionState(acao, INICIAL);
  const [canal, setCanal] = useState(paciente?.msg_canal ?? "whatsapp");
  const erros = estado.estado === "erro" ? estado.erros : [];
  const porCampo = (estado.estado === "erro" && estado.porCampo) || {};

  // `validarPaciente` já exige os dois (lib/paciente.ts) — o que faltava era o
  // formulário dizer isso antes do envio, em vez de depois.
  const precisaTelefone = canal === "whatsapp" || canal === "sms";
  const precisaEmail = canal === "email";

  return (
    <form action={despachar} className="rounded-cartao border border-linha bg-folha p-6">
      {paciente && <input type="hidden" name="id" value={paciente.id} />}

      <Secao titulo="Quem é">
        <div className="grid gap-3 sm:grid-cols-2">
          <Campo rotulo="Nome" obrigatorio erro={porCampo.nome}>
            <input
              name="nome"
              required
              autoComplete="off"
              defaultValue={paciente?.nome}
              className={ENTRADA}
            />
          </Campo>
          <Campo
            rotulo="Situação"
            erro={porCampo.estado}
            ajuda={
              <>
                Quem está em <strong>alta</strong>, <strong>encerrado</strong> ou{" "}
                <strong>arquivado</strong> não entra na fila de encaixe, e quem está em{" "}
                <strong>pausa</strong> não aparece na lista de quem pode ocupar uma vaga.
                O resto muda só o que você vê nas listas.
              </>
            }
          >
            <select name="estado" defaultValue={paciente?.estado ?? "interessado"} className={ENTRADA}>
              {ESTADOS.map((e) => (
                <option key={e} value={e}>
                  {ROTULO_ESTADO[e]}
                </option>
              ))}
            </select>
          </Campo>
          <Campo
            rotulo="Telefone"
            erro={porCampo.telefone}
            obrigatorio={precisaTelefone}
            dica={precisaTelefone ? "É por aqui que o aviso sai." : undefined}
          >
            <input
              name="telefone"
              inputMode="tel"
              autoComplete="off"
              required={precisaTelefone}
              placeholder="(11) 98765-4321"
              defaultValue={mascaraTelefone(paciente?.telefone ?? "")}
              onChange={mascarar(mascaraTelefone)}
              className={ENTRADA}
            />
          </Campo>
          <Campo rotulo="E-mail" erro={porCampo.email} obrigatorio={precisaEmail}>
            <input
              type="email"
              name="email"
              autoComplete="off"
              required={precisaEmail}
              defaultValue={paciente?.email ?? ""}
              className={ENTRADA}
            />
          </Campo>
          <Campo rotulo="CPF" erro={porCampo.cpf} dica="Só se for emitir recibo — Receita Saúde exige.">
            <input
              name="cpf"
              inputMode="numeric"
              /* O Chrome ignora autoComplete="off" em campo que ele acha que é
                 documento, e oferece o CPF **dela** dentro da ficha da paciente
                 — que no caminho do Receita Saúde vira recibo com o CPF errado. */
              autoComplete="new-password"
              placeholder="000.000.000-00"
              defaultValue={mascaraCpf(paciente?.cpf ?? "")}
              onChange={mascarar(mascaraCpf)}
              className={ENTRADA}
            />
          </Campo>
        </div>
      </Secao>

      {/* "Remetente neutro" só é verdade quando a plataforma manda. No manual o
          remetente é o número dela, e é isso que a nota passa a dizer — ver
          `notaDoComoAvisar`. */}
      <Secao titulo="Como avisar" nota={notaDoComoAvisar(envioAutomatico)}>
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

      {comEnquadre && <CamposEnquadre porCampo={porCampo} />}

      <Secao titulo="Anotação administrativa" nota="Nada clínico aqui — prontuário é outra camada, com outro sigilo.">
        <textarea
          name="observacao"
          rows={2}
          defaultValue={paciente?.observacao ?? ""}
          className={ENTRADA}
        />
      </Secao>

      <Erros erros={erros} />

      <RodapeDeAcao>
        <Salvar rotulo={rotuloBotao} />
      </RodapeDeAcao>
    </form>
  );
}

export function CamposEnquadre({
  base,
  porCampo = {},
}: {
  base?: EnquadreLinha;
  porCampo?: Record<string, string>;
}) {
  const [modelo, setModelo] = useState<Modelo>(
    (base?.modelo_cobranca as Modelo) ?? PADRAO_ENQUADRE.modelo_cobranca,
  );
  const [dia, setDia] = useState<number>(base?.dia_semana ?? PADRAO_ENQUADRE.dia_semana);
  const [valor, setValor] = useState(base?.valor ?? "");
  const [mensal, setMensal] = useState(base?.mensalidade_valor ?? "");

  // Quem já tinha 30% continua vendo 30% — o combinado dela não vira uma das
  // três opções por causa de uma mudança de tela.
  const guardado = (v: number | null | undefined, padrao: number, opcoes: string[]) => {
    const atual = String(v ?? padrao);
    return opcoes.includes(atual) ? atual : "outro";
  };
  const [horas, setHoras] = useState(() =>
    guardado(base?.politica_horas, PADRAO_ENQUADRE.politica_horas, ["12", "24", "48"]),
  );
  const [horasLivre, setHorasLivre] = useState(String(base?.politica_horas ?? PADRAO_ENQUADRE.politica_horas));
  const [pct, setPct] = useState(() =>
    guardado(base?.politica_percentual, PADRAO_ENQUADRE.politica_percentual, ["0", "50", "100"]),
  );
  const [pctLivre, setPctLivre] = useState(String(base?.politica_percentual ?? PADRAO_ENQUADRE.politica_percentual));
  const [confirma, setConfirma] = useState(
    base?.confirmacao_horas_antes == null ? "" : String(base.confirmacao_horas_antes),
  );

  return (
    <Secao
      titulo="O combinado"
      nota="Dia, hora, valor e a política de falta. É deste combinado que nascem as sessões, a cobrança e, depois, o contrato."
    >
      <div className="grid gap-3 sm:grid-cols-3">
        <Campo rotulo="Dia" erro={porCampo.dia_semana}>
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
        <Campo rotulo="Hora" erro={porCampo.hora}>
          <input
            type="time"
            step={900}
            name="hora"
            defaultValue={base?.hora?.slice(0, 5) ?? ""}
            className={ENTRADA}
          />
        </Campo>
        <Campo rotulo="Duração (min)" erro={porCampo.duracao_min}>
          <input
            type="number"
            onWheel={(e) => e.currentTarget.blur()}
            name="duracao_min"
            min={15}
            max={240}
            step={5}
            defaultValue={base?.duracao_min ?? PADRAO_ENQUADRE.duracao_min}
            className={ENTRADA}
          />
        </Campo>
        <Campo rotulo="Valor da sessão (R$)" erro={porCampo.valor}>
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
        <label className="flex flex-col justify-end gap-1 pb-2.5 text-[13px] text-tinta2">
          <span className="flex items-center gap-2">
            <input type="checkbox" name="social" defaultChecked={base?.social} className="accent-vaga" />
            valor social
          </span>
          <span className="text-[11px] leading-relaxed text-tinta3">
            Marca o combinado como valor social. Não muda o preço, o recibo nem a
            ordem da fila — é o que separa, no fechamento, o que você atendeu por
            um valor menor do que o seu.
          </span>
        </label>
      </div>

      {/*
        A política em palavra, não em número.

        Perguntar "Senão, cobra (%)" a quem se descreve como ruim com números é
        pedir um número que ela não tem — e o campo ainda ficava a uma rolagem
        de distância do cursor, então rolar a página em cima dele mudava a
        política de falta sem clique. As três respostas que quase todo mundo dá
        viram opção; quem cobra 30% continua tendo onde escrever 30.
      */}
      <div className="mt-4 grid gap-3 sm:grid-cols-2">
        <Campo rotulo="Desmarcar com menos de" erro={porCampo.politica_horas}>
          <>
            <select
              value={horas}
              onChange={(e) => setHoras(e.target.value)}
              className={ENTRADA}
            >
              <option value="12">12 horas</option>
              <option value="24">24 horas</option>
              <option value="48">48 horas</option>
              <option value="outro">outro prazo…</option>
            </select>
            {horas === "outro" && (
              <input
                type="number"
                onWheel={(e) => e.currentTarget.blur()}
                inputMode="numeric"
                min={0}
                max={168}
                value={horasLivre}
                onChange={(e) => setHorasLivre(e.target.value)}
                aria-label="Prazo em horas"
                className={`${ENTRADA} mt-2`}
              />
            )}
            <input
              type="hidden"
              name="politica_horas"
              value={horas === "outro" ? horasLivre : horas}
            />
          </>
        </Campo>
        <Campo rotulo="Aí a sessão é cobrada" erro={porCampo.politica_percentual}>
          <>
            <select
              value={pct}
              onChange={(e) => setPct(e.target.value)}
              className={ENTRADA}
            >
              <option value="0">nada</option>
              <option value="50">metade</option>
              <option value="100">por inteiro</option>
              <option value="outro">outro valor…</option>
            </select>
            {pct === "outro" && (
              <input
                type="number"
                onWheel={(e) => e.currentTarget.blur()}
                inputMode="numeric"
                min={0}
                max={100}
                value={pctLivre}
                onChange={(e) => setPctLivre(e.target.value)}
                aria-label="Percentual cobrado"
                className={`${ENTRADA} mt-2`}
              />
            )}
            <input
              type="hidden"
              name="politica_percentual"
              value={pct === "outro" ? pctLivre : pct}
            />
          </>
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
        <Campo rotulo="Pedir confirmação ao paciente" erro={porCampo.confirmacao_horas_antes}>
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
  // A prévia lê com o mesmo parser do servidor. Quando eram dois, digitar
  // "1.200" mostrava a previsão de R$ 1,20 e gravava R$ 1.200,00 — ou o
  // contrário. Prévia que discorda do que vai ser gravado é pior que prévia
  // nenhuma.
  const centavos = lerCentavos(valor) ?? 0;
  const fixo = lerCentavos(mensal);

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
