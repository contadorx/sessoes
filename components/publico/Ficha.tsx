"use client";

import { useActionState, useState } from "react";
import { useFormStatus } from "react-dom";
import { salvarFicha, type ResultadoFicha } from "@/app/p/agora/[token]/ficha/acoes";
import { ehMenor } from "@/lib/ficha";
import { mascaraCpf, mascaraTelefone } from "@/lib/formato";

const INICIAL: ResultadoFicha = { estado: "inicial" };

const ENTRADA =
  "mt-1.5 w-full rounded-[5px] border border-linha2 bg-folha px-3 py-2.5 text-[14px] text-tinta";

function Campo({
  rotulo,
  nome,
  erro,
  dica,
  children,
}: {
  rotulo: string;
  nome: string;
  erro?: string;
  dica?: string;
  children: React.ReactNode;
}) {
  return (
    <div className="mt-4">
      <label htmlFor={nome} className="rotulo">
        {rotulo}
      </label>
      {children}
      {dica && <p className="mt-1 text-[11.5px] leading-relaxed text-tinta3">{dica}</p>}
      {erro && (
        <p role="alert" className="mt-1 text-[12.5px] leading-relaxed text-vaga">
          {erro}
        </p>
      )}
    </div>
  );
}

function Enviar() {
  const { pending } = useFormStatus();
  return (
    <button
      type="submit"
      disabled={pending}
      className="mt-6 min-h-11 w-full rounded-full bg-vaga px-6 py-3 text-[14px] font-semibold text-white transition-opacity hover:opacity-90 disabled:opacity-45"
    >
      {pending ? "Enviando…" : "Enviar"}
    </button>
  );
}

/**
 * A pré-ficha administrativa (PR4), do lado de quem preenche.
 *
 * **Todos os campos desta tela são administrativos, e não é acaso.** A lista
 * fechada mora em `lib/ficha.ts`, a varredura de
 * `testes/nenhuma-pergunta-clinica.test.ts` confere esta tela contra o
 * vocabulário clínico, e `salvar_ficha` recusa no banco qualquer chave que não
 * esteja na lista. Três travas, e a do banco é a que sobrevive a uma tela nova.
 *
 * Não há "o que te traz aqui", nem escala, nem triagem, nem consentimento
 * clínico. Anamnese é da sala.
 *
 * **O formulário nasce vazio, inclusive para quem já preencheu.** Devolver o
 * que está guardado pouparia trinta segundos de digitação e transformaria o
 * token num leitor de CPF — quem achasse o link no histórico de um celular
 * emprestado veria os dados em vez de um formulário em branco.
 *
 * O campo do responsável aparece **quando a data de nascimento diz que
 * aparece**, e some quando ela muda. Perguntar por responsável a um adulto é
 * ruído; não perguntar a um menor é o registro nascendo incompleto.
 */
