import Link from "next/link";
import { db } from "@/lib/db";
import { supabaseSessao } from "@/lib/supabase/server";
import { sessaoAtual, acessosDa } from "@/lib/conta";
import { buscavel, fraseDoVazio, ondeBuscar, ROTULO_ACHADO } from "@/lib/navegacao";
import { podeFinanceiro } from "@/lib/permissao";
import { formatar, paraCentavos } from "@/lib/dinheiro";

export const metadata = { title: "Buscar" };

/**
 * A busca global.
 *
 * Não existia, e a auditoria pôs isso na lista de ausências que atingem a tela
 * aberta todos os dias: *"no celular, procurar paciente navegando por abas é
 * particularmente caro"*. O custo real é entre uma sessão e outra, com dez
 * minutos, abrindo o paciente errado.
 *
 * Duas decisões que valem mais que a implementação:
 *
 *   1. **Ela procura onde a pessoa pode ver, e diz onde procurou.** Buscar num
 *      lugar que a RLS vai esvaziar produz "nenhum resultado" — que se lê como
 *      "não existe", e não como "não é para você". A segunda resposta é pior:
 *      a pessoa procura de novo e conclui que o produto perdeu o documento.
 *
 *   2. **Ela não procura dentro de evolução, anamnese ou registro clínico.**
 *      Uma busca que varre o prontuário devolve trecho de sessão numa lista —
 *      e uma lista dessas aparece na tela do consultório com outra pessoa na
 *      sala. Nome, data e valor bastam para achar; o conteúdo se lê depois de
 *      abrir a ficha, que é onde a trilha de acesso registra quem abriu.
 */

type PacienteAchado = { id: string; nome: string; telefone: string | null; estado: string };
type SessaoAchada = {
  id: string;
  inicio: string;
  estado: string;
  valor: number;
  pacientes: { id: string; nome: string } | { id: string; nome: string }[] | null;
};
type DocumentoAchado = {
  id: string;
  numero: number;
  tipo: string;
  emitido_em: string;
  valor_total: number;
  pacientes: { nome: string } | { nome: string }[] | null;
};
type PagamentoAchado = {
  id: string;
  valor: number;
  estado: string;
  paga_em: string | null;
  competencia: string;
  pacientes: { id: string; nome: string } | { id: string; nome: string }[] | null;
};

function um<T>(x: T | T[] | null): T | null {
  if (!x) return null;
  return Array.isArray(x) ? (x[0] ?? null) : x;
}

function diaBr(iso: string): string {
  const d = iso.slice(0, 10).split("-");
  return d.length === 3 ? `${d[2]}/${d[1]}/${d[0]}` : iso;
}

/** Escapa o que o PostgREST leria como curinga ou separador de filtro. */
function seguro(termo: string): string {
  return termo.replace(/[%,()\\]/g, " ").trim();
}

