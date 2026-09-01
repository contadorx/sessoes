import Link from "next/link";
import { notFound } from "next/navigation";
import {
  obterPaciente,
  enquadreAberto,
  lastroDoPaciente,
  pacotesDoPaciente,
  filaDeEntradaDoPaciente,
  linhaDoTempoDoPaciente,
  registroDoPaciente,
  retencaoDaConta,
  anamneseDoPaciente,
} from "../dados";
import { atualizarPaciente } from "../acoes";
import { FormPaciente } from "@/components/app/FormPaciente";
import { NovoEnquadre } from "@/components/app/NovoEnquadre";
import { rotuloHorario, rotuloPolitica } from "@/lib/enquadre";
import { Privacidade } from "@/components/app/Privacidade";
import { Lastro } from "@/components/app/Lastro";
import { Pacote } from "@/components/app/Pacote";
import { FilaEntrada } from "@/components/app/FilaEntrada";
import { rotuloModelo } from "@/lib/cobranca";
import { hoje } from "@/lib/tempo-servidor";
import { LinhaDoTempo } from "@/components/app/LinhaDoTempo";
import { PainelRegistro } from "@/components/app/Registro";
import { PainelAnamnese } from "@/components/app/Anamnese";
import { sessaoAtual, acessosDa } from "@/lib/conta";
import { abasDoPaciente } from "@/lib/navegacao";

const brl = (v: string) =>
  Number(v).toLocaleString("pt-BR", { style: "currency", currency: "BRL" });

const MOTIVO: Record<string, string> = {
  reajuste: "reajuste",
  mudanca_horario: "mudança de horário",
  encerramento: "encerramento",
};

