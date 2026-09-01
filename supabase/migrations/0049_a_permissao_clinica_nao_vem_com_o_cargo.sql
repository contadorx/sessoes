-- =====================================================================
-- 0049 · A permissão clínica não vem com o cargo
-- =====================================================================
--
-- POR QUE ESTA MIGRAÇÃO EXISTE
--
-- Uma auditoria externa olhou o menu do aplicativo e escreveu a frase que
-- fecha o assunto: *"a secretária vê as mesmas doze abas, inclusive as que ela
-- não deveria usar"*. Fui conferir no banco esperando que fosse só menu. Não
-- era.
--
--     select tablename, policyname, qual from pg_policies
--      where schemaname = 'public' and tablename = 'evolucoes';
--     -- "evolucoes da conta: ler"  →  conta_id = conta_atual()
--
-- A coluna `usuarios.papel` existe desde a 0002, com 'dona', 'profissional' e
-- 'secretaria'. A função `papel_atual()` existe. E **nenhuma tabela clínica a
-- consultava**. Numa clínica com uma secretária cadastrada, ela lê evolução,
-- anamnese e registro clínico de todos os pacientes de todos os profissionais,
-- porque a única pergunta que a RLS fazia era "é da mesma conta?".
--
-- Isso não é excesso de menu. É a fronteira 6 do doc 11 — *o contador vê
-- finanças, nunca clínica* — valendo para o contador e não valendo para quem
-- senta na recepção. E é pior que o caso do contador, porque a pasta do
-- contador foi construída com minimização de dados por construção enquanto
-- este caminho ficou aberto por omissão.
--
--
-- A REGRA, EM UMA LINHA
--
--     **Acesso clínico não vem junto com o cargo administrativo.**
--
-- Quem marca a agenda não precisa ler a sessão. Quem confere o Pix não precisa
-- saber a demanda. São dois eixos independentes, e é assim que eles passam a
-- existir aqui: `acesso_clinico` e `acesso_financeiro`, cada um separado do
-- outro e os dois separados do `papel`.
--
--
-- POR QUE AS COLUNAS SÃO NULÁVEIS, E ISSO É DE PROPÓSITO
--
-- `boolean not null default true` erraria em toda conta que já existe: a
-- secretária nasceria com acesso clínico e alguém teria que lembrar de tirar.
-- `default false` erraria do outro lado: toda dona perderia o próprio
-- prontuário na hora do deploy.
--
-- Então as colunas são `boolean` **nulas**, e nulo quer dizer *"não foi
-- decidido, use o padrão do papel"*:
--
--     papel           clínico   financeiro
--     dona              sim        sim
--     profissional      sim        não      (atende; o dinheiro é da clínica)
--     administradora    não        sim      (o cargo novo desta migração)
--     secretaria        não        não
--
-- Um valor explícito na coluna ganha do padrão, nos dois sentidos: a dona pode
-- conceder financeiro a uma secretária que já cuida da conciliação, e pode
-- tirar o clínico de uma profissional que saiu da clínica sem apagar o
-- histórico. É isso que faz os dois eixos serem de fato independentes, em vez
-- de dois nomes para a mesma escada de cargos.
--
--
-- POR QUE UM GATILHO, E NÃO SÓ A RLS DA `usuarios`
--
-- A política de UPDATE de `usuarios` diz, desde a 0002:
--
--     (conta_id = conta_atual()) and (papel_atual() = 'dona' or auth_user_id = auth.uid())
--
-- O segundo ramo existe para a pessoa poder trocar o próprio nome. Com as
-- colunas novas ele viraria outra coisa: a secretária dá
-- `update usuarios set acesso_clinico = true where auth_user_id = auth.uid()`
-- e passa a ler prontuário. Permissão que o sujeito se concede não é permissão.
--
-- O gatilho fecha as duas portas: mudar papel/acesso exige ser a dona, **e**
-- não vale para a própria linha. A dona continua concedendo para as outras;
-- ninguém amplia o próprio acesso, ela inclusive.
--
-- Ele repete de propósito a lição da 0045c/0045d: dentro de `security
-- definer`, `current_user` é o dono da função e `session_user` é a conexão —
-- só `current_setting('role', true)` diz quem chamou. E a lição da 0041: o
-- plpgsql **não** faz curto-circuito, então nada de `old.` antes de saber que
-- é UPDATE.
--
--
-- ESCONDER A ABA NÃO É AUTORIZAR
--
-- A auditoria também escreveu isso, e é o motivo de esta migração vir antes da
-- tela: *"esconder uma aba também não basta; a autorização precisa existir no
-- servidor e nas exportações"*. Por isso o corte é na RLS e não no menu.
--
-- Ele pega de graça o caminho que mais me preocupava: `exportar_conta` e
-- `exportar_paciente` são `security invoker`, então a RLS vale dentro delas.
-- Uma secretária que baixe a exportação inteira recebe o arquivo **sem** as
-- evoluções, sem as anamneses e sem os registros — não porque o JSON as
-- esconde, mas porque o `select` não as enxergou. Um arquivo que vaza é a
-- forma mais silenciosa desse erro, e é a que nenhum teste de tela pegaria.
--
--
-- O QUE ESTA MIGRAÇÃO NÃO FAZ
--
-- Não separa prontuário *entre profissionais* da mesma clínica — a fronteira
-- "sigilo entre profissionais por construção" do plano Clínica continua sendo
-- trabalho futuro, e continua honesta na landing porque lá ela é promessa de
-- plano, não descrição de tela. O que muda hoje é o eixo administrativo, que
-- é onde o buraco estava aberto.
--
-- Não mexe em `pacientes`, `sessoes` nem `enquadres`: quem marca a agenda
-- precisa do nome, do horário e do valor combinado. Tirar isso não protegeria
-- ninguém e devolveria o trabalho para a psicóloga — que é exatamente o
-- contra-argumento que a própria auditoria levantou contra si mesma na
-- passagem 3, e que eu aceito.
-- =====================================================================

