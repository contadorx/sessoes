"use client";

import { cloneElement, isValidElement, useEffect, useRef } from "react";

export const ENTRADA =
  "mt-1.5 w-full rounded-[5px] border border-linha2 bg-folha px-3 py-2.5 text-[14px] text-tinta";

/**
 * O alvo de toque. Ela usa isto de pé, entre uma sessão e outra, às vezes com
 * a próxima paciente na sala de espera — os primários iam de 31 px a 40 px, e
 * 44 px é o mínimo em que o dedo acerta na primeira.
 */
export const BOTAO =
  "min-h-11 w-full rounded-full bg-vaga px-6 py-3 text-[13.5px] font-semibold text-white transition-opacity hover:opacity-90 disabled:opacity-45 sm:w-auto";

/**
 * Aplica uma máscara enquanto ela digita, sem transformar o campo em
 * controlado — controlar custa re-render numa tela que já faz quinze consultas.
 *
 * O cursor é reposto contando **dígitos à esquerda**, não caracteres: sem isso,
 * corrigir o meio de um CPF joga o cursor para o fim a cada tecla, e o campo
 * fica impossível de editar depois de preenchido.
 */
export function mascarar(mascara: (bruto: string) => string) {
  return (e: React.ChangeEvent<HTMLInputElement>) => {
    const alvo = e.currentTarget;
    const antes = alvo.value;
    const depois = mascara(antes);
    if (depois === antes) return;

    const caret = alvo.selectionStart ?? antes.length;
    const noFim = caret === antes.length;
    alvo.value = depois;

    if (noFim) return;

    const digitosAEsquerda = antes.slice(0, caret).replace(/\D/g, "").length;
    let i = 0;
    let vistos = 0;
    while (i < depois.length && vistos < digitosAEsquerda) {
      if (/\d/.test(depois[i])) vistos++;
      i++;
    }
    alvo.setSelectionRange(i, i);
  };
}

/** Um id estável a partir do rótulo — sem hook, para não depender de onde o campo é renderizado. */
function idDe(rotulo: string): string {
  return (
    "campo-" +
    rotulo
      .toLowerCase()
      .normalize("NFD")
      .replace(/[\u0300-\u036f]/g, "")
      .replace(/[^a-z0-9]+/g, "-")
      .replace(/(^-|-$)/g, "")
  );
}

/**
 * Um campo, e o que acontece quando ele está errado.
 *
 * O produto tinha **zero** `aria-invalid` e zero erros ao lado do campo que os
 * causou: toda mensagem ia para uma lista no fim do formulário, e num
 * formulário de duas telas e meia em 375 px isso quer dizer "está errado em
 * algum lugar aí atrás". Quem lê por leitor de tela não recebia nem isso.
 *
 * `erro` marca o controle com `aria-invalid` e escreve a frase embaixo dele.
 * `ajuda` é a explicação que só aparece se ela pedir — o que evita a tela que
 * explica demais na primeira vez e de menos na décima.
 */
export function Campo({
  rotulo,
  dica,
  ajuda,
  erro,
  obrigatorio,
  children,
}: {
  rotulo: string;
  dica?: string;
  ajuda?: React.ReactNode;
  erro?: string;
  obrigatorio?: boolean;
  children: React.ReactNode;
}) {
  const base = idDe(rotulo);
  const idErro = `${base}-erro`;
  const idDica = `${base}-dica`;

  const descrito = [erro ? idErro : null, dica ? idDica : null].filter(Boolean).join(" ");

  const controle =
    isValidElement(children) && (erro || dica)
      ? cloneElement(children as React.ReactElement<Record<string, unknown>>, {
          "aria-invalid": erro ? true : undefined,
          "aria-describedby": descrito || undefined,
        })
      : children;

  return (
    <label className="block">
      <span className="rotulo">
        {rotulo}
        {obrigatorio && (
          <span className="ml-1 font-normal text-tinta3" aria-hidden>
            (obrigatório)
          </span>
        )}
      </span>
      {controle}
      {erro && (
        <span id={idErro} className="mt-1 block text-[11.5px] font-medium text-vaga">
          {erro}
        </span>
      )}
      {dica && (
        <span id={idDica} className="mt-1 block text-[11px] text-tinta3">
          {dica}
        </span>
      )}
      {ajuda && (
        <details className="mt-1">
          <summary className="cursor-pointer text-[11px] text-tinta3 underline decoration-linha2 underline-offset-2">
            o que isso muda
          </summary>
          <div className="mt-1 text-[11.5px] leading-relaxed text-tinta2">{ajuda}</div>
        </details>
      )}
    </label>
  );
}

/**
 * O bloco de erros do formulário.
 *
 * `role="alert"` porque a lista aparece depois do envio, e sem isso o leitor de
 * tela não anuncia nada. O `scrollIntoView` porque em 375 px o botão está a
 * duas telas e meia do topo: sem rolar, ela aperta "Cadastrar", nada visível
 * muda, e a conclusão razoável é que o botão não funcionou.
 */
export function Erros({ erros }: { erros: string[] }) {
  const alvo = useRef<HTMLUListElement>(null);
  const assinatura = erros.join("|");

  useEffect(() => {
    if (assinatura === "") return;
    alvo.current?.scrollIntoView({ behavior: "smooth", block: "center" });
  }, [assinatura]);

  if (erros.length === 0) return null;

  return (
    <ul
      ref={alvo}
      role="alert"
      className="mt-4 rounded-cartao border border-vaga-linha bg-vaga-bg px-4 py-3"
    >
      {erros.map((e) => (
        <li key={e} className="text-[12.5px] font-medium text-vaga">
          {e}
        </li>
      ))}
    </ul>
  );
}

export function Secao({ titulo, nota, children }: { titulo: string; nota?: string; children: React.ReactNode }) {
  return (
    <fieldset className="mt-6 border-t border-linha pt-5 first:mt-0 first:border-0 first:pt-0">
      <legend className="sr-only">{titulo}</legend>
      <p className="rotulo">{titulo}</p>
      {nota && <p className="mt-1 text-[12px] leading-relaxed text-tinta3">{nota}</p>}
      <div className="mt-3">{children}</div>
    </fieldset>
  );
}

/**
 * A ação do formulário longo, ao alcance do polegar.
 *
 * O cadastro e a grade de horários têm ~2,5 telas de rolagem até o botão em
 * 375 px, e a grade guarda tudo em `useState` — sair antes do fim perde a
 * semana inteira. O rodapé senta **acima** da barra de navegação do celular
 * (`fixed bottom-0`, 56 px, que o layout já reserva com `pb-14`), e volta a ser
 * um rodapé comum a partir de `sm`, onde a barra não existe.
 */
export function RodapeDeAcao({ children, nota }: { children: React.ReactNode; nota?: string }) {
  return (
    <div className="sticky bottom-14 z-10 mt-6 border-t border-linha bg-folha/95 py-3 backdrop-blur sm:static sm:border-0 sm:bg-transparent sm:backdrop-blur-none">
      <div className="flex flex-col gap-2 sm:flex-row sm:items-center sm:gap-4">{children}</div>
      {nota && <p className="mt-2 text-[11.5px] leading-relaxed text-tinta3">{nota}</p>}
    </div>
  );
}
