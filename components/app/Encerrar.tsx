"use client";

import { useActionState, useEffect, useRef } from "react";
import { useFormStatus } from "react-dom";
import { useRouter } from "next/navigation";
import { supabaseNavegador } from "@/lib/supabase/navegador";
import { Sair } from "@/components/app/Sair";
import { encerrarConta, type Resultado } from "@/app/(app)/perfil/encerrar/acoes";
import type { Exportacao } from "@/app/(app)/perfil/encerrar/dados";

const INICIAL: Resultado = { estado: "inicial" };

const DIA_E_HORA = new Intl.DateTimeFormat("pt-BR", {
  timeZone: "America/Sao_Paulo",
  day: "2-digit",
  month: "2-digit",
  year: "numeric",
  hour: "2-digit",
  minute: "2-digit",
});

/**
 * O botão que encerra.
 *
 * **Não é vermelho de alarme e não está escondido.** Vermelho é a cor de um
 * erro, e isto não é um erro: é uma decisão legítima de quem quer a casa dela
 * de volta. Esconder seria pior ainda — um produto que guarda prontuário e
 * dificulta a saída não está retendo, está sequestrando, e é justamente saber
 * que dá para sair que torna razoável entrar.
 *
 * O que faz o peso da decisão aparecer não é a cor: é o texto do botão dizer o
 * que vai acontecer, e o campo acima exigir o nome digitado.
 */
function Encerrar({ podeTentar }: { podeTentar: boolean }) {
  const { pending } = useFormStatus();
  return (
    <button
      type="submit"
      disabled={pending || !podeTentar}
      className="rounded-full border border-linha2 px-5 py-2 text-[12.5px] font-medium text-tinta2 transition-colors hover:bg-folha2 disabled:opacity-45"
    >
      {pending ? "Encerrando…" : "Apagar tudo e encerrar a conta"}
    </button>
  );
}

