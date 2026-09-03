-- 0091 · B55 · A entrega se confere, e o silêncio deixa de ser conclusão
--
-- A TESE, QUE VEM DE FORA E VALE PARA OS TRÊS CANAIS
--
-- O provedor responde `success` quando a mensagem entra **na fila dele**, não
-- quando o destino recebe. A queda para um segundo provedor cobre o servidor
-- *recusar*; ela não cobre o caso que acontece — porta 25 bloqueada por volume,
-- API dizendo sucesso, mensagem apodrecendo na fila. Falha silenciosa não
-- quebra nada, não aparece em log de erro, e o prejuízo é uma pasta do contador
-- que ela jurou ter mandado.
--
-- Este produto já brigou com metade disso duas vezes: a B43 nasceu porque a
-- tela afirmava envio que não houve, e a 0089 separou `oferta_preparada` de
-- `oferta_enviada` porque a trilha dizia "enviada" onze vezes sem uma mensagem
-- ter saído. O grau que falta é este: **aceito ainda não é chegou.**
--
-- O QUE ESTA MIGRAÇÃO NÃO CRIA, E É A ADAPTAÇÃO QUE IMPORTA
--
-- **Não cria tabela de saída de e-mail.** O repasse técnico tem a dele
-- (`emails_saida`), e aqui isso seria a segunda fonte de verdade sobre "a
-- mensagem saiu?" — antipadrão nº 1, sobre mensagem que chega numa paciente.
-- `public.mensagens` já é esse registro, com `chave_idem`, ciclo de vida e a
-- camada manual.
--
-- **Não guarda o corpo da mensagem.** O repasse guarda o HTML para poder
-- reenviar *o documento*, e paga por isso com dado de paciente parado no banco
-- e um prazo de retenção novo para conciliar. Aqui o outbox guarda `template` e
-- `params`, e `renderizar()` monta o texto na hora do envio — **o reenvio
-- re-renderiza.** Não há segunda cópia, não há prazo novo, e a
-- `contas.retencao_anos` continua sendo a única palavra sobre retenção.
--
-- (O efeito colateral: se o template mudar entre o envio e o reenvio, o reenvio
-- sai com o texto novo. É o comportamento certo — o texto novo é o que o
-- produto considera correto hoje.)

-- ------------------------------------------------------- a confirmação

alter table public.mensagens
  add column if not exists confirmada_em timestamptz,
  add column if not exists reenvio_de uuid references public.mensagens (id) on delete set null;

comment on column public.mensagens.confirmada_em is
  'Quando o PROVEDOR confirmou a entrega, nunca quando o cliente HTTP devolveu 200. Nulo em mensagem enviada = aceita pelo provedor e sem confirmacao: e o estado que a varredura vigia.';

comment on column public.mensagens.reenvio_de is
  'A mensagem original, quando esta e um reenvio pelo caminho de queda. E o que distingue reenvio de mensagem nova na trilha e no dedup.';

-- FK sempre indexada (lei 2).
create index if not exists mensagens_reenvio_de_idx on public.mensagens (reenvio_de)
  where reenvio_de is not null;

-- O índice da varredura: ela procura enviadas sem confirmação, por canal.
create index if not exists mensagens_sem_confirmacao_idx
  on public.mensagens (canal, enviada_em)
  where estado = 'enviada' and confirmada_em is null;

alter table public.mensagens drop constraint if exists mensagens_estado_check;
alter table public.mensagens add constraint mensagens_estado_check
  check (estado in ('pendente', 'enviando', 'enviada', 'entregue', 'falhou',
                    'cancelada', 'barrada_no_teto', 'na_sua_mao',
                    'perdida', 'reenviada'));

-- ------------------------------------------------------------ o disjuntor
--
-- Uma linha por (conta, canal). `conta_id` nulo é a plataforma inteira, que é o
-- escopo do e-mail: o provedor é um só para todo mundo. O WhatsApp, quando
-- entrar, usa a mesma tabela com a conta preenchida, porque lá a instância é
-- dela — e é por isso que a coluna existe desde já em vez de nascer depois.

create table if not exists public.canal_disjuntor (
  canal          text        not null check (canal in ('whatsapp', 'sms', 'email')),
  conta_id       uuid        references public.contas (id) on delete cascade,
  estado         text        not null default 'fechado' check (estado in ('fechado', 'aberto')),
  motivo         text        not null default 'nunca abriu',
  desde          timestamptz not null default now(),
  atualizado_em  timestamptz not null default now(),
  unique nulls not distinct (canal, conta_id)
);

create index if not exists canal_disjuntor_conta_idx on public.canal_disjuntor (conta_id)
  where conta_id is not null;

comment on table public.canal_disjuntor is
  'O disjuntor por canal. Abre por taxa de perda com amostra minima; fecha SO por evidencia — amostra recente sem perda —, nunca pelo relogio. O que a passagem do tempo autoriza e sondar.';

