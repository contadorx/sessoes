"use client";

import { useState } from "react";
import { useActionState } from "react";
import { useFormStatus } from "react-dom";
import {
  esquecerContato,
  arquivarPaciente,
  type Resultado,
} from "@/app/(app)/pacientes/acoes";

const INICIAL: Resultado = { estado: "inicial" };

function Botao({ rotulo, tom }: { rotulo: string; tom?: "grave" }) {
  const { pending } = useFormStatus();
  return (
    <button
      type="submit"
      disabled={pending}
      className={`rounded-full border px-4 py-2 text-[12.5px] font-medium transition-colors disabled:opacity-45 ${
        tom === "grave"
          ? "border-vaga-linha text-vaga hover:bg-vaga-bg"
          : "border-linha2 text-tinta2 hover:bg-folha2"
      }`}
    >
      {pending ? "…" : rotulo}
    </button>
  );
}

function Recado({ r }: { r: Resultado }) {
  if (r.estado === "ok") {
    return (
      <p className="mt-2 text-[12.5px] leading-relaxed text-tinta2">{r.mensagem}</p>
    );
  }
  if (r.estado === "erro") {
    return (
      <p className="mt-2 text-[12.5px] leading-relaxed text-vaga">{r.erros[0]}</p>
    );
  }
  return null;
}

/**
 * O canto das decisões que não se desfazem.
 *
 * Ele é feio de propósito: sem cor de destaque, sem convite. As três ações aqui
 * são as únicas do produto que ninguém deve tomar por acidente, e a interface
 * tem de refletir isso — botão bonito é um convite, e não se convida ninguém a
 * encerrar um acompanhamento.
 */
