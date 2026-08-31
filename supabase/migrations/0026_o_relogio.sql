-- 0026 · O relógio.
--
-- Auditando o repositório antes da fase 2, encontrei um buraco que não é de
-- código e sim de operação: **quatro rotinas só rodavam quando alguém clicava
-- num botão.**
--
--   · `expirar_ofertas` — as ofertas nunca venciam sozinhas. A promessa central
--     da B7 ("a oferta expira em 40 minutos e a fila anda") dependia de a
--     psicóloga estar com a tela aberta. No piloto isso apareceria como "a fila
--     travou", e o motor da fila — que está certo — levaria a culpa;
--   · `materializar_conta` — a janela rolante de oito semanas nunca se
--     estendia. Em dois meses a agenda simplesmente acabaria;
--   · `expurgar_mensagens` — a retenção da B13 nunca acontecia;
--   · o lembrete da véspera não existia: o template estava desenhado, e nada
--     enfileirava nada.
--
-- Nenhum desses é bug de lógica. São peças corretas sem quem lhes dê corda — e
-- é por isso que passaram por todos os testes. Teste de função não pergunta
-- *quem chama a função*.
--
-- Este arquivo cria as duas variantes globais que faltavam (as existentes
-- dependem de `conta_atual()`, que é nulo para o worker) e o agendador de
-- lembretes.

-- ------------------------------------------------------------- o lembrete

alter table public.contas
  add column if not exists lembrete_horas smallint not null default 24
    check (lembrete_horas between 0 and 72);

comment on column public.contas.lembrete_horas is
  'Antecedencia do lembrete de sessao. 0 desliga — e ha quem nao queira lembrar ninguem.';

/**
 * Enfileira o lembrete das sessões que vêm aí.
 *
 * Chamada pelo cron diário, e **idempotente por sessão**: a chave é
 * `lembrete:<id da sessão>`, então rodar de hora em hora, ou duas vezes por
 * engano, não manda dois lembretes. É a mesma disciplina da 0017.
 *
 * O horário de saída é `início − antecedência`, e quem decide o resto é o
 * gatilho do outbox: nunca no passado, nunca dentro da janela de silêncio. Um
 * lembrete que chega às 3h da manhã é pior do que lembrete nenhum.
 *
 * Sessão cancelada não entra. Cancelamento já tem mensagem própria, e mandar
 * "lembrete do seu horário" para quem desmarcou é o tipo de erro que faz a
 * pessoa deixar de confiar em tudo o que vem depois.
 */
create or replace function public.agendar_lembretes()
returns int
language plpgsql
security invoker
set search_path = ''
as $$
declare
  s record;
  n int := 0;
begin
  for s in
    select ss.id, ss.paciente_id, ss.inicio, c.lembrete_horas
      from public.sessoes ss
      join public.contas c on c.id = ss.conta_id
      join public.pacientes p on p.id = ss.paciente_id
     where ss.estado in ('prevista', 'confirmada')
       and c.lembrete_horas > 0
       and p.msg_canal <> 'nao_avisar'
       and ss.inicio > now()
       -- A janela é a antecedência + um dia de folga, para que o cron diário
       -- nunca perca uma sessão por rodar tarde.
       and ss.inicio <= now() + make_interval(hours => c.lembrete_horas + 24)
  loop
    if public.enfileirar_mensagem(
         s.paciente_id,
         'lembrete_de_sessao',
         'lembrete:' || s.id::text,
         jsonb_build_object('sessao_id', s.id, 'inicio', s.inicio),
         s.inicio - make_interval(hours => s.lembrete_horas)
       ) is not null
    then
      n := n + 1;
    end if;
  end loop;

  return n;
end;
$$;

/**
 * Cancela o lembrete de uma sessão que deixou de existir.
 *
 * Gatilho, e não responsabilidade de quem cancela: a sessão pode sair de
 * `prevista` por vários caminhos, e esquecer um deles significa um lembrete
 * chegando para uma sessão desmarcada.
 */
create or replace function public.lembrete_segue_a_sessao()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  if new.estado in ('prevista', 'confirmada') then return new; end if;

  update public.mensagens
     set estado = 'cancelada'
   where chave_idem = 'lembrete:' || new.id::text
     and estado = 'pendente';

  return new;
end;
$$;

drop trigger if exists sessoes_cancelam_lembrete on public.sessoes;
create trigger sessoes_cancelam_lembrete after update of estado on public.sessoes
  for each row when (old.estado is distinct from new.estado)
  execute function public.lembrete_segue_a_sessao();

-- --------------------------------------------------------- as versões globais

/**
 * Estende a janela rolante de **todas** as contas.
 *
 * A `materializar_conta()` resolve a conta pelo `conta_atual()` — que é nulo
 * para o worker, de propósito. Esta é a irmã dela para o cron: percorre os
 * enquadres abertos de todo mundo, sem parâmetro de tenant vindo de fora.
 *
 * Só o `service_role` chama. Uma pessoa logada não tem por que materializar a
 * agenda alheia, mesmo que o efeito fosse inofensivo.
 */
create or replace function public.materializar_tudo()
returns int
language plpgsql
security definer
set search_path = ''
as $$
declare
  r record;
  total int := 0;
begin
  for r in
    select en.id from public.enquadres en where en.vigencia_fim is null
  loop
    total := total + public.materializar_enquadre(r.id);
  end loop;

  return total;
end;
$$;

revoke execute on function public.materializar_tudo() from public, anon, authenticated;
revoke execute on function public.agendar_lembretes() from public, anon;
revoke execute on function public.lembrete_segue_a_sessao() from public, anon, authenticated;
grant execute on function public.materializar_tudo() to service_role;
grant execute on function public.agendar_lembretes() to service_role;

comment on function public.materializar_tudo() is
  'Versao do cron: sem conta_atual(), percorre todos os enquadres abertos. So service_role.';
comment on function public.agendar_lembretes() is
  'Idempotente por sessao (chave lembrete:<id>). Rodar quantas vezes quiser.';
