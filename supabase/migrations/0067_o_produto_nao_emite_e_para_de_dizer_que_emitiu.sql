-- =====================================================================
-- 0067 · P8 · O produto não emite, e para de dizer que emitiu
-- =====================================================================
--
-- O `claude/25` abre o P8 com uma frase que parece de estilo e é de banco:
--
--     **O estado guardado é `marcado por ela`, nunca `emitido`.**
--     O produto não tem como saber, e escrever no banco uma palavra que ele
--     não pode provar é como o painel da automação mente.
--
-- Fui escrever o cartão de emissão e encontrei o contrário disso já em
-- produção. `marcar_recibo_rfb` faz, desde a B24:
--
--     update public.recibos_rfb
--        set estado = 'emitido', emitido_em = public.hoje_sp(), ...
--
-- **O produto nunca emitiu nada.** Não há API do Receita Saúde, não existe
-- função que emita, e há teste de estrutura desde a 0038 que reprova qualquer
-- função com esse nome. O que aconteceu foi que **ela** abriu o app da Receita
-- Federal, digitou, e depois veio aqui dizer que fez. A linha do banco afirma
-- um fato que só a Receita pode confirmar.
--
-- **Por que isso não é preciosismo.** O dia em que ela for questionada — pelo
-- contador, pela fiscalização, por ela mesma em fevereiro — a pergunta vai ser
-- *"este recibo foi mesmo emitido?"*. Um banco que responde `emitido` está
-- respondendo por cima de uma coisa que não observou. Um banco que responde
-- `marcado por ela em 02/09` responde o que aconteceu de fato, e devolve a
-- pergunta para o único lugar onde ela tem resposta: o e-CAC.
--
-- É a mesma família da coluna `recursos` (0045), da palavra "sem" que saiu da
-- página de privacidade e da `eliminar_conta` que não existia — **o software
-- afirmando comportamento que ele não tem.** A diferença é que aqui a
-- afirmação está numa linha de banco em vez de numa página, e por isso durou
-- quatro dias sem ninguém ver.
--
--
-- ---------------------------------------------------------------------
-- O QUE MUDA DE NOME, E O QUE DELIBERADAMENTE NÃO MUDA
-- ---------------------------------------------------------------------
--
--   `recibos_rfb.estado`      'emitido'    → **'marcado_por_ela'**
--   `recibos_rfb.emitido_em`               → **marcado_por_ela_em**
--   `recibos_rfb.numero_rfb`               → **numero_informado**
--
-- **`documentos.emitido_em` NÃO muda, e a distinção é o ponto inteiro.** Lá a
-- palavra é verdadeira: o recibo da B17 foi emitido *por este produto*, com
-- número queimado por ele e gatilho de imutabilidade em cima. Renomear as duas
-- por simetria apagaria justamente a diferença que esta migração existe para
-- escrever — de um lado o produto agiu, do outro ele só anotou.
--
-- E `numero_rfb` → `numero_informado` pelo mesmo motivo: o número não é "da
-- Receita" no sentido de ter vindo de lá. É o número que **ela leu na tela e
-- digitou aqui**, e pode estar errado. `numero_informado` diz isso; `numero_rfb`
-- sugere procedência que não existe.
--
-- **Não há coluna nova.** O `claude/25` pede `marcado_por_ela_em` e
-- `numero_informado` como colunas novas — mas as duas já existem com outro
-- nome e o mesmo significado, e criar as novas ao lado seria a mesma verdade
-- em dois lugares, que é o antipadrão que este projeto registrou lendo o
-- Enquadria (três fórmulas de MRR convivendo, e o histórico não batendo com a
-- tela). Renomear é mais barato e não deixa a segunda fonte.
--
--
-- ---------------------------------------------------------------------
-- ESTA MIGRAÇÃO RENOMEIA; A 0067b REESCREVE AS FUNÇÕES
-- ---------------------------------------------------------------------
--
-- Oito funções tocam esses identificadores: `ao_pagar_gera_recibo_rfb`,
-- `desmarcar_recibo_rfb`, `dias_para_desfazer`, `exportar_conta`,
-- `fechar_mes_da_conta`, `marcar_recibo_rfb`, `recalcular_eixos` e
-- `receita_saude_do_ano`.
--
-- Elas **não** são reescritas aqui, e a razão é a cicatriz de ontem: para pôr
-- as oito neste arquivo eu teria de copiar oito corpos de função à mão, e foi
-- exatamente assim que a 0060 apagou o `insert` da trilha e a 0060d perdeu o
-- `enfileirar_mensagem`. A 0067b lê cada uma do **banco**
-- (`pg_get_functiondef`), troca os identificadores e devolve — e depois chama
-- todas, porque `create or replace` não valida corpo.
--
-- **A janela entre as duas migrações é o risco, e ele está declarado:** se um
-- pagamento entrar nesse intervalo, o gatilho `ao_pagar_gera_recibo_rfb` erra.
-- É aceitável hoje por um motivo específico e datado — **não há conta pagante,
-- e não há webhook de pagamento ligado** (o cliente do Asaas espera credencial,
-- B16). No dia em que houver, uma mudança desta forma vira janela de manutenção
-- ou migração única, e não este par.
--
--
-- ---------------------------------------------------------------------
-- O RESTO DO P8
-- ---------------------------------------------------------------------
--
--   · **`contas.ritmo_recibo`** — a cada sessão, semanal, mensal, ou só o
--     alarme de fevereiro. Nasce `mensal` e **a tela diz que é provisório**,
--     porque o default de verdade sai da pergunta V3 da conversa (*"se desse
--     para fazer o mês inteiro de uma vez, num arquivo, você faria mensal?"*).
--     Um número que não se apresenta como palpite vira regra por hábito antes
--     de alguém opinar sobre ele — é a mesma manobra do `3` da anamnese.
--
--   · **`cartao_de_emissao(uuid)`** — os seis campos que o app da Receita pede,
--     um a um, prontos para copiar. **Seis campos separados e não um bloco**
--     porque o app da Receita é campo a campo: um bloco só obrigaria ela a
--     selecionar pedaço por pedaço com o dedo, que é a digitação de volta com
--     outro nome.
--
--     E o **sexto campo sai vazio de propósito**: a descrição é texto livre que
--     vai daqui para a Receita Federal, e escrever ali o nome de quem se trata
--     seria entregar a lista de pacientes por conveniência de preenchimento. É
--     a mesma decisão da coluna 6 do CSV da 0053, e a suíte cobra as duas.
--
--   · **`dispensar_por_pagador_pj(uuid)`** — o caso que ninguém no mercado
--     resolve: quando quem paga é uma empresa, o app da Receita não tem campo
--     de CNPJ. Hoje isso é dispensa com motivo escrito à mão, toda vez
--     diferente; passa a ter motivo pré-escrito e a aparecer num relatório. O
--     motivo continua **obrigatório e gravado**, porque é ele que responde a
--     pergunta daqui a dois anos.
--
--   · **`telemetria_do_receita_saude()`** — dias entre o pagamento e a baixa,
--     quantas pendências chegam a janeiro, e lote contra cartão. É o
--     instrumento que decide se esta build se pagou: o `claude/25` tem um
--     portão escrito (*se a periodicidade modal for mensal ou fevereiro e o
--     incômodo mediano for ≤ 4, o cartão não se constrói*), e uma feature que
--     não carrega consigo o que a mediria é uma feature que ninguém desliga
--     depois.
--
-- **O que não entra, e nenhuma razão comercial reabre:** emitir, autenticar,
-- navegar no e-CAC, guardar senha, guardar sessão, guardar token, ou integrar
-- com intermediador que peça a conta gov.br dela por dentro deste produto. É a
-- **fronteira 11 do doc 11**. A suíte planta um valor com cara de credencial e
-- reprova qualquer coluna que o aceite.
--
-- =====================================================================


-- ---------------------------------------------------------------------
-- 1 · os nomes que deixam de afirmar o que não aconteceu
-- ---------------------------------------------------------------------

alter table public.recibos_rfb rename column emitido_em to marcado_por_ela_em;
alter table public.recibos_rfb rename column numero_rfb  to numero_informado;

comment on column public.recibos_rfb.marcado_por_ela_em is
  'O dia em que ELA disse que emitiu no app da Receita. NAO e o dia em que o produto emitiu — o produto nao emite, nao tem API e ha teste de estrutura desde a 0038 que reprova qualquer funcao com esse nome. Chamava-se emitido_em ate a 0067, e o nome afirmava um fato que so a Receita pode confirmar.';

comment on column public.recibos_rfb.numero_informado is
  'O numero que ela LEU na tela da Receita e digitou aqui. Pode estar errado. Chamava-se numero_rfb, que sugeria procedencia de la — e nenhum byte deste banco veio de la.';

-- A migração dos dados vem antes da troca do check, senão o próprio `update`
-- seria recusado pelo check novo.
update public.recibos_rfb set estado = 'marcado_por_ela' where estado = 'emitido';

alter table public.recibos_rfb drop constraint if exists recibos_rfb_estado_check;
alter table public.recibos_rfb
  add constraint recibos_rfb_estado_check
  check (estado in ('pendente', 'marcado_por_ela', 'dispensado', 'vencido', 'cancelado'));

comment on column public.recibos_rfb.estado is
  'pendente | marcado_por_ela | dispensado | vencido | cancelado. NAO existe estado "emitido": o produto nao emite. Ver o cabecalho da 0067.';


-- ---------------------------------------------------------------------
-- 2 · o ritmo, e ele se declara provisório
-- ---------------------------------------------------------------------

alter table public.contas
  add column if not exists ritmo_recibo text not null default 'mensal'
    check (ritmo_recibo in ('sessao', 'semanal', 'mensal', 'fevereiro'));

comment on column public.contas.ritmo_recibo is
  'Com que frequencia ela quer ser lembrada de lancar no Receita Saude. O default mensal e PALPITE, nao medicao — sai da pergunta V3 da conversa com a psicologa (claude/25), e a tela diz que e provisorio. Mudar o ritmo hoje nao reenvia nada do passado.';


-- ---------------------------------------------------------------------
-- 3 · o cartão de emissão
-- ---------------------------------------------------------------------
--
-- `security invoker`: a RLS de `recibos_rfb` já responde a pergunta certa, e o
-- cartão não precisa de nada que ela não possa ver. `definer` aqui seria o
-- padrão da sonda que a OP2 encontrou em `teto_da_conta` — parâmetro de id,
-- concessão ampla, e nenhuma conferência.

create or replace function public.cartao_de_emissao(p_recibo uuid)
returns jsonb
language plpgsql
stable
security invoker
set search_path = ''
as $$
declare
  v_r    record;
  v_pac  record;
  v_conta record;
begin
  select * into v_r from public.recibos_rfb where id = p_recibo;
  if not found then
    raise exception 'recibo não encontrado';
  end if;

  select p.nome, p.cpf into v_pac
    from public.pacientes p where p.id = v_r.paciente_id;

  select c.regime into v_conta from public.contas c where c.id = v_r.conta_id;

  -- Conta PJ não tem esta obrigação, e o cartão não existe para ela. A 0053
  -- já dispensa a pendência; aqui a recusa é dita, para a tela não ter de
  -- adivinhar por que veio vazio.
  if coalesce(v_conta.regime, 'pf') <> 'pf' then
    raise exception 'esta conta é PJ: o caminho fiscal aqui é a NFS-e, não o Receita Saúde';
  end if;

  return jsonb_build_object(
    -- Os seis, na ordem em que o app da Receita pede.
    'cpf',        v_pac.cpf,
    'nome',       v_pac.nome,
    'pago_em',    v_r.pago_em,
    'valor',      v_r.valor,
    'ocupacao',   public.ocupacao_receita_saude(),
    -- **Vazio, e é decisão.** Campo livre que vai daqui para a Receita
    -- Federal; escrever ali o nome de quem se trata seria entregar a lista de
    -- pacientes por conveniência de preenchimento. Mesma coluna 6 do CSV.
    'descricao',  '',
    -- Fora dos seis, para a tela saber o que dizer:
    'estado',     v_r.estado,
    'competencia', v_r.competencia,
    'sem_cpf',    (v_pac.cpf is null or btrim(v_pac.cpf) = '')
  );
end;
$$;

comment on function public.cartao_de_emissao(uuid) is
  'P8. Os seis campos do app da Receita, um a um — o app e campo a campo, e um bloco unico obrigaria a selecionar pedaco por pedaco com o dedo, que e a digitacao de volta com outro nome. A descricao sai VAZIA: campo livre que vai para a Receita Federal nao carrega nome de paciente.';


-- ---------------------------------------------------------------------
-- 4 · o pagador pessoa jurídica
-- ---------------------------------------------------------------------

create or replace function public.dispensar_por_pagador_pj(p_recibo uuid)
returns text
language plpgsql
volatile
security invoker
set search_path = ''
as $$
begin
  update public.recibos_rfb
     set estado = 'dispensado',
         dispensa_motivo = 'Quem pagou é pessoa jurídica, e o app do Receita '
                           || 'Saúde não tem campo de CNPJ. O lançamento vai '
                           || 'pelo caminho da empresa.'
   where id = p_recibo and estado in ('pendente', 'vencido');

  if not found then
    raise exception 'este recibo não está pendente';
  end if;
  return 'dispensado';
end;
$$;

comment on function public.dispensar_por_pagador_pj(uuid) is
  'P8. O caso que ninguem no mercado resolve: pagador PJ, e o app da Receita sem campo de CNPJ. O motivo e PRE-ESCRITO e continua sendo gravado — dispensa sem motivo e a pergunta sem resposta daqui a dois anos. Ver relatorio_do_pagador_pj.';


create or replace function public.relatorio_do_pagador_pj(p_ano integer)
returns table (
  paciente     text,
  competencia  date,
  pago_em      date,
  valor        numeric
)
language sql
stable
security invoker
set search_path = ''
as $$
  select p.nome, r.competencia, r.pago_em, r.valor
    from public.recibos_rfb r
    join public.pacientes p on p.id = r.paciente_id
   where r.estado = 'dispensado'
     and position('pessoa jurídica' in coalesce(r.dispensa_motivo, '')) > 0
     and extract(year from r.competencia)::int = p_ano
   order by r.pago_em;
$$;

comment on function public.relatorio_do_pagador_pj(integer) is
  'P8. O que saiu pela via da empresa no ano. Existe porque dispensa sem lista e dispensa que ninguem confere: no fim do ano ela precisa saber quanto do faturamento nao passou pelo Receita Saude, e por que.';


-- ---------------------------------------------------------------------
-- 5 · a telemetria que decide se esta build se pagou
-- ---------------------------------------------------------------------
--
-- Mede o **produto**, não a pessoa. Nenhum paciente, nenhuma sessão, nenhum
-- rastro de navegação — a mesma disciplina do `usos_do_alerta` do P5 e do blog
-- que não conta leitor. E a frase que ela produz é dirigida a mim: se a
-- mediana de dias entre o pagamento e a baixa não cair, o cartão não serviu.

create or replace function public.telemetria_do_receita_saude()
returns jsonb
language plpgsql
stable
security invoker
set search_path = ''
as $$
declare
  v_conta uuid := public.conta_atual();
  v_dias  numeric;
  v_jan   integer;
  v_marc  integer;
  v_pend  integer;
begin
  if v_conta is null then
    raise exception 'sem conta';
  end if;

  select percentile_cont(0.5) within group (
           order by (r.marcado_por_ela_em - r.pago_em)
         )
    into v_dias
    from public.recibos_rfb r
   where r.conta_id = v_conta
     and r.estado = 'marcado_por_ela'
     and r.marcado_por_ela_em is not null;

  -- Pendência que chega a janeiro é a que vai virar multa: o prazo é o último
  -- dia de fevereiro do ano seguinte, e quem chegou a janeiro sem lançar tem
  -- um mês para lançar um ano inteiro.
  select count(*)::integer into v_jan
    from public.recibos_rfb r
   where r.conta_id = v_conta
     and r.estado = 'pendente'
     and extract(year from r.competencia)::int < extract(year from public.hoje_sp())::int;

  select count(*)::integer into v_marc
    from public.recibos_rfb r
   where r.conta_id = v_conta and r.estado = 'marcado_por_ela';

  select count(*)::integer into v_pend
    from public.recibos_rfb r
   where r.conta_id = v_conta and r.estado = 'pendente';

  return jsonb_build_object(
    -- Nulo, e não zero, quando ninguém marcou nada ainda: zero dia seria a
    -- afirmação de que ela é instantânea. Mesma escolha da mediana do
    -- `resumo_do_envio_manual` da OP9.
    'dias_ate_a_baixa', v_dias,
    'pendentes_de_anos_anteriores', v_jan,
    'marcados', v_marc,
    'pendentes', v_pend
  );
end;
$$;

comment on function public.telemetria_do_receita_saude() is
  'P8. Mede o PRODUTO, nao a pessoa: nenhum paciente, nenhuma sessao, nenhum rastro de navegacao. E o instrumento do portao escrito no claude/25 — se a mediana de dias ate a baixa nao cair, o cartao nao serviu e ele e candidato a sumir.';


revoke all on function public.cartao_de_emissao(uuid) from public, anon;
revoke all on function public.dispensar_por_pagador_pj(uuid) from public, anon;
revoke all on function public.relatorio_do_pagador_pj(integer) from public, anon;
revoke all on function public.telemetria_do_receita_saude() from public, anon;

grant execute on function public.cartao_de_emissao(uuid) to authenticated, service_role;
grant execute on function public.dispensar_por_pagador_pj(uuid) to authenticated, service_role;
grant execute on function public.relatorio_do_pagador_pj(integer) to authenticated, service_role;
grant execute on function public.telemetria_do_receita_saude() to authenticated, service_role;