begin;

-- ---------------------------------------------------------------- o cargo novo
--
-- 'administradora' é o cargo da clínica que cuida de operação e dinheiro sem
-- ser profissional. Sem ele, quem faz esse trabalho hoje só cabe em
-- 'secretaria' (e aí não vê o financeiro) ou em 'dona' (e aí vê tudo).

alter table public.usuarios drop constraint if exists usuarios_papel_check;
alter table public.usuarios add constraint usuarios_papel_check
  check (papel in ('dona', 'profissional', 'administradora', 'secretaria'));

-- ------------------------------------------------------------- os dois eixos
--
-- Nulo = "usa o padrão do papel". Ver o quadro no cabeçalho.

alter table public.usuarios add column if not exists acesso_clinico boolean;
alter table public.usuarios add column if not exists acesso_financeiro boolean;

comment on column public.usuarios.acesso_clinico is
  'Lê evolução, anamnese e registro clínico. Nulo = padrão do papel (dona e profissional sim; administradora e secretaria não). Concedido só pela dona, nunca pela própria pessoa.';
comment on column public.usuarios.acesso_financeiro is
  'Lê cobrança, recebimento, documento fiscal e pasta do contador. Nulo = padrão do papel (dona e administradora sim; profissional e secretaria não).';

-- --------------------------------------------------------- quem pode o quê
--
-- `security definer` porque a própria consulta a `usuarios` passaria pela RLS
-- de `usuarios` e daria recursão. `stable` porque não muda dentro da consulta.
-- `set search_path = ''` porque tudo aqui é qualificado.
--
-- Sem sessão o resultado é `false`, não nulo: numa cláusula de RLS, nulo e
-- falso barram igual, mas `false` é o que eu quero poder afirmar em teste.

create or replace function public.le_clinico()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(
           bool_or(coalesce(u.acesso_clinico, u.papel in ('dona', 'profissional'))),
           false)
    from public.usuarios u
   where u.auth_user_id = (select auth.uid());
