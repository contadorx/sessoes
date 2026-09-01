-- 0039 · B25 — a pasta do contador (F3).
--
-- O doc 03 chama esta feature de "diferencial confirmado: vazio nos oito
-- concorrentes, e nenhum deles sequer fala do contador". A parte que interessa
-- não é o e-mail automático — é **o que vai dentro**, e sobretudo o que não vai.
--
-- ## 1. O contador recebe dinheiro, nunca gente
--
-- O doc 07 escreve a regra numa linha: "o contador recebe dados financeiros,
-- nunca clínicos — minimização escrita na feature". Aqui ela deixa de ser
-- intenção e vira estrutura: **nenhum nome de paciente entra no retrato nem no
-- CSV**, e há um teste que planta um nome improvável na base e falha se ele
-- aparecer em qualquer lugar do que sai.
--
-- Não é zelo excessivo. Numa clínica de psicologia, a lista de quem pagou **é**
-- a lista de quem faz terapia — dado pessoal sensível do artigo 5º, II da LGPD.
-- Um contador não precisa dela para escriturar um livro caixa: ele precisa de
-- datas, valores e categorias. Quem precisa saber quem pagou é a Receita, e ela
-- já sabe, pelo recibo que a psicóloga emite no Receita Saúde (B24).
--
-- Se um dia ela precisar mandar a lista identificada, existe `exportar_conta`
-- (B13) — um ato deliberado, com trilha. O que não existe é uma caixinha
-- "incluir nomes" na pasta automática, porque caixinha assim todo mundo marca.
--
-- ## 2. A pasta não passa pela fila do paciente
--
-- Seria cômodo reusar o outbox da B9. Mas aquele outbox existe para proteger
-- **paciente**: janela de silêncio, opt-out do celular, destino recalculado do
-- cadastro, gatilho que exige um paciente na inserção. Nada disso se aplica a um
-- contador, e enfiá-lo lá dentro obrigaria a afrouxar justamente o gatilho que
-- protege as outras pessoas.
--
-- São duas filas porque protegem duas pessoas diferentes — o mesmo raciocínio
-- que a B22 usou para as duas listas de espera. E há uma consequência prática
-- boa: **nenhum template novo da Meta.** Continuam catorze.
--
-- ## 3. Só mês fechado
--
-- `fechar_mes_do_contador` recusa o mês corrente. Mandar ao contador o número de
-- um mês que ainda está acontecendo é mandar um número que vai mudar — e o
-- estrago não aparece hoje, aparece quando ele escriturar por ele.
--
-- ## 4. Gerada uma vez, congelada; mudou, vira outra versão
--
-- O retrato e o CSV ficam gravados como texto. Se um pagamento atrasado entrar
-- depois do fechamento, a pasta antiga **não muda**: nasce a v2, e o resumo diz
-- que substitui a v1 e de quando ela era. Um número que muda sozinho depois de
-- enviado é a forma mais rápida de o contador parar de confiar no arquivo.
--
-- Clicar duas vezes no mesmo dia, sem nada ter mudado, devolve a mesma pasta —
-- versão nova só quando o conteúdo é outro de verdade.
--
-- ## 5. O CSV abre no Excel em português sem ninguém mexer em nada
--
-- Separador `;`, vírgula decimal, uma coluna de entrada e uma de saída (é assim
-- que um livro caixa se lê). A pasta que precisa de configuração é a pasta que
-- volta com pergunta — e a pergunta chega no dia 5, quando ela está atendendo.
--
-- ## 6. Nasce desligada
--
-- Ao contrário do modo Receita Saúde (B24), que nasce ligado, esta nasce
-- **desligada**: mandar dado para fora, para um terceiro, é ato explícito. O
-- padrão protetivo aqui aponta para o outro lado.

alter table public.contas
  add column if not exists contador_email text
    check (contador_email is null or contador_email ~ '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$'),
  add column if not exists contador_nome text
    check (contador_nome is null or length(btrim(contador_nome)) between 2 and 120),
  add column if not exists pasta_ativa boolean not null default false,
  add column if not exists pasta_dia smallint not null default 5
    check (pasta_dia between 1 and 28);

comment on column public.contas.pasta_dia is
  'Dia do mes em que a pasta do mes anterior e fechada. Ate 28: fevereiro existe.';
