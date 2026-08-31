import { notFound } from "next/navigation";
import { db } from "@/lib/db";
import { supabaseServer } from "@/lib/supabase/server";
import { Aceite } from "@/components/publico/Aceite";

/**
 * O título é neutro de propósito, e não por acaso.
 *
 * Ele é o que aparece na prévia do link dentro do WhatsApp, na aba do navegador
 * e no histórico. "Contrato terapêutico" numa dessas três telas conta a alguém
 * que passa exatamente o que a discrição do produto inteiro existe para não
 * contar (D3, doc 11).
 *
 * `noindex` pelo mesmo motivo, e por mais um: um token vazado que também estava
 * indexado deixa de ser um acidente e vira uma página pública.
 */
export const metadata = {
  title: "Combinado",
  robots: { index: false, follow: false },
  openGraph: { title: "Combinado", description: "" },
};

export const dynamic = "force-dynamic";

type Visto = {
  estado: "pendente" | "aceito" | "expirado" | "revogado" | "inexistente";
  titulo: string | null;
  versao: string | null;
  texto: string | null;
  nome: string | null;
  aceito_em: string | null;
  aceito_por: string | null;
};

const DATA_HORA = new Intl.DateTimeFormat("pt-BR", {
  timeZone: "America/Sao_Paulo",
  day: "2-digit",
  month: "2-digit",
  year: "numeric",
  hour: "2-digit",
  minute: "2-digit",
});

export default async function PaginaDoContrato({
  params,
}: {
  params: Promise<{ token: string }>;
}) {
  const { token } = await params;
  const supabase = supabaseServer();

  const visto = (await db(
    "contrato.ver",
    supabase.rpc("contrato_por_token", { p_token: token }),
  )) as unknown as Visto;

  if (!visto || visto.estado === "inexistente") notFound();

  return (
    <main className="mx-auto max-w-2xl px-5 py-10 sm:px-8 sm:py-16">
      <p className="rotulo">{visto.titulo ?? "Combinado"}</p>

      <h1 className="mt-2 font-serif text-[26px] leading-tight tracking-[-0.015em]">
        {visto.nome ? `Oi, ${visto.nome}.` : "Oi."}
      </h1>

      {visto.estado === "revogado" && (
        <p className="mt-4 rounded-cartao border border-linha bg-folha2 px-5 py-4 text-[13.5px] leading-relaxed text-tinta2">
          Este combinado foi cancelado por quem te enviou. O texto continua
          abaixo, para você poder ver o que dizia.
        </p>
      )}

      {visto.estado === "expirado" && (
        <p className="mt-4 rounded-cartao border border-linha bg-folha2 px-5 py-4 text-[13.5px] leading-relaxed text-tinta2">
          Este link venceu. Você pode ler o texto abaixo, mas para confirmar
          precisa de um link novo — é só pedir para quem te enviou.
        </p>
      )}

      {visto.estado === "aceito" && visto.aceito_em && (
        <p className="mt-4 rounded-cartao border border-cheia-linha bg-cheia-bg px-5 py-4 text-[13.5px] leading-relaxed text-cheia">
          Confirmado por {visto.aceito_por} em{" "}
          {DATA_HORA.format(new Date(visto.aceito_em))}. Este é o texto exato que
          foi aceito — ele não muda mais.
        </p>
      )}

      <article className="mt-6 whitespace-pre-wrap rounded-cartao border border-linha bg-folha px-6 py-6 font-serif text-[15px] leading-[1.75] text-tinta">
        {visto.texto}
      </article>

      {visto.versao && (
        <p className="mt-3 font-mono text-[11.5px] text-tinta3">versão {visto.versao}</p>
      )}

      {visto.estado === "pendente" && <Aceite token={token} />}

      <footer className="mt-12 border-t border-linha pt-5">
        <p className="text-[11.5px] leading-relaxed text-tinta3">
          Esta página existe só para você ler e confirmar este combinado. Ela não
          pede nem mostra mais nada — nem sobre você, nem sobre ninguém.
        </p>
      </footer>
    </main>
  );
}
