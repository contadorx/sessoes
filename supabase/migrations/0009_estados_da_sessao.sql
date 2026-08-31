-- 0009 · Os estados da sessão, e quem decide o cancelamento.
--
-- Regra que sustenta a D2: **o cliente não escolhe se o cancelamento foi cedo
-- ou tarde.** Ele diz "cancelei"; quem classifica é o banco, comparando o
-- `now()` do servidor com a política gravada na própria sessão (o retrato do
-- combinado, da 0006). Nenhum relógio de navegador, nenhum campo editável:
-- se a classificação viesse do cliente, a cobrança de falta seria negociável
-- por quem soubesse abrir o inspetor.
--
-- E as transições viram regra: não se marca realizada uma sessão que ainda nem
-- começou, e cancelamento não vira presença.

-- ---------------------------------------------------------------- transições

create or replace function public.checa_transicao_sessao()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  if new.estado = old.estado then
    return new;
  end if;

  -- Tenant e paciente de uma sessão não mudam. Mudar horário é remarcar (D11).
  if new.conta_id <> old.conta_id or new.paciente_id <> old.paciente_id then
    raise exception 'sessão não muda de conta nem de paciente';
  end if;

  -- Realizada e falta são fatos sobre o passado.
  if new.estado in ('realizada', 'falta') and new.inicio > now() then
    raise exception 'a sessão ainda não começou';
  end if;

  -- Cancelamento ressuscitado viraria presença sem que ninguém tenha vindo — e
  -- o horário pode já ter sido dado a outra pessoa pela fila.
  if old.estado in ('cancelada_cedo', 'cancelada_tarde')
     and new.estado in ('realizada', 'falta', 'confirmada') then
    raise exception 'cancelamento não vira presença; reabra como prevista';
  end if;

  -- Voltar para prevista é desfazer, e é permitido: se o horário já tiver dono,
  -- a restrição de exclusão recusa sozinha.
  if new.estado = 'prevista' then
    new.cancelada_em := null;
    new.cancelada_por := null;
  end if;

  return new;
end;
$$;

drop trigger if exists sessoes_transicao on public.sessoes;
create trigger sessoes_transicao
  before update of estado on public.sessoes
  for each row execute function public.checa_transicao_sessao();

-- ---------------------------------------------------------------- cancelar

/**
 * Cancela e classifica. Devolve o estado resultante.
 *
 * A política vem da própria sessão — a que valia quando se combinou —, e o
 * "agora" vem do servidor. `security invoker`: a RLS decide se esta pessoa
 * pode tocar nesta sessão, como em qualquer update.
 */
create or replace function public.cancelar_sessao(
  p_sessao uuid,
  p_por text default 'paciente'
)
returns text
language plpgsql
security invoker
set search_path = ''
as $$
declare
  s record;
  horas_de_antecedencia numeric;
  novo_estado text;
begin
  if p_por not in ('paciente', 'profissional') then
    raise exception 'quem cancelou precisa ser paciente ou profissional';
  end if;

  select * into s from public.sessoes where id = p_sessao for update;

  if not found then
    raise exception 'sessão não encontrada';
  end if;

  if s.estado in ('realizada', 'falta') then
    raise exception 'esta sessão já aconteceu';
  end if;

  horas_de_antecedencia := extract(epoch from (s.inicio - now())) / 3600.0;

  novo_estado := case
    when horas_de_antecedencia >= s.politica_horas then 'cancelada_cedo'
    else 'cancelada_tarde'
  end;

  update public.sessoes
     set estado = novo_estado,
         cancelada_em = now(),
         cancelada_por = p_por
   where id = p_sessao;

  return novo_estado;
end;
$$;

revoke execute on function public.cancelar_sessao(uuid, text) from public, anon;
grant execute on function public.cancelar_sessao(uuid, text) to authenticated;

revoke execute on function public.checa_transicao_sessao() from public, anon, authenticated;

comment on function public.cancelar_sessao(uuid, text) is
  'Cancela e classifica cedo/tarde pela politica gravada na sessao e pelo relogio do servidor. O cliente nunca escolhe a classificacao.';
