-- 0041 · A falta é dado clínico, e não só um lançamento.
--
-- A PR8 é uma feature de uma coluna e meia, e mesmo assim o doc 03 a marca como
-- **diferencial**. O motivo não é técnico.
--
-- Em todos os oito concorrentes, faltar é um evento financeiro: gera uma
-- cobrança, entra num relatório de inadimplência e some. Só que numa clínica de
-- psicologia a ausência é, muitas vezes, o material da próxima sessão — o
-- enquadre sendo testado, a ambivalência aparecendo pela porta, a semana em que
-- a pessoa não conseguiu vir. Quem atende sabe disso; o software finge que não.
--
-- Esta migração faz a ausência aparecer **na linha do tempo da pessoa**, e não
-- só na régua de cobrança. É a ponte que o doc 03 chama de "a commodity
-- bem-feita, com as junções que só este produto tem".
--
--
-- ================================================== as quatro decisões
--
-- **1. O sistema mostra o que aconteceu. Ele nunca diz o que aquilo significa.**
--
-- Esta é a linha do doc 07 que não se atravessa: *"IA que interpreta, sugere
-- diagnóstico/conduta ou avalia risco"*. Vale para IA e vale para `case when`.
--
-- Então `ausencias_do_paciente` devolve **aritmética**: quantas sessões, quantas
-- ausências, quantas seguidas agora, há quantos dias foi a última realizada.
-- Não devolve rótulo, não devolve escore, não devolve cor, e não existe campo
-- `risco`, `alerta` ou `abandono` — há um teste de estrutura que falha se
-- alguém criar um. "Três das últimas cinco horas não aconteceram" é fato;
-- "padrão de resistência" é leitura clínica, e a leitura é dela.
--
-- A tentação aqui é enorme e é exatamente por isso que a regra está escrita no
-- banco: um dia alguém vai propor um badge vermelho de "risco de abandono", e
-- vai ser numa sexta-feira.
--
-- **2. A nota é dela, e só cabe na hora que não houve.**
--
-- Uma sessão **realizada** não aceita nota — e a recusa explica por quê: a
-- evolução da sessão é prontuário, e prontuário é fase 3, com o portão do doc
-- 07 na frente (conferência das resoluções do CFP com uma psicóloga, trilha
-- ativa, exportações funcionando). Começar o prontuário de lado, em fevereiro,
-- por uma caixa de texto que ninguém pensou direito, seria furar o portão pelo
-- caminho mais silencioso possível.
--
-- O que cabe aqui é o registro do que aconteceu com a hora que **não** houve:
-- "avisou que estava doente", "terceira seguida, conversar na próxima". É o
-- menor registro clínico possível, e é justamente o que a PR8 pede.
--
-- **Uma exceção deliberada:** se ela **corrigir** o desfecho depois — marcou
-- falta, era engano, a pessoa veio —, a nota **fica**. Apagar o que ela
-- escreveu para manter a invariante limpa seria o software destruindo registro
-- de guarda de cinco anos por elegância. O gatilho confere na **escrita** da
-- nota, não em toda atualização da sessão.
--
-- **3. A nota nunca vai para o paciente.**
--
-- Não existe template, não entra em documento, não sai no recibo, não entra na
-- pasta do contador (que não tem paciente nenhum desde a B25). Ela sai na
-- exportação da conta e na exportação do próprio paciente — que são direito de
-- portabilidade, e nas duas ela já viaja dentro de `sessoes`, sem uma linha a
-- mais. E **sobrevive ao "esquecer contato"** da B13: apagar telefone e e-mail é
-- minimização de dado de contato; a guarda de cinco anos da Res. CFP 001/2009
-- vale para o registro.
--
-- **4. Sessão importada conta presença, e continua não contando dinheiro.**
--
-- A B26 decidiu que histórico de outro sistema é memória, não dinheiro. A outra
-- metade da mesma decisão aparece aqui: para **presença**, ele conta. É
-- exatamente para isso que ele foi trazido — uma linha do tempo que começa no
-- dia em que a psicóloga instalou o app não é a linha do tempo do paciente
-- dela.

-- ====================================================== a nota da ausência

alter table public.sessoes
  add column if not exists nota text
    check (nota is null or length(nota) between 1 and 2000);
alter table public.sessoes
  add column if not exists nota_em timestamptz;

comment on column public.sessoes.nota is
  'PR8. O que aconteceu com a hora que nao houve. So em falta ou cancelamento; evolucao de sessao realizada e prontuario, fase 3.';

/**
 * A nota tem lugar, e o carimbo é do servidor.
 *
 * Confere só quando a **nota** muda. Uma correção de desfecho depois não apaga
 * o que ela escreveu (decisão 2), e um UPDATE que não toca na nota passa reto —
 * o que também evita que a agenda inteira pare de funcionar por causa desta
 * regra.
 *
 * O `nota_em` é sempre `now()` do banco, nunca o que veio no PATCH. É a mesma
 * lição da 0011: quem escolhe o carimbo, forja o carimbo.
 */
