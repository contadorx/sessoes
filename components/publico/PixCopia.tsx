"use client";

import { useState } from "react";

/**
 * O copia e cola, e **não há QR code aqui**.
 *
 * A decisão parece uma economia e não é. Quem abre esta página abre no celular
 * — o link chegou pelo WhatsApp —, e um QR code na tela do mesmo aparelho que
 * vai escanear é inútil: a pessoa teria de imprimir ou usar um segundo
 * telefone. O que ela faz de verdade é copiar o código e colar no aplicativo
 * do banco, que é exatamente o que este botão entrega em um toque.
 *
 * E a consequência técnica é boa: um QR exigiria uma dependência nova num
 * produto que tem cinco em tempo de execução, ou duzentas linhas de codificação
 * de bits para desenhar uma coisa que ninguém ia escanear.
 *
 * **O `navigator.clipboard` pode não existir**, e a página não pode quebrar por
 * isso: contexto inseguro, navegador antigo, permissão negada. Quando falha, o
 * código continua na tela, selecionável, e a frase muda para dizer o que fazer
 * com a mão — é a mesma escolha do fallback de uuid do Panorama, onde o
 * silêncio custaria a resposta inteira de alguém.
 */
export function PixCopia({ codigo }: { codigo: string }) {
  const [estado, setEstado] = useState<"parado" | "copiado" | "manual">("parado");

  async function copiar() {
    try {
      await navigator.clipboard.writeText(codigo);
      setEstado("copiado");
      window.setTimeout(() => setEstado("parado"), 4000);
    } catch {
      setEstado("manual");
    }
  }

  return (
    <div className="mt-3">
      <button
        type="button"
        onClick={copiar}
        className="w-full rounded-full bg-vaga px-4 py-3 text-center text-[14px] font-semibold text-white transition-opacity hover:opacity-90"
      >
        {estado === "copiado" ? "Copiado" : "Copiar o código do Pix"}
      </button>

      {estado === "manual" && (
        <p className="mt-2 text-[12.5px] leading-relaxed text-tinta2">
          Seu navegador não deixou copiar sozinho. Selecione o código abaixo e
          copie com o dedo.
        </p>
      )}

      {/* O código fica **sempre** visível, e não escondido atrás do botão.
          Um bloco que só existe depois de um clique é um bloco que some quando
          o clique falha — e quem está com o aplicativo do banco aberto do lado
          precisa do texto, não da promessa dele. */}
      <p className="mt-2.5 break-all rounded-cartao border border-linha bg-folha2 px-3.5 py-3 font-mono text-[11.5px] leading-relaxed text-tinta2 select-all">
        {codigo}
      </p>
    </div>
  );
}