export function Privacidade({
  pacienteId,
  nome,
  arquivado,
  contatoEsquecidoEm,
  restricaoJudicial,
  horarioVigente,
}: {
  pacienteId: string;
  nome: string;
  arquivado: boolean;
  contatoEsquecidoEm: string | null;
  restricaoJudicial: boolean;
  /**
   * "terça, 15h" — o horário do combinado que ainda está de pé, ou `null`.
   *
   * Ele existe aqui por uma razão só: arquivar **fecha esse combinado**, e
   * fechar um combinado dispara `ao_encerrar_enquadre`, que abre uma vaga fixa
   * com motivo `alta`. O horário entra na fila de entrada e passa a ser
   * oferecido — e a tela não dizia isso. Nomear o horário é a diferença entre
   * ela decidir e ela descobrir.
   */
  horarioVigente: string | null;
}) {
  const [rEsquecer, despacharEsquecer] = useActionState(esquecerContato, INICIAL);
  const [rArquivar, despacharArquivar] = useActionState(arquivarPaciente, INICIAL);
  const [confirmando, setConfirmando] = useState<null | "esquecer" | "arquivar">(null);

  const sufixo = restricaoJudicial ? "?ciente=1" : "";
  const urlPapel = `/pacientes/${pacienteId}/exportar/imprimir${sufixo}`;
  const urlJson = `/pacientes/${pacienteId}/exportar${sufixo}`;

  return (
    <section className="mt-10 border-t border-linha pt-6">
      <h2 className="rotulo">Registro e privacidade</h2>

      {/* -------------------------------------------------------- exportar */}
      <div className="mt-3 rounded-cartao border border-linha bg-folha2 px-5 py-4">
        <p className="text-[13px] font-medium text-tinta">
          Entregar o registro para {nome.split(" ")[0]}
        </p>
        <p className="mt-1 text-[12.5px] leading-relaxed text-tinta2">
          Direito de acesso ao próprio prontuário. Sai o cadastro, o combinado,
          as sessões e as cobranças — marcado como documento sigiloso.
        </p>

        {restricaoJudicial && (
          <p className="mt-2 rounded-cartao border border-vaga-linha bg-vaga-bg px-3 py-2 text-[12px] leading-relaxed text-tinta2">
            <b className="font-semibold text-vaga">Há restrição judicial nesta ficha.</b>{" "}
            Responsáveis de menor têm acesso mesmo sem a guarda — <b>salvo</b>{" "}
            decisão judicial. Ao baixar, você está declarando que conhece a
            decisão e que a entrega respeita o que ela determina.
          </p>
        )}

        {/* Dois botões, e a ordem é a decisão.

            Antes havia um só, e ele baixava JSON — um arquivo que a pessoa que
            exerce o direito de acesso não sabe abrir. Portabilidade é direito
            de máquina e legibilidade é direito de pessoa: o primeiro serve a
            quem troca de sistema, o segundo a quem quer ler o próprio
            prontuário. O primário é o segundo, porque quem pede a ficha na
            sala é uma pessoa. */}
        <div className="mt-3 flex flex-wrap items-center gap-2">
          <a
            href={urlPapel}
            className="inline-block rounded-full border border-linha2 bg-folha px-4 py-2 text-[12.5px] font-medium text-tinta transition-colors hover:bg-folha2"
          >
            Ver e imprimir
          </a>
          <a
            href={urlJson}
            className="inline-block text-[12.5px] text-tinta3 underline underline-offset-2 transition-colors hover:text-vaga"
          >
            Baixar em JSON
          </a>
        </div>
      </div>

      {/* --------------------------------------------------- pedido de exclusão */}
      {!contatoEsquecidoEm ? (
        <div className="mt-3 rounded-cartao border border-linha bg-folha2 px-5 py-4">
          <p className="text-[13px] font-medium text-tinta">
            Pediu para apagar os dados
          </p>
          <p className="mt-1 text-[12.5px] leading-relaxed text-tinta2">
            Dá para apagar <b>o contato</b> — telefone e e-mail — e parar todo
            envio na hora. O registro clínico não sai: o Conselho obriga a
            guardá-lo por cinco anos depois do último atendimento. Ao confirmar,
            aparece aqui a data exata em que ele pode ser eliminado, para você
            repassar.
          </p>

          {confirmando === "esquecer" ? (
            <form action={despacharEsquecer} className="mt-3 flex flex-wrap items-center gap-2">
              <input type="hidden" name="paciente_id" value={pacienteId} />
              {/*
                O "deixa" tem o mesmo peso do botão grave.

                Era o elemento de **menor** contraste da fileira — texto solto
                em `text-tinta3`, sem alvo de toque, ao lado de um botão cheio
                que apaga contato. Quem se arrependeu precisa achar a saída pelo
                menos tão rápido quanto achou a entrada, e num alvo que o polegar
                acerte de primeira.
              */}
              <span className="text-[12.5px] text-tinta2">Apagar o contato?</span>
              <Botao rotulo="Sim, apagar" tom="grave" />
              <button
                type="button"
                onClick={() => setConfirmando(null)}
className="min-h-11 rounded-full border border-linha2 px-4 py-2 text-[12.5px] font-medium text-tinta2 transition-colors hover:bg-folha2"
              >
                deixa
              </button>
            </form>
          ) : (
            <button
              type="button"
              onClick={() => setConfirmando("esquecer")}
              className="mt-3 rounded-full border border-linha2 px-4 py-2 text-[12.5px] font-medium text-tinta2 transition-colors hover:bg-folha"
            >
              Apagar o contato
            </button>
          )}

          <Recado r={rEsquecer} />
        </div>
      ) : (
        <p className="mt-3 rounded-cartao border border-linha bg-folha2 px-5 py-4 text-[12.5px] leading-relaxed text-tinta2">
          O contato desta pessoa foi apagado a pedido dela. O registro clínico
          continua guardado pelo prazo legal.
        </p>
      )}

      {/* ------------------------------------------------------- encerrar */}
      {!arquivado ? (
        <div className="mt-3 rounded-cartao border border-linha bg-folha2 px-5 py-4">
          <p className="text-[13px] font-medium text-tinta">Encerrar e arquivar</p>
          <p className="mt-1 text-[12.5px] leading-relaxed text-tinta2">
            Depois disso a ficha vira só leitura — é assim que ela serve de
            registro do que aconteceu. Escreva como o acompanhamento terminou;
            essa linha é exigida pela resolução do Conselho, e é ela que sustenta
            você se um dia alguém perguntar.
          </p>

          {/*
            O que mais acontece, dito antes.

            `arquivar_paciente` faz cinco coisas e a tela mencionava uma. As
            outras quatro não são detalhe de implementação: fecham o combinado,
            tiram a pessoa das duas filas e cancelam o que ia ser enviado. E o
            fechamento do combinado dispara `ao_encerrar_enquadre`, que **abre
            o horário para a fila de entrada** — a terça das 15h passa a ser
            oferecida a outra pessoa, e ela ficava sabendo depois.
          */}
          <ul className="mt-2 space-y-1 text-[12.5px] leading-relaxed text-tinta2">
            <li>· o combinado vigente é encerrado hoje;</li>
            {horarioVigente ? (
              <li>
                · <b className="font-medium text-tinta">{horarioVigente}</b> passa a
                ser oferecido para quem está na fila de entrada;
              </li>
            ) : (
              <li>· não há horário fixo para liberar;</li>
            )}
            <li>· ela sai da fila de encaixe e da fila de entrada;</li>
            <li>· as mensagens que ainda não saíram são canceladas.</li>
          </ul>
          <p className="mt-2 text-[12.5px] leading-relaxed text-tinta3">
            Nada é apagado: encerrar não é apagar, e o prontuário fica guardado
            pelo prazo.
          </p>

          {confirmando === "arquivar" ? (
            <form action={despacharArquivar} className="mt-3">
              <input type="hidden" name="paciente_id" value={pacienteId} />
              {/*
                O tipo, antes do texto — porque é ele que decide o que a frase
                precisa dizer, e porque sem ele o bloco 4 do registro não fecha.
                Três rádios e não um `select`: são três, e as três consequências
                clínicas são diferentes o bastante para ficarem à vista ao mesmo
                tempo. É a mesma escolha da camada do registro.
              */}
              <fieldset className="mb-3">
                <legend className="text-[12px] font-medium text-tinta2">
                  Como terminou
                </legend>
                <div className="mt-1.5 grid gap-2 sm:grid-cols-3">
                  {(
                    [
                      ["alta", "alta", "os objetivos combinados foram alcançados"],
                      ["encaminhamento", "encaminhamento", "seguiu com outro profissional"],
                      ["abandono", "abandono", "deixou de vir, sem encerrar com você"],
                    ] as const
                  ).map(([valor, rotulo, explica]) => (
                    <label
                      key={valor}
                      className="flex cursor-pointer gap-2 rounded-cartao border border-linha2 px-3 py-2 has-[:checked]:border-vaga has-[:checked]:bg-vaga-bg"
                    >
                      <input type="radio" name="tipo" value={valor} required className="mt-0.5" />
                      <span>
                        <span className="block text-[12.5px] text-tinta">{rotulo}</span>
                        <span className="mt-0.5 block text-[11px] leading-relaxed text-tinta3">
                          {explica}
                        </span>
                      </span>
                    </label>
                  ))}
                </div>
              </fieldset>

              <textarea
                name="encerramento"
                rows={3}
                required
                minLength={10}
                placeholder="Alta por objetivos alcançados, combinada na sessão de 12/03. Sem encaminhamento."
                className="w-full rounded-cartao border border-linha2 bg-folha px-3 py-2 text-[13px] leading-relaxed text-tinta placeholder:text-tinta3 focus:border-tinta3 focus:outline-none"
              />
              <div className="mt-2 flex flex-wrap items-center gap-2">
                <Botao rotulo="Encerrar" tom="grave" />
                <button
                  type="button"
                  onClick={() => setConfirmando(null)}
  className="min-h-11 rounded-full border border-linha2 px-4 py-2 text-[12.5px] font-medium text-tinta2 transition-colors hover:bg-folha2"
                >
                  deixa
                </button>
              </div>
            </form>
          ) : (
            <button
              type="button"
              onClick={() => setConfirmando("arquivar")}
              className="mt-3 rounded-full border border-linha2 px-4 py-2 text-[12.5px] font-medium text-tinta2 transition-colors hover:bg-folha"
            >
              Encerrar acompanhamento
            </button>
          )}

          <Recado r={rArquivar} />
        </div>
      ) : (
        <p className="mt-3 rounded-cartao border border-linha bg-folha2 px-5 py-4 text-[12.5px] leading-relaxed text-tinta2">
          Ficha encerrada e arquivada. É só leitura — e continua assim pelo prazo
          de guarda.
        </p>
      )}

      <p className="mt-3 text-[11.5px] leading-relaxed text-tinta3">
        Toda vez que esta ficha é aberta ou exportada, fica registrado quem fez e
        quando. A trilha não pode ser editada nem apagada, nem por você — é
        justamente isso que a torna uma defesa, e não um controle.
      </p>
    </section>
  );
}
