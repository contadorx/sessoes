"use client";

import { useState, useTransition } from "react";
import { mandeiPeloWhatsapp, naoVouMandar, type Resultado } from "@/app/(app)/agenda/acoes";
import { renderizar } from "@/lib/mensageria/templates";
import {
  linkDoWhatsapp,
  espera,
  rotuloDoQueE,
  fraseDoManual,
  fraseDoQueMudaNoPago,
  type NaMao,
  type ResumoManual,
} from "@/lib/canal";

/**
 * A caixa do que está esperando o dedo dela (OP9).
 *
 * **Ela é uma caixa de tarefa, e não um aviso de limite.** A diferença aparece
 * em cada decisão de tela aqui:
 *
 * 1. **O texto aparece por inteiro, antes de ela clicar.** É a mensagem que a
 *    paciente vai receber, no modo de discrição que aquela paciente escolheu, e
 *    ela precisa poder ler antes de mandar. Um botão que abre o WhatsApp com um
 *    texto que ela não viu é um texto que ela não escreveu.
 *
 * 2. **Abrir o WhatsApp e registrar o envio são dois atos.** O `wa.me` sai do
 *    controle do produto no instante do clique: dali em diante, se a mensagem
 *    saiu, só ela sabe. Registrar no próprio clique afirmaria uma entrega que
 *    ninguém observou.
 *
 * 3. **"Não vou mandar" tem o mesmo peso visual que "mandei".** É a mesma regra
 *    da caixa de decisões do P4: dois botões do mesmo tamanho, porque a escolha
 *    é dela. E não é só simetria estética — sem essa saída, uma oferta que ela
 *    decidiu não fazer seguraria a fila para sempre, já que a expiração passou a
 *    esperar por ela.
 *
 * 4. **Não há contagem regressiva.** O relógio da oferta só começa quando ela
 *    manda; inventar pressa sobre uma decisão dela seria criar a urgência que a
 *    política assistida do P4 recusou criar.
 */
export function CaixaNaSuaMao({
  mensagens,
  resumo,
  envioAutomatico,
}: {
  mensagens: NaMao[];
  resumo: ResumoManual;
  /**
   * Se existe um canal capaz de mandar sozinho **agora**. Vem de cima porque
   * quem sabe é o servidor (`lib/mensageria/adaptadores.ts`), e porque as duas
   * frases desta caixa que falam em automático são falsas quando ele é falso.
   */
  envioAutomatico: boolean;
}) {
  /*
    Quem vê esta caixa.

    Ela nasceu como caixa do plano Gratuito e só aparecia quando o plano era
    manual. A partir da B43 uma mensagem também cai aqui quando **não há canal
    de saída nenhum** — e nesse caso o plano é irrelevante. Manter a condição
    antiga faria as mensagens de um plano pago ficarem paradas sem tela que as
    mostrasse: a fila parada sem sintoma, que é o defeito que esta build
    existe para não criar.
  */
  if (!resumo.manual && mensagens.length === 0) return null;

  // Elas estão aqui apesar de o plano dela mandar sozinho — logo, o que falhou
  // foi o canal, e é isso que a frase tem que dizer.
  const porFaltaDeCanal = !resumo.manual && mensagens.length > 0;

  if (mensagens.length === 0) {
    return (
      <div className="rounded-cartao border border-linha bg-folha px-5 py-4">
        <h2 className="rotulo">Na sua mão</h2>
        <p className="mt-2 max-w-2xl text-[13px] leading-relaxed text-tinta2">
          {fraseDoManual(resumo)}
        </p>
      </div>
    );
  }

  return (
    <div className="rounded-cartao border border-linha bg-folha px-5 py-4">
      <div className="flex flex-wrap items-baseline justify-between gap-2">
        <h2 className="rotulo">Na sua mão</h2>
        {!porFaltaDeCanal && (
          <span className="text-[11.5px] text-tinta3">{fraseDoManual(resumo)}</span>
        )}
      </div>

      {porFaltaDeCanal && (
        <p className="mt-2 max-w-2xl text-[12.5px] leading-relaxed text-tinta2">
          O envio automático está indisponível, então estas não saíram. Elas
          esperam aqui até você mandar pelo seu WhatsApp — e a vaga espera junto.
        </p>
      )}

      <ul className="mt-3 space-y-3">
        {mensagens.map((m) => (
          <Item key={m.id} m={m} />
        ))}
      </ul>

      {/*
        As duas frases que falavam em "saem sozinhos" só aparecem quando isso é
        verdade. Enquanto não há provedor, nada sai sozinho em plano nenhum, e
        prometer o contrário aqui — ainda por cima como argumento de upgrade —
        é a mesma afirmação sem lastro que a build veio consertar.
      */}
      {envioAutomatico && (
        <p className="mt-3 max-w-2xl text-[11.5px] leading-relaxed text-tinta3">
          Lembrete de véspera, aviso de desmarque e confirmação de encaixe{" "}
          <b className="font-medium text-tinta2">saem sozinhos</b>, no seu plano
          também — quem receberia é o seu paciente. {fraseDoQueMudaNoPago()}
        </p>
      )}
    </div>
  );
}

