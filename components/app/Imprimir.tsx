"use client";

/**
 * Salvar em PDF.
 *
 * Não geramos o PDF no servidor, e é escolha. Uma biblioteca de PDF em
 * serverless significa posicionar texto à mão — e o conteúdo aqui é de tamanho
 * variável: um mês com duas sessões e outro com dez quebram layouts fixos de
 * formas diferentes, que só aparecem no mês em que quebram.
 *
 * O navegador já tem um motor de PDF excelente, respeita a tipografia da página
 * e o "Salvar como PDF" é o mesmo lugar onde toda brasileira já salva boleto.
 * O custo é um clique a mais; o ganho é um documento que nunca sai torto.
 */
export function Imprimir() {
  return (
    <button
      type="button"
      onClick={() => window.print()}
      className="rounded-full bg-vaga px-5 py-2 text-[13px] font-semibold text-white transition-opacity hover:opacity-90"
    >
      Imprimir ou salvar em PDF
    </button>
  );
}
