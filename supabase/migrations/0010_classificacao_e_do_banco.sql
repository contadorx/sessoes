-- 0010 · A classificação do cancelamento é do banco, venha de onde vier.
--
-- A 0009 colocou a classificação dentro de `cancelar_sessao()`. Mas a policy de
-- update permite escrever em `sessoes` direto pelo PostgREST — então quem
-- soubesse montar um PATCH podia gravar `cancelada_cedo` numa sessão que começa
-- em uma hora e escapar da multa. Uma função "certa" não protege nada enquanto
-- existir um caminho ao lado dela.
--
-- Aqui a regra sai da função e vira **invariante da tabela**: qualquer update
-- que leve a sessão para um estado cancelado tem a classificação recalculada
-- pelo relógio do servidor e pela política gravada na própria linha. Não existe
-- caminho que escolha o resultado — nem o nosso.

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

  -- O coração da D2: quem classifica é o banco.
  if new.estado in ('cancelada_cedo', 'cancelada_tarde') then
    if old.estado in ('realizada', 'falta') then
      raise exception 'esta sessão já aconteceu';
    end if;

    new.cancelada_em  := coalesce(new.cancelada_em, now());
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

drop trigger if exists sessoes_transicao on public.sessoes;
create trigger sessoes_transicao
  before update of estado, cancelada_em, cancelada_por on public.sessoes
  for each row execute function public.checa_transicao_sessao();

revoke execute on function public.checa_transicao_sessao() from public, anon, authenticated;

-- A política e o valor também não se editam depois: são o retrato do combinado
-- no momento em que a sessão foi marcada (0006). Mudar o preço da sessão de
-- ontem é reescrever a história.
create or replace function public.congela_retrato_da_sessao()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  if new.valor is distinct from old.valor
     or new.politica_horas is distinct from old.politica_horas
     or new.politica_percentual is distinct from old.politica_percentual then
    raise exception 'o combinado da sessão não se edita; reajuste abre outro enquadre';
  end if;
  return new;
end;
$$;

drop trigger if exists sessoes_retrato on public.sessoes;
create trigger sessoes_retrato
  before update of valor, politica_horas, politica_percentual on public.sessoes
  for each row execute function public.congela_retrato_da_sessao();

revoke execute on function public.congela_retrato_da_sessao() from public, anon, authenticated;
