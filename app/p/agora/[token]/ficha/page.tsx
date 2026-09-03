import Link from "next/link";
import { db } from "@/lib/db";
import { supabaseServer } from "@/lib/supabase/server";
import { hoje } from "@/lib/tempo-servidor";
import { Ficha } from "@/components/publico/Ficha";

/**
 * Título neutro e `noindex`, pelas mesmas duas razões da B19, da B21 e do P7.
 *
 * O título aparece na prévia do link dentro do WhatsApp, na aba e no histórico
 * — três telas que outra pessoa pode estar olhando. "Seus dados" não conta nada
 * sobre consultório.
 */
export const metadata = {
  title: "Seus dados",
  robots: { index: false, follow: false },
  openGraph: { title: "Seus dados", description: "" },
};

export const dynamic = "force-dynamic";

type Visto =
  | { estado: "inexistente" | "revogada" | "expirada" }
  | { estado: "aberta"; nome: string; preenchida_em: string | null };

const RECADO: Record<string, string> = {
  inexistente: "Este link não existe. Confira se ele veio inteiro.",
  expirada: "Este link venceu. Peça outro para quem te enviou.",
  revogada: "Este link foi cancelado por quem te enviou.",
};

export default async function PreFicha({
  params,
}: {
  params: Promise<{ token: string }>;
}) {
  const { token } = await params;
  const supabase = supabaseServer();

  const visto = ((await db(
    "paciente.ficha",
    supabase.rpc("ficha_do_paciente", { p_token: token }),
  )) ?? { estado: "inexistente" }) as unknown as Visto;

  if (visto.estado !== "aberta") {
    return (
      <main className="mx-auto max-w-md px-5 py-16">
        <h1 className="font-serif text-[24px] leading-tight text-tinta">Seus dados</h1>
        <p className="mt-3 text-[14px] leading-relaxed text-tinta2">
          {RECADO[visto.estado] ?? RECADO.inexistente}
        </p>
      </main>
    );
  }

  return (
    <main className="mx-auto max-w-md px-5 py-12">
      <h1 className="font-serif text-[24px] leading-tight text-tinta">
        Oi, {visto.nome}.
      </h1>

      {/*
        A frase que explica o formulário inteiro, e ela precisa dizer o que
        **não** vem depois. Quem recebe um link antes da primeira sessão espera
        um questionário — é o que os outros mandam. Dizer de saída que são só os
        dados do cadastro evita a pessoa abrir esperando falar de si e travar.
      */}
      <p className="mt-3 text-[14px] leading-relaxed text-tinta2">
        São os dados do seu cadastro: nome, nascimento, contato e como você
        prefere ser avisada.{" "}
        <b className="font-semibold text-tinta">
          Não há nenhuma pergunta sobre você aqui
        </b>{" "}
        — o que for de conversa fica para a sessão.
      </p>

      <div className="mt-7">
        <Ficha
          token={token}
          nome={visto.nome}
          preenchidaEm={visto.preenchida_em}
          hoje={hoje()}
        />
      </div>

      <p className="mt-8 border-t border-linha pt-5 text-[12.5px] text-tinta3">
        <Link href={`/p/agora/${token}`} className="underline underline-offset-4 hover:text-vaga">
          voltar
        </Link>
      </p>
    </main>
  );
}
