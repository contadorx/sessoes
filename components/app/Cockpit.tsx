"use client";

import Link from "next/link";
import type { CockpitLinha, AlertasLinha } from "@/app/(app)/agenda/dados";
import { usarAlerta } from "@/app/(app)/agenda/acoes";
import {
  lerCockpit,
  quatroNumeros,
  perdasComPeso,
  acaoDaPerda,
  fraseDoCockpit,
  fraseDoProtegido,
  fraseDoAlemDoDeclarado,
} from "@/lib/risco";
import { tituloDaCausa, explicaCausa } from "@/lib/livro";
import { formatar } from "@/lib/dinheiro";

/**
 * O cockpit do mês (P5).
 *
 * **Quatro números, nunca um.** O doc 30 é explícito, e a razão não é estética:
 * ocupação é manipulável de cinco jeitos — reduzindo horas declaradas, vendendo
 * abaixo do valor, contando antecipado como atendido, e deixando de reservar
 * tempo de registro. Um número solitário na tela de uma psicóloga empurra contra
 * o descanso dela. Ocupação subindo com receita por hora caindo é sintoma, e só
 * se enxerga com os dois lado a lado.
 *
 * Por isso `quatroNumeros` devolve a lista inteira ou nada, e por isso o tempo
 * protegido aparece embaixo, sempre: sem ele, ocupação se lê como espaço vazio a
 * preencher.
 *
 * **A lista de perdas tem botão, menos em duas linhas.** A falta já cobrada não
 * tem porque não é problema — é a política funcionando. E a hora nunca vendida
 * não tem por decisão ética: o Código de Ética veda induzir alguém a recorrer
 * aos serviços, e um botão de "avisar quem está esperando" ali é isso com outro
 * nome. As duas aparecem como fato, e é assim que ficam.
 *
 * **Não há meta.** Nenhuma barra de progresso rumo a 100%, nenhum alvo, nenhuma
 * cor que melhore com o número subindo.
 *
 * Some inteiro quando não há profissional — e diz o que falta quando não há
 * semana declarada, em vez de mostrar quatro travessões sem explicação.
 */
export function Cockpit({
  bruto,
  alertas,
  mes,
}: {
  bruto: CockpitLinha | null;
  alertas: AlertasLinha | null;
  mes: string;
}) {
  if (!bruto) return null;

  const c = lerCockpit(bruto);
  const numeros = quatroNumeros(c);
  const perdas = perdasComPeso(c);
  const alem = fraseDoAlemDoDeclarado(c);
  const protegido = fraseDoProtegido(c);

  // Quantos alertas apareceram e não levaram a nada. É medida do produto, e
  // aparece discreta: quem precisa dela sou eu, não ela.
  const semUso = alertas?.alertas?.length ?? 0;

  return (
    <section className="rounded-cartao border border-linha bg-folha px-5 py-4">
      <div className="flex flex-wrap items-baseline gap-x-3">
        <h2 className="rotulo">Quanto da sua capacidade virou receita</h2>
        <span className="text-[11.5px] text-tinta3">{mes}</span>
        <Link
          href="/fechamento/livro"
          className="ml-auto text-[11.5px] text-tinta3 underline decoration-linha2 underline-offset-4 hover:text-tinta2"
        >
          o mês inteiro
        </Link>
      </div>

      {/* Os quatro. Nunca um. */}
      <dl className="mt-3 grid grid-cols-2 gap-px overflow-hidden rounded-cartao border border-linha bg-linha lg:grid-cols-4">
        {numeros.map((n) => (
          <div key={n.chave} className="bg-folha2 px-4 py-3">
            <dt className="text-[11.5px] text-tinta3">{n.rotulo}</dt>
            <dd className="mt-0.5 font-mono text-[19px] tabular-nums text-tinta">{n.valor}</dd>
            <p className="mt-1 text-[11px] leading-snug text-tinta3">{n.nota}</p>
          </div>
        ))}
      </dl>

      <p className="mt-3 max-w-[68ch] text-[12.5px] leading-relaxed text-tinta2">
        {fraseDoCockpit(c)}
      </p>

      {alem && (
        <p className="mt-2 max-w-[68ch] text-[12px] leading-relaxed text-aviso">{alem}</p>
      )}

      {protegido && (
        <p className="mt-2 max-w-[68ch] text-[11.5px] leading-relaxed text-tinta3">{protegido}</p>
      )}

      {perdas.length > 0 && (
        <ul className="mt-4 flex flex-col gap-2.5 border-t border-linha pt-3.5">
          {perdas.map((p) => {
            const acao = acaoDaPerda(p.causa);
            return (
              <li key={p.causa} className="flex flex-wrap items-baseline gap-x-3 gap-y-1">
                <span className="text-[13px] text-tinta">{tituloDaCausa(p.causa)}</span>

                <span className="font-mono text-[12.5px] tabular-nums text-vaga">
                  {p.valor !== null && p.valor > 0
                    ? formatar(Math.round(p.valor * 100))
                    : p.minutos
                      ? `${(p.minutos / 60).toFixed(1).replace(".", ",")}h`
                      : ""}
                </span>

                {p.n !== null && p.n > 0 && (
                  <span className="text-[11.5px] text-tinta3">
                    {p.n} {p.n === 1 ? "hora" : "horas"}
                  </span>
                )}

                {/* Duas linhas não têm botão, e as duas de propósito. Ver o
                    comentário do componente. */}
                {acao && (
                  <Link
                    href={acao.href}
                    onClick={() => {
                      void usarAlerta(p.causa);
                    }}
                    className="ml-auto text-[11.5px] text-tinta3 underline decoration-linha2 underline-offset-4 hover:text-vaga"
                  >
                    {acao.rotulo}
                  </Link>
                )}
              </li>
            );
          })}
        </ul>
      )}

      {/* A explicação da linha que não tem botão fica embaixo, uma vez só. */}
      {perdas.some((p) => p.causa === "hora_nunca_vendida") && (
        <p className="mt-3 max-w-[68ch] text-[11px] leading-relaxed text-tinta3">
          {explicaCausa("hora_nunca_vendida")}
        </p>
      )}

      {semUso > 0 && (
        <p className="mt-3 max-w-[68ch] text-[11px] leading-relaxed text-tinta3">
          {semUso === 1
            ? "Um destes avisos vem aparecendo há três meses sem levar a nada — se continuar assim, ele sai da tela."
            : `${semUso} destes avisos vêm aparecendo há três meses sem levar a nada — se continuar assim, eles saem da tela.`}
        </p>
      )}
    </section>
  );
}