comment on column public.contas.pasta_ativa is
  'Nasce desligada. Mandar dado para um terceiro e ato explicito.';

-- ---------------------------------------------------------------- a tabela

create table if not exists public.pastas_contador (
  id          uuid primary key default gen_random_uuid(),
  conta_id    uuid not null references public.contas (id) on delete cascade,

  competencia date not null,
  versao      smallint not null default 1 check (versao >= 1),

  -- Os dois congelados. Depois de gravados não se recalculam.
  retrato     jsonb not null,
  csv         text not null,

  estado      text not null default 'gerada'
              check (estado in ('gerada', 'enviada', 'falhou')),
  destino     text,
  enviada_em  timestamptz,
  erro        text,
  tentativas  smallint not null default 0 check (tentativas >= 0),

  criado_em     timestamptz not null default now(),
  atualizado_em timestamptz not null default now()
);

create unique index if not exists pasta_por_competencia
  on public.pastas_contador (conta_id, competencia, versao);
create index if not exists pastas_da_conta
  on public.pastas_contador (conta_id, competencia desc, versao desc);
create index if not exists pastas_a_enviar
  on public.pastas_contador (criado_em) where estado = 'gerada';

drop trigger if exists pastas_atualizado_em on public.pastas_contador;
create trigger pastas_atualizado_em before update on public.pastas_contador
  for each row execute function public.tocar_atualizado_em();

/**
 * O conteúdo é congelado; o desfecho do envio, não.
 *
 * Sem isto, um PATCH no PostgREST reescreveria o retrato de uma pasta já
 * enviada — e aí o que está no e-mail do contador e o que está na tela deixam
 * de ser a mesma coisa, sem que ninguém perceba.
 */
create or replace function public.pasta_nao_muda()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  if new.retrato is distinct from old.retrato
     or new.csv is distinct from old.csv
     or new.competencia is distinct from old.competencia
     or new.versao is distinct from old.versao
     or new.conta_id is distinct from old.conta_id then
    raise exception 'a pasta é um fechamento: o conteúdo não se edita. Feche o mês de novo e nasce outra versão';
  end if;
  return new;
end;
$$;

drop trigger if exists pastas_imutaveis on public.pastas_contador;
create trigger pastas_imutaveis before update on public.pastas_contador
  for each row execute function public.pasta_nao_muda();

-- ------------------------------------------------------------- o CSV

/**
 * Um campo de texto no CSV.
 *
 * Sempre entre aspas, com aspas internas dobradas (RFC 4180). "Sempre" e não
 * "quando precisar" porque a descrição de uma despesa é texto que ela digitou:
 * um ponto e vírgula ali dentro quebraria a coluna no arquivo do contador, e
 * ninguém descobre isso olhando — descobre-se quando a soma dele não bate.
 *
 * O espelho em TypeScript é `escaparCsv`, em `lib/contador.ts`, e as duas
 * suítes usam a mesma string desagradável.
 */
create or replace function public.csv_campo(v text)
returns text
language sql
immutable
security invoker
set search_path = ''
as $$
  select '"' || replace(coalesce(v, ''), '"', '""') || '"';
$$;

/** 1234.50 → "1234,50". Vírgula decimal, sem separador de milhar: o Excel pt-BR soma. */
create or replace function public.csv_valor(v numeric)
returns text
language sql
immutable
security invoker
set search_path = ''
as $$
  select case when v is null then '' else replace(to_char(v, 'FM999999990.00'), '.', ',') end;
$$;

-- ------------------------------------------------------- o fechamento

/**
 * Fecha um mês para uma conta.
 *
 * `security definer` porque não existe política de INSERT em `pastas_contador`:
 * uma pasta nasce de um fechamento, nunca de um clique que escreve linha. A
 * conta vem por parâmetro porque quem chama pode ser a passada diária
 * (`service_role`, sem `conta_atual()`) ou a tela (pela função irmã abaixo).
 */
