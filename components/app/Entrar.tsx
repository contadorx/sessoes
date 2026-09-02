"use client";

import { useState } from "react";
import { useRouter, useSearchParams } from "next/navigation";
import { supabaseNavegador } from "@/lib/supabase/navegador";

type Modo = "entrar" | "cadastrar";

export function Entrar() {
  const router = useRouter();
  const params = useSearchParams();
  const proxima = params.get("proxima") ?? "/agenda";

  /**
   * Qual aba abre primeiro.
   *
   * `?criar` abre em "Criar conta", e é para onde o "Começar de graça" da
   * landing aponta. Sem isso, a promessa da hero ("a conta se cria agora")
   * caía numa tela de login com a aba errada selecionada — e um formulário de
   * senha em branco, para quem nunca teve conta, se lê como "você precisa de
   * algo que não tem".
   *
   * O parâmetro é lido uma vez, no estado inicial: se a pessoa trocar de aba
   * na mão, a URL não a arrasta de volta.
   */
  const [modo, setModo] = useState<Modo>(
    params.get("criar") !== null ? "cadastrar" : "entrar",
  );
  const [enviando, setEnviando] = useState(false);
  const [erro, setErro] = useState<string | null>(null);
  const [aviso, setAviso] = useState<string | null>(null);

  /**
   * A confirmação por e-mail deixou de ser um recado e virou **a tela**.
   *
   * O Leandro criou uma conta e não ficou claro que era preciso confirmar. E
   * não era falta de aviso: a frase existia, em 12,5px, embaixo de um botão que
   * continuava dizendo "Criar minha conta", num formulário que continuava
   * cheio. Tudo na tela dizia "nada aconteceu ainda" e uma linha de texto
   * dizia o contrário.
   *
   * Agora o formulário some. O que fica é o endereço para onde o e-mail foi,
   * o que fazer, e o que fazer quando ele não chega — que é a pergunta
   * seguinte, e que nenhuma tela costuma responder.
   */
  const [confirmar, setConfirmar] = useState<string | null>(null);
  const [reenviando, setReenviando] = useState(false);
  const [reenviado, setReenviado] = useState(false);

  async function reenviar() {
    if (!confirmar) return;
    setReenviando(true);
    try {
      const supabase = supabaseNavegador();
      // Erro aqui não vira alarme: o Supabase recusa reenvio repetido dentro de
      // um intervalo curto, e "aguarde 60 segundos" seria a resposta mais
      // provável de um segundo clique ansioso. O que importa é a pessoa saber
      // que o pedido saiu.
      await supabase.auth.resend({ type: "signup", email: confirmar });
    } catch (e) {
      console.error("[auth] reenvio", e);
    } finally {
      setReenviando(false);
      setReenviado(true);
    }
  }

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
        //
        // E o `plano_desejado` viaja junto quando a pessoa clicou no card do
        // Solo ou do Pro. Ele **não** liga plano nenhum — o gatilho ignora a
        // chave, a conta nasce no Grátis e quem abre assinatura é uma pessoa
        // (OP5). Ele existe para a escolha não se perder no clique: sem isso,
        // os dois botões pagos da landing eram indistinguíveis do gratuito, e
        // a única informação que eu tinha sobre demanda de plano era nenhuma.
        const plano = params.get("plano");
        const desejado = plano === "solo" || plano === "pro" ? plano : undefined;

        const { data, error } = await supabase.auth.signUp({
          email,
          password: senha,
          options: { data: desejado ? { nome, plano_desejado: desejado } : { nome } },
        });
        if (error) throw error;

        // Sem sessão = o projeto exige confirmação por e-mail. É o caminho
        // normal, e não um caso de borda: é o que acontece com toda conta nova.
        if (!data.session) {
          setConfirmar(email);
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

  if (confirmar) {
    return (
      <div className="rounded-cartao border border-cheia-linha bg-cheia-bg p-6 text-center">
        <p className="font-serif text-[22px] leading-snug text-cheia">
          Falta um passo: confirme o seu e-mail.
        </p>

        <p className="mt-3 text-[13.5px] leading-relaxed text-tinta2">
          Mandamos uma mensagem para{" "}
          <b className="font-medium text-tinta">{confirmar}</b>. Abra e clique no
          link que está lá — é o que abre a sua conta.
        </p>

        <p className="mt-4 text-[12.5px] leading-relaxed text-tinta2">
          Sem esse clique não dá para entrar, e não é burocracia: é o que impede
          alguém de criar uma conta com o seu endereço.
        </p>

        <div className="mt-5 border-t border-cheia-linha pt-4 text-left">
          <p className="text-[12px] font-medium text-tinta2">Não chegou?</p>
          <ul className="mt-1.5 flex flex-col gap-1 text-[12px] leading-relaxed text-tinta2">
            <li>· Pode levar um ou dois minutos.</li>
            <li>· Veja em spam, promoções e lixeira.</li>
            <li>· Confira se o endereço acima está certo.</li>
          </ul>

          <div className="mt-3 flex flex-wrap items-center gap-3">
            <button
              type="button"
              onClick={reenviar}
              disabled={reenviando || reenviado}
              className="rounded-full border border-linha2 bg-folha px-3.5 py-1.5 text-[12.5px] font-medium text-tinta2 transition-opacity hover:bg-folha2 disabled:opacity-45"
            >
              {reenviando ? "Enviando…" : reenviado ? "Enviado de novo" : "Enviar de novo"}
            </button>
            <button
              type="button"
              onClick={() => {
                setConfirmar(null);
                setReenviado(false);
                setModo("cadastrar");
              }}
              className="text-[12px] text-tinta3 underline decoration-linha2 underline-offset-4 hover:text-vaga"
            >
              usar outro e-mail
            </button>
          </div>

          {reenviado && (
            <p className="mt-2 text-[11.5px] leading-relaxed text-tinta3">
              Se ainda não chegar em alguns minutos, escreva para
              oi@sessoes.com.br e a gente resolve por lá.
            </p>
          )}
        </div>

        <p className="mt-5 text-[12px] text-tinta3">
          Já confirmou?{" "}
          <button
            type="button"
            onClick={() => {
              setConfirmar(null);
              setModo("entrar");
            }}
            className="underline decoration-linha2 underline-offset-4 hover:text-vaga"
          >
            entrar agora
          </button>
        </p>
      </div>
    );
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

      {/* O aviso vem ANTES do clique, e não só depois.
          Saber que existe um e-mail de confirmação enquanto se digita a senha é
          diferente de descobrir isso na tela seguinte: a pessoa já sai daqui
          sabendo que precisa abrir a caixa de entrada. */}
      {modo === "cadastrar" && (
        <>
          <p className="mt-3 text-center text-[12px] leading-relaxed text-tinta3">
            Vamos enviar um e-mail de confirmação. O clique nele é o que abre a
            conta.
          </p>
          {/* O aceite fica no botão, e os documentos a um clique dali. Não é
              caixinha de marcar: uma caixinha que todo mundo marca sem ler é
              consentimento de fachada — e o que faz diferença aqui é o link
              estar onde a decisão acontece. */}
          <p className="mt-1.5 text-center text-[11px] leading-relaxed text-tinta3">
            Ao criar a conta você aceita os{" "}
            <a href="/termos" className="underline underline-offset-2 hover:text-vaga">
              termos
            </a>
            ,{" "}
            <a href="/privacidade" className="underline underline-offset-2 hover:text-vaga">
              a privacidade
            </a>{" "}
            e{" "}
            <a href="/seguranca" className="underline underline-offset-2 hover:text-vaga">
              a segurança
            </a>
            .
          </p>
        </>
      )}

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