export function EncerrarConta({
  nomeDaConta,
  exportacao,
  ehDona,
}: {
  nomeDaConta: string;
  exportacao: Exportacao;
  ehDona: boolean;
}) {
  const [r, despachar] = useActionState(encerrarConta, INICIAL);
  const router = useRouter();
  // Ref, e não estado: o logout acontece uma vez só e nada na tela depende de
  // ele ter acontecido — a frase já está renderizada. Um `useState` aqui seria
  // um render a mais para guardar um fato que ninguém desenha.
  const jaSaiu = useRef(false);

  const recente = exportacao.estado === "ok" && exportacao.recente;

  /**
   * A sessão termina junto — e só depois de a frase estar na tela.
   *
   * A função apagou a linha de `auth.users`: continuar logada seria continuar
   * com um crachá de uma casa que não existe mais. O logout é o mesmo de
   * `Sair`, e a saída para `/entrar` também é ele, renderizado abaixo — assim a
   * frase sobre a guarda de cinco anos fica legível, em vez de ser substituída
   * por um redirecionamento que ninguém leu.
   */
  useEffect(() => {
    if (r.estado !== "ok" || jaSaiu.current) return;
    jaSaiu.current = true;
    void supabaseNavegador().auth.signOut();
  }, [r]);

  if (r.estado === "ok") {
    return (
      <section className="rounded-cartao border border-linha bg-folha px-5 py-5">
        <p className="max-w-[62ch] text-[13.5px] leading-relaxed text-tinta">{r.mensagem}</p>
        <p className="mt-3 max-w-[62ch] text-[12.5px] leading-relaxed text-tinta2">
          A sua sessão foi encerrada. Não há mais nada aqui para abrir.
        </p>
        <div className="mt-4 text-[13px]">
          <Sair />
        </div>
      </section>
    );
  }

  return (
    <div className="space-y-4">
      {/* ------------------------------------------------ a exportação, no caminho

          O botão de exportar mora **dentro** do fluxo de encerrar, antes do
          campo de confirmação, e não numa outra seção do perfil. Mandar a
          pessoa "exportar antes" e deixá-la procurar onde é transforma a única
          proteção real desta tela num passo opcional. */}
      <section className="rounded-cartao border border-linha bg-folha2 px-5 py-4">
        <h2 className="rotulo">Antes: leve a sua cópia</h2>

        <p className="mt-2 max-w-[62ch] text-[13px] leading-relaxed text-tinta2">
          A guarda de cinco anos continua sendo sua depois que a conta acabar — é
          obrigação sua, não nossa —, e{" "}
          <b className="font-semibold text-tinta">
            o arquivo exportado é a única cópia que sobrevive
          </b>
          . É ele que responde se o Conselho pedir o prontuário daqui a quatro
          anos.
        </p>

        <div className="mt-3 flex flex-wrap items-center gap-3">
          <a
            href="/perfil/exportar"
            className="inline-block rounded-full border border-linha2 bg-folha px-4 py-2 text-[12.5px] font-medium text-tinta transition-colors hover:bg-folha2"
          >
            Exportar a conta agora
          </a>
          <button
            type="button"
            onClick={() => router.refresh()}
            className="text-[12.5px] text-tinta3 underline underline-offset-2 hover:text-vaga"
          >
            já exportei, conferir
          </button>
        </div>

        <p className="mt-3 text-[12.5px] leading-relaxed text-tinta2">
          {exportacao.estado === "indisponivel" ? (
            exportacao.motivo
          ) : exportacao.quando === null ? (
            "Nenhuma exportação registrada nesta conta."
          ) : (
            <>
              Última exportação:{" "}
              <b className="font-medium text-tinta">
                {DIA_E_HORA.format(new Date(exportacao.quando))}
              </b>
              .{" "}
              {recente
                ? "Vale para encerrar hoje."
                : "É antiga demais para valer: ela não tem o que aconteceu desde então, e o que você levaria seria um arquivo com cara de completo e um buraco no fim."}
            </>
          )}
        </p>
      </section>

      {/* ---------------------------------------------------------- a confirmação */}
      <form action={despachar} className="rounded-cartao border border-linha bg-folha2 px-5 py-4">
        <h2 className="rotulo">Depois: encerrar</h2>

        {/* O estado do papel é **mostrado**, não checado aqui: quem recusa é o
            banco, e a tela que repetisse a regra seria um segundo lugar onde
            ela mora. */}
        {!ehDona && (
          <p className="mt-2 max-w-[62ch] text-[12.5px] leading-relaxed text-tinta2">
            Você não entra nesta conta como responsável por ela. Encerrar a casa
            é da responsável — o banco recusa qualquer outra pessoa.
          </p>
        )}

        <fieldset disabled={!recente} className="mt-2">
          <label htmlFor="confirmacao" className="block text-[12.5px] font-medium text-tinta">
            Para confirmar, digite o nome da conta: {nomeDaConta}
          </label>
          <p className="mt-0.5 max-w-[62ch] text-[12px] leading-relaxed text-tinta2">
            Não é um &ldquo;tem certeza?&rdquo;. É a única operação do produto que
            não se desfaz, e um clique acidental não pode alcançá-la.
          </p>

          <input
            id="confirmacao"
            name="confirmacao"
            autoComplete="off"
            placeholder={nomeDaConta}
            className="mt-2 w-full max-w-md rounded-cartao border border-linha2 bg-folha px-3 py-2 text-[13px] text-tinta placeholder:text-tinta3 focus:border-tinta3 focus:outline-none disabled:opacity-45"
          />

          {/* A lista do que some estava incompleta, e conferi no banco antes de
              mexer: `eliminar_conta` não apaga por lista escrita — ela varre o
              `information_schema` atrás de toda tabela de `public` com
              `conta_id` (lei 7). Entre elas estão `assinaturas`, `faturas`,
              `avisos_assinatura` e `eventos_pagamento`, que a frase não citava.
              Quem lê "pacientes, sessões, cobranças" e encerra fica achando que
              a assinatura continua de pé em algum lugar — e o histórico de
              faturas é o que ela levaria para o contador dela. */}
          <p className="mt-3 max-w-[62ch] text-[12.5px] leading-relaxed text-tinta2">
            Ao encerrar, tudo o que é desta conta é apagado do banco em produção:
            pacientes, sessões, combinados, cobranças, documentos, mensagens, a
            trilha de acesso e também a sua assinatura e o histórico de faturas.
            O seu login some junto. As cópias de segurança expiram em até 7 dias.
          </p>

          <div className="mt-3">
            <Encerrar podeTentar={recente} />
          </div>
        </fieldset>

        {/* A trava das 24h se explicava **só** quando a leitura da exportação
            dava certo. No estado `indisponivel` sobrava um campo cinza, sem
            nada escrito ao lado: ela via um formulário desabilitado e nenhuma
            razão. É o pior lugar do produto para deixar alguém adivinhando, e
            a diferença entre "você não exportou" e "eu não consegui perguntar"
            é justamente a que essa tela existe para não apagar. */}
        {!recente && (
          <p className="mt-3 max-w-[62ch] text-[12.5px] leading-relaxed text-tinta3">
            O campo acima abre depois de uma exportação das últimas 24 horas. O
            prazo é curto de propósito: é o que faz a cópia ser a cópia do que
            existia.
            {exportacao.estado === "indisponivel" && (
              <>
                {" "}
                Agora ele está fechado porque não consegui verificar a sua última
                exportação — não porque ela não exista. Tente de novo em alguns
                minutos, ou exporte outra vez.
              </>
            )}
          </p>
        )}

        {r.estado === "erro" && (
          <p className="mt-3 max-w-[62ch] text-[12.5px] leading-relaxed text-vaga">
            {r.erros[0]}
          </p>
        )}
      </form>
    </div>
  );
}