create or replace function public.nota_so_na_ausencia()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
declare
  antes text := null;
  mudou boolean := false;
begin
  if tg_op = 'UPDATE' then
    antes := old.nota;
  end if;

  mudou := new.nota is distinct from antes;

  if not mudou then
    -- Nada a conferir. O carimbo antigo continua valendo.
    if tg_op = 'UPDATE' then
      new.nota_em := old.nota_em;
    end if;
    return new;
  end if;

  if new.nota is null then
    new.nota_em := null;
    return new;
  end if;

  if new.estado not in ('falta', 'cancelada_cedo', 'cancelada_tarde') then
    raise exception 'a nota é da hora que não houve: só falta ou cancelamento aceitam. A evolução da sessão atendida é prontuário, e prontuário é da fase 3';
  end if;

  new.nota_em := now();
  return new;
end;
$$;

drop trigger if exists nota_so_na_ausencia on public.sessoes;
create trigger nota_so_na_ausencia
  before insert or update on public.sessoes
  for each row execute function public.nota_so_na_ausencia();

-- ================================================ anotar (e desanotar)

/**
 * Escrever a nota.
 *
 * `invoker` de propósito: a RLS de `sessoes` já resolve de quem é a linha, e o
 * gatilho acima já é a invariante. A função existe pela conveniência de um só
 * lugar — e porque é ela quem carimba a trilha de acesso.
 *
 * Nota vazia apaga. Não é um caso especial escondido: é o desfazer, e desfazer
 * tem de ser tão fácil quanto fazer.
 */
create or replace function public.anotar_ausencia(p_sessao uuid, p_nota text)
returns void
language plpgsql
security invoker
set search_path = ''
as $$
declare
  limpa text := nullif(btrim(coalesce(p_nota, '')), '');
  pac uuid;
  n int;
begin
  if limpa is not null and length(limpa) > 2000 then
    raise exception 'a nota tem no máximo 2000 caracteres';
  end if;

  update public.sessoes set nota = limpa where id = p_sessao
  returning paciente_id into pac;

  get diagnostics n = row_count;

  -- Sem política que alcance a linha, o UPDATE afeta zero linhas e **não
  -- reclama** — foi assim que o perdão da B11 falhou em silêncio, e foi assim
  -- que dois testes da B26 passaram pelo motivo errado. Aqui a ausência de
  -- efeito vira exceção.
  if n = 0 then
    raise exception 'não encontrei essa sessão';
  end if;

  insert into public.trilha_acesso (conta_id, paciente_id, acao, detalhe)
  values (public.conta_atual(), pac, 'anotou_ausencia',
          jsonb_build_object('sessao', p_sessao, 'apagou', limpa is null));
end;
$$;

-- A lista corrente veio do **banco**, não da 0024: a 0031 acrescentou os três
-- valores de contrato depois, e reescrever a partir da migração antiga apagaria
-- os três. É a pedra em que a 0040 tropeçou com `sessoes_origem_check`.
alter table public.trilha_acesso drop constraint if exists trilha_acesso_acao_check;
alter table public.trilha_acesso add constraint trilha_acesso_acao_check
  check (acao in (
    'leu_ficha', 'editou_ficha', 'exportou_paciente', 'exportou_conta',
    'esqueceu_contato', 'arquivou',
    'contrato_enviado', 'contrato_aceito', 'contrato_revogado',
    'anotou_ausencia'));

-- ==================================================== a linha do tempo

/**
 * O que aconteceu com esta pessoa, em ordem.
 *
 * Junta numa consulta só o que hoje mora em quatro tabelas: o desfecho da hora,
 * a nota dela, o estado do dinheiro e a origem (encaixe, remarcada, importada).
 * A origem importa na leitura clínica: uma hora que **nasceu de um encaixe** é
 * uma pessoa que topou vir com um dia de aviso, e isso é informação sobre o
 * vínculo, não sobre a agenda.
 *
 * `invoker`: a RLS decide o que aparece, e perguntar por um paciente de outra
 * conta devolve vazio em vez de erro — inútil, que é o objetivo (lição da 0015).
 */
create or replace function public.linha_do_tempo(p_paciente uuid, p_limite int default 60)
returns table (
  sessao_id       uuid,
  inicio          timestamptz,
  dia             date,
  estado          text,
  origem          text,
  valor           numeric,
  nota            text,
  nota_em         timestamptz,
  cobranca_estado text,
  cobranca_tipo   text,
  cobranca_valor  numeric
)
language sql
stable
security invoker
set search_path = ''
as $$
  select s.id,
         s.inicio,
         (s.inicio at time zone 'America/Sao_Paulo')::date,
         s.estado,
         s.origem,
         s.valor,
         s.nota,
         s.nota_em,
         cb.estado,
         cb.tipo,
         cb.valor
    from public.sessoes s
    left join public.cobrancas cb
           on cb.sessao_id = s.id and cb.estado <> 'cancelada'
   where s.paciente_id = p_paciente
   order by s.inicio desc
   limit greatest(1, least(coalesce(p_limite, 60), 500));
