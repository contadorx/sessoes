"use server";

import { revalidatePath } from "next/cache";
import { problemaNasHoras } from "@/lib/confirmacao";
import { redirect } from "next/navigation";
import { db, ErroDeBanco } from "@/lib/db";
import { supabaseSessao } from "@/lib/supabase/server";
import { sessaoAtual } from "@/lib/conta";
import { validarPaciente } from "@/lib/paciente";
import { hoje } from "@/lib/tempo-servidor";
import { adaptadorPara } from "@/lib/pagamentos/adaptadores";
import { deCentavos, paraCentavos } from "@/lib/dinheiro";
import { caixaMarcada, lerCentavos } from "@/lib/formato";

export type Resultado =
  | { estado: "inicial" }
  // `porCampo` é a mesma lista, endereçada: o formulário mostra a frase
  // embaixo do campo que a causou, e não só no bloco do fim.
  | { estado: "erro"; erros: string[]; porCampo?: Record<string, string> }
  // Salvar cadastro redireciona, então não precisava de "ok". As ações de
  // privacidade (B13) precisam: a resposta do banco — a data até quando o
  // registro fica guardado — é justamente o que a psicóloga vai repassar.
  | { estado: "ok"; mensagem: string };

const INICIAL: Resultado = { estado: "inicial" };

/** Lê os campos do enquadre do formulário. Devolve null quando ela não preencheu. */
function lerEnquadre(form: FormData): {
  erros: string[];
  porCampo: Record<string, string>;
  dados: Record<string, unknown> | null;
} {
  const hora = String(form.get("hora") ?? "").trim();
  const valorBruto = String(form.get("valor") ?? "").trim();

  if (hora === "" && valorBruto === "") return { erros: [], porCampo: {}, dados: null };

  const erros: string[] = [];
  const porCampo: Record<string, string> = {};
  const problema = (campo: string, frase: string) => {
    erros.push(frase);
    if (!porCampo[campo]) porCampo[campo] = frase;
  };

  if (!/^\d{2}:\d{2}$/.test(hora)) problema("hora", "Informe o horário da sessão.");

  const valorCentavos = lerCentavos(valorBruto);
  if (valorCentavos === null) problema("valor", "Informe o valor da sessão.");

  const dia = Number(form.get("dia_semana"));
  if (!Number.isInteger(dia) || dia < 0 || dia > 6) problema("dia_semana", "Escolha o dia da semana.");

  const duracao = Number(form.get("duracao_min") ?? 50);
  if (!Number.isInteger(duracao) || duracao < 15 || duracao > 240) {
    problema("duracao_min", "A duração precisa ficar entre 15 e 240 minutos.");
  }

  // O valor fixo do mês é opcional por desenho: em branco significa "cobro por
  // sessão do mês", e é essa ausência que responde ao mês de cinco terças.
  const mensalBruto = String(form.get("mensalidade_valor") ?? "").trim();
  let mensalidade: string | null = null;
  if (mensalBruto !== "") {
    const m = lerCentavos(mensalBruto);
    if (m === null) {
      problema("mensalidade_valor", "O valor fixo do mês não parece um número.");
    } else {
      mensalidade = deCentavos(m);
    }
  }

  const horas = Number(form.get("politica_horas") ?? 24);
  const pct = Number(form.get("politica_percentual") ?? 50);
  if (!Number.isInteger(horas) || horas < 0 || horas > 168) {
    problema("politica_horas", "Prazo da política inválido.");
  }
  if (!Number.isInteger(pct) || pct < 0 || pct > 100) {
    problema("politica_percentual", "Percentual da política inválido.");
  }

  // A confirmação da 0057. Vazio é **não pedir**, e é o padrão — quem não pede
  // confirmação hoje não passa a pedir porque o formulário ganhou um campo.
  const confBruto = String(form.get("confirmacao_horas_antes") ?? "").trim();
  const confirmacao = confBruto === "" ? null : Number(confBruto);
  const problemaConf = problemaNasHoras(confirmacao);
  if (problemaConf) problema("confirmacao_horas_antes", problemaConf);

  if (erros.length > 0) return { erros, porCampo, dados: null };

  return {
    erros: [],
    porCampo,
    dados: {
      dia_semana: dia,
      hora,
      duracao_min: duracao,
      valor: deCentavos(valorCentavos ?? 0), // numeric vai como string; nunca float no caminho
      social: caixaMarcada(form, "social"),
      modelo_cobranca: String(form.get("modelo_cobranca") ?? "avulso"),
      // Só faz sentido no mensal: guardar um valor fixo num combinado avulso
      // criaria um número que a tela mostra e o sistema nunca usa.
      mensalidade_valor:
        String(form.get("modelo_cobranca") ?? "avulso") === "mensal" ? mensalidade : null,
      falta_cobra_a_parte: caixaMarcada(form, "falta_cobra_a_parte"),
      politica_horas: horas,
      politica_percentual: pct,
      confirmacao_horas_antes: confirmacao,
    },
  };
}

