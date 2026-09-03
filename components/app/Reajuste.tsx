"use client";

import { useState } from "react";
import { useFormStatus } from "react-dom";
import { useActionState } from "react";
import { reajustarCombinado, type Resultado } from "@/app/(app)/pacientes/acoes";
import type { EnquadreLinha } from "@/app/(app)/pacientes/dados";
import { BOTAO, Campo, Erros, ENTRADA } from "./campos";
import { lerCentavos, paraCampo } from "@/lib/formato";
import { paraCentavos } from "@/lib/dinheiro";
import { fraseDoReajuste, primeiroDoMesQueVem } from "@/lib/reajuste";
import { renderizar } from "@/lib/mensageria/templates";

const INICIAL: Resultado = { estado: "inicial" };

function Confirmar() {
  const { pending } = useFormStatus();
  return (
    <button type="submit" disabled={pending} className={BOTAO}>
      {pending ? "Reajustando…" : "Reajustar"}
    </button>
  );
}

/**
 * O reajuste, e ele é uma conversa antes de ser um número.
 *
 * O que essa psicóloga faz hoje: adia. Não porque mexer no valor seja difícil —
 * é uma linha desde a B4 —, mas porque **avisar** é difícil, e porque ela não
 * sabe o que acontece com a sessão que já está marcada. Esta tela responde as
 * duas antes de ela confirmar:
 *
 *  · a data em que o valor novo passa a valer, escolhida por ela;
 *  · a frase que diz o que muda **e o que não muda**;
 *  · o texto exato que a paciente vai receber, à vista.
 *
 * **O texto não é escrito aqui.** Ele vem de `renderizar`, o mesmo caminho que
 * monta a mensagem de verdade — se a pré-visualização tivesse redação própria,
 * seriam duas versões do único aviso que a paciente recebe sobre dinheiro, e a
 * que ela leu antes de mandar não seria a que saiu.
 *
 * E o que esta tela **não** faz: não sugere valor, não calcula percentual, não
 * lembra de reajustar no ano que vem. Ver o cabeçalho de `lib/reajuste.ts`.
 */
export function Reajuste({
  pacienteId,
  pacienteNome,
  aberto,
  hoje,
}: {
  pacienteId: string;
  pacienteNome: string;
  aberto: EnquadreLinha;
  hoje: string;
}) {
  const [abertoNaTela, setAbertoNaTela] = useState(false);
  const [estado, despachar] = useActionState(reajustarCombinado, INICIAL);

  const atual = paraCentavos(aberto.valor);
  const [valor, setValor] = useState(paraCampo(atual));
  const [vigencia, setVigencia] = useState(primeiroDoMesQueVem(hoje));
  const [avisar, setAvisar] = useState(true);

  const erros = estado.estado === "erro" ? estado.erros : [];
  const porCampo = (estado.estado === "erro" && estado.porCampo) || {};

  if (!abertoNaTela) {
    return (
      <button
        type="button"
        onClick={() => setAbertoNaTela(true)}
        className="mt-3 text-[13px] font-medium text-vaga hover:underline"
      >
        Reajustar o valor →
      </button>
    );
  }

  const novo = lerCentavos(valor);
  const dataValida = /^\d{4}-\d{2}-\d{2}$/.test(vigencia);
  const podeMostrar = novo !== null && novo > 0 && dataValida;

  // O corpo real do template, montado com os mesmos dados que vão para a fila.
  const previa = podeMostrar
    ? renderizar("aviso_de_reajuste", {
        nome: pacienteNome,
        vale_de: vigencia,
        valor_centavos: novo,
      }).texto
    : "";

  return (
    <form action={despachar} className="mt-4 rounded-cartao border border-linha bg-folha p-6">
      <input type="hidden" name="paciente_id" value={pacienteId} />
      <input type="hidden" name="enquadre_id" value={aberto.id} />

      <Campo rotulo="Novo valor da sessão" erro={porCampo.valor} obrigatorio>
        <input
          name="valor"
          inputMode="decimal"
          value={valor}
          onChange={(e) => setValor(e.target.value)}
          className={ENTRADA}
        />
      </Campo>

      {aberto.mensalidade_valor !== null && (
        <Campo
          rotulo="Novo valor fixo do mês"
          erro={porCampo.mensalidade_valor}
          dica="Em branco passa a cobrar por sessão do mês."
        >
          <input
            name="mensalidade_valor"
            inputMode="decimal"
            defaultValue={paraCampo(paraCentavos(aberto.mensalidade_valor))}
            className={ENTRADA}
          />
        </Campo>
      )}

      <Campo
        rotulo="A partir de"
        erro={porCampo.vigencia}
        dica="Sugestão: o dia 1º do mês que vem, que é quando a mensalidade vira."
        obrigatorio
      >
        <input
          type="date"
          name="vigencia"
          min={hoje}
          value={vigencia}
          onChange={(e) => setVigencia(e.target.value)}
          className={ENTRADA}
        />
      </Campo>

      {podeMostrar && (
        <p className="mt-4 rounded-cartao border border-linha bg-folha2 px-4 py-3 text-[13px] leading-relaxed text-tinta">
          {fraseDoReajuste(atual, novo, hoje, vigencia)}
        </p>
      )}

      <label className="mt-4 flex cursor-pointer items-start gap-2.5 rounded-cartao border border-linha2 px-3 py-2.5 has-[:checked]:border-vaga has-[:checked]:bg-vaga-bg">
        <input
          type="checkbox"
          name="avisar"
          checked={avisar}
          onChange={(e) => setAvisar(e.target.checked)}
          className="mt-0.5"
        />
        <span className="text-[13px] leading-relaxed text-tinta2">
          Preparar o aviso para {pacienteNome.split(" ")[0]}
        </span>
      </label>

      {avisar && podeMostrar && (
        <div className="mt-2 rounded-cartao border border-dashed border-linha2 bg-folha px-4 py-3">
          <p className="text-[11.5px] text-tinta3">O que ela recebe:</p>
          <p className="mt-1 text-[13px] leading-relaxed text-tinta">{previa}</p>
        </div>
      )}

      <Erros erros={erros} />
      {estado.estado === "ok" && (
        <p className="mt-3 text-[12.5px] leading-relaxed text-cheia">{estado.mensagem}</p>
      )}

      <div className="mt-6 flex flex-wrap items-center gap-4">
        <Confirmar />
        <button
          type="button"
          onClick={() => setAbertoNaTela(false)}
          className="px-2 text-[13px] text-tinta3 hover:text-tinta2"
        >
          deixa
        </button>
      </div>
    </form>
  );
}
