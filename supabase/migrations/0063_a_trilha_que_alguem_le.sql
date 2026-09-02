-- 0063 · A trilha que alguém lê (B33, metade 1).
--
-- A `trilha_acesso` existe desde a B13. É gravada, é carimbada pelo servidor, é
-- append-only, e **não aceita edição nem exclusão nem pela conta que a gerou** —
-- é isso que a torna defesa em vez de anotação. A página `/seguranca` promete
-- essa propriedade em voz alta desde 01/09.
--
-- O que nunca existiu é a psicóloga poder **ler a própria**. A mesma página
-- admite isso com todas as letras: *"A tela em que você lê a sua própria trilha
-- ainda não existe."*
--
-- ## Registro que ninguém lê é registro que só serve depois do problema
--
-- E hoje isso deixou de ser argumento de doc para ser fato observado. A 0060
-- apagou, sem querer, o `insert` que grava `exportou_conta` — **a exportação da
-- conta parou de deixar rastro por três horas**, e ninguém teria notado se a
-- verificação 11 da suíte 0024 não olhasse o corpo da função.
--
-- Uma trilha que só uma suíte lê é uma suíte, não uma trilha. A tela é o que
-- transforma a propriedade em prática — e é também o que faz a psicóloga
-- descobrir sozinha o dia em que algo parar de ser gravado.
--
-- ## Três decisões
--
-- **1 · A leitura exige acesso clínico, e não o papel de dona.** A trilha diz
-- quem abriu a ficha de quem — o nome do paciente está nela. Desde a 0049 o
-- acesso clínico não vem com o cargo, e quem não pode ler prontuário não pode
-- ler a lista de quem leu prontuário. A recusa é explícita e não silenciosa:
-- policy ausente devolve zero linhas, e zero linhas numa tela de auditoria é
-- indistinguível de "ninguém acessou nada".
--
-- **2 · Devolve o nome de quem olhou, e não o `auth_user_id`.** A trilha guarda
-- o id porque ele sobrevive à saída da pessoa da conta; a tela precisa do nome,
-- e quando a pessoa já saiu precisa dizer isso em vez de mostrar um uuid.
--
-- **3 · Não há filtro por ação na assinatura.** Poderia haver, e é justamente
-- por isso que não há: uma tela de auditoria com filtro por tipo de evento é uma
-- tela onde o evento inconveniente é o que ninguém marca. O recorte é por
-- período e, opcionalmente, por paciente — as duas perguntas que alguém faz
-- quando desconfia de alguma coisa.
--
-- ## O que esta migração NÃO faz
--
--   · **não deixa apagar nada.** Não há `update`, não há `delete`, não há
--     "limpar trilha antiga". A retenção da trilha é a da conta;
--   · **não mostra a trilha ao paciente.** Ele ver quem leu a ficha dele é a
--     pergunta certa e a resposta é da conversa com a psicóloga, não minha —
--     está registrado como fora de escopo no doc 20;
--   · **não exporta a trilha em separado.** Ela já sai inteira em
--     `exportar_conta`, desde a B13.

-- ============================================================ a leitura

/**
 * A trilha da conta, no período.
 *
 * `security definer` com recusa explícita, e não `invoker`: a policy de leitura
 * exige `le_clinico()` desde a 0049, e sem policy o Postgres devolve **zero
 * linhas em silêncio**. Numa tela de auditoria, zero linhas em silêncio é a
 * pior resposta possível — ela é idêntica a "ninguém acessou nada".
 */
create or replace function public.minha_trilha(
  p_de        date,
  p_ate       date,
  p_paciente  uuid default null,
  p_limite    integer default 500
)
returns table (
  em        timestamptz,
  acao      text,
  quem      text,
  saiu      boolean,
  paciente  text,
  detalhe   jsonb
)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  c uuid := public.conta_atual();
begin
  if c is null then raise exception 'sem conta'; end if;

  if not public.le_clinico() then
    raise exception 'a trilha diz quem abriu a ficha de quem: ela é lida por quem tem acesso ao registro clínico';
  end if;

  if p_ate < p_de then
    raise exception 'o período termina antes de começar';
  end if;
  if p_ate - p_de > 400 then
    raise exception 'período longo demais: peça no máximo um ano por vez';
  end if;

  return query
  select tr.em,
         tr.acao,
         -- Quem olhou. A trilha guarda o id porque ele sobrevive à saída da
         -- pessoa da conta; a tela precisa do nome, e quando ele não existe mais
         -- a frase tem de dizer isso em vez de mostrar um uuid.
         coalesce(us.nome, us.email, 'quem não está mais na conta') as quem,
         (us.id is null) as saiu,
         pa.nome as paciente,
         tr.detalhe
    from public.trilha_acesso tr
    left join public.usuarios us
           on us.auth_user_id = tr.auth_user_id and us.conta_id = tr.conta_id
    left join public.pacientes pa on pa.id = tr.paciente_id
   where tr.conta_id = c
     and (tr.em at time zone 'America/Sao_Paulo')::date between p_de and p_ate
     and (p_paciente is null or tr.paciente_id = p_paciente)
   order by tr.em desc
   limit least(greatest(coalesce(p_limite, 500), 1), 2000);
end;
$$;

comment on function public.minha_trilha(date, date, uuid, integer) is
  'A trilha da conta, por periodo e opcionalmente por paciente. NAO tem filtro por acao de proposito: tela de auditoria com filtro por tipo de evento e tela onde o evento inconveniente e o que ninguem marca. Recusa explicita sem acesso clinico — zero linhas em silencio numa tela de auditoria e indistinguivel de "ninguem acessou nada".';

/**
 * O tamanho da trilha, para a tela dizer de quando ela começa.
 *
 * Existe por uma razão só, e ela é sobre confiança: uma tela que mostra as
 * últimas cinquenta linhas sem dizer que há dezoito mil parece uma tela que
 * esconde. O número inteiro e a data da primeira linha respondem isso antes de
 * alguém perguntar.
 */
create or replace function public.tamanho_da_trilha()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  c uuid := public.conta_atual();
  n integer;
  primeira timestamptz;
begin
  if c is null then raise exception 'sem conta'; end if;
  if not public.le_clinico() then
    raise exception 'a trilha é lida por quem tem acesso ao registro clínico';
  end if;

  select count(*)::integer, min(tr.em)
    into n, primeira
    from public.trilha_acesso tr where tr.conta_id = c;

  return jsonb_build_object('linhas', n, 'primeira', primeira);
end;
$$;

-- ============================================================ as trancas

revoke execute on function public.minha_trilha(date, date, uuid, integer) from public, anon;
revoke execute on function public.tamanho_da_trilha()                     from public, anon;

grant execute on function public.minha_trilha(date, date, uuid, integer)  to authenticated;
grant execute on function public.tamanho_da_trilha()                      to authenticated;
