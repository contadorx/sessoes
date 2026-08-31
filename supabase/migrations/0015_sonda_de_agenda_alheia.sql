-- 0015 · Fecha a sonda da agenda alheia.
--
-- Apontado pelos advisors depois da 0012: `vaga_esta_livre()` e
-- `proximo_envio()` nasceram `security definer` e ficaram executáveis por
-- qualquer usuário logado em /rest/v1/rpc. Ambas recebem o alvo por parâmetro.
--
-- O que isso permitia: com o uuid de um profissional de outra conta, perguntar
-- **se ele está livre na terça às 15h** — e ir varrendo. Não vaza nome de
-- paciente, mas vaza a agenda de um consultório para fora dele, que é
-- exatamente o tipo de coisa que este produto promete não fazer.
--
-- A correção não é revogar o execute (as duas são chamadas por
-- `elegiveis_para_vaga`, `avancar_fila` e `responder_oferta`, que rodam como
-- invoker e precisam do privilégio). É tirar o `definer`: como **invoker**, a
-- RLS passa a valer dentro delas. Perguntar sobre outra conta deixa de ser
-- proibido e passa a ser inútil — a função não enxerga nada e responde sobre o
-- vazio.
--
-- Uso interno segue idêntico: quem chama sempre é dono do dado.

create or replace function public.vaga_esta_livre(
  p_profissional uuid,
  p_inicio timestamptz,
  p_fim timestamptz,
  p_ignorar uuid default null
)
returns boolean
language sql
stable
security invoker
set search_path = ''
as $$
  select not exists (
    select 1 from public.sessoes s
     where s.profissional_id = p_profissional
       and s.id is distinct from p_ignorar
       and s.estado in ('prevista', 'confirmada', 'realizada', 'falta')
       and tstzrange(s.inicio, s.fim, '[)') && tstzrange(p_inicio, p_fim, '[)')
  )
  and not exists (
    select 1 from public.excecoes_agenda x
     where x.profissional_id = p_profissional
       and (p_inicio at time zone 'America/Sao_Paulo')::date between x.inicio and x.fim
  );
$$;

create or replace function public.proximo_envio(p_conta uuid, p_agora timestamptz default now())
returns timestamptz
language plpgsql
stable
security invoker
set search_path = ''
as $$
declare
  c record;
  agora_local timestamp;
  hora_local time;
  dentro_do_silencio boolean;
begin
  select silencio_inicio, silencio_fim into c from public.contas where id = p_conta;
  if not found then return p_agora; end if;

  agora_local := p_agora at time zone 'America/Sao_Paulo';
  hora_local := agora_local::time;

  dentro_do_silencio := case
    when c.silencio_inicio < c.silencio_fim
      then hora_local >= c.silencio_inicio and hora_local < c.silencio_fim
    else hora_local >= c.silencio_inicio or hora_local < c.silencio_fim
  end;

  if not dentro_do_silencio then
    return p_agora;
  end if;

  return case
    when hora_local < c.silencio_fim
      then (agora_local::date + c.silencio_fim) at time zone 'America/Sao_Paulo'
    else ((agora_local::date + 1) + c.silencio_fim) at time zone 'America/Sao_Paulo'
  end;
end;
$$;

grant execute on function public.vaga_esta_livre(uuid, timestamptz, timestamptz, uuid) to authenticated;
grant execute on function public.proximo_envio(uuid, timestamptz) to authenticated;
revoke execute on function public.vaga_esta_livre(uuid, timestamptz, timestamptz, uuid) from anon;
revoke execute on function public.proximo_envio(uuid, timestamptz) from anon;
