"use client";

import { useActionState, useState } from "react";
import { useFormStatus } from "react-dom";
import {
  salvarPix,
  salvarRitmo,
  salvarAssinatura,
  salvarRegua,
  type Resultado,
} from "@/app/(app)/conta/acoes";
import { tipoDaChave } from "@/lib/pix";

const INICIAL: Resultado = { estado: "inicial" };

const NOME_DA_CHAVE: Record<string, string> = {
  cpf: "CPF",
  cnpj: "CNPJ",
  telefone: "telefone",
  email: "e-mail",
  aleatoria: "chave aleatória",
};

function Salvar({ rotulo = "Salvar" }: { rotulo?: string }) {
  const { pending } = useFormStatus();
  return (
    <button
      type="submit"
      disabled={pending}
      className="rounded-full border border-linha2 px-4 py-2 text-[12.5px] font-medium text-tinta2 transition-colors hover:bg-folha2 disabled:opacity-45"
    >
      {pending ? "…" : rotulo}
    </button>
  );
}

function Recado({ r }: { r: Resultado }) {
  if (r.estado === "ok") {
    return <p className="mt-2 text-[12.5px] text-cheia">{r.mensagem}</p>;
  }
  if (r.estado === "erro") {
    return (
      <ul className="mt-2 space-y-1">
        {r.erros.map((e, i) => (
          <li key={i} className="text-[12.5px] leading-relaxed text-vaga">
            {e}
          </li>
        ))}
      </ul>
    );
  }
  return null;
}

const CAMPO =
  "w-full rounded-cartao border border-linha2 bg-folha px-3 py-2 text-[13px] text-tinta placeholder:text-tinta3 focus:border-tinta3 focus:outline-none";

export function FormPix({
  chave,
  nome,
  cidade,
  podeEditar,
}: {
  chave: string | null;
  nome: string | null;
  cidade: string | null;
  podeEditar: boolean;
}) {
  const [r, despachar] = useActionState(salvarPix, INICIAL);
  const [digitada, setDigitada] = useState(chave ?? "");

  // O reconhecimento acontece enquanto ela digita. É o único jeito de ela
  // descobrir *agora* que colou o CPF com pontos — em vez de descobrir pelo
  // paciente, dizendo que o código não funciona.
  const tipo = digitada.trim() === "" ? null : tipoDaChave(digitada.trim());

  return (
    <form action={despachar} className="rounded-cartao border border-linha bg-folha2 px-5 py-4">
      <fieldset disabled={!podeEditar} className="space-y-3">
        <div>
          <label htmlFor="pix_chave" className="text-[12px] font-medium text-tinta2">
            Chave PIX
          </label>
          <input
            id="pix_chave"
            name="pix_chave"
            value={digitada}
            onChange={(e) => setDigitada(e.target.value)}
            placeholder="CPF só com números, +5511900000001, e-mail ou chave aleatória"
            className={`mt-1 ${CAMPO}`}
            autoComplete="off"
          />
          {digitada.trim() !== "" && (
            <p
              className={`mt-1 text-[11.5px] ${tipo ? "text-cheia" : "text-vaga"}`}
            >
              {tipo
                ? `Reconheci como ${NOME_DA_CHAVE[tipo]}.`
                : "Ainda não reconheci. CPF e CNPJ só com números; telefone com +55 na frente."}
            </p>
          )}
        </div>

        <div className="grid gap-3 sm:grid-cols-2">
          <div>
            <label htmlFor="pix_nome" className="text-[12px] font-medium text-tinta2">
              Nome de quem recebe
            </label>
            <input
              id="pix_nome"
              name="pix_nome"
              defaultValue={nome ?? ""}
              maxLength={25}
              placeholder="como está na conta"
              className={`mt-1 ${CAMPO}`}
            />
          </div>
          <div>
            <label htmlFor="pix_cidade" className="text-[12px] font-medium text-tinta2">
              Cidade
            </label>
            <input
              id="pix_cidade"
              name="pix_cidade"
              defaultValue={cidade ?? ""}
              maxLength={15}
              placeholder="Sao Paulo"
              className={`mt-1 ${CAMPO}`}
            />
          </div>
        </div>

        <p className="text-[11.5px] leading-relaxed text-tinta3">
          Nome e cidade vão no código e aparecem no aplicativo do banco de quem
          paga. O padrão do Banco Central limita a 25 e 15 caracteres, sem
          acento — o que passar disso é cortado.
        </p>

        {podeEditar && <Salvar />}
      </fieldset>

      <Recado r={r} />
    </form>
  );
}