export async function criarPaciente(_anterior: Resultado, form: FormData): Promise<Resultado> {
  const sessao = await sessaoAtual();
  if (!sessao.profissionalId) {
    return { estado: "erro", erros: ["Sua conta está sem profissional cadastrado."] };
  }

  const paciente = validarPaciente({
    nome: String(form.get("nome") ?? ""),
    telefone: String(form.get("telefone") ?? ""),
    email: String(form.get("email") ?? ""),
    cpf: String(form.get("cpf") ?? ""),
    estado: String(form.get("estado") ?? "interessado"),
    msg_canal: String(form.get("msg_canal") ?? "whatsapp"),
    msg_modo: String(form.get("msg_modo") ?? "discreto"),
    observacao: String(form.get("observacao") ?? ""),
  });

  const enquadre = lerEnquadre(form);

  if (!paciente.ok || enquadre.erros.length > 0) {
    return {
      estado: "erro",
      erros: [...(paciente.ok ? [] : paciente.erros), ...enquadre.erros],
      porCampo: { ...(paciente.ok ? {} : paciente.porCampo), ...enquadre.porCampo },
    };
  }

  const supabase = await supabaseSessao();
  let id: string;

  try {
    const criado = await db(
      "pacientes.criar",
      supabase
        .from("pacientes")
        .insert({ ...paciente.dados, profissional_id: sessao.profissionalId })
        .select("id")
        .limit(1),
    );

    id = (criado ?? [])[0]?.id as string;
    if (!id) return { estado: "erro", erros: ["Não consegui criar o cadastro."] };

    if (enquadre.dados) {
      await db(
        "enquadres.criar",
        supabase.from("enquadres").insert({ ...enquadre.dados, paciente_id: id }),
      );
    }
  } catch (e) {
    return { estado: "erro", erros: [traduzir(e)] };
  }

  revalidatePath("/pacientes");
  redirect(`/pacientes/${id}`);
}

export async function atualizarPaciente(_anterior: Resultado, form: FormData): Promise<Resultado> {
  const id = String(form.get("id") ?? "");
  if (!id) return { estado: "erro", erros: ["Cadastro não identificado."] };

  const paciente = validarPaciente({
    nome: String(form.get("nome") ?? ""),
    telefone: String(form.get("telefone") ?? ""),
    email: String(form.get("email") ?? ""),
    cpf: String(form.get("cpf") ?? ""),
    estado: String(form.get("estado") ?? "interessado"),
    msg_canal: String(form.get("msg_canal") ?? "whatsapp"),
    msg_modo: String(form.get("msg_modo") ?? "discreto"),
    observacao: String(form.get("observacao") ?? ""),
  });

  if (!paciente.ok) {
    return { estado: "erro", erros: paciente.erros, porCampo: paciente.porCampo };
  }

  const supabase = await supabaseSessao();

  try {
    await db(
      "pacientes.atualizar",
      supabase.from("pacientes").update(paciente.dados).eq("id", id),
    );
  } catch (e) {
    return { estado: "erro", erros: [traduzir(e)] };
  }

  revalidatePath(`/pacientes/${id}`);
  revalidatePath("/pacientes");
  return INICIAL;
}

/**
 * O mecanismo que a D14 vai usar: **nunca** se edita o valor de um enquadre
 * vigente. Fecha-se o atual com um motivo e abre-se o próximo. O histórico do
 * que foi combinado, e quando, fica de pé — e o índice parcial do banco garante
 * que só existe um aberto por vez.
 */