$$;

-- ============================================ a aritmética, e só a aritmética

/**
 * As contas das ausências.
 *
 * Tudo aqui é contagem, data ou diferença de datas. Nenhum campo é adjetivo.
 * Se um dia aparecer um `risco`, um `escore` ou um `alerta` nesta saída, é
 * porque alguém atravessou a linha do doc 07 — e a verificação nº 9 da suíte
 * existe para não deixar isso passar em silêncio.
 *
 * `ultimos` sai do mais antigo para o mais recente porque a tela desenha uma
 * faixa, e faixa se lê da esquerda para a direita.
 *
 * `seguidas` é a sequência **corrente** (as últimas, em cadeia), não a maior de
 * todos os tempos: o que interessa a quem vai atender amanhã é o agora.
 */
create or replace function public.ausencias_do_paciente(p_paciente uuid)
returns jsonb
language plpgsql
stable
security invoker
set search_path = ''
as $$
declare
  n_sessoes int := 0;
  n_realizadas int := 0;
  n_faltas int := 0;
  n_cedo int := 0;
  n_tarde int := 0;
  ultimos jsonb := '[]'::jsonb;
  seguidas int := 0;
  d record;
  primeira date;
  ultima date;
  ultima_realizada date;
begin
  select count(*) filter (where estado in ('realizada','falta','cancelada_cedo','cancelada_tarde')),
         count(*) filter (where estado = 'realizada'),
         count(*) filter (where estado = 'falta'),
         count(*) filter (where estado = 'cancelada_cedo'),
         count(*) filter (where estado = 'cancelada_tarde'),
         min((inicio at time zone 'America/Sao_Paulo')::date)
           filter (where estado in ('realizada','falta','cancelada_cedo','cancelada_tarde')),
         max((inicio at time zone 'America/Sao_Paulo')::date)
           filter (where estado in ('realizada','falta','cancelada_cedo','cancelada_tarde')),
         max((inicio at time zone 'America/Sao_Paulo')::date) filter (where estado = 'realizada')
    into n_sessoes, n_realizadas, n_faltas, n_cedo, n_tarde, primeira, ultima, ultima_realizada
    from public.sessoes
   where paciente_id = p_paciente;

  -- Os oito últimos desfechos, do mais antigo para o mais recente.
  select coalesce(jsonb_agg(x.estado order by x.inicio), '[]'::jsonb)
    into ultimos
    from (
      select estado, inicio
        from public.sessoes
       where paciente_id = p_paciente
         and estado in ('realizada','falta','cancelada_cedo','cancelada_tarde')
       order by inicio desc
       limit 8
    ) x;

  -- A cadeia corrente de ausências: conta do fim para trás e para na primeira
  -- realizada.
  for d in
    select estado from public.sessoes
     where paciente_id = p_paciente
       and estado in ('realizada','falta','cancelada_cedo','cancelada_tarde')
     order by inicio desc
  loop
    exit when d.estado = 'realizada';
    seguidas := seguidas + 1;
  end loop;

  return jsonb_build_object(
    'sessoes', n_sessoes,
    'realizadas', n_realizadas,
    'faltas', n_faltas,
    'cancelou_cedo', n_cedo,
    'cancelou_tarde', n_tarde,
    'ausencias', n_faltas + n_cedo + n_tarde,
    'seguidas', seguidas,
    'ultimos', ultimos,
    'primeira', primeira,
    'ultima', ultima,
    'ultima_realizada', ultima_realizada,
    'dias_desde_a_ultima_realizada',
      case when ultima_realizada is null then null
           else public.hoje_sp() - ultima_realizada end,
    'com_nota', (select count(*) from public.sessoes
                  where paciente_id = p_paciente and nota is not null)
  );
end;
$$;

-- ================================================================ privilégios

revoke execute on function public.nota_so_na_ausencia() from public, anon, authenticated;
revoke execute on function public.anotar_ausencia(uuid, text) from public, anon;
revoke execute on function public.linha_do_tempo(uuid, int) from public, anon;
revoke execute on function public.ausencias_do_paciente(uuid) from public, anon;

grant execute on function public.anotar_ausencia(uuid, text) to authenticated;
grant execute on function public.linha_do_tempo(uuid, int) to authenticated;
grant execute on function public.ausencias_do_paciente(uuid) to authenticated;

comment on function public.ausencias_do_paciente(uuid) is
  'PR8. So aritmetica: contagens, datas e diferencas. Nenhum rotulo, escore ou juizo — a leitura clinica e dela (doc 07).';
comment on function public.linha_do_tempo(uuid, int) is
  'O que aconteceu com a pessoa, em ordem: desfecho, nota, dinheiro e origem da hora.';