create or replace function public.fechar_mes_da_conta(p_conta uuid, p_competencia date)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  cont  record;
  prof  record;
  mes   date;
  fim   date;
  receitas jsonb;
  despesas jsonb;
  rec_total numeric := 0;  rec_n int := 0;  pessoas int := 0;
  des_total numeric := 0;  des_n int := 0;
  pend_n int := 0; emit_n int := 0;
  novo_retrato jsonb;
  novo_csv text;
  anterior record;
  proxima smallint := 1;
  -- Escalar, e não `anterior.criado_em` dentro do CASE do INSERT: ler campo de
  -- um record não atribuído estoura mesmo quando o CASE nunca chegaria lá. É a
  -- terceira vez que esta armadilha aparece (B20, B24, agora) — e a terceira em
  -- que é evitada por já estar escrita no diário.
  substitui_em timestamptz := null;
  novo uuid;
begin
  select * into cont from public.contas where id = p_conta;
  if not found then raise exception 'conta não encontrada'; end if;

  mes := date_trunc('month', p_competencia)::date;
  fim := (mes + interval '1 month - 1 day')::date;

  -- O mês corrente não fecha. Um número que ainda vai mudar não é fechamento.
  if mes >= date_trunc('month', public.hoje_sp())::date then
    raise exception 'este mês ainda não terminou: fechar um mês que está acontecendo é mandar ao contador um número que vai mudar';
  end if;

  select pr.*, u.nome as prof_nome into prof
    from public.profissionais pr
    join public.usuarios u on u.id = pr.usuario_id
   where pr.conta_id = p_conta
   order by pr.criado_em
   limit 1;

  -- ------------------------------------------------------------- receitas
  -- Regime de caixa: a data que vale é a do pagamento (B23).
  select coalesce(sum(cb.valor), 0), count(*), count(distinct cb.paciente_id)
    into rec_total, rec_n, pessoas
    from public.cobrancas cb
   where cb.conta_id = p_conta
     and cb.estado = 'paga'
     and cb.paga_em is not null
     and (cb.paga_em at time zone 'America/Sao_Paulo')::date between mes and fim;

  select coalesce(jsonb_object_agg(t.tipo, t.soma), '{}'::jsonb)
    into receitas
    from (
      select cb.tipo, sum(cb.valor) as soma
        from public.cobrancas cb
       where cb.conta_id = p_conta and cb.estado = 'paga' and cb.paga_em is not null
         and (cb.paga_em at time zone 'America/Sao_Paulo')::date between mes and fim
       group by cb.tipo
    ) t;

  -- ------------------------------------------------------------- despesas
  select coalesce(sum(d.valor), 0), count(*)
    into des_total, des_n
    from public.despesas d
   where d.conta_id = p_conta and d.paga_em between mes and fim;

  select coalesce(jsonb_object_agg(g.categoria, g.soma), '{}'::jsonb)
    into despesas
    from (
      select d.categoria, sum(d.valor) as soma
        from public.despesas d
       where d.conta_id = p_conta and d.paga_em between mes and fim
       group by d.categoria
    ) g;

  -- --------------------------------------------------------------- fiscal
  select
    count(*) filter (where estado = 'pendente'),
    count(*) filter (where estado = 'emitido')
    into pend_n, emit_n
    from public.recibos_rfb
   where conta_id = p_conta and competencia between mes and fim;

  -- -------------------------------------------------------------- retrato
  -- Repare no que **não** está aqui: paciente, sessão, diagnóstico, telefone.
  -- O contador recebe o dinheiro, e o dinheiro não tem nome.
  novo_retrato := jsonb_build_object(
    'competencia', to_char(mes, 'YYYY-MM'),
    'de', mes,
    'ate', fim,
    'conta', jsonb_build_object('nome', cont.nome, 'cidade', cont.cidade),
    'profissional', jsonb_build_object(
      'nome', coalesce(prof.assina_como, prof.prof_nome),
      'documento', prof.documento
    ),
    'receitas', jsonb_build_object(
      'total', rec_total, 'lancamentos', rec_n, 'pessoas', pessoas, 'por_tipo', receitas
    ),
    'despesas', jsonb_build_object(
      'total', des_total, 'lancamentos', des_n, 'por_categoria', despesas
    ),
    'sobra', rec_total - des_total,
    'fiscal', jsonb_build_object(
      'recibos_pendentes', pend_n,
      'recibos_emitidos', emit_n,
      'prazo_receita_saude', public.prazo_do_ano(extract(year from mes)::int)
    ),
    'aviso', 'Regime de caixa: as datas são as do pagamento. Sem identificação de pacientes, por minimização (LGPD art. 5º, II).'
  );

  -- ------------------------------------------------------------------ CSV
  select
    'data;tipo;descricao;entrada;saida' || E'\n' ||
    coalesce(string_agg(linha, E'\n' order by ordem, linha), '')
    into novo_csv
    from (
      select
        (cb.paga_em at time zone 'America/Sao_Paulo')::date as ordem,
        to_char((cb.paga_em at time zone 'America/Sao_Paulo')::date, 'DD/MM/YYYY') || ';' ||
        public.csv_campo('Receita') || ';' ||
        public.csv_campo(case cb.tipo
                           when 'sessao' then 'Atendimento'
                           when 'mensalidade' then 'Mensalidade'
                           when 'pacote' then 'Pacote de sessões'
                           when 'falta' then 'Compensação por cancelamento'
                           else cb.tipo end) || ';' ||
        public.csv_valor(cb.valor) || ';' as linha
        from public.cobrancas cb
       where cb.conta_id = p_conta and cb.estado = 'paga' and cb.paga_em is not null
         and (cb.paga_em at time zone 'America/Sao_Paulo')::date between mes and fim

      union all

      select
        d.paga_em as ordem,
        to_char(d.paga_em, 'DD/MM/YYYY') || ';' ||
        public.csv_campo('Despesa') || ';' ||
        public.csv_campo(d.categoria || ' · ' || d.descricao) || ';' ||
        ';' || public.csv_valor(d.valor) as linha
        from public.despesas d
       where d.conta_id = p_conta and d.paga_em between mes and fim
    ) linhas;

  -- ------------------------------------------------- já existe igual a esta?
  select * into anterior
    from public.pastas_contador
   where conta_id = p_conta and competencia = mes
   order by versao desc
   limit 1;

  if found then
    -- Clicar de novo sem nada ter mudado devolve a mesma pasta: versão nova só
    -- quando o conteúdo é outro, senão a v7 de agosto não quer dizer nada.
    -- `versao` e `substitui` entram só na gravação, então saem da comparação.
    if anterior.csv = novo_csv
       and (anterior.retrato - 'versao' - 'substitui') = novo_retrato then
      return anterior.id;
    end if;
    proxima := anterior.versao + 1;
    substitui_em := anterior.criado_em;
  end if;

  insert into public.pastas_contador (conta_id, competencia, versao, retrato, csv, destino)
  values (
    p_conta, mes, proxima,
    novo_retrato || jsonb_build_object(
      'versao', proxima,
      'substitui', substitui_em
    ),
    novo_csv,
    cont.contador_email
  )
  returning id into novo;

  return novo;
