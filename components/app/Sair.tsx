"use client";

import { useRouter } from "next/navigation";
import { useState } from "react";
import { supabaseNavegador } from "@/lib/supabase/navegador";

export function Sair() {
  const router = useRouter();
  const [saindo, setSaindo] = useState(false);

  async function sair() {
    setSaindo(true);
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
