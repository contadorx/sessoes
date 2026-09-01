-- 0040d · O espelho tem de ver a sessão antes de ela sumir.
--
-- Achado pelo teste 17 da suíte 0040, e é um furo de ordem de execução — o tipo
-- que não aparece lendo o código, porque cada peça está certa sozinha.
--
-- O desenho era: `espelhos_calendario.sessao_id` é `on delete set null` para o
-- espelho **sobreviver** à sessão e conseguir remover o evento lá fora; e o
-- gatilho `sessao_espelha`, no DELETE, encontra o espelho por `sessao_id` e o
-- vira em `remover`.
--
-- As duas coisas são AFTER na mesma instrução. A ação referencial da FK rodou
-- primeiro, zerou o `sessao_id`, e aí o gatilho procurou por um vínculo que já
-- não existia, não achou nada e voltou em silêncio. Resultado: férias de duas
-- semanas apagavam as instâncias previstas aqui e deixavam **catorze eventos
-- órfãos na Google Agenda dela, para sempre** — e nada no sistema saberia.
--
-- Silêncio é o que torna isso grave. Nenhuma exceção, nenhuma linha de log:
-- só a agenda dela enchendo de sessão que não existe mais, exatamente na
-- semana em que ela viajou.
--
-- A correção é separar por momento, e não por ação: o caminho do DELETE vira um
-- gatilho **BEFORE**, que roda antes de a FK apagar o vínculo. INSERT e UPDATE
-- continuam AFTER, onde precisam estar (no INSERT, a sessão ainda não existe
-- para a FK do espelho apontar).
--
-- **Regra que fica:** quando um gatilho depende de um vínculo que uma ação
-- referencial vai desfazer, ele não pode disputar ordem com ela — tem de rodar
-- antes.

create or replace function public.sessao_apagada_espelha()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  cal record;
  tem_cal boolean := false;
  existente record;
  tem_espelho boolean := false;
begin
  select * into cal
    from public.calendarios
   where profissional_id = old.profissional_id
     and estado in ('ligado', 'pausado')
     and direcao in ('escrever', 'duas_vias');
  tem_cal := found;

  if not tem_cal then return old; end if;

  select * into existente
    from public.espelhos_calendario
   where calendario_id = cal.id and sessao_id = old.id;
  tem_espelho := found;

  if not tem_espelho then return old; end if;

  if existente.evento_externo is null then
    -- Nunca chegou a existir lá fora: não há o que remover.
    delete from public.espelhos_calendario where id = existente.id;
  else
    update public.espelhos_calendario
       set acao = 'remover', estado = 'pendente', sessao_id = null,
           tentativas = 0, erro = null
     where id = existente.id;
  end if;

  return old;
end;
$$;

drop trigger if exists sessao_apagada_espelha on public.sessoes;
create trigger sessao_apagada_espelha
  before delete on public.sessoes
  for each row execute function public.sessao_apagada_espelha();

/**
 * `sessao_espelha` fica só com INSERT e UPDATE.
 *
 * O corpo perde o ramo do DELETE inteiro — inclusive o `if tg_op = 'DELETE'
 * then quem_prof := old.profissional_id` do começo, que existia só para ele.
 * O cuidado com o curto-circuito do plpgsql continua valendo para o UPDATE:
 * `old.estado` só é lido dentro do `if tg_op = 'UPDATE'`, nunca na condição.
 */
create or replace function public.sessao_espelha()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  cal record;
  tem_cal boolean := false;
  antes_inicio timestamptz := null;
  antes_fim    timestamptz := null;
  antes_estado text := null;
  mudou boolean := false;
  sai boolean;      -- este estado ocupa a hora lá fora?
  existente record;
  tem_espelho boolean := false;
begin
  select * into cal
    from public.calendarios
   where profissional_id = new.profissional_id
     and estado in ('ligado', 'pausado')
     and direcao in ('escrever', 'duas_vias');
  tem_cal := found;

  if not tem_cal then return new; end if;

  -- Sessão importada é memória: não vai para a agenda de ninguém.
  if new.origem = 'importada' then
    return new;
  end if;

  -- Cancelada devolve a hora; realizada e falta consumiram a hora e ficam.
  sai := new.estado in ('prevista', 'confirmada', 'realizada', 'falta');

  if tg_op = 'UPDATE' then
    antes_inicio := old.inicio;
    antes_fim    := old.fim;
    antes_estado := old.estado;
    mudou := new.inicio is distinct from antes_inicio
          or new.fim    is distinct from antes_fim
          or new.estado is distinct from antes_estado;
    if not mudou then
      return new;
    end if;
  end if;

  select * into existente
    from public.espelhos_calendario
   where calendario_id = cal.id and sessao_id = new.id;
  tem_espelho := found;

  if sai then
    if not tem_espelho then
      insert into public.espelhos_calendario (conta_id, calendario_id, sessao_id, acao)
      values (cal.conta_id, cal.id, new.id, 'criar');
    else
      update public.espelhos_calendario
         set acao = case when evento_externo is null then 'criar' else 'atualizar' end,
             estado = 'pendente', tentativas = 0, erro = null
       where id = existente.id;
    end if;
  else
    if tem_espelho then
      if existente.evento_externo is null then
        delete from public.espelhos_calendario where id = existente.id;
      else
        update public.espelhos_calendario
           set acao = 'remover', estado = 'pendente', tentativas = 0, erro = null
         where id = existente.id;
      end if;
    end if;
  end if;

  return new;
end;
$$;

drop trigger if exists sessao_espelha on public.sessoes;
create trigger sessao_espelha
  after insert or update on public.sessoes
  for each row execute function public.sessao_espelha();

comment on function public.sessao_apagada_espelha() is
  'BEFORE DELETE de proposito: o on delete set null da FK e AFTER e apagaria o vinculo antes de o gatilho encontrar o espelho, deixando o evento orfao na agenda externa.';