end;
$$;

/** A mesma coisa, pela tela: a conta é a de quem está logada. */
create or replace function public.fechar_mes_do_contador(p_competencia date)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  c uuid := public.conta_atual();
begin
  if c is null then raise exception 'sem conta'; end if;
  return public.fechar_mes_da_conta(c, p_competencia);
end;
$$;

/**
 * Quem fecha o mês num determinado dia.
 *
 * Separada da passada por causa de um teste que não conseguia rodar: como
 * `pasta_dia` vai só até 28 (fevereiro existe), no dia 31 nenhuma conta pode ter
 * "hoje" como o dia dela, e o caminho positivo da passada ficava sem como ser
 * exercitado três dias por mês. Uma regra que só dá para testar em 28 dos 31
 * dias não é uma regra testada.
 *
 * Vira a mesma solução da B7: **a regra é uma função que responde sozinha**, e
 * a rotina só a chama com o dia de hoje. De quebra, dias 29, 30 e 31 nunca
 * pertencem a ninguém — e isso agora é uma frase verificável, não uma nota.
 */
create or replace function public.contas_para_fechar(p_dia smallint)
returns table (conta_id uuid)
language sql
stable
security definer
set search_path = ''
as $$
  select id from public.contas
   where pasta_ativa
     and contador_email is not null
     and pasta_dia = p_dia;
$$;

/**
 * A passada diária: fecha o mês anterior para quem marcou hoje como o dia.
 *
 * Roda todo dia e só age no dia escolhido por cada conta. Rodar duas vezes no
 * mesmo dia não gera duas pastas — o fechamento devolve a mesma quando nada
 * mudou, e é essa propriedade que torna seguro reexecutar o cron à mão.
 */