export async function substituirEnquadre(
  _anterior: Resultado,
  form: FormData,
): Promise<Resultado> {
  const pacienteId = String(form.get("paciente_id") ?? "");
  const abertoId = String(form.get("enquadre_aberto_id") ?? "");
  const motivo = String(form.get("motivo_fim") ?? "reajuste");

  if (!pacienteId) return { estado: "erro", erros: ["Paciente não identificado."] };

  const enquadre = lerEnquadre(form);
  if (enquadre.erros.length > 0) {
    return { estado: "erro", erros: enquadre.erros, porCampo: enquadre.porCampo };
  }
  if (!enquadre.dados) return { estado: "erro", erros: ["Preencha o novo combinado."] };

  const supabase = await supabaseSessao();
  const dia = hoje();

  try {
    if (abertoId) {
      await db(
        "enquadres.fechar",
        supabase
          .from("enquadres")
          .update({ vigencia_fim: dia, motivo_fim: motivo })
          .eq("id", abertoId)
          .is("vigencia_fim", null),
      );
    }

    await db(
      "enquadres.abrir",
      supabase
        .from("enquadres")
        .insert({ ...enquadre.dados, paciente_id: pacienteId, vigencia_inicio: dia }),
    );
  } catch (e) {
    return { estado: "erro", erros: [traduzir(e)] };
  }

  revalidatePath(`/pacientes/${pacienteId}`);
  return INICIAL;
}

function traduzir(e: unknown): string {
  if (e instanceof ErroDeBanco) {
    if (e.codigo === "23505") return "Já existe um combinado aberto para este paciente.";
    if (e.codigo === "23514") return "Algum valor está fora do permitido.";
    if (e.codigo === "42501") return "Sem permissão para esta operação.";
  }
  console.error("[pacientes] erro não traduzido", e);
  return "Não consegui salvar agora. Tente de novo em instantes.";
}

/**
 * O pedido de exclusão, respondido com honestidade.
 *
 * A mensagem que volta é do banco de propósito: é ela que a psicóloga repassa ao
 * paciente, com a data exata em que o registro pode sair. Improvisar uma
 * explicação sobre a LGPD no meio de uma conversa difícil é como se erra aqui.
 */
export async function esquecerContato(_anterior: Resultado, form: FormData): Promise<Resultado> {
  const id = String(form.get("paciente_id") ?? "");
  if (!id) return { estado: "erro", erros: ["Paciente não identificado."] };

  const supabase = await supabaseSessao();

  try {
    const explicacao = await db<string>(
      "paciente.esquecer_contato",
      supabase.rpc("esquecer_contato", { p_paciente: id }),
    );
    revalidatePath(`/pacientes/${id}`);
    revalidatePath("/pacientes");
    return { estado: "ok", mensagem: explicacao };
  } catch (e) {
    console.error("[paciente] falhou esquecer contato", e);
    return { estado: "erro", erros: ["Não consegui agora. Tente de novo em instantes."] };
  }
}

/**
 * Encerrar.
 *
 * O texto do encerramento é exigido pelo banco, não pelo formulário — a Res. CFP
 * 001/2009 pede o registro de como o acompanhamento terminou, e um prontuário
 * que acaba no silêncio é o que o Conselho aponta como falta.
 */
export async function arquivarPaciente(_anterior: Resultado, form: FormData): Promise<Resultado> {
  const id = String(form.get("paciente_id") ?? "");
  const encerramento = String(form.get("encerramento") ?? "").trim();

  if (!id) return { estado: "erro", erros: ["Paciente não identificado."] };
  if (encerramento.length < 10) {
    return {
      estado: "erro",
      erros: ["Escreva como o acompanhamento terminou — alta, encaminhamento, abandono."],
    };
  }

  const supabase = await supabaseSessao();

  try {
    await db(
      "paciente.arquivar",
      supabase.rpc("arquivar_paciente", { p_paciente: id, p_encerramento: encerramento }),
    );
  } catch (e) {
    console.error("[paciente] falhou arquivar", e);
    return { estado: "erro", erros: ["Não consegui agora. Tente de novo em instantes."] };
  }

  revalidatePath(`/pacientes/${id}`);
  revalidatePath("/pacientes");
  return {
    estado: "ok",
    mensagem: "Ficha encerrada e arquivada. Daqui em diante ela é só leitura.",
  };
}

/**
 * Vender um pacote.
 *
 * A validação daqui é cortesia — quem recusa validade no passado é a
 * `vender_pacote` da 0033. O que esta função faz de útil é traduzir: a pessoa
 * digitou "1.800,00" e o banco espera numeric.
 */
