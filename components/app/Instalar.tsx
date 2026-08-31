"use client";

import { useEffect } from "react";

/**
 * Registra o service worker.
 *
 * Fica dentro do layout logado, e não na landing, de propósito: quem só visitou
 * o site não precisa de um worker instalado no navegador dela. Instalar algo
 * persistente no aparelho de quem ainda não é cliente é uma liberdade que não
 * temos.
 *
 * Falha em silêncio por escolha. Navegador antigo, aba privada, permissão
 * negada — nada disso pode aparecer como erro na tela de quem só queria ver a
 * agenda. O que se perde quando falha é o ícone na tela inicial; o app inteiro
 * continua funcionando pelo navegador.
 */
export function Instalar() {
  useEffect(() => {
    if (typeof navigator === "undefined" || !("serviceWorker" in navigator)) return;

    // Depois do load: registrar durante a renderização disputa banda com o que
    // a pessoa está esperando ver.
    const registrar = () => {
      navigator.serviceWorker.register("/sw.js", { scope: "/" }).catch(() => {
        /* sem service worker o app funciona igual — só não instala */
      });
    };

    if (document.readyState === "complete") registrar();
    else window.addEventListener("load", registrar, { once: true });

    return () => window.removeEventListener("load", registrar);
  }, []);

  return null;
}