export default async function Paciente({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  // A auditoria pediu "cadastro, dados administrativos e área clínica conforme
  // permissão", e é aqui que os dois eixos aparecem na mesma tela. A RLS já
  // devolveria vazio para quem não pode (migração 0049) — o que muda aqui é
  // não **oferecer** a seção: uma caixa de evolução em branco para quem não
  // pode escrever nela é uma promessa que a próxima tela quebra.
  const acessos = acessosDa(await sessaoAtual());
  const abas = abasDoPaciente(acessos);
  const veClinico = abas.includes("clinico");
  const paciente = await obterPaciente(id);
  if (!paciente) notFound();

  const aberto = enquadreAberto(paciente);
  const historico = paciente.enquadres.filter((e) => e.vigencia_fim !== null);
  const lastro = await lastroDoPaciente(paciente.id, aberto?.id ?? null);
  const pacotes = aberto?.modelo_cobranca === "pacote" ? await pacotesDoPaciente(paciente.id) : [];
  const entrada = aberto ? { naFila: false, desde: null } : await filaDeEntradaDoPaciente(paciente.id);
  const tempo = await linhaDoTempoDoPaciente(paciente.id);
  const [registro, retencao, anamnese] = await Promise.all([
    registroDoPaciente(paciente.id),
    retencaoDaConta(),
    anamneseDoPaciente(paciente.id),
  ]);

  return (
    <div className="mx-auto max-w-3xl">
      <Link href="/pacientes" className="text-[12.5px] text-tinta3 hover:text-vaga">
        ← pacientes
      </Link>

      <h1 className="mt-2 font-serif text-[28px] leading-tight tracking-[-0.015em]">
        {paciente.nome}
      </h1>

      {/* o combinado vigente */}
      <section className="mt-6">
        <h2 className="rotulo">O combinado</h2>
        {aberto ? (
          <div className="mt-2 rounded-cartao border border-cheia-linha bg-cheia-bg px-5 py-4">
            <p className="font-mono text-[16px] text-cheia">
              {rotuloHorario(aberto.dia_semana, aberto.hora)} · {aberto.duracao_min} min ·{" "}
              {brl(aberto.valor)}
              {aberto.social && " · social"}
            </p>
            <p className="mt-1 text-[13px] text-tinta2">
              {rotuloPolitica({
                horas: aberto.politica_horas,
                percentual: aberto.politica_percentual,
              })}
              {aberto.modelo_cobranca !== "avulso" &&
                ` · ${rotuloModelo(aberto.modelo_cobranca)}`}
              {aberto.modelo_cobranca === "mensal" &&
                (aberto.mensalidade_valor
                  ? ` de ${brl(aberto.mensalidade_valor)} fixos`
                  : " por sessão do mês")}
            </p>
            {aberto.modelo_cobranca !== "avulso" && aberto.falta_cobra_a_parte && (
              <p className="mt-1 text-[12px] text-aviso">
                A falta é cobrada à parte, além do que já foi pago.
              </p>
            )}
            <p className="mt-2 font-mono text-[11.5px] text-tinta3">
              vigente desde {aberto.vigencia_inicio}
            </p>
          </div>
        ) : (
          <p className="mt-2 rounded-cartao border border-dashed border-vaga-linha bg-vaga-bg px-5 py-4 text-[13.5px] text-vaga">
            Sem combinado aberto. Sem ele não há sessão, cobrança nem fila.
          </p>
        )}

        <NovoEnquadre pacienteId={paciente.id} aberto={aberto} />
      </section>

      {/* Sem combinado aberto: é aqui que a fila de entrada faz sentido. */}
      {!aberto && !paciente.arquivado_em && (
        <section className="mt-8">
          <h2 className="rotulo">Esperando um horário fixo</h2>
          <p className="mt-2 max-w-xl text-[13px] leading-relaxed text-tinta2">
            Esta é a outra fila: não a de encaixe — que é de quem já tem horário
            e topa uma hora extra —, mas a de quem ainda não tem nenhum e está
            esperando um vagar.
          </p>
          <div className="mt-3">
            <FilaEntrada
              pacienteId={paciente.id}
              naFila={entrada.naFila}
              desde={entrada.desde}
            />
          </div>
        </section>
      )}

      {aberto?.modelo_cobranca === "pacote" && (
        <section className="mt-8">
          <h2 className="rotulo">O pacote</h2>
          <p className="mt-2 max-w-xl text-[13px] leading-relaxed text-tinta2">
            Cada encontro consome um crédito — e a falta também, porque a hora
            foi reservada e perdida. Quando os créditos acabam ou o prazo vence,
            as sessões voltam a ser cobradas uma a uma.
          </p>
          <div className="mt-3">
            <Pacote
              pacienteId={paciente.id}
              pacotes={pacotes}
              hoje={hoje()}
              valorDaSessao={aberto?.valor ?? null}
            />
          </div>
        </section>
      )}

      {/* o lastro: o combinado por escrito, aceito com data */}
      <section className="mt-8">
        <h2 className="rotulo">O combinado por escrito</h2>
        <p className="mt-2 max-w-xl text-[13px] leading-relaxed text-tinta2">
          É o que dá lastro à cobrança automática: quando o sistema cobra uma
          falta, ele aplica uma regra que a pessoa leu e aceitou — com data e
          hora, no texto que estava na tela naquele instante.
        </p>
        <div className="mt-3">
          <Lastro
            pacienteId={paciente.id}
            pacienteNome={paciente.nome}
            telefone={paciente.telefone}
            enquadreId={aberto?.id ?? null}
            temContrato={lastro.temContrato}
            aceite={lastro.aceite}
          />
        </div>
      </section>

      {/* ------------------------------------------------------ o registro (PR2/PR6) */}
      {veClinico && registro && (
        <section className="mt-10 border-t border-linha pt-6">
          <h2 className="font-serif text-[21px] leading-tight">O registro</h2>
          <p className="mt-2 max-w-xl text-[13.5px] leading-relaxed text-tinta2">
            O Prontuário Psicológico desta pessoa, nos quatro blocos que a Res. CFP 001/2009 e o
            Manual de nov/2025 pedem. O que estiver vazio aparece vazio — o Manual pede que se
            evitem espaços em branco, e um buraco anunciado é melhor que um silencioso.
          </p>

          <PainelRegistro
            pacienteId={paciente.id}
            registro={registro}
            ultimoRegistro={hoje()}
            retencaoAnos={retencao}
          />

          <p className="mt-5 max-w-xl text-[11.5px] leading-relaxed text-tinta3">
            O que estiver na <b className="font-medium">gaveta</b> não sai na cópia que o
            paciente pode pedir: é o Registro Documental, de acesso restrito a você. Tudo o
            mais sai — o direito de acesso ao próprio prontuário é dele. Nada aqui se apaga
            dentro do prazo de guarda, nem por engano.
          </p>
        </section>
      )}

      {/* ------------------------------------------------------- a anamnese (PR3/PR5) */}
      {veClinico && (
      <section className="mt-10 border-t border-linha pt-6">
        <h2 className="font-serif text-[21px] leading-tight">A anamnese</h2>
        <p className="mt-2 max-w-xl text-[13.5px] leading-relaxed text-tinta2">
          A avaliação da demanda em profundidade — o bloco 2 do registro, escrito com tempo.
          Enquanto está aberta, edita-se à vontade; depois de fechada, o que chegar entra como
          adendo, com a data em que chegou.
        </p>

        <PainelAnamnese
          pacienteId={paciente.id}
          anamnese={anamnese.anamnese}
          aviso={anamnese.aviso}
        />
      </section>
      )}

      {!veClinico && (
        <section className="mt-10 border-t border-linha pt-6">
          <p className="max-w-xl text-[13px] leading-relaxed text-tinta3">
            O registro clínico desta pessoa não aparece no seu acesso. Não é
            omissão da tela: acesso clínico é uma decisão separada do cargo, e
            quem concede é a responsável pela conta.
          </p>
        </section>
      )}

      {/* ------------------------------------------------- a linha do tempo (PR8) */}
      <section className="mt-10 border-t border-linha pt-6">
        <h2 className="font-serif text-[21px] leading-tight">A linha do tempo</h2>
        <p className="mt-2 max-w-xl text-[13.5px] leading-relaxed text-tinta2">
          As horas desta pessoa, na ordem em que aconteceram — ou não
          aconteceram. Faltar não é só um lançamento financeiro: é o que se leva
          para a próxima sessão.
        </p>

        <LinhaDoTempo linhas={tempo.linhas} ausencias={tempo.ausencias} hoje={hoje()} />

        <p className="mt-5 max-w-xl text-[11.5px] leading-relaxed text-tinta3">
          O sistema conta; quem lê é você. Aqui não há escore, alerta nem
          rótulo — só o que aconteceu e quando. E a nota existe na hora que{" "}
          <b className="font-medium">não</b> houve: a evolução da sessão
          atendida é prontuário, que entra depois, com as resoluções do CFP
          conferidas.
        </p>
      </section>

      {historico.length > 0 && (
        <section className="mt-8">
          <h2 className="rotulo">Histórico do combinado</h2>
          <ul className="mt-2 overflow-hidden rounded-cartao border border-linha bg-folha">
            {historico.map((e) => (
              <li
                key={e.id}
                className="flex flex-wrap items-baseline gap-x-3 gap-y-1 border-t border-linha px-5 py-3 first:border-t-0"
              >
                <span className="font-mono text-[13px] text-tinta2">
                  {rotuloHorario(e.dia_semana, e.hora)} · {brl(e.valor)}
                </span>
                <span className="font-mono text-[11.5px] text-tinta3">
                  {e.vigencia_inicio} → {e.vigencia_fim}
                </span>
                {e.motivo_fim && (
                  <span className="ml-auto text-[11.5px] text-tinta3">
                    {MOTIVO[e.motivo_fim] ?? e.motivo_fim}
                  </span>
                )}
              </li>
            ))}
          </ul>
          <p className="mt-2 text-[11.5px] leading-relaxed text-tinta3">
            Valor de sessão nunca é editado no lugar: reajustar fecha o combinado
            atual e abre outro. É o que mantém de pé o que foi acertado, e quando.
          </p>
        </section>
      )}

      <section className="mt-8">
        <h2 className="rotulo">Cadastro</h2>
        {paciente.arquivado_em ? (
          <div className="mt-2 rounded-cartao border border-linha bg-folha2 px-5 py-4">
            <p className="text-[12.5px] leading-relaxed text-tinta2">
              Ficha arquivada — só leitura. Encerramento registrado:
            </p>
            <p className="mt-2 whitespace-pre-wrap text-[13px] leading-relaxed text-tinta">
              {paciente.encerramento}
            </p>
          </div>
        ) : (
          <div className="mt-2">
            <FormPaciente
              acao={atualizarPaciente}
              paciente={paciente}
              rotuloBotao="Salvar cadastro"
            />
          </div>
        )}
      </section>

      <Privacidade
        pacienteId={paciente.id}
        nome={paciente.nome}
        arquivado={Boolean(paciente.arquivado_em)}
        contatoEsquecidoEm={paciente.contato_esquecido_em}
        restricaoJudicial={paciente.restricao_judicial}
      />
    </div>
  );
}