$$;

create or replace function public.ve_financeiro()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(
           bool_or(coalesce(u.acesso_financeiro, u.papel in ('dona', 'administradora'))),
           false)
    from public.usuarios u
   where u.auth_user_id = (select auth.uid());
$$;

comment on function public.le_clinico() is
  'A pessoa logada pode ler prontuário. Gêmeo de podeClinico() em lib/permissao.ts.';
comment on function public.ve_financeiro() is
  'A pessoa logada pode ler dinheiro. Gêmeo de podeFinanceiro() em lib/permissao.ts.';

-- ------------------------------------------------ ninguém amplia o próprio acesso

create or replace function public.permissao_nao_se_autoconcede()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  -- Só o `role` diz quem chamou de fato. Lição da 0045d, e ela custou três
  -- tentativas: dentro de `security definer`, `current_user` é o dono da
  -- função e `session_user` é a conexão do PostgREST.
  papel_da_conexao text := coalesce(current_setting('role', true), 'none');
  mudou boolean := false;
begin
  -- Fora do PostgREST (service_role, postgres, migração) nada disto se aplica:
  -- é o caminho por onde a conta nasce e por onde eu conserto.
  if papel_da_conexao not in ('authenticated', 'anon') then
    return new;
  end if;

  if tg_op = 'INSERT' then
    -- Convidar alguém já com acesso é concessão, e passa pela dona igual.
    if new.papel <> 'dona'
       and (new.acesso_clinico is true or new.acesso_financeiro is true) then
      if public.papel_atual() is distinct from 'dona' then
        raise exception 'quem concede acesso é a dona da conta';
      end if;
    end if;
    return new;
  end if;

  -- plpgsql não faz curto-circuito: `old.` só depois de saber que é UPDATE.
  if tg_op = 'UPDATE' then
    mudou := (new.papel is distinct from old.papel)
          or (new.acesso_clinico is distinct from old.acesso_clinico)
          or (new.acesso_financeiro is distinct from old.acesso_financeiro);

    if not mudou then
      return new;
    end if;

    if public.papel_atual() is distinct from 'dona' then
      raise exception 'quem concede acesso é a dona da conta';
    end if;

    -- E nem a dona em si mesma. Permissão que o sujeito se concede não é
    -- permissão — é a diferença entre uma porta e a foto de uma porta.
    if new.auth_user_id = (select auth.uid()) then
      raise exception 'ninguém amplia o próprio acesso';
    end if;
  end if;

  return new;
end;
$$;

drop trigger if exists permissao_nao_se_autoconcede on public.usuarios;
create trigger permissao_nao_se_autoconcede
  before insert or update on public.usuarios
  for each row execute function public.permissao_nao_se_autoconcede();

-- =====================================================================
-- A RLS clínica
--
-- Todas as políticas abaixo são reescritas inteiras, com a cláusula de conta
-- **preservada exatamente como está no banco hoje** (lida de `pg_policies`,
-- não da migração que a criou — lição da 0046d, que me custou uma regressão
-- real). O que se acrescenta é o `and public.le_clinico()`.
-- =====================================================================

-- evolucoes -----------------------------------------------------------------
drop policy if exists "evolucoes da conta: ler" on public.evolucoes;
create policy "evolucoes da conta: ler" on public.evolucoes
  for select to authenticated
  using (conta_id = (select public.conta_atual()) and public.le_clinico());

drop policy if exists "evolucoes da conta: criar" on public.evolucoes;
create policy "evolucoes da conta: criar" on public.evolucoes
  for insert to authenticated
  with check (conta_id = (select public.conta_atual()) and public.le_clinico());

drop policy if exists "evolucoes da conta: editar" on public.evolucoes;
create policy "evolucoes da conta: editar" on public.evolucoes
  for update to authenticated
  using (conta_id = (select public.conta_atual()) and public.le_clinico())
  with check (conta_id = (select public.conta_atual()) and public.le_clinico());

