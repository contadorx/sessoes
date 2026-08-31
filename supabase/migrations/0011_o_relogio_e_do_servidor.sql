-- 0011 · O relógio do cancelamento é do servidor.
--
-- A 0010 fechou a classificação, mas deixou uma fresta: ela usava o
-- `cancelada_em` que viesse no update. Um PATCH com `cancelada_em` de dez dias
-- atrás voltava a comprar um `cancelada_cedo`.
--
-- Na fase 1 o único que poderia fazer isso é a própria dona da conta, contra o
-- próprio bolso. Mas na fase 4 existe secretária, e de todo modo um campo que
-- significa "o instante em que isto aconteceu" não se recebe de fora.
--
-- `cancelada_em` passa a ser sempre `now()`. Importação histórica, se um dia
-- existir, entra por outra porta e com trilha.

create or replace function public.checa_transicao_sessao()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
declare
  horas_de_antecedencia numeric;
begin
  if new.estado = old.estado
     and new.cancelada_em is not distinct from old.cancelada_em then
    return new;
  end if;

  if new.conta_id <> old.conta_id or new.paciente_id <> old.paciente_id then
    raise exception 'sessão não muda de conta nem de paciente';
  end if;

  if new.estado in ('realizada', 'falta') and new.inicio > now() then
    raise exception 'a sessão ainda não começou';
  end if;

  if old.estado in ('cancelada_cedo', 'cancelada_tarde')
     and new.estado in ('realizada', 'falta', 'confirmada') then
    raise exception 'cancelamento não vira presença; reabra como prevista';
  end if;

  if new.estado = 'prevista' then
    new.cancelada_em := null;
    new.cancelada_por := null;
  end if;

  if new.estado in ('cancelada_cedo', 'cancelada_tarde') then
    if old.estado in ('realizada', 'falta') then
      raise exception 'esta sessão já aconteceu';
    end if;

    -- O instante é do servidor. Sempre.
    new.cancelada_em  := now();
    new.cancelada_por := coalesce(new.cancelada_por, 'paciente');

    horas_de_antecedencia :=
      extract(epoch from (new.inicio - new.cancelada_em)) / 3600.0;

    new.estado := case
      when horas_de_antecedencia >= new.politica_horas then 'cancelada_cedo'
      else 'cancelada_tarde'
    end;
  end if;

  return new;
end;
$$;

revoke execute on function public.checa_transicao_sessao() from public, anon, authenticated;