-- --------------------------------------------------------- as varreduras
--
-- O quarto silêncio: se o cron parar, nada muda em lugar nenhum. Não há erro,
-- não há estado novo, a ausência é o próprio sintoma. Só a data da última
-- passada denuncia — e ela é gravada **inclusive quando a varredura se declara
-- cega**, que é justamente quando alguém precisa saber.

create table if not exists public.varreduras_do_canal (
  nome     text        primary key,
  em       timestamptz not null default now(),
  cega     boolean     not null default false,
  detalhe  jsonb       not null default '{}'::jsonb
);

comment on table public.varreduras_do_canal is
  'Batimento das varreduras do canal. Gravado a cada passada, inclusive quando ela se declara cega. Passar de tres ciclos sem linha nova e o unico sintoma de cron parado.';

alter table public.canal_disjuntor    enable row level security;
alter table public.varreduras_do_canal enable row level security;

-- Infraestrutura da plataforma: quem lê é o operador; quem escreve é o worker.
drop policy if exists canal_disjuntor_operador on public.canal_disjuntor;
create policy canal_disjuntor_operador on public.canal_disjuntor
  for select to authenticated using (public.e_operador());

drop policy if exists varreduras_operador on public.varreduras_do_canal;
create policy varreduras_operador on public.varreduras_do_canal
  for select to authenticated using (public.e_operador());

revoke all on public.canal_disjuntor    from anon;
revoke all on public.varreduras_do_canal from anon;
grant select on public.canal_disjuntor    to authenticated;
grant select on public.varreduras_do_canal to authenticated;
grant all    on public.canal_disjuntor     to service_role;
grant all    on public.varreduras_do_canal to service_role;

-- ------------------------------------------------- o que o webhook escreve

/*
  A tradução do evento do provedor para o estado da mensagem.

  Três decisões dentro:

  · **`entregue` é terminal e não volta.** Um evento de bounce que chegue depois
    de uma confirmação de entrega é ruído do provedor, não um desmentido.
  · **Reenvio confirma o original junto.** A pergunta que importa é "a paciente
    recebeu?", e quem recebeu foi ela — não a linha do banco. Sem isto, o
    original ficaria `reenviada` para sempre e a taxa de perda nunca fecharia.
  · **Devolve o que fez**, para o webhook poder responder 200 sem mentir sobre
    ter processado.
*/
create or replace function public.confirmar_mensagem(
  p_provedor_msg_id text,
  p_evento          text
)
returns text
language plpgsql
security definer
set search_path = ''
as $function$
declare
  m record;
begin
  if p_provedor_msg_id is null or btrim(p_provedor_msg_id) = '' then
    return 'sem_id';
  end if;

  select id, estado, reenvio_de into m
    from public.mensagens
   where provedor_msg_id = p_provedor_msg_id
   limit 1;

  if not found then return 'desconhecida'; end if;
  if m.estado = 'entregue' then return 'ja_entregue'; end if;

  if p_evento = 'entregue' then
    update public.mensagens
       set estado = 'entregue', confirmada_em = now(), erro = null
     where id = m.id;

    if m.reenvio_de is not null then
      update public.mensagens
         set confirmada_em = now()
       where id = m.reenvio_de and confirmada_em is null;
    end if;

    return 'entregue';
  end if;

  if p_evento = 'falhou' then
    update public.mensagens
       set estado = 'falhou', erro = 'o destino recusou'
     where id = m.id;
    return 'falhou';
  end if;

  return 'ignorado';
end;
$function$;

revoke all on function public.confirmar_mensagem(text, text) from public, anon, authenticated;
grant execute on function public.confirmar_mensagem(text, text) to service_role;

comment on function public.confirmar_mensagem(text, text) is
  'O webhook do provedor entra por aqui. entregue e terminal; bounce depois de entregue e ruido. Reenvio confirmado confirma o original junto: quem recebeu foi a paciente, nao a linha.';

-- --------------------------------------------- a amostra, e nada de conclusão

/*
  A foto que o disjuntor e a trava do instrumento leem.

  `confirmadas` existe para separar **silêncio** de **vazio**: sem nenhuma
  confirmação na janela, com saídas maiores que zero, não se conclui perda de
  ninguém. Ausência total de sinal é falta de instrumento, não evidência — a
  mesma regra que a 0088 escreveu para a oferta sem mensagem.

  Esta função só **lê**. Quem decide é `lib/mensageria/entrega.ts`, que é puro e
  testado — a decisão mora no lado que se prova sem banco.
*/
create or replace function public.amostra_do_canal(p_canal text, p_janela_min integer)
returns table (total bigint, confirmadas bigint, sem_confirmacao bigint)
language sql
stable
security definer
set search_path = ''
as $function$
  select
    count(*),
    count(*) filter (where m.confirmada_em is not null),
    count(*) filter (where m.confirmada_em is null and m.estado in ('enviada', 'perdida'))
  from public.mensagens m
 where m.canal = p_canal
   and m.enviada_em is not null
   and m.enviada_em >= now() - make_interval(mins => p_janela_min);
