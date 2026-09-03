"use client";

import { useEffect } from "react";
import { expirarRascunhos } from "@/lib/rascunho";

/**
 * A faxina dos rascunhos vencidos, ao entrar na área logada.
 *
 * Não desenha nada. Existe porque a promessa de validade do `lib/rascunho.ts`
 * não estava sendo cumprida: a expiração só era avaliada quando ela **reabria a
 * mesma sessão**, e o rascunho abandonado — o caso que a promessa descreve — é
 * justamente o que nunca é reaberto.
 *
 * Aqui, e não no botão Sair: quem fecha a aba não passa pelo Sair, e a sessão
 * que expira sozinha também não. Entrar é o momento que **sempre** acontece.
 */
export function Rascunhos() {
  useEffect(() => {
    expirarRascunhos(typeof window === "undefined" ? null : window.localStorage);
  }, []);

  return null;
}