export function Ficha({
  token,
  nome,
  preenchidaEm,
  hoje,
}: {
  token: string;
  nome: string;
  preenchidaEm: string | null;
  hoje: string;
}) {
  const [estado, despachar] = useActionState(salvarFicha, INICIAL);
  const [nascimento, setNascimento] = useState("");

  const porCampo = (estado.estado === "erro" && estado.porCampo) || {};
  const erros = estado.estado === "erro" ? estado.erros : [];
  const menor = /^\d{4}-\d{2}-\d{2}$/.test(nascimento) && ehMenor(nascimento, hoje);

  if (estado.estado === "ok") {
    return (
      <div className="rounded-cartao border border-cheia-linha bg-cheia-bg px-5 py-6">
        <p className="font-serif text-[19px] text-tinta">Recebido, {nome}.</p>
        <p className="mt-2 text-[13.5px] leading-relaxed text-tinta2">
          Os seus dados foram guardados. Se algo mudar, é só abrir este link de
          novo e enviar outra vez.
        </p>
      </div>
    );
  }

  return (
    <form action={despachar}>
      <input type="hidden" name="token" value={token} />

      {preenchidaEm && (
        <p className="mb-5 rounded-cartao border border-linha bg-folha2 px-4 py-3 text-[13px] leading-relaxed text-tinta2">
          Você já enviou os seus dados em{" "}
          {new Date(preenchidaEm).toLocaleDateString("pt-BR", {
            timeZone: "America/Sao_Paulo",
          })}
          . Se algo mudou, preencha de novo — o que ficar em branco continua como
          está.
        </p>
      )}

      <Campo rotulo="Nome completo" nome="nome" erro={porCampo.nome}>
        <input id="nome" name="nome" autoComplete="name" required className={ENTRADA} />
      </Campo>

      <Campo rotulo="Data de nascimento" nome="nascimento" erro={porCampo.nascimento}>
        <input
          id="nascimento"
          name="nascimento"
          type="date"
          required
          value={nascimento}
          onChange={(e) => setNascimento(e.target.value)}
          className={ENTRADA}
        />
      </Campo>

      <Campo
        rotulo="CPF"
        nome="cpf"
        erro={porCampo.cpf}
        dica="Usado no recibo, para você poder lançar no seu Imposto de Renda. Pode deixar em branco e mandar depois."
      >
        <input
          id="cpf"
          name="cpf"
          inputMode="numeric"
          autoComplete="off"
          onChange={(e) => {
            e.currentTarget.value = mascaraCpf(e.currentTarget.value);
          }}
          className={ENTRADA}
        />
      </Campo>

      <Campo rotulo="Telefone" nome="telefone" erro={porCampo.telefone}>
        <input
          id="telefone"
          name="telefone"
          inputMode="tel"
          autoComplete="tel"
          onChange={(e) => {
            e.currentTarget.value = mascaraTelefone(e.currentTarget.value);
          }}
          className={ENTRADA}
        />
      </Campo>

      <Campo rotulo="E-mail" nome="email" erro={porCampo.email}>
        <input id="email" name="email" type="email" autoComplete="email" className={ENTRADA} />
      </Campo>

      <Campo rotulo="Como prefere ser avisada" nome="msg_canal" erro={porCampo.msg_canal}>
        <select id="msg_canal" name="msg_canal" defaultValue="whatsapp" className={ENTRADA}>
          {/* Sem SMS: ele é medida de crise da cascata, e não escolha de
              menu — ver `CANAIS_OFERECIDOS`. Oferecer aqui seria pedir à
              paciente que escolhesse o canal mais caro do produto sem ter como
              saber disso. */}
          <option value="whatsapp">WhatsApp</option>
          <option value="email">E-mail</option>
          <option value="nao_avisar">Prefiro não receber aviso</option>
        </select>
      </Campo>

      {/* A escolha do modo discreto, e ela é da pessoa — não da conta.
          Quem divide o celular escolhe a mensagem que não diz do que se trata. */}
      <Campo
        rotulo="O que a mensagem pode dizer"
        nome="msg_modo"
        erro={porCampo.msg_modo}
        dica="No modo discreto, a mensagem fala só de um horário — sem citar consultório nem quem atende."
      >
        <select id="msg_modo" name="msg_modo" defaultValue="discreto" className={ENTRADA}>
          <option value="discreto">Só o horário (discreto)</option>
          <option value="completo">Pode citar quem atende</option>
        </select>
      </Campo>

      {menor && (
        <fieldset className="mt-6 rounded-cartao border border-linha bg-folha2 px-4 py-3">
          <legend className="rotulo px-1">Responsável</legend>
          <p className="text-[12.5px] leading-relaxed text-tinta2">
            Pela data de nascimento, quem vai ser atendido tem menos de 18 anos.
            Precisamos de quem responde legalmente.
          </p>

          <Campo rotulo="Nome do responsável" nome="responsavel_nome" erro={porCampo.responsavel_nome}>
            <input id="responsavel_nome" name="responsavel_nome" className={ENTRADA} />
          </Campo>

          <Campo
            rotulo="CPF do responsável"
            nome="responsavel_documento"
            erro={porCampo.responsavel_documento}
          >
            <input
              id="responsavel_documento"
              name="responsavel_documento"
              inputMode="numeric"
              onChange={(e) => {
                e.currentTarget.value = mascaraCpf(e.currentTarget.value);
              }}
              className={ENTRADA}
            />
          </Campo>

          <Campo
            rotulo="Telefone do responsável"
            nome="responsavel_telefone"
            erro={porCampo.responsavel_telefone}
          >
            <input
              id="responsavel_telefone"
              name="responsavel_telefone"
              inputMode="tel"
              onChange={(e) => {
                e.currentTarget.value = mascaraTelefone(e.currentTarget.value);
              }}
              className={ENTRADA}
            />
          </Campo>
        </fieldset>
      )}

      {erros.length > 0 && (
        <ul role="alert" className="mt-5 space-y-1">
          {erros.map((e, i) => (
            <li key={i} className="text-[13px] leading-relaxed text-vaga">
              {e}
            </li>
          ))}
        </ul>
      )}

      <Enviar />
    </form>
  );
}