function Item({ m }: { m: NaMao }) {
  const [feito, setFeito] = useState<null | "mandei" | "nao">(null);
  const [erro, setErro] = useState<string | null>(null);
  const [pendente, iniciar] = useTransition();

  // O texto é montado aqui, com o mesmo renderizador que o worker usa. Duas
  // fontes de texto para a mesma mensagem seriam duas mensagens diferentes
  // saindo pelo mesmo produto.
  let texto = "";
  try {
    texto = renderizar(m.template, m.params as never).texto;
  } catch {
    texto = "";
  }

  // Sem texto renderizado não há link: quem recusa é o `linkDoWhatsapp`, para
  // que a próxima tela que montar um wa.me não repita o defeito.
  const link = linkDoWhatsapp(m.destino, texto);

  /*
    O erro fica **no item**, não num aviso global.

    Ela está com o polegar em cima deste item. Um toast no alto da tela é uma
    mensagem que ela não lê e um item que continua parecendo intocado — então
    ela toca de novo, e a paciente recebe duas vezes.
  */
  const agir = (acao: () => Promise<Resultado>, marca: "mandei" | "nao") =>
    iniciar(async () => {
      setErro(null);
      const r = await acao();
      if (r.estado === "erro") {
        setErro(r.erros.join(" "));
        return;
      }
      setFeito(marca);
    });

  if (feito) {
    return (
      <li className="rounded-cartao border border-linha bg-folha2 px-4 py-2.5 text-[12.5px] text-tinta3">
        {m.paciente} — {feito === "mandei" ? "marcada como enviada" : "tirada da lista"}
      </li>
    );
  }

  return (
    <li className="rounded-cartao border border-linha2 px-4 py-3">
      <div className="flex flex-wrap items-baseline justify-between gap-2">
        <span className="text-[13px] font-medium text-tinta">
          {rotuloDoQueE(m.template)} — {m.paciente}
        </span>
        <span className="font-mono text-[11px] text-tinta3">{espera(m.espera_desde)}</span>
      </div>

      {texto === "" ? (
        <p className="mt-2 text-[12.5px] leading-relaxed text-vaga">
          Não consegui montar o texto desta mensagem. Ela fica aqui até dar para
          mandar — nada foi enviado.
        </p>
      ) : (
        <p className="mt-2 whitespace-pre-wrap rounded-cartao bg-folha2 px-3 py-2 text-[12.5px] leading-relaxed text-tinta2">
          {texto}
        </p>
      )}

      <div className="mt-3 flex flex-wrap items-center gap-2">
        {link && (
          <a
            href={link}
            target="_blank"
            rel="noopener noreferrer"
            className="rounded-full border border-linha2 px-4 py-2 text-[12.5px] font-medium text-tinta transition-colors hover:bg-folha2"
          >
            Abrir no WhatsApp
          </a>
        )}
        <button
          type="button"
          disabled={pendente}
          onClick={() => agir(() => mandeiPeloWhatsapp(m.id), "mandei")}
          className="rounded-full border border-linha2 px-4 py-2 text-[12.5px] font-medium text-tinta2 transition-colors hover:bg-folha2 disabled:opacity-45"
        >
          Já mandei
        </button>
        <button
          type="button"
          disabled={pendente}
          onClick={() => agir(() => naoVouMandar(m.id), "nao")}
          className="rounded-full border border-linha2 px-4 py-2 text-[12.5px] font-medium text-tinta2 transition-colors hover:bg-folha2 disabled:opacity-45"
        >
          Não vou mandar
        </button>
      </div>

      {erro && (
        <p role="alert" className="mt-2 text-[12px] font-medium leading-relaxed text-vaga">
          {erro}
        </p>
      )}

      {m.oferta_id && (
        <p className="mt-2 text-[11.5px] leading-relaxed text-tinta3">
          O prazo de resposta desta vaga só começa quando você marcar que mandou —
          até lá ela não passa para a próxima pessoa.
        </p>
      )}
    </li>
  );
}
