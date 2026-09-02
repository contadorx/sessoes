import Link from "next/link";
import { notFound } from "next/navigation";
import { sessaoAtual } from "@/lib/conta";
import { BlogEditor } from "@/components/app/BlogEditor";

export const metadata = { title: "Escrever" };

export default async function NovoPost() {
  const sessao = await sessaoAtual();
  if (!sessao.operador) notFound();

  return (
    <div className="mx-auto max-w-3xl">
      <Link href="/negocio/blog" className="text-[12.5px] text-tinta3 hover:text-vaga">
        ← o blog
      </Link>

      <h1 className="mt-2 font-serif text-[26px] leading-tight tracking-[-0.015em]">
        Escrever
      </h1>
      <p className="mt-2 max-w-[62ch] text-[12.5px] leading-relaxed text-tinta3">
        Nasce rascunho. Ninguém vê até você publicar, e até lá o endereço ainda
        pode mudar.
      </p>

      <div className="mt-7">
        <BlogEditor />
      </div>
    </div>
  );
}