export async function venderPacote(_anterior: Resultado, form: FormData): Promise<Resultado> {
  const paciente = String(form.get("paciente") ?? "");
  const quantidade = Number(form.get("quantidade") ?? 0);
  const validade = String(form.get("validade") ?? "").trim();
  const bruto = String(form.get("valor") ?? "").trim();

  const erros: string[] = [];
  if (!Number.isInteger(quantidade) || quantidade < 1 || quantidade > 60) {
    erros.push("Um pacote tem de 1 a 60 sessões.");
  }
  if (!/^\d{4}-\d{2}-\d{2}$/.test(validade)) {
    erros.push("Escolha até quando o pacote vale.");
  }
  const valorCentavos = lerCentavos(bruto);
  if (valorCentavos === null) {
    erros.push("Informe o valor total do pacote.");
  }
  if (erros.length > 0) return { estado: "erro", erros };

  const supabase = await supabaseSessao();
  try {
    await db(
      "pacote.vender",
      supabase.rpc("vender_pacote", {
        p_paciente: paciente,
        p_quantidade: quantidade,
        p_valor: deCentavos(valorCentavos ?? 0),
        p_validade: validade,
      }),
    );
  } catch (e) {
    return { estado: "erro", erros: [traduzir(e)] };
  }

  revalidatePath(`/pacientes/${paciente}`);
  revalidatePath("/recebimentos");
  return { estado: "ok", mensagem: "Pacote vendido. A cobrança do total já está em aberto." };
}

/** Cancelar não devolve dinheiro e não apaga o que já foi consumido. */
export async function cancelarPacote(_anterior: Resultado, form: FormData): Promise<Resultado> {
  const pacote = String(form.get("pacote") ?? "");
  const paciente = String(form.get("paciente") ?? "");

  const supabase = await supabaseSessao();
  try {
    await db("pacote.cancelar", supabase.rpc("cancelar_pacote", { p_pacote: pacote }));
  } catch (e) {
    return { estado: "erro", erros: [traduzir(e)] };
  }

  revalidatePath(`/pacientes/${paciente}`);
  revalidatePath("/recebimentos");
  return {
    estado: "ok",
    mensagem:
      "Pacote encerrado e a cobrança em aberto cancelada. Os créditos já usados continuam registrados.",
  };
}

/**
 * A nota da hora que não houve (PR8, B27).
 *
 * A validação séria mora no gatilho `nota_so_na_ausencia`: é lá que se decide
 * que evolução de sessão realizada é prontuário, e prontuário é fase 3. Aqui só
 * se traduz o "não" do banco para uma frase que explique — porque uma recusa
 * sem motivo, numa caixa de texto, parece defeito.
 */
export async function anotarAusencia(
  _anterior: Resultado,
  form: FormData,
): Promise<Resultado> {
  const sessao = String(form.get("sessao_id") ?? "").trim();
  const nota = String(form.get("nota") ?? "");

  if (sessao === "") return { estado: "erro", erros: ["Sem sessão."] };
  if (nota.length > 2000) {
    return { estado: "erro", erros: ["A nota tem no máximo 2000 caracteres."] };
  }

  const supabase = await supabaseSessao();
  try {
    await db(
      "paciente.anotar",
      supabase.rpc("anotar_ausencia", { p_sessao: sessao, p_nota: nota }),
    );
  } catch (e) {
    const m = e instanceof Error ? e.message : String(e);
    if (/prontuário/i.test(m)) {
      return {
        estado: "erro",
        erros: [
          "Esta hora aconteceu — e a evolução da sessão atendida é prontuário, que entra na fase 3, depois da conferência das resoluções do CFP. Aqui a nota é da hora que não houve.",
        ],
      };
    }
    return { estado: "erro", erros: ["Não consegui guardar a nota agora."] };
  }

  revalidatePath("/pacientes");
  revalidatePath("/agenda");
  return { estado: "ok", mensagem: "Guardado." };
}

/**
 * O bloco 2 do conteúdo mínimo: a avaliação da demanda (B28).
 *
 * A modalidade tem asterisco: ela é conteúdo mínimo desde a Res. CFP 09/2024, e
 * não um detalhe de preenchimento. O formulário deixa em branco quem não quiser
 * responder — obrigar produz resposta de fachada, e resposta de fachada num
 * prontuário é pior que campo vazio.
 */