-- anamneses -----------------------------------------------------------------
drop policy if exists "anamneses da conta: ler" on public.anamneses;
create policy "anamneses da conta: ler" on public.anamneses
  for select to authenticated
  using (conta_id = (select public.conta_atual()) and public.le_clinico());

drop policy if exists "anamneses da conta: criar" on public.anamneses;
create policy "anamneses da conta: criar" on public.anamneses
  for insert to authenticated
  with check (conta_id = (select public.conta_atual()) and public.le_clinico());

drop policy if exists "anamneses da conta: editar" on public.anamneses;
create policy "anamneses da conta: editar" on public.anamneses
  for update to authenticated
  using (conta_id = (select public.conta_atual()) and public.le_clinico())
  with check (conta_id = (select public.conta_atual()) and public.le_clinico());

-- anamnese_adendos ----------------------------------------------------------
drop policy if exists "adendos da conta: ler" on public.anamnese_adendos;
create policy "adendos da conta: ler" on public.anamnese_adendos
  for select to authenticated
  using (conta_id = (select public.conta_atual()) and public.le_clinico());

drop policy if exists "adendos da conta: criar" on public.anamnese_adendos;
create policy "adendos da conta: criar" on public.anamnese_adendos
  for insert to authenticated
  with check (conta_id = (select public.conta_atual()) and public.le_clinico());

-- registros -----------------------------------------------------------------
drop policy if exists "registros da conta: ler" on public.registros;
create policy "registros da conta: ler" on public.registros
  for select to authenticated
  using (conta_id = (select public.conta_atual()) and public.le_clinico());

drop policy if exists "registros da conta: criar" on public.registros;
create policy "registros da conta: criar" on public.registros
  for insert to authenticated
  with check (conta_id = (select public.conta_atual()) and public.le_clinico());

drop policy if exists "registros da conta: editar" on public.registros;
create policy "registros da conta: editar" on public.registros
  for update to authenticated
  using (conta_id = (select public.conta_atual()) and public.le_clinico())
  with check (conta_id = (select public.conta_atual()) and public.le_clinico());

-- trilha_acesso -------------------------------------------------------------
--
-- A leitura fecha junto com o clínico: a trilha diz *quem abriu o prontuário
-- de quem*, e o nome do paciente ao lado do nome do profissional é
-- informação clínica com outra roupa.
--
-- A escrita continua aberta de propósito. Trilha é registro de fato
-- consumado, e uma trilha que pode falhar por permissão é uma trilha que se
-- burla desligando o acesso.

drop policy if exists "trilha da conta: ler" on public.trilha_acesso;
create policy "trilha da conta: ler" on public.trilha_acesso
  for select to authenticated
  using (conta_id = public.conta_atual() and public.le_clinico());

-- =====================================================================
-- A RLS financeira
-- =====================================================================

-- cobrancas -----------------------------------------------------------------
drop policy if exists "cobranças da conta: ler" on public.cobrancas;
create policy "cobranças da conta: ler" on public.cobrancas
  for select to authenticated
  using (conta_id = public.conta_atual() and public.ve_financeiro());

drop policy if exists "cobranças da conta: criar" on public.cobrancas;
create policy "cobranças da conta: criar" on public.cobrancas
  for insert to authenticated
  with check (conta_id = public.conta_atual() and public.ve_financeiro());

drop policy if exists "cobranças da conta: editar" on public.cobrancas;
create policy "cobranças da conta: editar" on public.cobrancas
  for update to authenticated
  using (conta_id = public.conta_atual() and public.ve_financeiro())
  with check (conta_id = public.conta_atual() and public.ve_financeiro());

-- despesas ------------------------------------------------------------------
drop policy if exists "despesas da conta: ler" on public.despesas;
create policy "despesas da conta: ler" on public.despesas
  for select to authenticated
  using (conta_id = public.conta_atual() and public.ve_financeiro());

drop policy if exists "despesas da conta: criar" on public.despesas;
create policy "despesas da conta: criar" on public.despesas
  for insert to authenticated
  with check (conta_id = public.conta_atual() and public.ve_financeiro());

