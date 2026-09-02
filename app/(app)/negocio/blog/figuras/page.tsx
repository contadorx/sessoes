import Link from "next/link";
import { notFound } from "next/navigation";
import { sessaoAtual } from "@/lib/conta";
import { lerFiguras } from "@/lib/blog-dados";
import { Acervo } from "@/components/app/Acervo";

export const metadata = { title: "Figuras" };

/**
 * A biblioteca inteira, fora do editor.
 *
 * Ela existe separada porque subir figura e escrever texto são dois trabalhos
 * com ritmos diferentes: as imagens de uma semana costumam ser preparadas de
 * uma vez, e o texto depois. Obrigar a passar pelo editor para subir uma figura
 * seria criar um rascunho vazio só para ter onde clicar.
 */
export default async function FigurasDoBlog() {
  const sessao = await sessaoAtual();
  if (!sessao.operador) notFound();

  const figuras = await lerFiguras();

  return (
    <div className="mx-auto max-w-4xl">
      <Link href="/negocio/blog" className="text-[12.5px] text-tinta3 hover:text-vaga">
        ← o blog
      </Link>

      <h1 className="mt-2 font-serif text-[26px] leading-tight tracking-[-0.015em]">
        Figuras
      </h1>
      <p className="mt-2 max-w-[62ch] text-[12.5px] leading-relaxed text-tinta3">
        Cada figura guarda a própria descrição e as próprias medidas — quem usa
        num texto herda as duas coisas. Uma figura que já está num texto
        publicado não sai daqui: apagá-la deixaria buraco no que as pessoas já
        leram.
      </p>

      <div className="mt-7">
        <Acervo figuras={figuras} />
      </div>
    </div>
  );
}
