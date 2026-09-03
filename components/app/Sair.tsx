"use client";

import { useRouter } from "next/navigation";
import { useState } from "react";
import { supabaseNavegador } from "@/lib/supabase/navegador";
import { limparRascunhos } from "@/lib/rascunho";

export function Sair() {
  const router = useRouter();
  const [saindo, setSaindo] = useState(false);

  async function sair() {
    setSaindo(true);

    // Os rascunhos de evolução saem junto com ela.
    //
    // Eles são texto clínico guardado neste aparelho (`lib/rascunho.ts`), e o
    // aparelho pode ser o da recepção — onde senta a segunda persona do
    // produto, a secretária ou sócia **sem acesso clínico**. Sair da conta e
    // deixar meia evolução no navegador é o caminho por onde ela lê o que não
    // pode ler, sem ninguém ter feito nada errado.
    limparRascunhos(typeof window === "undefined" ? null : window.localStorage);

    await supabaseNavegador().auth.signOut();
    router.replace("/entrar");
    router.refresh();
  }

  return (
    <button
      type="button"
      onClick={sair}
      disabled={saindo}
      className="text-tinta3 transition-colors hover:text-vaga disabled:opacity-50"
    >
      {saindo ? "Saindo…" : "Sair"}
    </button>
  );
}