drop policy if exists "despesas da conta: editar" on public.despesas;
create policy "despesas da conta: editar" on public.despesas
  for update to authenticated
  using (conta_id = public.conta_atual() and public.ve_financeiro())
  with check (conta_id = public.conta_atual() and public.ve_financeiro());

drop policy if exists "despesas da conta: apagar" on public.despesas;
create policy "despesas da conta: apagar" on public.despesas
  for delete to authenticated
  using (conta_id = public.conta_atual() and public.ve_financeiro());

-- documentos ----------------------------------------------------------------
--
-- Recibo, declaração de comparecimento e informe anual. Nenhum deles carrega
-- narrativa clínica — por isso o eixo aqui é o financeiro, e não o clínico.
-- Se um dia entrar declaração com conteúdo de sessão, o corte muda de eixo e
-- esta é a linha que tem de mudar junto.

drop policy if exists "documentos da conta: ler" on public.documentos;
create policy "documentos da conta: ler" on public.documentos
  for select to authenticated
  using (conta_id = public.conta_atual() and public.ve_financeiro());

drop policy if exists "documentos da conta: emitir" on public.documentos;
create policy "documentos da conta: emitir" on public.documentos
  for insert to authenticated
  with check (conta_id = public.conta_atual() and public.ve_financeiro());

drop policy if exists "documentos da conta: cancelar" on public.documentos;
create policy "documentos da conta: cancelar" on public.documentos
  for update to authenticated
  using (conta_id = public.conta_atual() and public.ve_financeiro())
  with check (conta_id = public.conta_atual() and public.ve_financeiro());

-- recibos_rfb ---------------------------------------------------------------
drop policy if exists "recibos rfb da conta: ler" on public.recibos_rfb;
create policy "recibos rfb da conta: ler" on public.recibos_rfb
  for select to authenticated
  using (conta_id = public.conta_atual() and public.ve_financeiro());

drop policy if exists "recibos rfb da conta: editar" on public.recibos_rfb;
create policy "recibos rfb da conta: editar" on public.recibos_rfb
  for update to authenticated
  using (conta_id = public.conta_atual() and public.ve_financeiro())
  with check (conta_id = public.conta_atual() and public.ve_financeiro());

-- pastas_contador -----------------------------------------------------------
drop policy if exists "pastas da conta: ler" on public.pastas_contador;
create policy "pastas da conta: ler" on public.pastas_contador
  for select to authenticated
  using (conta_id = public.conta_atual() and public.ve_financeiro());

-- pacotes e consumos --------------------------------------------------------
drop policy if exists "pacotes da conta: ler" on public.pacotes;
create policy "pacotes da conta: ler" on public.pacotes
  for select to authenticated
  using (conta_id = public.conta_atual() and public.ve_financeiro());

drop policy if exists "pacotes da conta: escrever" on public.pacotes;
create policy "pacotes da conta: escrever" on public.pacotes
  for insert to authenticated
  with check (conta_id = public.conta_atual() and public.ve_financeiro());

drop policy if exists "pacotes da conta: editar" on public.pacotes;
create policy "pacotes da conta: editar" on public.pacotes
  for update to authenticated
  using (conta_id = public.conta_atual() and public.ve_financeiro())
  with check (conta_id = public.conta_atual() and public.ve_financeiro());

drop policy if exists "consumos da conta: ler" on public.pacote_consumos;
create policy "consumos da conta: ler" on public.pacote_consumos
  for select to authenticated
  using (conta_id = public.conta_atual() and public.ve_financeiro());

-- eventos_pagamento ---------------------------------------------------------
drop policy if exists "eventos de pagamento da conta: ler" on public.eventos_pagamento;
create policy "eventos de pagamento da conta: ler" on public.eventos_pagamento
  for select to authenticated
  using (conta_id is not null and conta_id = public.conta_atual() and public.ve_financeiro());

commit;
