import Link from "next/link";

export const metadata = { title: "Sem conexão" };

/**
 * A tela que ela vê quando o aparelho está sem rede — e **só** isso.
 *
 * Instalada na tela inicial, a PWA não tem barra de endereço. Sem esta página,
 * ficar sem sinal no corredor da clínica entregava a tela de erro do navegador
 * dentro de uma janela sem nenhum controle: nem recarregar, nem voltar, nem
 * sair. O único jeito era fechar o aplicativo.
 *
 * **Ela não tem dado nenhum, e isso é a decisão inteira.** Nem nome de
 * paciente, nem horário, nem número. O `sw.js` a guarda no cache do aparelho —
 * um banco de dados que sobrevive ao logout e que não é apagado quando a sessão
 * termina —, então tudo o que estiver aqui fica no celular de quem usou o app
 * naquele navegador, inclusive num computador emprestado. Uma página sem
 * conteúdo é a única que pode ser guardada assim sem custo.
 *
 * É por isso, também, que ela não tenta ser útil: não lista "suas próximas
 * sessões", não mostra o último recibo, não guarda rascunho. Cada uma dessas
 * coisas seria prontuário ou dinheiro parado no aparelho, e o modo offline não
 * vale esse preço.
 */
export default function SemConexao() {
  return (
    <main className="mx-auto flex min-h-[70vh] max-w-md flex-col justify-center px-5 py-16">
      <h1 className="font-serif text-[28px] leading-tight tracking-[-0.015em]">
        Sem conexão
      </h1>
      <p className="mt-3 text-[14px] leading-relaxed text-tinta2">
        O aparelho está sem internet no momento. Nada do que você fez se perdeu:
        o Sessões guarda tudo no servidor, e a agenda volta como estava assim que
        o sinal voltar.
      </p>
      <p className="mt-3 text-[13px] leading-relaxed text-tinta3">
        Esta tela não guarda nenhuma informação sua no celular — por isso ela
        está vazia.
      </p>

      <div className="mt-7">
        <Link
          href="/agenda"
          className="inline-flex min-h-11 items-center rounded-full bg-vaga px-6 text-[13.5px] font-semibold text-white transition-opacity hover:opacity-90"
        >
          Tentar de novo
        </Link>
      </div>
    </main>
  );
}
