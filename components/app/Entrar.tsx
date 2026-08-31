"use client";

import { useState } from "react";
import { useRouter, useSearchParams } from "next/navigation";
import { supabaseNavegador } from "@/lib/supabase/navegador";

type Modo = "entrar" | "cadastrar";

export function Entrar() {
  const router = useRouter();
  const params = useSearchParams();
  const proxima = params.get("proxima") ?? "/agenda";

  const [modo, setModo] = useState<Modo>("entrar");
  const [enviando, setEnviando] = useState(false);
  const [erro, setErro] = useState<string | null>(null);
  const [aviso, setAviso] = useState<string | null>(null);

  async function enviar(form: FormData) {
    setEnviando(true);
    setErro(null);
    setAviso(null);

    const email = String(form.get("email") ?? "").trim().toLowerCase();
    const senha = String(form.get("senha") ?? "");
    const nome = String(form.get("nome") ?? "").trim();
    const supabase = supabaseNavegador();

    try {
      if (modo === "cadastrar") {
        // O gatilho ao_criar_auth_user cria conta + usuário + profissional.
        // O `nome` viaja nos metadados e vira o nome da conta.
        const { data, error } = await supabase.auth.signUp({
          email,
          password: senha,
          options: { data: { nome } },
        });
        if (error) throw error;

        if (!data.session) {
          setAviso("Confirme o e-mail que acabamos de enviar para entrar.");
          return;
        }
      } else {
        const { error } = await supabase.auth.signInWithPassword({ email, password: senha });
        if (error) throw error;
      }

      router.replace(proxima);
      router.refresh();
    } catch (e) {
      setErro(mensagem(e));
    } finally {
      setEnviando(false);
    }
  }

  return (
    <form action={enviar} className="rounded-cartao border border-linha bg-folha p-6">
      <div className="mb-5 inline-flex gap-1 rounded-full border border-linha bg-folha2 p-1">
        {(["entrar", "cadastrar"] as const).map((m) => (
          <button
            key={m}
            type="button"
            onClick={() => {
              setModo(m);
              setErro(null);
              setAviso(null);
            }}
            aria-pressed={modo === m}
            className={`rounded-full px-3.5 py-1.5 text-[12.5px] font-medium transition-colors ${
              modo === m ? "bg-folha text-tinta shadow-sm" : "text-tinta3 hover:text-tinta2"
            }`}
          >
            {m === "entrar" ? "Entrar" : "Criar conta"}
          </button>
        ))}
      </div>

      {modo === "cadastrar" && (
        <label className="mb-3 block">
          <span className="rotulo">Seu nome</span>
          <input
            name="nome"
            required
            autoComplete="name"
            className="mt-1.5 w-full rounded-[5px] border border-linha2 bg-folha px-3 py-2.5 text-[14px]"
          />
        </label>
      )}

      <label className="mb-3 block">
        <span className="rotulo">E-mail</span>
        <input
          type="email"
          name="email"
          required
          autoComplete="email"
          className="mt-1.5 w-full rounded-[5px] border border-linha2 bg-folha px-3 py-2.5 text-[14px]"
        />
      </label>

      <label className="block">
        <span className="rotulo">Senha</span>
        <input
          type="password"
          name="senha"
          required
          minLength={8}
          autoComplete={modo === "entrar" ? "current-password" : "new-password"}
          className="mt-1.5 w-full rounded-[5px] border border-linha2 bg-folha px-3 py-2.5 text-[14px]"
        />
      </label>

      <button
        type="submit"
        disabled={enviando}
        className="mt-5 w-full rounded-full bg-vaga px-6 py-3 text-[13.5px] font-semibold text-white transition-opacity hover:opacity-90 disabled:opacity-45"
      >
        {enviando ? "Um instante…" : modo === "entrar" ? "Entrar" : "Criar minha conta"}
      </button>

      {erro && <p className="mt-3 text-[12.5px] font-medium text-vaga">{erro}</p>}
      {aviso && <p className="mt-3 text-[12.5px] font-medium text-cheia">{aviso}</p>}
    </form>
  );
}

/** Traduz o que o Supabase devolve para algo que uma pessoa entenda. */
function mensagem(e: unknown): string {
  const bruto = e instanceof Error ? e.message : String(e);

  if (/invalid login credentials/i.test(bruto)) return "E-mail ou senha não conferem.";
  if (/user already registered/i.test(bruto)) return "Esse e-mail já tem conta. Tente entrar.";
  if (/password should be at least/i.test(bruto)) return "A senha precisa de ao menos 8 caracteres.";
  if (/email not confirmed/i.test(bruto)) return "Confirme o e-mail antes de entrar.";

  console.error("[auth] erro não traduzido", e);
  return "Não consegui completar agora. Tente de novo em instantes.";
}