export async function salvarDemanda(_anterior: Resultado, form: FormData): Promise<Resultado> {
  const paciente = String(form.get("paciente_id") ?? "").trim();
  const demanda = String(form.get("demanda") ?? "");
  const objetivos = String(form.get("objetivos") ?? "");
  const frequencia = String(form.get("frequencia") ?? "");
  const modalidade = String(form.get("modalidade") ?? "");

  if (paciente === "") return { estado: "erro", erros: ["Sem paciente."] };
  if (demanda.length > 5000 || objetivos.length > 5000) {
    return { estado: "erro", erros: ["Texto longo demais para um bloco do registro."] };
  }

  const supabase = await supabaseSessao();
  try {
    await db(
      "registro.demanda",
      supabase.rpc("salvar_demanda", {
        p_paciente: paciente,
        p_demanda: demanda,
        p_objetivos: objetivos,
        p_frequencia: frequencia,
        p_modalidade: modalidade === "" ? null : modalidade,
      }),
    );
  } catch (e) {
    return { estado: "erro", erros: [legivelClinico(e)] };
  }

  revalidatePath("/pacientes");
  return { estado: "ok", mensagem: "Guardado no registro." };
}

/** O bloco 3: a evolução da sessão que aconteceu (B28). */
export async function escreverEvolucao(_anterior: Resultado, form: FormData): Promise<Resultado> {
  const sessao = String(form.get("sessao_id") ?? "").trim();
  const texto = String(form.get("texto") ?? "");
  const camada = String(form.get("camada") ?? "prontuario");

  if (sessao === "") return { estado: "erro", erros: ["Sem sessão."] };
  if (texto.trim() === "") {
    return {
      estado: "erro",
      erros: ["Evolução em branco não é evolução — o registro não guarda espaço vazio."],
    };
  }
  if (texto.length > 20000) return { estado: "erro", erros: ["Texto longo demais."] };

  const supabase = await supabaseSessao();
  try {
    await db(
      "registro.evolucao",
      supabase.rpc("escrever_evolucao", {
        p_sessao: sessao,
        p_texto: texto,
        p_camada: camada === "documental" ? "documental" : "prontuario",
      }),
    );
  } catch (e) {
    return { estado: "erro", erros: [legivelClinico(e)] };
  }

  revalidatePath("/pacientes");
  revalidatePath("/agenda");
  return { estado: "ok", mensagem: "Guardado." };
}

/**
 * As recusas do registro chegam prontas do banco, e é assim que tem de ser: a
 * regra mora lá, e repetir o texto aqui é criar uma segunda verdade que um dia
 * discorda da primeira. O que esta função faz é só evitar que uma mensagem de
 * Postgres crua apareça na tela de quem está atendendo.
 */
function legivelClinico(e: unknown): string {
  const m = e instanceof Error ? e.message : String(e);
  const limpo = m.replace(/^.*?:\s*/, "").trim();
  return limpo.length > 3 && limpo.length < 400
    ? limpo.charAt(0).toUpperCase() + limpo.slice(1)
    : "Não consegui guardar agora.";
}

// =========================================================== a anamnese (B29)

export async function abrirAnamnese(_anterior: Resultado, form: FormData): Promise<Resultado> {
  const paciente = String(form.get("paciente_id") ?? "").trim();
  const modelo = String(form.get("modelo") ?? "adulto");
  if (paciente === "") return { estado: "erro", erros: ["Sem paciente."] };

  const supabase = await supabaseSessao();
  try {
    await db(
      "anamnese.abrir",
      supabase.rpc("abrir_anamnese", { p_paciente: paciente, p_modelo: modelo }),
    );
  } catch (e) {
    return { estado: "erro", erros: [legivelClinico(e)] };
  }
  revalidatePath("/pacientes");
  return { estado: "ok", mensagem: "Anamnese aberta com o roteiro do modelo." };
}

/**
 * Salvar a anamnese.
 *
 * O conteúdo chega como uma lista de seções — título e texto —, e a ordem que
 * veio da tela é a ordem que se guarda: a estrutura é dela.
 */