create or replace function public.gerar_pastas_do_dia()
returns int
language plpgsql
security definer
set search_path = ''
as $$
declare
  mes  date := (date_trunc('month', public.hoje_sp()) - interval '1 month')::date;
  c    record;
  n    int := 0;
begin
  for c in
    select f.conta_id as id
      from public.contas_para_fechar(extract(day from public.hoje_sp())::smallint) f
  loop
    begin
      perform public.fechar_mes_da_conta(c.id, mes);
      n := n + 1;
    exception when others then
      -- Uma conta com problema não pode derrubar a passada das outras.
      raise warning 'pasta do contador falhou para a conta %: %', c.id, sqlerrm;
    end;
  end loop;

  return n;
end;
$$;

-- --------------------------------------------------------------- o envio

/** O que o worker precisa mandar. Só o que tem para onde ir. */
create or replace function public.pastas_a_enviar(p_limite int default 20)
returns table (
  id      uuid,
  destino text,
  assunto text,
  retrato jsonb,
  csv     text,
  arquivo text
)
language sql
stable
security invoker
set search_path = ''
as $$
  select p.id,
         p.destino,
         'Pasta do contador · ' || (p.retrato->>'competencia') ||
           case when p.versao > 1 then ' (v' || p.versao || ')' else '' end,
         p.retrato,
         p.csv,
         'sessoes-' || (p.retrato->>'competencia') ||
           case when p.versao > 1 then '-v' || p.versao else '' end || '.csv'
    from public.pastas_contador p
   where p.estado = 'gerada'
     and p.destino is not null
     and p.tentativas < 5
   order by p.criado_em
   limit p_limite;
$$;

create or replace function public.marcar_pasta_enviada(p_pasta uuid)
returns void
language sql
security invoker
set search_path = ''
as $$
  update public.pastas_contador
     set estado = 'enviada', enviada_em = now(), erro = null
   where id = p_pasta and estado = 'gerada';
$$;

create or replace function public.marcar_pasta_falhou(p_pasta uuid, p_erro text)
returns void
language sql
security invoker
set search_path = ''
as $$
  update public.pastas_contador
     set tentativas = tentativas + 1,
         erro = left(coalesce(p_erro, ''), 300),
         estado = case when tentativas + 1 >= 5 then 'falhou' else 'gerada' end
   where id = p_pasta;
$$;

-- ---------------------------------------------------------------- RLS

alter table public.pastas_contador enable row level security;

drop policy if exists "pastas da conta: ler" on public.pastas_contador;
create policy "pastas da conta: ler" on public.pastas_contador
  for select to authenticated
  using (conta_id = public.conta_atual());

-- Sem INSERT, sem UPDATE e sem DELETE para a tela: a pasta nasce de um
-- fechamento e o desfecho do envio é do worker. Um fechamento que a tela
-- escreve é um fechamento que a tela pode escrever errado.

-- ---------------------------------------------------------------- grants

revoke execute on function public.pasta_nao_muda() from public, anon, authenticated;
revoke execute on function public.csv_campo(text) from public, anon;
revoke execute on function public.csv_valor(numeric) from public, anon;
revoke execute on function public.fechar_mes_da_conta(uuid, date) from public, anon, authenticated;
revoke execute on function public.fechar_mes_do_contador(date) from public, anon;
revoke execute on function public.contas_para_fechar(smallint) from public, anon, authenticated;
revoke execute on function public.gerar_pastas_do_dia() from public, anon, authenticated;
revoke execute on function public.pastas_a_enviar(int) from public, anon, authenticated;
revoke execute on function public.marcar_pasta_enviada(uuid) from public, anon, authenticated;
revoke execute on function public.marcar_pasta_falhou(uuid, text) from public, anon, authenticated;

grant execute on function public.csv_campo(text) to authenticated;
grant execute on function public.csv_valor(numeric) to authenticated;
grant execute on function public.fechar_mes_do_contador(date) to authenticated;
grant execute on function public.fechar_mes_da_conta(uuid, date) to service_role;
grant execute on function public.contas_para_fechar(smallint) to service_role;
grant execute on function public.gerar_pastas_do_dia() to service_role;
grant execute on function public.pastas_a_enviar(int) to service_role;
grant execute on function public.marcar_pasta_enviada(uuid) to service_role;
grant execute on function public.marcar_pasta_falhou(uuid, text) to service_role;