export function FormRitmo({
  atraso,
  lembrete,
  mensalidadeDia,
  cobraSessao,
  podeEditar,
}: {
  atraso: number;
  lembrete: number;
  mensalidadeDia: number;
  cobraSessao: boolean;
  podeEditar: boolean;
}) {
  const [r, despachar] = useActionState(salvarRitmo, INICIAL);

  return (
    <form action={despachar} className="rounded-cartao border border-linha bg-folha2 px-5 py-4">
      <fieldset disabled={!podeEditar} className="space-y-4">
        <div>
          <label
            htmlFor="cobranca_atraso_min"
            className="text-[12.5px] font-medium text-tinta"
          >
            Espera antes do aviso de cobrança
          </label>
          <p className="mt-0.5 text-[12px] leading-relaxed text-tinta2">
            Quem desmarca em cima da hora costuma estar num dia ruim. Esta é
            também a janela em que você pode perdoar antes de qualquer coisa
            sair.
          </p>
          <select
            id="cobranca_atraso_min"
            name="cobranca_atraso_min"
            defaultValue={String(atraso)}
            className="mt-1.5 rounded border border-linha2 bg-folha px-2 py-1 text-[12.5px] text-tinta"
          >
            <option value="0">sai na hora</option>
            <option value="30">30 minutos</option>
            <option value="60">1 hora</option>
            <option value="180">3 horas</option>
            <option value="720">12 horas</option>
            <option value="1440">no dia seguinte</option>
          </select>
        </div>

        <div>
          <label htmlFor="lembrete_horas" className="text-[12.5px] font-medium text-tinta">
            Lembrete antes da sessão
          </label>
          <p className="mt-0.5 text-[12px] leading-relaxed text-tinta2">
            No texto discreto, para quem aceita receber. É a mensagem que mais
            reduz falta.
          </p>
          <select
            id="lembrete_horas"
            name="lembrete_horas"
            defaultValue={String(lembrete)}
            className="mt-1.5 rounded border border-linha2 bg-folha px-2 py-1 text-[12.5px] text-tinta"
          >
            <option value="0">não lembrar</option>
            <option value="3">3 horas antes</option>
            <option value="12">12 horas antes</option>
            <option value="24">24 horas antes</option>
            <option value="48">2 dias antes</option>
          </select>
        </div>

        <div>
          <label htmlFor="mensalidade_dia" className="text-[12.5px] font-medium text-tinta">
            Dia em que a mensalidade é gerada
          </label>
          <p className="mt-0.5 text-[12px] leading-relaxed text-tinta2">
            Vale só para quem você cobra por mensalidade. Vai até 28 porque
            fevereiro existe — um &ldquo;dia 30&rdquo; deixaria fevereiro sem
            cobrança, e em silêncio.
          </p>
          <select
            id="mensalidade_dia"
            name="mensalidade_dia"
            defaultValue={String(mensalidadeDia)}
            className="mt-1.5 rounded border border-linha2 bg-folha px-2 py-1 text-[12.5px] text-tinta"
          >
            {[1, 5, 10, 15, 20, 25, 28].map((d) => (
              <option key={d} value={d}>
                dia {d}
              </option>
            ))}
          </select>
        </div>

        <label className="flex items-start gap-2.5 border-t border-linha pt-4">
          <input
            type="checkbox"
            name="cobra_sessao"
            value="1"
            defaultChecked={cobraSessao}
            className="mt-0.5"
          />
          <span className="text-[12.5px] leading-relaxed text-tinta">
            Cada sessão realizada vira uma cobrança
            <span className="mt-0.5 block text-[12px] text-tinta2">
              Ligue se é o sistema que controla quem já pagou. Se você recebe em
              dinheiro na hora e usa isto como agenda, deixe desligado:{" "}
              <b className="font-medium">ligado, toda sessão fica em aberto até
              você marcar como paga</b> — e os lembretes de pagamento passam a
              alcançar quem não deve nada. Só vale para o modelo por sessão;
              mensalidade e pacote têm cobrança própria.
            </span>
          </span>
        </label>

        {podeEditar && <Salvar rotulo="Salvar ajustes" />}
      </fieldset>

      <Recado r={r} />
    </form>
  );
}

