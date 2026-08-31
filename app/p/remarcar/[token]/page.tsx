import { notFound } from "next/navigation";
import { db } from "@/lib/db";
import { supabaseServer } from "@/lib/supabase/server";
import { Escolha } from "@/components/publico/Escolha";
import { rotuloPublico, quando, type EstadoDaRemarcacao, type Opcao } from "@/lib/remarcacao";

/**
 * Título neutro e `noindex`, pelas mesmas duas razões da B19.
 *
 * O título é o que aparece na prévia do link dentro do WhatsApp, na aba do
 * navegador e no histórico — três telas que outra pessoa pode estar olhando. E
 * um token vazado que também estivesse indexado deixaria de ser um acidente
 * para virar uma página pública.
 */
export const metadata = {
  title: "Horários",
  robots: { index: false, follow: false },
  openGraph: { title: "Horários", description: "" },
};

export const dynamic = "force-dynamic";

type Visto = {
  estado: EstadoDaRemarcacao;
  nome: string | null;
  atual: string | null;
  escolhido: string | null;
  opcoes: Opcao[];
};

export default async function PaginaDaRemarcacao({
  params,
}: {
  params: Promise<{ token: string }>;
}) {
  const { token } = await params;
  const supabase = supabaseServer();

  const visto = (await db(
    "remarcacao.ver",
    supabase.rpc("remarcacao_por_token", { p_token: token }),
  )) as unknown as Visto;

  if (!visto || visto.estado === "inexistente") notFound();

  return (
    <main className="mx-auto max-w-lg px-5 py-10 sm:px-8 sm:py-16">
      <h1 className="font-serif text-[26px] leading-tight tracking-[-0.015em]">
        {visto.nome ? `Oi, ${visto.nome}.` : "Oi."}
      </h1>

      <p className="mt-3 text-[15px] leading-relaxed text-tinta2">
        {rotuloPublico(visto.estado)}
      </p>

      {visto.atual && visto.estado === "aberta" && (
        <p className="mt-4 rounded-cartao border border-linha bg-folha2 px-4 py-3 text-[13px] leading-relaxed text-tinta2">
          Hoje está marcado para{" "}
          <b className="font-medium text-tinta">{quando(visto.atual)}</b>. Escolher
          um dos horários abaixo troca por ele.
        </p>
      )}

      {visto.estado === "escolhida" && visto.escolhido && (
        <p className="mt-4 rounded-cartao border border-cheia-linha bg-cheia-bg px-5 py-4 text-[14px] leading-relaxed text-cheia">
          Ficou <b className="font-semibold">{quando(visto.escolhido)}</b>.
        </p>
      )}

      {visto.estado === "aberta" && (
        <Escolha token={token} opcoes={visto.opcoes ?? []} />
      )}

      <footer className="mt-12 border-t border-linha pt-5">
        <p className="text-[11.5px] leading-relaxed text-tinta3">
          Esta página existe só para você escolher um horário. Ela não pede nem
          mostra mais nada — nem sobre você, nem sobre ninguém.
        </p>
      </footer>
    </main>
  );
}