comment on table public.pastas_contador is
  'F3: fechamento mensal congelado. Dinheiro sem nome: nenhum paciente aparece no retrato nem no CSV.';

-- ------------------------------------------ a pasta sai junto (LGPD/B13)

/**
 * Portabilidade é levar tudo, e a pasta é dela: o fechamento de cada mês, com
 * o CSV que foi para o contador. Se ficasse de fora, "tudo" viraria "quase
 * tudo" — e faltaria justamente o histórico que ela mostraria a um contador
 * novo.
 */
create or replace function public.exportar_conta()
returns jsonb
language plpgsql
security invoker
set search_path = ''
as $$
declare
  c uuid := public.conta_atual();
  saida jsonb;
begin
  if c is null then raise exception 'sem conta'; end if;

  select jsonb_build_object(
    'gerado_em', now(),
    'aviso', 'Contém dado pessoal sensível. Guarde como guardaria o armário do consultório.',
    'conta', (select to_jsonb(x) from public.contas x where x.id = c),
    'profissionais', (select coalesce(jsonb_agg(to_jsonb(p)), '[]'::jsonb)
                        from public.profissionais p where p.conta_id = c),
    'pacientes', (select coalesce(jsonb_agg(to_jsonb(p) order by p.nome), '[]'::jsonb)
                    from public.pacientes p where p.conta_id = c),
    'enquadres', (select coalesce(jsonb_agg(to_jsonb(e)), '[]'::jsonb)
                    from public.enquadres e where e.conta_id = c),
    'sessoes', (select coalesce(jsonb_agg(to_jsonb(s) order by s.inicio), '[]'::jsonb)
                  from public.sessoes s where s.conta_id = c),
    'excecoes_agenda', (select coalesce(jsonb_agg(to_jsonb(x)), '[]'::jsonb)
                          from public.excecoes_agenda x where x.conta_id = c),
    'fila_encaixe', (select coalesce(jsonb_agg(to_jsonb(f)), '[]'::jsonb)
                       from public.fila_encaixe f where f.conta_id = c),
    'ofertas', (select coalesce(jsonb_agg(to_jsonb(o)), '[]'::jsonb)
                  from public.ofertas o where o.conta_id = c),
    'eventos_fila', (select coalesce(jsonb_agg(to_jsonb(ev)), '[]'::jsonb)
                       from public.eventos_fila ev where ev.conta_id = c),
    'cobrancas', (select coalesce(jsonb_agg(to_jsonb(cb)), '[]'::jsonb)
                    from public.cobrancas cb where cb.conta_id = c),
    'despesas', (select coalesce(jsonb_agg(to_jsonb(d) - 'conta_id' order by d.paga_em), '[]'::jsonb)
                   from public.despesas d where d.conta_id = c),
    'recibos_rfb', (select coalesce(jsonb_agg(to_jsonb(rf) - 'conta_id' order by rf.pago_em), '[]'::jsonb)
                      from public.recibos_rfb rf where rf.conta_id = c),
    'pastas_contador', (select coalesce(jsonb_agg(to_jsonb(pc) - 'conta_id'
                                        order by pc.competencia, pc.versao), '[]'::jsonb)
                          from public.pastas_contador pc where pc.conta_id = c),
    'contratos', (select coalesce(jsonb_agg(to_jsonb(ct) - 'conta_id' order by ct.versao), '[]'::jsonb)
                    from public.contratos ct where ct.conta_id = c),
    'aceites', (select coalesce(jsonb_agg(to_jsonb(a) - 'conta_id' - 'token' order by a.criado_em), '[]'::jsonb)
                  from public.aceites a where a.conta_id = c),
    'trilha_acesso', (select coalesce(jsonb_agg(to_jsonb(t) order by t.em), '[]'::jsonb)
                        from public.trilha_acesso t where t.conta_id = c)
  ) into saida;

  insert into public.trilha_acesso (conta_id, acao, detalhe)
  values (c, 'exportou_conta', '{}'::jsonb);

  return saida;
end;
$$;

revoke execute on function public.exportar_conta() from public, anon;
grant  execute on function public.exportar_conta() to authenticated;