export default async function Buscar({
  searchParams,
}: {
  searchParams: Promise<{ q?: string }>;
}) {
  const { q } = await searchParams;
  const termo = (q ?? "").trim();

  const sessao = await sessaoAtual();
  const acessos = acessosDa(sessao);
  const onde = ondeBuscar(acessos);

  if (!buscavel(termo)) {
    return (
      <div className="mx-auto max-w-2xl">
        <h1 className="font-serif text-[26px] leading-tight tracking-[-0.015em]">Buscar</h1>
        <p className="mt-3 text-[13.5px] leading-relaxed text-tinta2">{fraseDoVazio(termo, acessos)}</p>
        <p className="mt-2 text-[12.5px] leading-relaxed text-tinta3">
          Procura em {onde.map((t) => ROTULO_ACHADO[t]).join(", ")}. Não procura
          dentro de evolução, anamnese ou registro clínico — o conteúdo da
          sessão se lê abrindo a ficha, não numa lista.
        </p>
      </div>
    );
  }

  const supabase = await supabaseSessao();
  const alvo = `%${seguro(termo)}%`;
  const dinheiro = podeFinanceiro(acessos);

  const [pacientes, sessoes, documentos, pagamentos] = await Promise.all([
    db(
      "buscar.pacientes",
      supabase
        .from("pacientes")
        .select("id, nome, telefone, estado")
        .ilike("nome", alvo)
        .order("nome")
        .limit(8),
    ) as Promise<unknown>,
    db(
      "buscar.sessoes",
      supabase
        .from("sessoes")
        .select("id, inicio, estado, valor, pacientes ( id, nome )")
        .order("inicio", { ascending: false })
        .limit(200),
    ) as Promise<unknown>,
    dinheiro
      ? (db(
          "buscar.documentos",
          supabase
            .from("documentos")
            .select("id, numero, tipo, emitido_em, valor_total, pacientes ( nome )")
            .order("emitido_em", { ascending: false })
            .limit(200),
        ) as Promise<unknown>)
      : Promise.resolve([]),
    dinheiro
      ? (db(
          "buscar.pagamentos",
          supabase
            .from("cobrancas")
            .select("id, valor, estado, paga_em, competencia, pacientes ( id, nome )")
            .order("competencia", { ascending: false })
            .limit(200),
        ) as Promise<unknown>)
      : Promise.resolve([]),
  ]);

  const alvoBaixo = termo.toLowerCase();
  const casa = (nome: string | undefined) => (nome ?? "").toLowerCase().includes(alvoBaixo);

  const ps = (pacientes ?? []) as PacienteAchado[];
  const ss = ((sessoes ?? []) as SessaoAchada[])
    .filter((s) => casa(um(s.pacientes)?.nome))
    .slice(0, 8);
  const ds = ((documentos ?? []) as DocumentoAchado[])
    .filter((d) => casa(um(d.pacientes)?.nome) || String(d.numero) === termo)
    .slice(0, 8);
  const gs = ((pagamentos ?? []) as PagamentoAchado[])
    .filter((c) => casa(um(c.pacientes)?.nome))
    .slice(0, 8);

  const nada = ps.length + ss.length + ds.length + gs.length === 0;

  return (
    <div className="mx-auto max-w-2xl">
      <h1 className="font-serif text-[26px] leading-tight tracking-[-0.015em]">
        “{termo}”
      </h1>

      {nada && (
        <p className="mt-4 text-[13.5px] leading-relaxed text-tinta2">{fraseDoVazio(termo, acessos)}</p>
      )}

      {ps.length > 0 && (
        <section className="mt-8">
          <h2 className="rotulo">Pacientes</h2>
          <ul className="mt-3 grid gap-px overflow-hidden rounded-cartao border border-linha bg-linha">
            {ps.map((p) => (
              <li key={p.id} className="bg-folha">
                <Link href={`/pacientes/${p.id}`} className="block px-4 py-3 text-[13.5px] hover:text-vaga">
                  {p.nome}
                  <span className="ml-2 text-[12px] text-tinta3">{p.estado.replace(/_/g, " ")}</span>
                </Link>
              </li>
            ))}
          </ul>
        </section>
      )}

      {ss.length > 0 && (
        <section className="mt-8">
          <h2 className="rotulo">Sessões</h2>
          <ul className="mt-3 grid gap-px overflow-hidden rounded-cartao border border-linha bg-linha">
            {ss.map((s) => (
              <li key={s.id} className="bg-folha">
                {/*
                  Toda sessão ia para `/encaixes/{id}`, e aquela página recusa
                  sessão que não seja vaga aberta — quatro dos seis estados
                  batiam na recusa. Buscar o nome de alguém, achar a sessão de
                  terça e receber "esta sessão não é uma vaga" é o resultado da
                  busca funcionando e a busca parecendo quebrada.
                */}
                <Link
                  href={`/agenda?sessao=${s.id}`}
                  className="block px-4 py-3 text-[13.5px] hover:text-vaga"
                >
                  {diaBr(s.inicio)} · {um(s.pacientes)?.nome}
                  <span className="ml-2 text-[12px] text-tinta3">{s.estado.replace(/_/g, " ")}</span>
                </Link>
              </li>
            ))}
          </ul>
        </section>
      )}

      {ds.length > 0 && (
        <section className="mt-8">
          <h2 className="rotulo">Documentos</h2>
          <ul className="mt-3 grid gap-px overflow-hidden rounded-cartao border border-linha bg-linha">
            {ds.map((d) => (
              <li key={d.id} className="bg-folha">
                <Link
                  href={`/fechamento/documentos/${d.id}`}
                  className="block px-4 py-3 text-[13.5px] hover:text-vaga"
                >
                  nº {d.numero} · {d.tipo.replace(/_/g, " ")} · {um(d.pacientes)?.nome}
                  <span className="ml-2 text-[12px] text-tinta3">{diaBr(d.emitido_em)}</span>
                </Link>
              </li>
            ))}
          </ul>
        </section>
      )}

      {gs.length > 0 && (
        <section className="mt-8">
          <h2 className="rotulo">Pagamentos</h2>
          <ul className="mt-3 grid gap-px overflow-hidden rounded-cartao border border-linha bg-linha">
            {gs.map((c) => (
              <li key={c.id} className="bg-folha">
                <Link
                  href={c.estado === "paga" ? "/recebimentos/movimentacoes" : "/recebimentos"}
                  className="block px-4 py-3 text-[13.5px] hover:text-vaga"
                >
                  {um(c.pacientes)?.nome} · {formatar(paraCentavos(c.valor))}
                  <span className="ml-2 text-[12px] text-tinta3">
                    {c.estado}
                    {c.paga_em ? ` em ${diaBr(c.paga_em)}` : ""}
                  </span>
                </Link>
              </li>
            ))}
          </ul>
        </section>
      )}

      <p className="mt-10 text-[12px] leading-relaxed text-tinta3">
        A busca procura por nome e por número de documento, em{" "}
        {onde.map((t) => ROTULO_ACHADO[t]).join(", ")}. Ela não entra em
        evolução, anamnese nem registro clínico: o conteúdo da sessão se lê
        abrindo a ficha — que é onde fica registrado quem abriu.
      </p>
    </div>
  );
}
