"use client";

import { useEffect, useState } from "react";
import { useRouter } from "next/navigation";
import { supabaseNavegador } from "@/lib/supabase/navegador";

/**
 * O outro lado do link de confirmação — a metade que o servidor não alcança.
 *
 * O PROBLEMA, EXATAMENTE
 *
 * O Leandro clicou no link de confirmação e não entrou em lugar nenhum. A
 * `/auth/callback` existe desde a B14 e trata `?code=` — o formato do fluxo
 * PKCE. Mas o link que o Supabase manda por padrão vai para o `/auth/v1/verify`
 * dele, que **verifica e redireciona com os tokens no fragmento**:
 *
 *     https://sessoes.com.br/#access_token=...&refresh_token=...&type=signup
 *
 * E fragmento **nunca chega ao servidor**. O navegador não o envia; nem o
 * proxy, nem a rota, nem o componente de servidor têm como vê-lo. Então a
 * pessoa confirmava o e-mail de verdade, era redirecionada de verdade, e caía
 * numa landing anônima — com a sessão inteira pendurada num pedaço de URL que
 * ninguém leu. Do lado dela, o link simplesmente não fez nada.
 *
 * Este componente é o que lê esse pedaço. Ele roda no navegador, pega o
 * fragmento, entrega para o Supabase montar a sessão, **limpa a URL** e leva
 * para dentro.
 *
 * POR QUE ELE MORA NA LANDING E EM /ENTRAR
 *
 * Porque o destino do redirecionamento é o "Site URL" configurado no Supabase, e
 * ele pode ser a raiz. Um componente só numa das duas páginas resolveria metade
 * dos casos — e a metade que falha é silenciosa, que é o pior tipo.
 *
 * O QUE ELE NÃO FAZ
 *
 * Não mostra nada quando não há nada a fazer. Sem fragmento de autenticação na
 * URL, ele devolve `null` e a página é a de sempre. Uma faixa "verificando…"
 * piscando em toda visita à página inicial seria pagar o preço do caso raro em
 * todos os casos.
 *
 * E ele **limpa a URL antes de navegar**. Um `access_token` no endereço fica no
 * histórico do navegador, vaza no `Referer` e é o que a pessoa cola quando
 * manda "olha o link que recebi" para alguém.
 */
export function Confirmar() {
  const router = useRouter();
  const [estado, setEstado] = useState<"nada" | "entrando" | "erro">("nada");
  const [recado, setRecado] = useState("");

  useEffect(() => {
    const bruto = window.location.hash.replace(/^#/, "");
    if (!bruto) return;

    const p = new URLSearchParams(bruto);
    const acesso = p.get("access_token");
    const atualizacao = p.get("refresh_token");
    const erro = p.get("error_description") ?? p.get("error");

    // Nem todo fragmento é autenticação: "#planos" e "#conversa" são âncoras da
    // própria página, e uma delas leva a pessoa exatamente para onde ela pediu.
    if (!acesso && !erro) return;

    // A URL é limpa PRIMEIRO — antes de qualquer espera. Se a rede demorar, o
    // token não fica na barra enquanto isso.
    window.history.replaceState(null, "", window.location.pathname + window.location.search);

    // Tudo o que muda estado acontece **dentro de uma promessa**, e não no
    // corpo do efeito. Não é ginástica para o lint passar: `setState` síncrono
    // aqui renderiza duas vezes antes de o navegador pintar, e a segunda
    // renderização é a que troca a página inteira por uma faixa. A promessa
    // deixa a primeira pintura acontecer.
    const trabalho = erro
      ? Promise.resolve({
          estado: "erro" as const,
          recado: /expired|invalid/i.test(erro)
            ? "Esse link de confirmação já foi usado ou passou da validade. Entre com a sua senha, ou peça outro."
            : "Não consegui completar a confirmação por este link. Tente entrar com a sua senha.",
        })
      : supabaseNavegador()
          .auth.setSession({
            access_token: acesso!,
            refresh_token: atualizacao ?? "",
          })
          .then(({ error }) => {
            if (error) {
              console.error("[auth] fragmento não virou sessão", error);
              return {
                estado: "erro" as const,
                recado:
                  "A confirmação chegou, mas não consegui abrir a sessão. Entre com a sua senha.",
              };
            }
            return { estado: "entrando" as const, recado: "" };
          });

    let vivo = true;
    trabalho.then((r) => {
      if (!vivo) return;
      setEstado(r.estado);
      setRecado(r.recado);
      if (r.estado === "entrando") {
        router.replace("/agenda");
        router.refresh();
      }
    });

    return () => {
      vivo = false;
    };
  }, [router]);

  if (estado === "nada") return null;

  return (
    <div className="fixed inset-x-0 top-0 z-50 border-b border-linha bg-folha px-5 py-3 text-center">
      {estado === "entrando" ? (
        <p className="text-[13px] text-tinta2">
          E-mail confirmado. Abrindo a sua conta…
        </p>
      ) : (
        <p className="text-[13px] text-vaga">
          {recado}{" "}
          <a href="/entrar" className="underline underline-offset-2">
            ir para a tela de entrar
          </a>
        </p>
      )}
    </div>
  );
}