$function$;

revoke all on function public.amostra_do_canal(text, integer) from public, anon, authenticated;
grant execute on function public.amostra_do_canal(text, integer) to service_role;

-- --------------------------------------------------- marcar o que se perdeu

create or replace function public.marcar_perdidas(p_canal text, p_janela_min integer)
returns integer
language plpgsql
security definer
set search_path = ''
as $function$
declare n integer;
begin
  update public.mensagens
     set estado = 'perdida'
   where canal = p_canal
     and estado = 'enviada'
     and confirmada_em is null
     and enviada_em is not null
     and enviada_em < now() - make_interval(mins => p_janela_min);

  get diagnostics n = row_count;
  return n;
end;
$function$;

revoke all on function public.marcar_perdidas(text, integer) from public, anon, authenticated;
grant execute on function public.marcar_perdidas(text, integer) to service_role;

comment on function public.marcar_perdidas(text, integer) is
  'Marca como perdida a mensagem aceita pelo provedor e sem confirmacao alem da janela. Quem chama tem de ter passado pela trava do instrumento antes: sem nenhuma confirmacao na janela, nao se conclui perda de ninguem.';

-- ---------------------------------------------------------- o batimento

create or replace function public.registrar_varredura(
  p_nome text, p_cega boolean, p_detalhe jsonb
)
returns void
language sql
security definer
set search_path = ''
as $function$
  insert into public.varreduras_do_canal (nome, em, cega, detalhe)
  values (p_nome, now(), p_cega, coalesce(p_detalhe, '{}'::jsonb))
  on conflict (nome) do update
     set em = now(), cega = excluded.cega, detalhe = excluded.detalhe;
$function$;

revoke all on function public.registrar_varredura(text, boolean, jsonb) from public, anon, authenticated;
grant execute on function public.registrar_varredura(text, boolean, jsonb) to service_role;

-- A linha do e-mail nasce fechada, como manda a ordem de implantação.
insert into public.canal_disjuntor (canal, conta_id, estado, motivo)
values ('email', null, 'fechado', 'nunca abriu')
on conflict (canal, conta_id) do nothing;

-- ------------------------------------------------------------- o reenvio
--
-- A outbox tem **uma porta de entrada**, e o reenvio não abre uma segunda: ele
-- devolve a mensagem para a mesma fila, com `chave_idem` derivada (`#r1`, `#r2`)
-- para não colidir com a original e com `reenvio_de` apontando para ela.
--
-- **Não copia corpo nenhum**, porque não existe corpo guardado: o texto sai de
-- `renderizar(template, params)` na hora do envio, como em toda mensagem deste
-- produto. É o que dispensa a tabela de HTML do repasse técnico e o prazo de
-- retenção que viria junto com ela.
--
-- Teto de dois reenvios. Passou disso a original vira `falhou` **com o motivo
-- escrito** e ninguém manda mais nada: reenviar em laço transforma um problema
-- de entrega num problema de reputação, e o que sobra é visível na tela em vez
-- de sair de novo.

create or replace function public.reenfileirar_mensagem(p_mensagem uuid)
returns uuid
language plpgsql
security definer
set search_path = ''
as $function$
declare
  m    record;
  n    integer;
  novo uuid;
begin
  select * into m from public.mensagens where id = p_mensagem;
  if not found then raise exception 'mensagem não encontrada'; end if;

  if m.estado <> 'perdida' then return null; end if;

  select count(*) into n from public.mensagens
   where reenvio_de = coalesce(m.reenvio_de, m.id);

  if n >= 2 then
    update public.mensagens
       set estado = 'falhou',
           erro = 'não confirmou entrega depois de ' || n || ' reenvios'
     where id = p_mensagem;
    return null;
  end if;

  insert into public.mensagens (
    conta_id, paciente_id, canal, template, params, destino,
    chave_idem, agendada_para, reenvio_de, estado
  )
  values (
    m.conta_id, m.paciente_id, m.canal, m.template, m.params, m.destino,
    m.chave_idem || '#r' || (n + 1), now(), coalesce(m.reenvio_de, m.id), 'pendente'
  )
  returning id into novo;

  update public.mensagens set estado = 'reenviada' where id = p_mensagem;
  return novo;
end;
$function$;

revoke all on function public.reenfileirar_mensagem(uuid) from public, anon, authenticated;
grant execute on function public.reenfileirar_mensagem(uuid) to service_role;

comment on function public.reenfileirar_mensagem(uuid) is
  'Poe a mensagem perdida de volta na outbox, com chave_idem derivada (#r1, #r2) e reenvio_de apontando para a original. Nao guarda corpo: o texto e re-renderizado de template + params no envio. Teto de 2 reenvios; alem disso a original vira falhou e ninguem manda mais nada.';
