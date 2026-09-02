import { notFound } from "next/navigation";
import {
  obterPaciente,
  enquadreAberto,
  lastroDoPaciente,
  pacotesDoPaciente,
  filaDeEntradaDoPaciente,
  linkDoPaciente,
} from "../dados";
import { NovoEnquadre } from "@/components/app/NovoEnquadre";
import { rotuloHorario, rotuloPolitica } from "@/lib/enquadre";
import { Lastro } from "@/components/app/Lastro";
import { LinkDoPaciente } from "@/components/app/LinkDoPaciente";
import { Pacote } from "@/components/app/Pacote";
import { FilaEntrada } from "@/components/app/FilaEntrada";
import { rotuloModelo } from "@/lib/cobranca";
import { hoje } from "@/lib/tempo-servidor";

const brl = (v: string) =>
  Number(v).toLocaleString("pt-BR", { style: "currency", currency: "BRL" });

const MOTIVO: Record<string, string> = {
  reajuste: "reajuste",
  mudanca_horario: "mudança de horário",
  encerramento: "encerramento",
};

/**
 * O combinado — a primeira aba, e a que abre por padrão.
 *
 * Abre esta, e não o cadastro, porque a pergunta de quem abre uma ficha no meio
 * da semana é "que horas é, quanto é, o que foi acertado". O cadastro se
 * preenche uma vez e se relê quase nunca.
 *
 * O que mora aqui é tudo o que gira em torno do acordo: o enquadre vigente, a
 * fila de entrada de quem ainda não tem horário, o pacote quando existe, o
 * contrato aceito, e o histórico dos combinados anteriores — que é o que faz
 * um reajuste não apagar março.
 */
export default async function Combinado({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  const paciente = await obterPaciente(id);
  if (!paciente) notFound();

  const aberto = enquadreAberto(paciente);
  const historico = paciente.enquadres.filter((e) => e.vigencia_fim !== null);
  const lastro = await lastroDoPaciente(paciente.id, aberto?.id ?? null);
  const pacotes = aberto?.modelo_cobranca === "pacote" ? await pacotesDoPaciente(paciente.id) : [];
  const entrada = aberto ? { naFila: false, desde: null } : await filaDeEntradaDoPaciente(paciente.id);
  const link = await linkDoPaciente(paciente.id);

  return (
    <>
      <section>
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

      {/* ------------------------------------------------- a página do paciente

          Fica **depois do contrato e antes do histórico**, e a posição é
          argumento: as duas seções acima são o que foi combinado; esta é o que
          está aberto agora. Pôr o link no topo faria a ficha começar por uma
          ferramenta de envio, e quem abre uma ficha no meio da semana quer
          primeiro saber que horas é e quanto é. */}
      <section className="mt-8">
        <h2 className="rotulo">A página dele</h2>
        <p className="mt-2 max-w-xl text-[13px] leading-relaxed text-tinta2">
          Um link só, que mostra o que estiver esperando por ele: horário para
          confirmar, pagamento em aberto e documentos dos últimos três meses.
          Não mostra prontuário, não mostra histórico e não deixa cancelar
          sessão — cancelar continua sendo conversa com você.
        </p>
        <div className="mt-3">
          <LinkDoPaciente
            pacienteId={paciente.id}
            pacienteNome={paciente.nome}
            telefone={paciente.telefone}
            link={link}
          />
        </div>
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
    </>
  );
}