export async function salvarAnamnese(_anterior: Resultado, form: FormData): Promise<Resultado> {
  const anamnese = String(form.get("anamnese_id") ?? "").trim();
  const bruto = String(form.get("conteudo") ?? "[]");
  const medicacao = String(form.get("medicacao") ?? "");
  if (anamnese === "") return { estado: "erro", erros: ["Sem anamnese."] };

  let conteudo: { titulo: string; texto: string }[];
  try {
    const lido = JSON.parse(bruto);
    if (!Array.isArray(lido)) throw new Error("não é lista");
    conteudo = lido.map((s: { titulo?: unknown; texto?: unknown }) => ({
      titulo: String(s.titulo ?? "").slice(0, 200),
      texto: String(s.texto ?? "").slice(0, 20000),
    }));
  } catch {
    return { estado: "erro", erros: ["Não consegui ler as seções."] };
  }

  const supabase = await supabaseSessao();
  try {
    await db(
      "anamnese.salvar",
      supabase.rpc("salvar_anamnese", {
        p_anamnese: anamnese,
        p_conteudo: conteudo,
        p_medicacao: medicacao,
      }),
    );
  } catch (e) {
    return { estado: "erro", erros: [legivelClinico(e)] };
  }
  revalidatePath("/pacientes");
  return { estado: "ok", mensagem: "Guardado." };
}

export async function fecharAnamnese(_anterior: Resultado, form: FormData): Promise<Resultado> {
  const anamnese = String(form.get("anamnese_id") ?? "").trim();
  if (String(form.get("confirma") ?? "") !== "fechar") {
    return { estado: "erro", erros: ['Escreva "fechar" para confirmar — não há como reabrir depois.'] };
  }

  const supabase = await supabaseSessao();
  try {
    await db("anamnese.fechar", supabase.rpc("fechar_anamnese", { p_anamnese: anamnese }));
  } catch (e) {
    return { estado: "erro", erros: [legivelClinico(e)] };
  }
  revalidatePath("/pacientes");
  return {
    estado: "ok",
    mensagem: "Fechada. O que chegar depois entra como adendo, com a data em que chegou.",
  };
}

export async function acrescentarAdendo(_anterior: Resultado, form: FormData): Promise<Resultado> {
  const anamnese = String(form.get("anamnese_id") ?? "").trim();
  const texto = String(form.get("texto") ?? "");
  if (texto.trim() === "") return { estado: "erro", erros: ["Adendo em branco não é adendo."] };

  const supabase = await supabaseSessao();
  try {
    await db(
      "anamnese.adendo",
      supabase.rpc("acrescentar_adendo", { p_anamnese: anamnese, p_texto: texto }),
    );
  } catch (e) {
    return { estado: "erro", erros: [legivelClinico(e)] };
  }
  revalidatePath("/pacientes");
  return { estado: "ok", mensagem: "Adendo guardado com a data de hoje." };
}

/**
 * O link da página do paciente (P7).
 *
 * **Abrir revoga o anterior**, e isso acontece dentro da função do banco, numa
 * transação só. Se fossem dois passos, o dia em que o segundo falhasse
 * deixaria dois links vivos — e o índice único, que é a rede, transformaria
 * isso num erro sem explicação na tela dela.
 *
 * **E o Pix é cunhado aqui, não lá.** O BR Code depende de `contas.pix_chave`,
 * e chave Pix é o endereço da conta bancária dela: montá-lo numa função que
 * qualquer pessoa com um token alcança seria pôr a chave num caminho anônimo.
 * Então quem cunha é este caminho, que exige sessão; a página pública só lê o
 * que já está gravado. Cobrança sem Pix aparece lá com o valor e sem o código,
 * dizendo a verdade.
 */
export async function abrirLinkDoPaciente(
  _anterior: Resultado,
  form: FormData,
): Promise<Resultado> {
  const id = String(form.get("paciente_id") ?? "");
  if (!id) return { estado: "erro", erros: ["Paciente não identificado."] };

  const supabase = await supabaseSessao();

  try {
    const r = (await db(
      "paciente.abrir_link",
      supabase.rpc("abrir_link_do_paciente", { p_paciente: id }),
    )) as unknown as { ok?: boolean; token?: string };

    if (!r?.ok || !r.token) {
      return { estado: "erro", erros: ["Não consegui gerar o link agora."] };
    }

    // Cunhar o Pix é parte de abrir o link, e é aqui que ele pode ser cunhado:
    // este caminho tem sessão, e o BR Code precisa da chave dela. Se não der —
    // conta sem chave Pix cadastrada, provedor não ligado — o link nasce
    // assim mesmo e a página diz a verdade ao paciente. **Falhar aqui não pode
    // derrubar o link**: o valor e o horário continuam valendo sem o código.
    await cunharPixDasAbertas(id);

    revalidatePath(`/pacientes/${id}`);
    return { estado: "ok", mensagem: r.token };
  } catch (e) {
    console.error("[paciente] falhou abrir link", e);
    return {
      estado: "erro",
      erros: ["Não consegui gerar o link. Se a ficha estiver encerrada, ele não é gerado."],
    };
  }
}