export function FormAssinatura({
  assinaComo,
  crp,
  documento,
  cidade,
  podeEditar,
}: {
  assinaComo: string | null;
  crp: string | null;
  documento: string | null;
  cidade: string | null;
  podeEditar: boolean;
}) {
  const [r, despachar] = useActionState(salvarAssinatura, INICIAL);

  return (
    <form action={despachar} className="rounded-cartao border border-linha bg-folha2 px-5 py-4">
      <fieldset disabled={!podeEditar} className="space-y-3">
        <div>
          <label htmlFor="assina_como" className="text-[12px] font-medium text-tinta2">
            Nome como aparece nos documentos
          </label>
          <input
            id="assina_como"
            name="assina_como"
            defaultValue={assinaComo ?? ""}
            placeholder="Ana Paula Ferreira"
            className={`mt-1 ${CAMPO}`}
          />
        </div>

        <div className="grid gap-3 sm:grid-cols-2">
          <div>
            <label htmlFor="crp" className="text-[12px] font-medium text-tinta2">
              CRP
            </label>
            <input
              id="crp"
              name="crp"
              defaultValue={crp ?? ""}
              placeholder="06/123456"
              className={`mt-1 ${CAMPO}`}
            />
          </div>
          <div>
            <label htmlFor="documento" className="text-[12px] font-medium text-tinta2">
              CPF ou CNPJ
            </label>
            <input
              id="documento"
              name="documento"
              defaultValue={documento ?? ""}
              placeholder="000.000.000-00"
              className={`mt-1 ${CAMPO}`}
            />
          </div>
        </div>

        <div>
          <label htmlFor="cidade" className="text-[12px] font-medium text-tinta2">
            Cidade
          </label>
          <input
            id="cidade"
            name="cidade"
            defaultValue={cidade ?? ""}
            placeholder="São Paulo"
            className={`mt-1 ${CAMPO}`}
          />
          <p className="mt-1 text-[11.5px] leading-relaxed text-tinta3">
            Aparece acima da assinatura, junto com a data — é a fórmula que os
            convênios esperam ver.
          </p>
        </div>

        {podeEditar && <Salvar />}
      </fieldset>

      <Recado r={r} />
    </form>
  );
}

const RITMOS = [
  { valor: "7", rotulo: "um lembrete, uma semana depois" },
  { valor: "7,21", rotulo: "dois: uma semana e três semanas" },
  { valor: "5,15,30", rotulo: "três: cinco dias, quinze e trinta" },
];

export function FormRegua({
  ativa,
  dias,
  podeEditar,
}: {
  ativa: boolean;
  dias: number[];
  podeEditar: boolean;
}) {
  const [r, despachar] = useActionState(salvarRegua, INICIAL);
  const atual = (dias ?? [7, 21]).join(",");

  return (
    <form action={despachar} className="rounded-cartao border border-linha bg-folha2 px-5 py-4">
      <fieldset disabled={!podeEditar} className="space-y-4">
        <label className="flex items-start gap-2.5">
          <input
            type="checkbox"
            name="regua_ativa"
            value="1"
            defaultChecked={ativa}
            className="mt-0.5"
          />
          <span className="text-[12.5px] leading-relaxed text-tinta">
            Lembrar quem ficou com cobrança em aberto
            <span className="mt-0.5 block text-[12px] text-tinta2">
              Desmarcado, nenhum lembrete sai — as cobranças continuam
              registradas e visíveis em Em aberto.
            </span>
          </span>
        </label>

        <div>
          <label htmlFor="regua_dias" className="text-[12.5px] font-medium text-tinta">
            Quantos, e quando
          </label>
          <select
            id="regua_dias"
            name="regua_dias"
            defaultValue={RITMOS.some((x) => x.valor === atual) ? atual : "7,21"}
            className="mt-1.5 w-full rounded border border-linha2 bg-folha px-2 py-1.5 text-[12.5px] text-tinta"
          >
            {RITMOS.map((x) => (
              <option key={x.valor} value={x.valor}>
                {x.rotulo}
              </option>
            ))}
          </select>
          <p className="mt-1.5 text-[11.5px] leading-relaxed text-tinta3">
            Três é o teto, e é do banco, não da tela. Uma régua com sete degraus
            não é lembrete — é perseguição, e o produto existe para tirar o
            constrangimento da relação, não para trocá-lo de lado.
          </p>
        </div>

        {podeEditar && <Salvar rotulo="Salvar" />}
      </fieldset>

      <Recado r={r} />
    </form>
  );
}