export async function revogarLinkDoPaciente(
  _anterior: Resultado,
  form: FormData,
): Promise<Resultado> {
  const id = String(form.get("paciente_id") ?? "");
  if (!id) return { estado: "erro", erros: ["Paciente não identificado."] };

  const supabase = await supabaseSessao();

  try {
    await db(
      "paciente.revogar_link",
      supabase.rpc("revogar_link_do_paciente", { p_paciente: id }),
    );
    revalidatePath(`/pacientes/${id}`);
    return { estado: "ok", mensagem: "O link antigo deixou de funcionar agora." };
  } catch (e) {
    console.error("[paciente] falhou revogar link", e);
    return { estado: "erro", erros: ["Não consegui revogar agora. Tente de novo."] };
  }
}


/**
 * Cunha o copia-e-cola das cobranças abertas do paciente.
 *
 * Mesma aritmética do `gerarPix` da agenda, e o código continua sendo gravado
 * na cobrança em vez de recalculado a cada leitura — o motivo é o retrato: o
 * que foi mandado para o paciente tem de continuar existindo igual, mesmo que
 * ela troque a chave Pix amanhã. Um copia-e-cola que muda debaixo de quem já
 * recebeu é uma cobrança que não pode ser paga.
 *
 * **Best-effort de propósito, e a exceção é engolida com o registro no log.**
 * A alternativa seria o link não nascer porque a conta ainda não cadastrou
 * chave Pix — e o link serve para confirmar horário e entregar documento
 * também. O que a página faz quando não há código é dizer isso, em vez de
 * mostrar um campo vazio.
 */
async function cunharPixDasAbertas(pacienteId: string): Promise<void> {
  try {
    const supabase = await supabaseSessao();
    const sessao = await sessaoAtual();

    const contas = (await db(
      "paciente.pix.conta",
      supabase
        .from("contas")
        .select("pix_chave, pix_nome, pix_cidade, provedor_pagamento, provedor_estado")
        .eq("id", sessao.contaId)
        .limit(1),
    )) as unknown as {
      pix_chave: string | null;
      pix_nome: string | null;
      pix_cidade: string | null;
      provedor_pagamento: string | null;
      provedor_estado: string | null;
    }[];

    const conta = contas[0];
    if (!conta?.pix_chave) return;

    const abertas = (await db(
      "paciente.pix.abertas",
      supabase
        .from("cobrancas")
        .select("id, valor")
        .eq("paciente_id", pacienteId)
        .eq("estado", "aberta")
        .is("pix_copia_cola", null),
    )) as unknown as { id: string; valor: string }[];

    const adaptador = adaptadorPara(
      conta.provedor_pagamento ?? null,
      conta.provedor_estado ?? null,
    );

    for (const cobranca of abertas ?? []) {
      const txid = await db<string>(
        "paciente.pix.txid",
        supabase.rpc("txid_da_cobranca", { p_cobranca: cobranca.id }),
      );

      const criada = await adaptador.criar(
        {
          cobrancaId: cobranca.id,
          valorCentavos: paraCentavos(cobranca.valor),
          txid,
        },
        {
          pixChave: conta.pix_chave,
          pixNome: conta.pix_nome ?? null,
          pixCidade: conta.pix_cidade ?? null,
        },
      );

      await db(
        "paciente.pix.salvar",
        supabase
          .from("cobrancas")
          .update({
            txid,
            provedor: criada.provedor,
            pix_copia_cola: criada.pixCopiaCola,
            link_pagamento: criada.link,
            provedor_cobranca_id: criada.provedorCobrancaId,
          })
          .eq("id", cobranca.id)
          .select("id"),
      );
    }
  } catch (e) {
    console.error("[paciente] não consegui cunhar o pix das cobranças abertas", e);
  }
}
